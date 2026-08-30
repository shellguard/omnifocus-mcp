import Foundation
import OmniFocusCore

@main
struct OmniFocusMCPServer {
    static func main() {
        let server = MCPServer()
        server.run()
    }
}

enum ProtocolEra {
    case legacy
    case modern
}

struct RequestContext {
    let id: Any?
    let era: ProtocolEra
    let protocolVersion: String
    let requestLogLevel: String?
}

final class MCPServer {
    let engine = OFEngine()
    let stdout = FileHandle.standardOutput
    let stdin = FileHandle.standardInput

    let maxBufferSize = 10 * 1024 * 1024 // 10 MB
    let serverVersion = "0.8.0"
    let serverDescription = "OmniFocus MCP server and CLI for macOS (Omni Automation + JXA)"
    let modernProtocolVersion = "2026-07-28"
    let legacyHandshakeVersions = ["2025-11-25", "2025-06-18", "2024-11-05"]
    let defaultLegacyVersion = "2025-11-25"
    let defaultToolsPageSize = 100
    let listCacheTtlMs = 3_600_000

    var supportedProtocolVersions: [String] {
        [modernProtocolVersion] + legacyHandshakeVersions
    }

    // Logging (legacy session-scoped; modern uses per-request _meta logLevel)
    static let logLevelOrder = ["debug", "info", "notice", "warning", "error", "critical", "alert", "emergency"]
    var logLevel: String = "warning"

    // Sampling (legacy clients only)
    var clientSupportsSampling = false
    private var nextRequestId = 1

    // Shared read buffer (extracted from run() to support bidirectional reads)
    private var buffer = Data()

    // Last initialize-negotiated version for legacy requests that omit _meta
    var legacyNegotiatedVersion = "2025-11-25"

    // Prompts
    struct Prompt {
        let name: String
        let title: String
        let description: String
        let arguments: [[String: Any]]
    }

    let prompts: [Prompt] = [
        Prompt(
            name: "capture",
            title: "Capture Task",
            description: "Capture a task to OmniFocus inbox",
            arguments: [[
                "name": "task",
                "description": "Task description to capture",
                "required": false
            ]]
        ),
        Prompt(
            name: "forecast",
            title: "Forecast",
            description: "Show your OmniFocus forecast — overdue, today, and flagged tasks",
            arguments: []
        ),
        Prompt(
            name: "review",
            title: "Review",
            description: "Run a quick OmniFocus review — inbox, overdue, stalled projects",
            arguments: []
        )
    ]

    // MARK: - Main Loop

    func run() {
        while let lineData = readNextLine() {
            handleLine(lineData)
        }
        if !buffer.isEmpty {
            handleLine(buffer)
            buffer.removeAll()
        }
    }

    func readNextLine() -> Data? {
        while true {
            if let range = buffer.range(of: Data([0x0A])) {
                let lineData = buffer.subdata(in: buffer.startIndex..<range.lowerBound)
                buffer.removeSubrange(buffer.startIndex...range.lowerBound)
                return lineData
            }
            let chunk = stdin.availableData
            if chunk.isEmpty { return nil }
            buffer.append(chunk)
            if buffer.count > maxBufferSize {
                sendError(id: nil, code: -32600, message: "Request too large", data: "Input exceeds \(maxBufferSize) byte limit")
                buffer.removeAll()
            }
        }
    }

    // MARK: - Message Handling

    func handleLine(_ data: Data) {
        guard let line = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !line.isEmpty else {
            return
        }
        let jsonObject: Any
        do {
            jsonObject = try JSONSerialization.jsonObject(with: Data(line.utf8), options: [])
        } catch {
            sendError(id: nil, code: -32700, message: "Parse error", data: error.localizedDescription)
            return
        }
        guard let message = jsonObject as? [String: Any] else {
            sendError(id: nil, code: -32600, message: "Invalid Request", data: "Message is not an object")
            return
        }
        do {
            try handleMessage(message)
        } catch let error as MCPError {
            let code: Int
            switch error {
            case .methodNotFound:
                code = -32601
            case .invalidParams, .toolNotFound:
                code = -32602
            case .invalidRequest:
                code = -32600
            case .toolError, .scriptError:
                code = -32000
            }
            sendError(id: message["id"], code: code, message: error.description)
        } catch {
            sendError(id: message["id"], code: -32603, message: "Internal error", data: error.localizedDescription)
        }
    }

