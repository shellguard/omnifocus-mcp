import Foundation

@main
struct OmniFocusMCPServer {
    static func main() {
        let server = MCPServer()
        server.run()
    }
}

final class MCPServer {
    static let destructiveScriptRegex: NSRegularExpression = {
        let keywords = ["delete", "remove", "drop", "markComplete", "markIncomplete", "cleanUp"]
        let dotPatterns = keywords.map { "\\.\($0)\\s*\\(" }
        let bracketPatterns = keywords.map { "\\[['\"]\\s*\($0)\\s*['\"]\\]\\s*\\(" }
        let namedPatterns = [
            "\\bdeleteObject\\s*\\(", "\\bcleanUp\\s*\\(",
            "\\bconvertTasksToProjects\\s*\\(", "\\bmoveSections\\s*\\(",
            "\\bmoveTags\\s*\\(", "\\bduplicateSections\\s*\\(",
            "Task\\.byParsingTransportText\\s*\\(",
            "\\bcopyTasksToPasteboard\\s*\\(", "\\bpasteTasksFromPasteboard\\s*\\("
        ]
        let combined = (dotPatterns + bracketPatterns + namedPatterns).joined(separator: "|")
        return try! NSRegularExpression(pattern: combined, options: [])
    }()

    let tools = allTools
    let stdout = FileHandle.standardOutput
    let stdin = FileHandle.standardInput
    var automationBackendProbe: (available: Bool, time: Date)?

    let maxBufferSize = 10 * 1024 * 1024 // 10 MB

    func run() {
        var buffer = Data()
        while true {
            let chunk = stdin.availableData
            if chunk.isEmpty {
                break
            }
            buffer.append(chunk)
            if buffer.count > maxBufferSize {
                sendError(id: nil, code: -32600, message: "Request too large", data: "Input exceeds \(maxBufferSize) byte limit")
                buffer.removeAll()
                continue
            }
            while let range = buffer.range(of: Data([0x0A])) {
                let lineData = buffer.subdata(in: buffer.startIndex..<range.lowerBound)
                buffer.removeSubrange(buffer.startIndex...range.lowerBound)
                handleLine(lineData)
            }
        }
        if !buffer.isEmpty {
            handleLine(buffer)
        }
    }

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
        let method = message["method"] as? String

        if method == nil {
            throw MCPError.invalidRequest("Missing method")
        }

        switch method {
        case "initialize":
            let result: [String: Any] = [
                "protocolVersion": "2024-11-05",
                "capabilities": ["tools": [String: Any]()],
                "serverInfo": ["name": "omnifocus-mcp", "version": "0.2.0"]
            ]
            sendResult(id: id, result: result)
        case "tools/list":
            let toolEntries = tools.map { tool -> [String: Any] in
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
            sendResult(id: id, result: ["tools": toolEntries])
        case "tools/call":
            guard let params = message["params"] as? [String: Any],
                  let toolName = params["name"] as? String else {
                throw MCPError.invalidParams("Missing tool name")
            }
            let arguments = params["arguments"] as? [String: Any] ?? [String: Any]()
            let resultValue = try callTool(named: toolName, arguments: arguments)
            let jsonText: String
            if let str = resultValue as? String {
                jsonText = str
            } else if JSONSerialization.isValidJSONObject(resultValue),
                      let jsonData = try? JSONSerialization.data(withJSONObject: resultValue, options: [.sortedKeys]),
                      let encoded = String(data: jsonData, encoding: .utf8) {
                jsonText = encoded
            } else {
                jsonText = "{}"
            }
            let response: [String: Any] = [
                "content": [["type": "text", "text": jsonText]]
            ]
            sendResult(id: id, result: response)
        case "initialized", "shutdown", "exit":
            return
        default:
            throw MCPError.methodNotFound("Unknown method: \(method ?? "")")
        }
    }

    static let toolNameToAction: [String: String] = [
        "omnifocus_convert_task_to_project": "convert_to_project"
    ]

