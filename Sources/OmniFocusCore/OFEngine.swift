import Foundation

public final class OFEngine: @unchecked Sendable {
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

    public let tools = allTools
    private let probeLock = NSLock()
    private var automationBackendProbe: (available: Bool, time: Date)?

    static let toolNameToAction: [String: String] = [
        "omnifocus_convert_task_to_project": "convert_to_project"
    ]

    public init() {}

    /// Serialize a tool result to a JSON string.
    /// Throws if the result cannot be represented as JSON.
    public static func serializeToolResult(_ result: Any) throws -> String {
        if let str = result as? String {
            return str
        }
        if JSONSerialization.isValidJSONObject(result),
           let data = try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]),
           let encoded = String(data: data, encoding: .utf8) {
            return encoded
        }
        throw MCPError.toolError("Tool returned non-serializable result of type \(type(of: result))")
    }

    public func callTool(named name: String, arguments: [String: Any]) throws -> Any {
        if name == "omnifocus_eval_automation" {
            guard let script = arguments["script"] as? String else {
                throw MCPError.invalidParams("Missing script")
            }
            let allowDestructive = arguments["allowDestructive"] as? Bool ?? false
            if !allowDestructive {
                if OFEngine.destructiveScriptRegex.firstMatch(in: script, options: [], range: NSRange(script.startIndex..., in: script)) != nil {
                    throw MCPError.invalidParams(
                        "Script matches common destructive patterns (delete/drop/remove/etc). Use the dedicated MCP tools for these operations, or pass allowDestructive: true to bypass this hint. Note: this check is a best-effort regex, not a security boundary."
                    )
                }
            }
            let parseJson = arguments["parseJson"] as? Bool ?? true
            return try runOmniAutomationScript(script, parseJson: parseJson)
        }
        guard name.hasPrefix("omnifocus_"),
              tools.contains(where: { $0.name == name }) else {
            throw MCPError.toolNotFound(name)
        }
        let action = OFEngine.toolNameToAction[name]
            ?? String(name.dropFirst("omnifocus_".count))
        return try callAction(action, params: arguments)
    }

    public func callAction(_ action: String, params: [String: Any]) throws -> Any {
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
        let timedOutFlag = NSLock()
        nonisolated(unsafe) var _timedOut = false
        let timeoutItem = DispatchWorkItem {
            timedOutFlag.lock()
            _timedOut = true
            timedOutFlag.unlock()
            process.terminate()
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 30, execute: timeoutItem)

        // Drain pipes concurrently to avoid deadlock when output exceeds pipe buffer (~64KB)
        let group = DispatchGroup()
        nonisolated(unsafe) var outputData = Data()
        nonisolated(unsafe) var errorData = Data()
        group.enter()
        DispatchQueue.global().async { outputData = stdoutPipe.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        group.enter()
        DispatchQueue.global().async { errorData = stderrPipe.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        process.waitUntilExit()
        group.wait()
        timeoutItem.cancel()

        timedOutFlag.lock()
        let timedOut = _timedOut
        timedOutFlag.unlock()
        if timedOut {
            throw MCPError.scriptError("OmniFocus script timed out after 30 seconds")
        }

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
        let timedOutFlag = NSLock()
        nonisolated(unsafe) var _timedOut = false
        let timeoutItem = DispatchWorkItem {
            timedOutFlag.lock()
            _timedOut = true
            timedOutFlag.unlock()
            process.terminate()
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 30, execute: timeoutItem)

        // Drain pipes concurrently to avoid deadlock when output exceeds pipe buffer (~64KB)
        let group = DispatchGroup()
        nonisolated(unsafe) var outputData = Data()
        nonisolated(unsafe) var errorData = Data()
        group.enter()
        DispatchQueue.global().async { outputData = stdoutPipe.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        group.enter()
        DispatchQueue.global().async { errorData = stderrPipe.fileHandleForReading.readDataToEndOfFile(); group.leave() }
        process.waitUntilExit()
        group.wait()
        timeoutItem.cancel()

        timedOutFlag.lock()
        let timedOut = _timedOut
        timedOutFlag.unlock()
        if timedOut {
            throw MCPError.scriptError("OmniFocus script timed out after 30 seconds")
        }

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
        probeLock.lock()
        if let probe = automationBackendProbe, Date().timeIntervalSince(probe.time) < 300 {
            let result = probe.available
            probeLock.unlock()
            return result
        }
        probeLock.unlock()

        let probeScript = "JSON.stringify({hasDatabase: (typeof database !== 'undefined') || (typeof document !== 'undefined' && document && typeof document.database !== 'undefined') || (typeof flattenedProjects !== 'undefined') || (typeof moveSections !== 'undefined')})"
        if let result = try? runOmniAutomationScript(probeScript, parseJson: true),
           let dict = result as? [String: Any],
           let hasDatabase = dict["hasDatabase"] as? Bool {
            probeLock.lock()
            automationBackendProbe = (hasDatabase, Date())
            probeLock.unlock()
            return hasDatabase
        }
        probeLock.lock()
        automationBackendProbe = (false, Date())
        probeLock.unlock()
        return false
    }
}
