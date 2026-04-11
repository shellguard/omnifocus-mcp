import Foundation
import OmniFocusCore

let socketPath = (NSString("~/.omnifocus-cli.sock").expandingTildeInPath)
let pidPath = (NSString("~/.omnifocus-cli.pid").expandingTildeInPath)
let launchdLabel = "com.omnifocus-cli.daemon"
let launchdPlistPath = (NSString(string: "~/Library/LaunchAgents/\(launchdLabel).plist").expandingTildeInPath)
nonisolated(unsafe) var daemonStartTime = Date()

@main
struct OmniFocusCLI {
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())

        if args.isEmpty || args.first == "--help" || args.first == "-h" {
            printUsage()
            return
        }

        switch args.first {
        case "--daemon":
            runDaemon()
        case "--stop":
            stopDaemon()
        case "--status":
            printStatus()
        case "--install":
            installLaunchd()
        case "--uninstall":
            uninstallLaunchd()
        default:
            runCommand(args)
        }
    }

    // MARK: - Command execution

    static func runCommand(_ args: [String]) {
        let commandName = args[0]
        let toolName = "omnifocus_" + commandName.replacingOccurrences(of: "-", with: "_")

        guard let tool = allTools.first(where: { $0.name == toolName }) else {
            fputs("Error: unknown command '\(commandName)'\n", stderr)
            fputs("Run 'omnifocus-cli --help' for a list of commands.\n", stderr)
            exit(1)
        }

        let flagArgs = Array(args.dropFirst())

        if flagArgs.contains("--help") || flagArgs.contains("-h") {
            printCommandHelp(tool)
            return
        }

        let arguments: [String: Any]
        do {
            arguments = try parseArguments(flagArgs, schema: tool.inputSchema)
        } catch {
            fputs("Error: \(error.localizedDescription)\n", stderr)
            exit(1)
        }

        // Try daemon first, fall back to direct execution
        if let result = sendToDaemon(toolName: toolName, arguments: arguments) {
            print(result)
        } else {
            let engine = OFEngine()
            do {
                let result = try engine.callTool(named: toolName, arguments: arguments)
                let output = formatOutput(result)
                print(output)
            } catch {
                fputs("Error: \(error)\n", stderr)
                exit(1)
            }
        }
    }

    // MARK: - Daemon server

    static func runDaemon() {
        daemonStartTime = Date()
        // Remove stale socket
        unlink(socketPath)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            fputs("Error: failed to create socket\n", stderr)
            exit(1)
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutablePointer(to: &addr.sun_path) { pathPtr in
            pathPtr.withMemoryRebound(to: CChar.self, capacity: 104) { buf in
                _ = socketPath.withCString { strncpy(buf, $0, 103) }
            }
        }

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                bind(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else {
            fputs("Error: failed to bind socket at \(socketPath): \(String(cString: strerror(errno)))\n", stderr)
            close(fd)
            exit(1)
        }

        // Restrict socket to owner only (0600)
        chmod(socketPath, 0o600)

        guard listen(fd, 8) == 0 else {
            fputs("Error: failed to listen on socket\n", stderr)
            close(fd)
            exit(1)
        }

        // Write PID file
        try? "\(ProcessInfo.processInfo.processIdentifier)".write(toFile: pidPath, atomically: true, encoding: .utf8)

        let engine = OFEngine()
        fputs("omnifocus-cli daemon started (pid \(ProcessInfo.processInfo.processIdentifier), socket \(socketPath))\n", stderr)

        // Clean shutdown on signals
        let shutdownHandler: @convention(c) (Int32) -> Void = { _ in
            unlink(socketPath)
            unlink(pidPath)
            exit(0)
        }
        signal(SIGTERM, shutdownHandler)
        signal(SIGINT, shutdownHandler)

        while true {
            var clientAddr = sockaddr_un()
            var clientLen = socklen_t(MemoryLayout<sockaddr_un>.size)
            let clientFd = withUnsafeMutablePointer(to: &clientAddr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                    accept(fd, sockPtr, &clientLen)
                }
            }
            guard clientFd >= 0 else { continue }

            // Handle each connection in a background thread
            DispatchQueue.global().async {
                handleClient(clientFd, engine: engine)
            }
        }
    }

    static func handleClient(_ fd: Int32, engine: OFEngine) {
        defer { close(fd) }

        // Read until newline
        var buffer = Data()
        var byte: UInt8 = 0
        while recv(fd, &byte, 1, 0) == 1 {
            if byte == 0x0A { break }
            buffer.append(byte)
            if buffer.count > 1_048_576 { return } // 1MB limit
        }

        guard !buffer.isEmpty,
              let request = try? JSONSerialization.jsonObject(with: buffer, options: []) as? [String: Any],
              let command = request["command"] as? String else {
            writeResponse(fd, error: "Invalid request")
            return
        }

        // Special commands
        if command == "__shutdown__" {
            let response: [String: Any] = ["ok": true]
            writeResponse(fd, result: response)
            unlink(socketPath)
            unlink(pidPath)
            exit(0)
        }

        if command == "__status__" {
            let uptime = Int(Date().timeIntervalSince(daemonStartTime))
            let response: [String: Any] = [
                "pid": ProcessInfo.processInfo.processIdentifier,
                "uptime": uptime,
                "socket": socketPath
            ]
            writeResponse(fd, result: response)
            return
        }

        let arguments = request["arguments"] as? [String: Any] ?? [:]

        do {
            let result = try engine.callTool(named: command, arguments: arguments)
            let jsonText = try OFEngine.serializeToolResult(result)
            writeResponse(fd, result: ["data": jsonText])
        } catch {
            writeResponse(fd, error: "\(error)")
        }
    }

    static func writeResponse(_ fd: Int32, result: Any) {
        let envelope: [String: Any] = ["ok": true, "result": result]
        guard let data = try? JSONSerialization.data(withJSONObject: envelope, options: []),
              var payload = String(data: data, encoding: .utf8) else { return }
        payload += "\n"
        _ = payload.withCString { send(fd, $0, strlen($0), 0) }
    }

    static func writeResponse(_ fd: Int32, error: String) {
        let envelope: [String: Any] = ["ok": false, "error": error]
        guard let data = try? JSONSerialization.data(withJSONObject: envelope, options: []),
              var payload = String(data: data, encoding: .utf8) else { return }
        payload += "\n"
        _ = payload.withCString { send(fd, $0, strlen($0), 0) }
    }

    static func setRecvTimeout(_ fd: Int32, seconds: Int) {
        var tv = timeval(tv_sec: seconds, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
    }

    // MARK: - Socket client

    static func sendToDaemon(toolName: String, arguments: [String: Any]) -> String? {
        guard FileManager.default.fileExists(atPath: socketPath) else { return nil }

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutablePointer(to: &addr.sun_path) { pathPtr in
            pathPtr.withMemoryRebound(to: CChar.self, capacity: 104) { buf in
                _ = socketPath.withCString { strncpy(buf, $0, 103) }
            }
        }

        let connectResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connectResult == 0 else { return nil }

        setRecvTimeout(fd, seconds: 60)

        // Send request
        var request: [String: Any] = ["command": toolName]
        if !arguments.isEmpty { request["arguments"] = arguments }
        guard let data = try? JSONSerialization.data(withJSONObject: request, options: []),
              var payload = String(data: data, encoding: .utf8) else { return nil }
        payload += "\n"
        let sent = payload.withCString { send(fd, $0, strlen($0), 0) }
        guard sent > 0 else { return nil }

        // Read response
        var buffer = Data()
        var byte: UInt8 = 0
        while recv(fd, &byte, 1, 0) == 1 {
            if byte == 0x0A { break }
            buffer.append(byte)
            if buffer.count > 10_485_760 { return nil } // 10MB limit
        }

        guard !buffer.isEmpty,
              let response = try? JSONSerialization.jsonObject(with: buffer, options: []) as? [String: Any] else {
            return nil
        }

        guard response["ok"] as? Bool == true else {
            let errMsg = response["error"] as? String ?? "Unknown daemon error"
            fputs("Error: \(errMsg)\n", stderr)
            exit(1)
        }

        guard let result = response["result"] else { return nil }
        return formatOutput(result)
    }

    static func sendDaemonCommand(_ command: String) -> [String: Any]? {
        guard FileManager.default.fileExists(atPath: socketPath) else { return nil }

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutablePointer(to: &addr.sun_path) { pathPtr in
            pathPtr.withMemoryRebound(to: CChar.self, capacity: 104) { buf in
                _ = socketPath.withCString { strncpy(buf, $0, 103) }
            }
        }

        let connectResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connectResult == 0 else { return nil }

        setRecvTimeout(fd, seconds: 5)

        let request: [String: Any] = ["command": command]
        guard let data = try? JSONSerialization.data(withJSONObject: request, options: []),
              var payload = String(data: data, encoding: .utf8) else { return nil }
        payload += "\n"
        _ = payload.withCString { send(fd, $0, strlen($0), 0) }

        var buffer = Data()
        var byte: UInt8 = 0
        while recv(fd, &byte, 1, 0) == 1 {
            if byte == 0x0A { break }
            buffer.append(byte)
        }

        guard !buffer.isEmpty else { return nil }
        return try? JSONSerialization.jsonObject(with: buffer, options: []) as? [String: Any]
    }

    // MARK: - Daemon control

    static func stopDaemon() {
        if let response = sendDaemonCommand("__shutdown__"), response["ok"] as? Bool == true {
            print("Daemon stopped.")
        } else if FileManager.default.fileExists(atPath: pidPath),
                  let pidStr = try? String(contentsOfFile: pidPath, encoding: .utf8),
                  let pid = Int32(pidStr.trimmingCharacters(in: .whitespacesAndNewlines)) {
            kill(pid, SIGTERM)
            unlink(socketPath)
            unlink(pidPath)
            print("Daemon killed (pid \(pid)).")
        } else {
            fputs("No daemon running.\n", stderr)
            exit(1)
        }
    }

    static func printStatus() {
        if let response = sendDaemonCommand("__status__"),
           let result = response["result"] as? [String: Any],
           let pid = result["pid"] as? Int {
            let uptime = result["uptime"] as? Int ?? 0
            let hours = uptime / 3600
            let minutes = (uptime % 3600) / 60
            let seconds = uptime % 60
            print("Daemon running (pid \(pid), uptime \(hours)h\(minutes)m\(seconds)s)")
            print("Socket: \(socketPath)")
        } else {
            print("Daemon not running.")
        }
    }

    // MARK: - launchd integration

    static func installLaunchd() {
        let binaryPath = CommandLine.arguments[0]
        // Resolve to absolute path
        let resolvedPath: String
        if binaryPath.hasPrefix("/") {
            resolvedPath = binaryPath
        } else {
            resolvedPath = FileManager.default.currentDirectoryPath + "/" + binaryPath
        }

        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(launchdLabel)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(resolvedPath)</string>
                <string>--daemon</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <true/>
            <key>StandardErrorPath</key>
            <string>/tmp/omnifocus-cli-daemon.log</string>
        </dict>
        </plist>
        """

        do {
            try plist.write(toFile: launchdPlistPath, atomically: true, encoding: .utf8)
        } catch {
            fputs("Error: failed to write plist: \(error)\n", stderr)
            exit(1)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["load", launchdPlistPath]
        try? process.run()
        process.waitUntilExit()

        if process.terminationStatus == 0 {
            print("Daemon installed and started.")
            print("  Plist: \(launchdPlistPath)")
            print("  Binary: \(resolvedPath)")
            print("  Log: /tmp/omnifocus-cli-daemon.log")
        } else {
            fputs("Warning: plist written but launchctl load failed.\n", stderr)
            fputs("  Try: launchctl load \(launchdPlistPath)\n", stderr)
        }
    }

    static func uninstallLaunchd() {
        // Stop daemon first
        let _ = sendDaemonCommand("__shutdown__")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["unload", launchdPlistPath]
        try? process.run()
        process.waitUntilExit()

        if FileManager.default.fileExists(atPath: launchdPlistPath) {
            try? FileManager.default.removeItem(atPath: launchdPlistPath)
        }

        unlink(socketPath)
        unlink(pidPath)
        print("Daemon uninstalled.")
    }

    // MARK: - Argument parsing

    static func parseArguments(_ args: [String], schema: [String: Any]) throws -> [String: Any] {
        let properties = schema["properties"] as? [String: Any] ?? [:]
        var result = [String: Any]()
        var i = 0
        while i < args.count {
            let arg = args[i]
            guard arg.hasPrefix("--") else {
                throw CLIError.unexpectedArgument(arg)
            }
            let key = String(arg.dropFirst(2))
            let camelKey = toCamelCase(key)

            guard let propSchema = properties[camelKey] ?? properties[key] else {
                throw CLIError.unknownFlag(arg)
            }

            let propDict = propSchema as? [String: Any] ?? [:]
            let type = propDict["type"] as? String ?? "string"

            switch type {
            case "boolean":
                if i + 1 < args.count && !args[i + 1].hasPrefix("--") {
                    let val = args[i + 1].lowercased()
                    if val == "true" || val == "false" {
                        result[camelKey.isEmpty ? key : camelKey] = val == "true"
                        i += 2
                        continue
                    }
                }
                result[camelKey.isEmpty ? key : camelKey] = true
                i += 1
            case "integer":
                guard i + 1 < args.count else {
                    throw CLIError.missingValue(arg)
                }
                guard let intVal = Int(args[i + 1]) else {
                    throw CLIError.invalidValue(arg, args[i + 1], "integer")
                }
                result[camelKey.isEmpty ? key : camelKey] = intVal
                i += 2
            case "array":
                guard i + 1 < args.count else {
                    throw CLIError.missingValue(arg)
                }
                let rawValue = args[i + 1]
                let values = rawValue.contains(",") ? rawValue.split(separator: ",").map(String.init) : [rawValue]
                let finalKey = camelKey.isEmpty ? key : camelKey
                var existing = result[finalKey] as? [String] ?? []
                existing.append(contentsOf: values)
                result[finalKey] = existing
                i += 2
            case "object":
                guard i + 1 < args.count else {
                    throw CLIError.missingValue(arg)
                }
                let jsonStr = args[i + 1]
                guard let data = jsonStr.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
                    throw CLIError.invalidValue(arg, jsonStr, "JSON object")
                }
                result[camelKey.isEmpty ? key : camelKey] = obj
                i += 2
            default: // string
                guard i + 1 < args.count else {
                    throw CLIError.missingValue(arg)
                }
                result[camelKey.isEmpty ? key : camelKey] = args[i + 1]
                i += 2
            }
        }
        return result
    }

    // MARK: - Formatting

    static func toCamelCase(_ kebab: String) -> String {
        let parts = kebab.split(separator: "-")
        if parts.count <= 1 { return kebab }
        return String(parts[0]) + parts.dropFirst().map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined()
    }

    static func formatOutput(_ value: Any) -> String {
        if let str = value as? String {
            if let data = str.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
               let pretty = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
               let result = String(data: pretty, encoding: .utf8) {
                return result
            }
            return str
        }
        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]),
           let result = String(data: data, encoding: .utf8) {
            return result
        }
        return "\(value)"
    }

    // MARK: - Help

    static func printUsage() {
        print("Usage: omnifocus-cli <command> [--key value ...]")
        print("")
        print("Commands:")

        var groups = [(label: String, tools: [ToolDefinition])]()
        var seen = Set<String>()

        let prefixes: [(String, String)] = [
            ("list", "List"),
            ("get", "Get"),
            ("search", "Search"),
            ("create", "Create"),
            ("update", "Update"),
            ("set", "Set"),
            ("move", "Move"),
            ("delete", "Delete"),
            ("complete", "Complete / Drop"),
            ("uncomplete", "Uncomplete"),
            ("duplicate", "Duplicate"),
            ("mark", "Review"),
            ("add", "Add"),
            ("remove", "Remove"),
        ]

        for (prefix, label) in prefixes {
            let matching = allTools.filter { tool in
                let cmd = commandName(for: tool)
                return cmd.hasPrefix(prefix) && !seen.contains(tool.name)
            }
            if !matching.isEmpty {
                groups.append((label, matching))
                matching.forEach { seen.insert($0.name) }
            }
        }

        let remaining = allTools.filter { !seen.contains($0.name) }
        if !remaining.isEmpty {
            groups.append(("Other", remaining))
        }

        for group in groups {
            print("")
            print("  \(group.label):")
            for tool in group.tools {
                let cmd = commandName(for: tool)
                print("    \(pad(cmd, to: 32)) \(tool.description)")
            }
        }

        print("")
        print("Daemon mode:")
        print("  --daemon                       Start background daemon (faster repeated calls)")
        print("  --stop                         Stop the running daemon")
        print("  --status                       Check if daemon is running")
        print("  --install                      Install as launchd service (auto-start at login)")
        print("  --uninstall                    Remove launchd service")
        print("")
        print("Run 'omnifocus-cli <command> --help' for command details.")
        print("")
        print("Environment variables:")
        print("  OF_BACKEND=jxa|automation    Force backend (default: auto-detect)")
        print("  OF_APP_PATH=<path>           OmniFocus app path")
    }

    static func printCommandHelp(_ tool: ToolDefinition) {
        let cmd = commandName(for: tool)
        print("Usage: omnifocus-cli \(cmd) [options]")
        print("")
        print(tool.description)

        let properties = tool.inputSchema["properties"] as? [String: Any] ?? [:]
        let required = Set(tool.inputSchema["required"] as? [String] ?? [])

        if properties.isEmpty {
            print("")
            print("  No parameters.")
            return
        }

        print("")
        print("Options:")
        for key in properties.keys.sorted() {
            guard let propDict = properties[key] as? [String: Any] else { continue }
            let type = propDict["type"] as? String ?? "string"
            let isRequired = required.contains(key)
            let flag = "--\(toKebabCase(key))"

            var desc = ""
            if let d = propDict["description"] as? String { desc = d }
            if let enumVals = propDict["enum"] as? [String] {
                desc += (desc.isEmpty ? "" : " ") + "[\(enumVals.joined(separator: "|"))]"
            }

            let reqTag = isRequired ? " (required)" : ""
            print("    \(pad(flag, to: 32)) \(type)\(reqTag)  \(desc)")
        }
    }

    static func commandName(for tool: ToolDefinition) -> String {
        String(tool.name.dropFirst("omnifocus_".count)).replacingOccurrences(of: "_", with: "-")
    }

    static func toKebabCase(_ camel: String) -> String {
        var result = ""
        for ch in camel {
            if ch.isUppercase && !result.isEmpty {
                result += "-"
            }
            result += ch.lowercased()
        }
        return result
    }

    static func pad(_ s: String, to width: Int) -> String {
        s.count >= width ? s : s + String(repeating: " ", count: width - s.count)
    }
}

enum CLIError: LocalizedError {
    case unexpectedArgument(String)
    case unknownFlag(String)
    case missingValue(String)
    case invalidValue(String, String, String)

    var errorDescription: String? {
        switch self {
        case .unexpectedArgument(let arg):
            return "Unexpected argument: \(arg)"
        case .unknownFlag(let flag):
            return "Unknown flag: \(flag)"
        case .missingValue(let flag):
            return "Missing value for \(flag)"
        case .invalidValue(let flag, let value, let expected):
            return "Invalid value '\(value)' for \(flag) (expected \(expected))"
        }
    }
}
