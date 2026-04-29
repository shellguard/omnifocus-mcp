import Foundation
import OmniFocusCore

@main
struct OmniFocusMCPServer {
    static func main() {
        let server = MCPServer()
        server.run()
    }
}

final class MCPServer {
    let engine = OFEngine()
    let stdout = FileHandle.standardOutput
    let stdin = FileHandle.standardInput

    let maxBufferSize = 10 * 1024 * 1024 // 10 MB
    let serverVersion = "0.7.0"
    let supportedProtocolVersions = ["2025-11-25", "2025-06-18", "2024-11-05"]
    let defaultToolsPageSize = 100

    // Logging
    static let logLevelOrder = ["debug", "info", "notice", "warning", "error", "critical", "alert", "emergency"]
    var logLevel: String = "warning"

    // Sampling
    var clientSupportsSampling = false
    private var nextRequestId = 1

    // Shared read buffer (extracted from run() to support bidirectional reads)
    private var buffer = Data()

    // Prompts
    struct Prompt {
        let name: String
        let description: String
        let arguments: [[String: String]]
    }

    let prompts: [Prompt] = [
        Prompt(
            name: "capture",
            description: "Capture a task to OmniFocus inbox",
            arguments: [["name": "task", "description": "Task description to capture"]]
        ),
        Prompt(
            name: "forecast",
            description: "Show your OmniFocus forecast — overdue, today, and flagged tasks",
            arguments: []
        ),
        Prompt(
            name: "review",
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

        switch method {
        case "initialize":
            let params = message["params"] as? [String: Any] ?? [:]
            let requestedVersion = params["protocolVersion"] as? String
            let negotiatedVersion = negotiateProtocolVersion(requestedVersion)

            // Detect client sampling capability
            if let clientCaps = params["capabilities"] as? [String: Any],
               clientCaps["sampling"] != nil {
                clientSupportsSampling = true
            }

            let result: [String: Any] = [
                "protocolVersion": negotiatedVersion,
                "capabilities": [
                    "tools": [String: Any](),
                    "prompts": [String: Any](),
                    "logging": [String: Any]()
                ],
                "serverInfo": ["name": "omnifocus-mcp", "version": serverVersion]
            ]
            sendResult(id: id, result: result)

        case "tools/list":
            let params = message["params"] as? [String: Any]
            let result = try buildToolsListResult(params: params)
            sendResult(id: id, result: result)

        case "tools/call":
            guard let params = message["params"] as? [String: Any],
                  let toolName = params["name"] as? String else {
                throw MCPError.invalidParams("Missing tool name")
            }
            let arguments = params["arguments"] as? [String: Any] ?? [String: Any]()
            sendLog(level: "info", data: "Calling tool: \(toolName)")
            do {
                let resultValue = try engine.callTool(named: toolName, arguments: arguments)
                let jsonText = try OFEngine.serializeToolResult(resultValue)
                sendLog(level: "debug", data: "Tool \(toolName) completed successfully")
                let response: [String: Any] = [
                    "content": [["type": "text", "text": jsonText]]
                ]
                sendResult(id: id, result: response)
            } catch let error as MCPError {
                switch error {
                case .toolNotFound:
                    throw error
                case .invalidParams, .toolError, .scriptError:
                    sendLog(level: "error", data: "Tool \(toolName) failed: \(error.description)")
                    sendToolErrorResult(id: id, message: error.description)
                case .invalidRequest, .methodNotFound:
                    throw error
                }
            } catch {
                sendLog(level: "error", data: "Tool \(toolName) failed: \(error.localizedDescription)")
                sendToolErrorResult(id: id, message: "Internal tool execution error: \(error.localizedDescription)")
            }

        case "prompts/list":
            sendResult(id: id, result: buildPromptsListResult())

        case "prompts/get":
            guard let params = message["params"] as? [String: Any],
                  let name = params["name"] as? String else {
                throw MCPError.invalidParams("Missing prompt name")
            }
            let arguments = params["arguments"] as? [String: String] ?? [:]
            let result = try buildPromptGetResult(name: name, arguments: arguments)
            sendResult(id: id, result: result)

        case "logging/setLevel":
            guard let params = message["params"] as? [String: Any],
                  let level = params["level"] as? String else {
                throw MCPError.invalidParams("Missing log level")
            }
            guard MCPServer.logLevelOrder.contains(level) else {
                throw MCPError.invalidParams("Invalid log level: \(level)")
            }
            logLevel = level
            sendResult(id: id, result: [:])

        case "initialized", "notifications/initialized":
            return
        case "shutdown":
            sendResult(id: id, result: [:])
            return
        case "exit":
            return
        default:
            throw MCPError.methodNotFound("Unknown method: \(method ?? "")")
        }
    }

    // MARK: - Prompts

    func buildPromptsListResult() -> [String: Any] {
        let entries = prompts.map { prompt -> [String: Any] in
            var entry: [String: Any] = [
                "name": prompt.name,
                "description": prompt.description
            ]
            if !prompt.arguments.isEmpty {
                entry["arguments"] = prompt.arguments.map { arg -> [String: Any] in
                    var a: [String: Any] = ["name": arg["name"]!]
                    if let d = arg["description"] { a["description"] = d }
                    return a
                }
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
                3. **Planned today** — `plannedToday` (intended-work-date today, OmniFocus 4.7+).
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

    func sendLog(level: String, data: String, logger: String = "omnifocus-mcp") {
        let levelIndex = MCPServer.logLevelOrder.firstIndex(of: level) ?? 0
        let currentIndex = MCPServer.logLevelOrder.firstIndex(of: logLevel) ?? 0
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

            // Check if this is our response
            if let responseId = msg["id"] as? Int, responseId == requestId {
                if let error = msg["error"] as? [String: Any] {
                    throw MCPError.scriptError(error["message"] as? String ?? "Sampling request failed")
                }
                if let result = msg["result"] as? [String: Any] {
                    return result
                }
                throw MCPError.scriptError("Invalid sampling response")
            }

            // Handle other messages that arrive while waiting
            handleLine(lineData)
        }
        throw MCPError.scriptError("Sampling request timed out")
    }

    // MARK: - Protocol Helpers

    func negotiateProtocolVersion(_ requestedVersion: String?) -> String {
        guard let requestedVersion else {
            return supportedProtocolVersions[0]
        }
        if supportedProtocolVersions.contains(requestedVersion) {
            return requestedVersion
        }
        return supportedProtocolVersions[0]
    }

    func sendToolErrorResult(id: Any?, message: String) {
        let response: [String: Any] = [
            "content": [["type": "text", "text": message]],
            "isError": true
        ]
        sendResult(id: id, result: response)
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
        let toolEntries = page.map { tool -> [String: Any] in
            var entry: [String: Any] = [
                "name": tool.name,
                "description": tool.description,
                "inputSchema": tool.inputSchema
            ]
            if let annotations = tool.annotations {
                entry["annotations"] = annotations
            }
            return entry
        }

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

    func sendResult(id: Any?, result: [String: Any]) {
        guard let responseId = id else {
            return
        }
        send([
            "jsonrpc": "2.0",
            "id": responseId,
            "result": result
        ])
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
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: []) else {
            return
        }
        stdout.write(data)
        stdout.write(Data([0x0A]))
    }
}