    func handleMessage(_ message: [String: Any]) throws {
        let id = message["id"]

        // Route responses to outgoing requests (e.g. sampling)
        if message["result"] != nil || message["error"] != nil {
            return
        }

        let method = message["method"] as? String

        if method == nil {
            throw MCPError.invalidRequest("Missing method")
        }

        let params = message["params"] as? [String: Any] ?? [:]
        let context: RequestContext
        do {
            context = try makeRequestContext(id: id, method: method, params: params)
        } catch let unsupported as UnsupportedProtocol {
            sendUnsupportedProtocolVersion(id: id, requested: unsupported.requested)
            return
        }

        switch method {
        case "initialize":
            let requestedVersion = params["protocolVersion"] as? String
            let negotiatedVersion = negotiateHandshakeVersion(requestedVersion)
            legacyNegotiatedVersion = negotiatedVersion

            if let clientCaps = params["capabilities"] as? [String: Any],
               clientCaps["sampling"] != nil {
                clientSupportsSampling = true
            }

            sendResult(id: id, result: [
                "protocolVersion": negotiatedVersion,
                "capabilities": handshakeCapabilities(for: negotiatedVersion),
                "serverInfo": serverInfoObject
            ], context: RequestContext(
                id: id,
                era: .legacy,
                protocolVersion: negotiatedVersion,
                requestLogLevel: context.requestLogLevel
            ))

        case "server/discover":
            sendResult(id: id, result: buildDiscoverResult(), context: RequestContext(
                id: id,
                era: .modern,
                protocolVersion: modernProtocolVersion,
                requestLogLevel: context.requestLogLevel
            ), cacheable: true)

        case "tools/list":
            let result = try buildToolsListResult(params: params)
            sendResult(id: id, result: result, context: context, cacheable: true)

        case "tools/call":
            guard let toolName = params["name"] as? String else {
                throw MCPError.invalidParams("Missing tool name")
            }
            let arguments = params["arguments"] as? [String: Any] ?? [String: Any]()
            sendLog(level: "info", data: "Calling tool: \(toolName)", context: context)
            do {
                let resultValue = try engine.callTool(named: toolName, arguments: arguments)
                let jsonText = try OFEngine.serializeToolResult(resultValue)
                sendLog(level: "debug", data: "Tool \(toolName) completed successfully", context: context)
                var response: [String: Any] = [
                    "content": [["type": "text", "text": jsonText]]
                ]
                if let structured = structuredContent(from: resultValue, jsonText: jsonText) {
                    response["structuredContent"] = structured
                }
                sendResult(id: id, result: response, context: context)
            } catch let error as MCPError {
                switch error {
                case .toolNotFound:
                    throw error
                case .invalidParams, .toolError, .scriptError:
                    sendLog(level: "error", data: "Tool \(toolName) failed: \(error.description)", context: context)
                    sendToolErrorResult(id: id, message: error.description, context: context)
                case .invalidRequest, .methodNotFound:
                    throw error
                }
            } catch {
                sendLog(level: "error", data: "Tool \(toolName) failed: \(error.localizedDescription)", context: context)
                sendToolErrorResult(id: id, message: "Internal tool execution error: \(error.localizedDescription)", context: context)
            }

        case "prompts/list":
            sendResult(id: id, result: buildPromptsListResult(), context: context, cacheable: true)

        case "prompts/get":
            guard let name = params["name"] as? String else {
                throw MCPError.invalidParams("Missing prompt name")
            }
            let arguments = params["arguments"] as? [String: String] ?? [:]
            let result = try buildPromptGetResult(name: name, arguments: arguments)
            sendResult(id: id, result: result, context: context)

        case "logging/setLevel":
            if context.era == .modern {
                throw MCPError.methodNotFound("logging/setLevel was removed in protocol 2026-07-28; set io.modelcontextprotocol/logLevel on request _meta")
            }
            guard let level = params["level"] as? String else {
                throw MCPError.invalidParams("Missing log level")
            }
            guard MCPServer.logLevelOrder.contains(level) else {
                throw MCPError.invalidParams("Invalid log level: \(level)")
            }
            logLevel = level
            sendResult(id: id, result: [:], context: context)

        case "initialized", "notifications/initialized":
            return
        case "shutdown":
            sendResult(id: id, result: [:], context: context)
            return
        case "exit":
            return
        default:
            throw MCPError.methodNotFound("Unknown method: \(method ?? "")")
        }
    }