    func callTool(named name: String, arguments: [String: Any]) throws -> Any {
        // Special case: eval_automation has inline safety logic
        if name == "omnifocus_eval_automation" {
            guard let script = arguments["script"] as? String else {
                throw MCPError.invalidParams("Missing script")
            }
            let allowDestructive = arguments["allowDestructive"] as? Bool ?? false
            if !allowDestructive {
                if MCPServer.destructiveScriptRegex.firstMatch(in: script, options: [], range: NSRange(script.startIndex..., in: script)) != nil {
                    throw MCPError.invalidParams(
                        "Script contains destructive operations. Use the dedicated MCP tools for delete/drop/move/complete operations, or pass allowDestructive: true to override this safety check."
                    )
                }
            }
            let parseJson = arguments["parseJson"] as? Bool ?? true
            return try runOmniAutomationScript(script, parseJson: parseJson)
        }
        // All other tools: derive action name from tool name
        guard name.hasPrefix("omnifocus_"),
              tools.contains(where: { $0.name == name }) else {
            throw MCPError.toolNotFound(name)
        }
        let action = MCPServer.toolNameToAction[name]
            ?? String(name.dropFirst("omnifocus_".count))
        return try callAction(action, params: arguments)
    }

    func callAction(_ action: String, params: [String: Any]) throws -> Any {
        let payload: [String: Any] = ["action": action, "params": params]
        let backend = preferredBackend()
        switch backend {
        case .automation:
            let jsonData = try JSONSerialization.data(withJSONObject: payload, options: [])
            guard let jsonString = String(data: jsonData, encoding: .utf8) else {
                throw MCPError.scriptError("Unable to encode input JSON")
            }
            let script = omniAutomationScript.replacingOccurrences(of: "__OF_INPUT_JSON__", with: javaScriptStringLiteral(jsonString))
            return try runOmniAutomationScript(script, parseJson: true)
        case .jxa:
            return try runJXAScript(payload)
        }
    }

    func runJXAScript(_ payload: [String: Any]) throws -> Any {
        let jsonData = try JSONSerialization.data(withJSONObject: payload, options: [])
        guard let jsonString = String(data: jsonData, encoding: .utf8) else {
            throw MCPError.scriptError("Unable to encode input JSON")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-l", "JavaScript", "-e", jxaScript]

        var environment = ProcessInfo.processInfo.environment
        environment["OF_INPUT_JSON"] = jsonString
        process.environment = environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        var timedOut = false
        let timeoutItem = DispatchWorkItem { timedOut = true; process.terminate() }
        DispatchQueue.global().asyncAfter(deadline: .now() + 30, execute: timeoutItem)
        process.waitUntilExit()
        timeoutItem.cancel()

        if timedOut {
            throw MCPError.scriptError("OmniFocus script timed out after 30 seconds")
        }

        let outputData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let errorText = String(data: errorData, encoding: .utf8) ?? ""
        let outputText = String(data: outputData, encoding: .utf8) ?? ""
        let trimmedOutput = outputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedError = errorText.trimmingCharacters(in: .whitespacesAndNewlines)

        if process.terminationStatus != 0 {
            if let parsed = parseJsonIfPossible(trimmedOutput) ?? parseJsonIfPossible(trimmedError) {
                return parsed
            }
            throw MCPError.scriptError(trimmedError.isEmpty ? "OmniFocus script failed" : trimmedError)
        }

        if let parsed = parseJsonIfPossible(trimmedOutput) {
            return parsed
        }
        if trimmedOutput.isEmpty, let parsed = parseJsonIfPossible(trimmedError) {
            return parsed
        }
        if trimmedOutput.isEmpty {
            throw MCPError.scriptError(trimmedError.isEmpty ? "Empty response from OmniFocus" : trimmedError)
        }
        throw MCPError.scriptError("Unable to parse OmniFocus response")
    }

    func runOmniAutomationScript(_ script: String, parseJson: Bool) throws -> Any {
        let rawAppPath = ProcessInfo.processInfo.environment["OF_APP_PATH"] ?? "/Applications/OmniFocus.app"
        // Validate path: only allow characters safe for embedding in AppleScript string literals
        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "/._- "))
        guard rawAppPath.unicodeScalars.allSatisfy({ allowedCharacters.contains($0) }) else {
            throw MCPError.scriptError("OF_APP_PATH contains unsafe characters: \(rawAppPath)")
        }
        let appPath = rawAppPath
        let termsPath = appPath.replacingOccurrences(of: "\"", with: "\\\"")
        let appleScriptLines = [
            "using terms from application \"\(termsPath)\"",
            "on run argv",
            "set appPath to item 1 of argv",
            "set js to item 2 of argv",
            "tell application appPath",
            "try",
            "tell default document",
            "set resultValue to evaluate javascript js",
            "end tell",
            "on error",
            "set resultValue to evaluate javascript js",
            "end try",
            "end tell",
            "return resultValue",
            "end run",
            "end using terms from"
        ]

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = appleScriptLines.flatMap { ["-e", $0] } + [appPath, script]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        var timedOut = false
        let timeoutItem = DispatchWorkItem { timedOut = true; process.terminate() }
        DispatchQueue.global().asyncAfter(deadline: .now() + 30, execute: timeoutItem)
        process.waitUntilExit()
        timeoutItem.cancel()