    // MARK: - Protocol era

    struct UnsupportedProtocol: Error {
        let requested: String
    }

    func makeRequestContext(id: Any?, method: String?, params: [String: Any]) throws -> RequestContext {
        let meta = params["_meta"] as? [String: Any] ?? [:]
        let requestLogLevel = meta["io.modelcontextprotocol/logLevel"] as? String
        if let requested = meta["io.modelcontextprotocol/protocolVersion"] as? String {
            guard supportedProtocolVersions.contains(requested) else {
                throw UnsupportedProtocol(requested: requested)
            }
            let era: ProtocolEra = requested == modernProtocolVersion ? .modern : .legacy
            return RequestContext(id: id, era: era, protocolVersion: requested, requestLogLevel: requestLogLevel)
        }
        if method == "server/discover" {
            return RequestContext(id: id, era: .modern, protocolVersion: modernProtocolVersion, requestLogLevel: requestLogLevel)
        }
        return RequestContext(id: id, era: .legacy, protocolVersion: legacyNegotiatedVersion, requestLogLevel: requestLogLevel)
    }

    func negotiateHandshakeVersion(_ requestedVersion: String?) -> String {
        guard let requestedVersion else {
            return defaultLegacyVersion
        }
        if requestedVersion == modernProtocolVersion || legacyHandshakeVersions.contains(requestedVersion) {
            return requestedVersion
        }
        return defaultLegacyVersion
    }

    var serverInfoObject: [String: Any] {
        [
            "name": "omnifocus-mcp",
            "version": serverVersion,
            "description": serverDescription
        ]
    }

    func handshakeCapabilities(for version: String) -> [String: Any] {
        var caps: [String: Any] = [
            "tools": ["listChanged": false],
            "prompts": [String: Any]()
        ]
        // Logging remains on the legacy path only (deprecated in 2026-07-28).
        if version != modernProtocolVersion {
            caps["logging"] = [String: Any]()
        }
        return caps
    }

    func modernCapabilities() -> [String: Any] {
        [
            "tools": ["listChanged": false],
            "prompts": [String: Any]()
        ]
    }

    func buildDiscoverResult() -> [String: Any] {
        [
            "supportedVersions": supportedProtocolVersions,
            "capabilities": modernCapabilities(),
            "instructions": "OmniFocus task manager for macOS. Prefer dedicated omnifocus_* tools over eval. Date fields: due is a deadline, planned is intended work (4.7+), defer hides until a date. Mutually exclusive tag groups may reject extra tags."
        ]
    }

    // MARK: - Prompts

    func buildPromptsListResult() -> [String: Any] {
        let entries = prompts.map { prompt -> [String: Any] in
            var entry: [String: Any] = [
                "name": prompt.name,
                "title": prompt.title,
                "description": prompt.description
            ]
            if !prompt.arguments.isEmpty {
                entry["arguments"] = prompt.arguments
            }
            return entry
        }
        return ["prompts": entries]
    }

    func buildPromptGetResult(name: String, arguments: [String: String]) throws -> [String: Any] {
        guard let prompt = prompts.first(where: { $0.name == name }) else {
            throw MCPError.invalidParams("Unknown prompt: \(name)")
        }

        let text: String
        switch name {
        case "capture":
            let task = arguments["task"]
            if let task, !task.isEmpty {
                text = """
                    Capture "\(task)" as a task in OmniFocus.

                    Parse the input and call `omnifocus_create_task`. Extract any project name, due date, tags, or other details from the text. Put it in the inbox if no project is clear.

                    Confirm with a single short sentence: what was captured and where.
                    """
            } else {
                text = """
                    Ask the user what they'd like to capture as a task in OmniFocus.

                    Once they provide input, parse it and call `omnifocus_create_task`. Extract any project name, due date, tags, or other details from the text. Put it in the inbox if no project is clear.

                    Confirm with a single short sentence: what was captured and where.
                    """
            }
        case "forecast":
            text = """
                Show my OmniFocus forecast using `omnifocus_get_forecast`.

                The result has seven lists. Render only non-empty sections in this order:
                1. **Overdue** — `overdue`. Flag this section.
                2. **Due today** — `today`.
                3. **Planned today** — `plannedToday` (intended-work-date today, including inherited `effectivePlannedDate`).
                4. **Forecast tag** — `forecastTagged` (tasks carrying the user's Forecast tag, not already listed above).
                5. **Flagged** — `flagged`, excluding entries already shown.
                6. **Due this week** — `dueThisWeek`.
                7. **Planned soon** — `plannedSoon`.

                Keep each task to one line: name plus due date or planned date. Don't list a task in more than one section — first match wins.
                End with a one-line summary count, e.g. "3 overdue · 5 due today · 2 planned · 4 flagged".

                If everything is empty, say so briefly and offer to help plan the day.

                Date semantics reminder when offering help: `due` is a real deadline, `planned` is an intended work date, `defer` hides until a date. Don't push the user to put work on `due` if it's just an intent.
                """
        case "review":
            text = """
                Run a structured OmniFocus review in three parts:

                **1. Inbox**
                Call `omnifocus_list_inbox`. If there are items, list them and ask whether to process them (assign projects, tags, due dates) or leave for later.

                **2. Overdue & today**
                Call `omnifocus_get_forecast`. List overdue tasks first, then today's. For each overdue task, ask: complete it, reschedule it, or drop it?

                **3. Projects**
                Call `omnifocus_get_project_counts` and `omnifocus_list_projects`. Flag any stalled projects (active but no next action). Offer to add a next action for each stalled project.

                After each section, pause and let the user respond before moving on. Keep the tone practical and focused on clearing blockers.
                """
        default:
            throw MCPError.invalidParams("Unknown prompt: \(name)")
        }

        return [
            "description": prompt.description,
            "messages": [
                ["role": "user", "content": ["type": "text", "text": text]]
            ]
        ]
    }

    // MARK: - Logging

    func sendLog(level: String, data: String, logger: String = "omnifocus-mcp", context: RequestContext) {
        let effectiveLevel: String?
        switch context.era {
        case .modern:
            effectiveLevel = context.requestLogLevel
        case .legacy:
            effectiveLevel = logLevel
        }
        guard let effectiveLevel else { return }
        let levelIndex = MCPServer.logLevelOrder.firstIndex(of: level) ?? 0
        let currentIndex = MCPServer.logLevelOrder.firstIndex(of: effectiveLevel) ?? 0
        guard levelIndex >= currentIndex else { return }
        sendNotification(method: "notifications/message", params: [
            "level": level,
            "logger": logger,
            "data": data
        ])
    }

    // MARK: - Sampling