        if timedOut {
            throw MCPError.scriptError("OmniFocus script timed out after 30 seconds")
        }

        let outputData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let errorText = String(data: errorData, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            throw MCPError.scriptError(errorText.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        let outputText = String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if outputText.isEmpty {
            let trimmedError = errorText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedError.isEmpty {
                throw MCPError.scriptError(trimmedError)
            }
            return ""
        }

        if parseJson, let data = outputText.data(using: .utf8) {
            if let json = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) {
                return json
            }
        }

        return outputText
    }

    func javaScriptStringLiteral(_ value: String) -> String {
        var result = "'"
        for unit in value.utf16 {
            switch unit {
            case 0x27:
                result += "\\'"
            case 0x5C:
                result += "\\\\"
            case 0x0A:
                result += "\\n"
            case 0x0D:
                result += "\\r"
            case 0x09:
                result += "\\t"
            default:
                if unit < 0x20 || unit > 0x7E {
                    result += String(format: "\\u%04X", unit)
                } else if let scalar = UnicodeScalar(unit) {
                    result.append(Character(scalar))
                }
            }
        }
        result += "'"
        return result
    }

    func parseJsonIfPossible(_ text: String) -> Any? {
        guard !text.isEmpty, let data = text.data(using: .utf8) else {
            return nil
        }
        return try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    enum BackendChoice {
        case automation
        case jxa
    }

    func preferredBackend() -> BackendChoice {
        if let forced = ProcessInfo.processInfo.environment["OF_BACKEND"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            if forced == "jxa" || forced == "applescript" {
                return .jxa
            }
            if forced == "automation" || forced == "omnijs" || forced == "omni-automation" {
                return .automation
            }
        }
        if isAutomationBackendAvailable() {
            return .automation
        }
        return .jxa
    }

    func isAutomationBackendAvailable() -> Bool {
        // Re-probe every 5 minutes in case OmniFocus was restarted
        if let probe = automationBackendProbe, Date().timeIntervalSince(probe.time) < 300 {
            return probe.available
        }
        let probeScript = "JSON.stringify({hasDatabase: (typeof database !== 'undefined') || (typeof document !== 'undefined' && document && typeof document.database !== 'undefined') || (typeof flattenedProjects !== 'undefined') || (typeof moveSections !== 'undefined')})"
        if let result = try? runOmniAutomationScript(probeScript, parseJson: true),
           let dict = result as? [String: Any],
           let hasDatabase = dict["hasDatabase"] as? Bool {
            automationBackendProbe = (hasDatabase, Date())
            return hasDatabase
        }
        automationBackendProbe = (false, Date())
        return false
    }

    func sendResult(id: Any?, result: [String: Any]) {
        guard let responseId = id else {
            return
        }
        let response: [String: Any] = [
            "jsonrpc": "2.0",
            "id": responseId,
            "result": result
        ]
        send(response)
    }

    func sendError(id: Any?, code: Int, message: String, data: Any? = nil) {
        var errorObject: [String: Any] = ["code": code, "message": message]
        if let data = data { errorObject["data"] = data }
        let response: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id ?? NSNull(),
            "error": errorObject
        ]
        send(response)
    }

    func send(_ payload: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: []) else {
            return
        }
        stdout.write(data)
        stdout.write(Data([0x0A]))
    }
}