    func createSamplingMessage(messages: [[String: Any]], maxTokens: Int, systemPrompt: String? = nil) throws -> [String: Any] {
        guard clientSupportsSampling else {
            throw MCPError.invalidRequest("Client does not support sampling")
        }

        let requestId = nextRequestId
        nextRequestId += 1

        var params: [String: Any] = [
            "messages": messages,
            "maxTokens": maxTokens
        ]
        if let systemPrompt { params["systemPrompt"] = systemPrompt }

        send([
            "jsonrpc": "2.0",
            "id": requestId,
            "method": "sampling/createMessage",
            "params": params
        ])

        // Read from stdin until we get our response, handling other messages inline
        let deadline = Date().addingTimeInterval(60)
        while Date() < deadline {
            guard let lineData = readNextLine() else {
                throw MCPError.scriptError("Connection closed while waiting for sampling response")
            }
            guard let line = String(data: lineData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !line.isEmpty,
                  let jsonObject = try? JSONSerialization.jsonObject(with: Data(line.utf8), options: []),
                  let msg = jsonObject as? [String: Any] else {
                continue
            }

            if let responseId = msg["id"] as? Int, responseId == requestId {
                if let error = msg["error"] as? [String: Any] {
                    throw MCPError.scriptError(error["message"] as? String ?? "Sampling request failed")
                }
                if let result = msg["result"] as? [String: Any] {
                    return result
                }
                throw MCPError.scriptError("Invalid sampling response")
            }

            handleLine(lineData)
        }
        throw MCPError.scriptError("Sampling request timed out")
    }

    // MARK: - Protocol Helpers

    func sendToolErrorResult(id: Any?, message: String, context: RequestContext) {
        let response: [String: Any] = [
            "content": [["type": "text", "text": message]],
            "structuredContent": ["message": message],
            "isError": true
        ]
        sendResult(id: id, result: response, context: context)
    }

    func structuredContent(from resultValue: Any, jsonText: String) -> Any? {
        if JSONSerialization.isValidJSONObject(resultValue) {
            return resultValue
        }
        if resultValue is NSNumber || resultValue is Bool || resultValue is NSNull {
            return resultValue
        }
        if let data = jsonText.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) {
            return parsed
        }
        return jsonText
    }

    func buildToolsListResult(params: [String: Any]?) throws -> [String: Any] {
        let pageSize = resolvedToolsPageSize()
        let cursor = params?["cursor"]
        let start: Int
        if let cursorString = cursor as? String {
            guard let parsed = Int(cursorString), parsed >= 0 else {
                throw MCPError.invalidParams("Invalid cursor for tools/list")
            }
            start = parsed
        } else if cursor == nil || cursor is NSNull {
            start = 0
        } else {
            throw MCPError.invalidParams("Invalid cursor for tools/list")
        }

        guard start <= engine.tools.count else {
            throw MCPError.invalidParams("Cursor out of range for tools/list")
        }

        let end = min(start + pageSize, engine.tools.count)
        let page = Array(engine.tools[start..<end])
        let toolEntries = page.map { $0.mcpListEntry() }

        var result: [String: Any] = ["tools": toolEntries]
        if end < engine.tools.count {
            result["nextCursor"] = String(end)
        }
        return result
    }

    func resolvedToolsPageSize() -> Int {
        let env = ProcessInfo.processInfo.environment["OF_MCP_TOOLS_PAGE_SIZE"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let env, let pageSize = Int(env), pageSize > 0 {
            return pageSize
        }
        return defaultToolsPageSize
    }

    // MARK: - Transport

    func sendResult(id: Any?, result: [String: Any], context: RequestContext, cacheable: Bool = false) {
        guard let responseId = id else {
            return
        }
        var result = result
        if context.era == .modern {
            if result["resultType"] == nil {
                result["resultType"] = "complete"
            }
            var meta = result["_meta"] as? [String: Any] ?? [:]
            meta["io.modelcontextprotocol/serverInfo"] = serverInfoObject
            result["_meta"] = meta
            if cacheable {
                if result["ttlMs"] == nil {
                    result["ttlMs"] = listCacheTtlMs
                }
                if result["cacheScope"] == nil {
                    result["cacheScope"] = "public"
                }
            }
        }
        send([
            "jsonrpc": "2.0",
            "id": responseId,
            "result": result
        ])
    }

    func sendUnsupportedProtocolVersion(id: Any?, requested: String) {
        sendError(
            id: id,
            code: -32022,
            message: "Unsupported protocol version",
            data: [
                "supported": supportedProtocolVersions,
                "requested": requested
            ]
        )
    }

    func sendError(id: Any?, code: Int, message: String, data: Any? = nil) {
        var errorObject: [String: Any] = ["code": code, "message": message]
        if let data = data { errorObject["data"] = data }
        send([
            "jsonrpc": "2.0",
            "id": id ?? NSNull(),
            "error": errorObject
        ])
    }

    func sendNotification(method: String, params: [String: Any]) {
        send([
            "jsonrpc": "2.0",
            "method": method,
            "params": params
        ])
    }

    func send(_ payload: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.withoutEscapingSlashes]) else {
            return
        }
        stdout.write(data)
        stdout.write(Data([0x0A]))
    }
}
