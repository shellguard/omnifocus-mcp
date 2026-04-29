import Foundation
import OmniFocusCore

let socketPath = (NSString("~/.omnifocus-cli.sock").expandingTildeInPath)
let pidPath = (NSString("~/.omnifocus-cli.pid").expandingTildeInPath)
let launchdLabel = "com.omnifocus-cli.daemon"
let launchdPlistPath = (NSString(string: "~/Library/LaunchAgents/\(launchdLabel).plist").expandingTildeInPath)
let launchdLogPath = "/tmp/omnifocus-cli-daemon.log"
nonisolated(unsafe) var daemonStartTime = Date()
nonisolated(unsafe) var signalSocketPath: UnsafeMutablePointer<CChar>?
nonisolated(unsafe) var signalPidPath: UnsafeMutablePointer<CChar>?

private let signalShutdownHandler: @convention(c) (Int32) -> Void = { _ in
    if let p = signalSocketPath { unlink(p) }
    if let p = signalPidPath { unlink(p) }
    _exit(0)
}

struct OutputOptions {
    var compact = false
    var ndjson = false
    var quiet = false
}

@main
struct OmniFocusCLI {
    nonisolated(unsafe) static var cachedStdin: String?

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

        var flagArgs = Array(args.dropFirst())

        if flagArgs.contains("--help") || flagArgs.contains("-h") {
            printCommandHelp(tool)
            return
        }

        // Strip global output flags (--compact / --ndjson / --quiet) and
        // global input flag (--args-json). What remains is per-tool flags.
        let outputOpts = extractOutputFlags(&flagArgs)
        let preset: [String: Any]
        do {
            preset = try extractArgsJson(&flagArgs)
        } catch {
            fputs("Error: \(error.localizedDescription)\n", stderr)
            exit(1)
        }

        var arguments: [String: Any]
        do {
            arguments = try parseArguments(flagArgs, schema: tool.inputSchema)
        } catch {
            fputs("Error: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
        // Explicit flags take precedence over --args-json values
        for (k, v) in preset where arguments[k] == nil {
            arguments[k] = v
        }

        // Try daemon first, fall back to direct execution
        if let raw = sendToDaemonRaw(toolName: toolName, arguments: arguments) {
            emit(raw, options: outputOpts)
        } else {
            let engine = OFEngine()
            do {
                let result = try engine.callTool(named: toolName, arguments: arguments)
                emit(result, options: outputOpts)
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

        guard var addr = socketAddress(for: socketPath, reportErrors: true) else {
            close(fd)
            exit(1)
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
        if chmod(socketPath, 0o600) != 0 {
            fputs("Error: failed to set socket permissions: \(String(cString: strerror(errno)))\n", stderr)
            close(fd)
            exit(1)
        }

        guard listen(fd, 8) == 0 else {
            fputs("Error: failed to listen on socket\n", stderr)
            close(fd)
            exit(1)
        }

        // Write PID file
        try? "\(ProcessInfo.processInfo.processIdentifier)".write(toFile: pidPath, atomically: true, encoding: .utf8)

        let engine = OFEngine()
        fputs("omnifocus-cli daemon started (pid \(ProcessInfo.processInfo.processIdentifier), socket \(socketPath))\n", stderr)

        // Store C strings for async-signal-safe cleanup
        signalSocketPath = strdup(socketPath)
        signalPidPath = strdup(pidPath)
        signal(SIGTERM, signalShutdownHandler)
        signal(SIGINT, signalShutdownHandler)

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
        _ = payload.withCString { send(fd, $0, payload.utf8.count, 0) }
    }

    static func writeResponse(_ fd: Int32, error: String) {
        let envelope: [String: Any] = ["ok": false, "error": error]
        guard let data = try? JSONSerialization.data(withJSONObject: envelope, options: []),
              var payload = String(data: data, encoding: .utf8) else { return }
        payload += "\n"
        _ = payload.withCString { send(fd, $0, payload.utf8.count, 0) }
    }

    static func setRecvTimeout(_ fd: Int32, seconds: Int) {
        var tv = timeval(tv_sec: seconds, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
    }

    static func socketAddress(for path: String, reportErrors: Bool) -> sockaddr_un? {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let capacity = MemoryLayout.size(ofValue: addr.sun_path)
        let maxBytes = capacity - 1
        let pathBytes = path.lengthOfBytes(using: .utf8)
        guard pathBytes <= maxBytes else {
            if reportErrors {
                fputs("Error: socket path is too long (\(pathBytes) bytes). Maximum for this platform is \(maxBytes) bytes.\n", stderr)
                fputs("       Path: \(path)\n", stderr)
            }
            return nil
        }

        withUnsafeMutablePointer(to: &addr.sun_path) { pathPtr in
            pathPtr.withMemoryRebound(to: CChar.self, capacity: capacity) { buf in
                memset(buf, 0, capacity)
                _ = path.withCString { strncpy(buf, $0, maxBytes) }
            }
        }
        return addr
    }

    static func launchdDomainTarget() -> String {
        "gui/\(getuid())"
    }

    static func launchdServiceTarget() -> String {
        "\(launchdDomainTarget())/\(launchdLabel)"
    }

    static func runLaunchctl(_ arguments: [String]) -> (status: Int32, stderrText: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments

        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        process.standardOutput = Pipe()

        do {
            try process.run()
        } catch {
            return (-1, error.localizedDescription)
        }
        process.waitUntilExit()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrText = String(data: stderrData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return (process.terminationStatus, stderrText)
    }

    // MARK: - Socket client

    /// Send a tool call through the daemon socket. Returns the raw result
    /// (the inner serialized JSON string the engine produced) so the caller
    /// can format it however it wants. Returns nil if no daemon is reachable.
    static func sendToDaemonRaw(toolName: String, arguments: [String: Any]) -> Any? {
        guard FileManager.default.fileExists(atPath: socketPath) else { return nil }

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }

        guard var addr = socketAddress(for: socketPath, reportErrors: false) else { return nil }

        let connectResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connectResult == 0 else { return nil }

        setRecvTimeout(fd, seconds: 60)

        var request: [String: Any] = ["command": toolName]
        if !arguments.isEmpty { request["arguments"] = arguments }
        guard let data = try? JSONSerialization.data(withJSONObject: request, options: []),
              var payload = String(data: data, encoding: .utf8) else { return nil }
        payload += "\n"
        let sent = payload.withCString { send(fd, $0, payload.utf8.count, 0) }
        guard sent > 0 else { return nil }

        var buffer = Data()
        var byte: UInt8 = 0
        while recv(fd, &byte, 1, 0) == 1 {
            if byte == 0x0A { break }
            buffer.append(byte)
            if buffer.count > 10_485_760 { return nil }
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

        // The daemon wraps the engine result as { "data": "<json string>" }.
        // Unwrap and return the inner string so the formatter can re-parse it.
        if let result = response["result"] as? [String: Any], let dataStr = result["data"] {
            return dataStr
        }
        return response["result"]
    }

    static func sendToDaemon(toolName: String, arguments: [String: Any]) -> String? {
        guard FileManager.default.fileExists(atPath: socketPath) else { return nil }

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }

        guard var addr = socketAddress(for: socketPath, reportErrors: false) else { return nil }

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
        let sent = payload.withCString { send(fd, $0, payload.utf8.count, 0) }
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

        guard var addr = socketAddress(for: socketPath, reportErrors: false) else { return nil }

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
        _ = payload.withCString { send(fd, $0, payload.utf8.count, 0) }

        var buffer = Data()
        var byte: UInt8 = 0
        while recv(fd, &byte, 1, 0) == 1 {
            if byte == 0x0A { break }
            buffer.append(byte)
            if buffer.count > 1_048_576 { return nil } // 1MB limit
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
                  let pid = Int32(pidStr.trimmingCharacters(in: .whitespacesAndNewlines)),
                  pid > 0 {
            // Verify the PID belongs to omnifocus-cli before sending SIGTERM
            let probe = Process()
            probe.executableURL = URL(fileURLWithPath: "/bin/ps")
            probe.arguments = ["-p", "\(pid)", "-o", "comm="]
            let pipe = Pipe()
            probe.standardOutput = pipe
            probe.standardError = Pipe()
            var isOurProcess = false
            if let _ = try? probe.run() {
                probe.waitUntilExit()
                let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                isOurProcess = output.hasSuffix("omnifocus-cli")
            }
            guard isOurProcess else {
                fputs("Stale PID file (process \(pid) is not omnifocus-cli). Cleaning up.\n", stderr)
                unlink(socketPath)
                unlink(pidPath)
                return
            }
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

        let escapedPath = escapeXML(resolvedPath)

        let escapedLabel = escapeXML(launchdLabel)
        let escapedLogPath = escapeXML(launchdLogPath)

        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(escapedLabel)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(escapedPath)</string>
                <string>--daemon</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <true/>
            <key>StandardErrorPath</key>
            <string>\(escapedLogPath)</string>
        </dict>
        </plist>
        """

        do {
            try plist.write(toFile: launchdPlistPath, atomically: true, encoding: .utf8)
        } catch {
            fputs("Error: failed to write plist: \(error)\n", stderr)
            exit(1)
        }

        // Make re-installs idempotent: best-effort bootout before bootstrap.
        _ = runLaunchctl(["bootout", launchdServiceTarget()])
        let bootstrap = runLaunchctl(["bootstrap", launchdDomainTarget(), launchdPlistPath])
        if bootstrap.status == 0 {
            print("Daemon installed and started.")
            print("  Plist: \(launchdPlistPath)")
            print("  Binary: \(resolvedPath)")
            print("  Log: \(launchdLogPath)")
            return
        }

        // Older systems may still rely on load/unload style behavior.
        let legacyLoad = runLaunchctl(["load", launchdPlistPath])
        if legacyLoad.status == 0 {
            print("Daemon installed and started.")
            print("  Plist: \(launchdPlistPath)")
            print("  Binary: \(resolvedPath)")
            print("  Log: \(launchdLogPath)")
            return
        }

        fputs("Warning: plist written but launchctl bootstrap/load failed.\n", stderr)
        if !bootstrap.stderrText.isEmpty {
            fputs("  bootstrap error: \(bootstrap.stderrText)\n", stderr)
        }
        if !legacyLoad.stderrText.isEmpty {
            fputs("  load error: \(legacyLoad.stderrText)\n", stderr)
        }
        fputs("  Try: launchctl bootstrap \(launchdDomainTarget()) \(launchdPlistPath)\n", stderr)
    }

    static func uninstallLaunchd() {
        // Stop daemon first
        let _ = sendDaemonCommand("__shutdown__")

        let bootout = runLaunchctl(["bootout", launchdServiceTarget()])
        if bootout.status != 0 {
            _ = runLaunchctl(["unload", launchdPlistPath])
        }

        if FileManager.default.fileExists(atPath: launchdPlistPath) {
            try? FileManager.default.removeItem(atPath: launchdPlistPath)
        }

        unlink(socketPath)
        unlink(pidPath)
        print("Daemon uninstalled.")
    }

    // MARK: - Argument parsing

    /// Strip global output flags from the arg list and return what was set.
    static func extractOutputFlags(_ args: inout [String]) -> OutputOptions {
        var opts = OutputOptions()
        var kept: [String] = []
        kept.reserveCapacity(args.count)
        for arg in args {
            switch arg {
            case "--compact": opts.compact = true
            case "--ndjson":  opts.ndjson = true
            case "--quiet", "-q": opts.quiet = true
            default: kept.append(arg)
            }
        }
        args = kept
        return opts
    }

    /// Strip and parse `--args-json <value>` from the arg list. Value may be
    /// a JSON string, `@file`, or `-` (stdin). Returns an empty dict if absent.
    static func extractArgsJson(_ args: inout [String]) throws -> [String: Any] {
        var i = 0
        var result: [String: Any] = [:]
        var kept: [String] = []
        kept.reserveCapacity(args.count)
        while i < args.count {
            if args[i] == "--args-json" {
                guard i + 1 < args.count else {
                    throw CLIError.missingValue("--args-json")
                }
                let raw = try resolveValue(args[i + 1], flag: "--args-json")
                guard let data = raw.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
                    throw CLIError.invalidValue("--args-json", raw, "JSON object")
                }
                result.merge(obj, uniquingKeysWith: { _, new in new })
                i += 2
            } else {
                kept.append(args[i])
                i += 1
            }
        }
        args = kept
        return result
    }

    /// Resolve a flag value: literal string by default; if it begins with `@`,
    /// read the named file; if it is exactly `-`, read stdin (cached so multiple
    /// flags can share the same buffer).
    static func resolveValue(_ raw: String, flag: String) throws -> String {
        if raw == "-" {
            if let cached = cachedStdin { return cached }
            let data = FileHandle.standardInput.readDataToEndOfFile()
            let text = String(data: data, encoding: .utf8) ?? ""
            cachedStdin = text
            return text
        }
        if raw.hasPrefix("@") {
            let path = String(raw.dropFirst())
            do {
                return try String(contentsOfFile: path, encoding: .utf8)
            } catch {
                throw CLIError.invalidValue(flag, raw, "readable file path (\(error.localizedDescription))")
            }
        }
        return raw
    }

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
            let finalKey = camelKey.isEmpty ? key : camelKey

            switch type {
            case "boolean":
                if i + 1 < args.count && !args[i + 1].hasPrefix("--") {
                    let val = args[i + 1].lowercased()
                    if val == "true" || val == "false" {
                        result[finalKey] = val == "true"
                        i += 2
                        continue
                    }
                }
                result[finalKey] = true
                i += 1
            case "integer":
                guard i + 1 < args.count else {
                    throw CLIError.missingValue(arg)
                }
                let raw = try resolveValue(args[i + 1], flag: arg).trimmingCharacters(in: .whitespacesAndNewlines)
                guard let intVal = Int(raw) else {
                    throw CLIError.invalidValue(arg, raw, "integer")
                }
                result[finalKey] = intVal
                i += 2
            case "array":
                guard i + 1 < args.count else {
                    throw CLIError.missingValue(arg)
                }
                let raw = try resolveValue(args[i + 1], flag: arg)
                let parsed = try parseArrayValue(raw, flag: arg, itemSchema: propDict["items"] as? [String: Any])
                var existing = result[finalKey] as? [Any] ?? []
                existing.append(contentsOf: parsed)
                result[finalKey] = existing
                i += 2
            case "object":
                guard i + 1 < args.count else {
                    throw CLIError.missingValue(arg)
                }
                let raw = try resolveValue(args[i + 1], flag: arg)
                guard let data = raw.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
                    throw CLIError.invalidValue(arg, raw, "JSON object")
                }
                result[finalKey] = obj
                i += 2
            default: // string
                guard i + 1 < args.count else {
                    throw CLIError.missingValue(arg)
                }
                let raw = args[i + 1]
                // For string flags, only resolve @file/- if explicitly used.
                let resolved = try resolveValue(raw, flag: arg)
                // Trim a trailing newline that's almost always unwanted from
                // file/stdin reads. Argv values are unaffected (no newline).
                if raw == "-" || raw.hasPrefix("@") {
                    result[finalKey] = resolved.trimmingCharacters(in: .newlines)
                } else {
                    result[finalKey] = resolved
                }
                i += 2
            }
        }
        return result
    }

    /// Parse an array flag value. Accepts:
    /// - JSON array (any leading whitespace then `[`)
    /// - JSON Lines (multiple lines, each parses as JSON, used when items are objects or auto-detected)
    /// - One value per line (line-format, common when piped from `jq -r`)
    /// - Comma-separated (single-line, no JSON markers — argv ergonomics)
    static func parseArrayValue(_ raw: String, flag: String, itemSchema: [String: Any]?) throws -> [Any] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return [] }

        // JSON array literal
        if trimmed.first == "[" {
            guard let data = trimmed.data(using: .utf8),
                  let arr = try? JSONSerialization.jsonObject(with: data, options: []) as? [Any] else {
                throw CLIError.invalidValue(flag, raw, "JSON array")
            }
            return arr
        }

        // Multi-line content: NDJSON or line-format
        if raw.contains("\n") {
            let lines = raw.split(whereSeparator: { $0.isNewline })
                .map { String($0).trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && !$0.hasPrefix("#") }
            // If items look like JSON objects/arrays/quoted strings, parse each as JSON.
            let looksJSON = lines.first.map { line in
                ["{", "[", "\""].contains(where: { line.hasPrefix($0) })
            } ?? false
            let itemType = (itemSchema?["type"] as? String) ?? "string"
            if looksJSON || itemType == "object" {
                var out: [Any] = []
                for line in lines {
                    guard let data = line.data(using: .utf8),
                          let obj = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
                        throw CLIError.invalidValue(flag, line, "JSON value (one per line)")
                    }
                    out.append(obj)
                }
                return out
            }
            return lines.map { $0 as Any }
        }

        // Single-line: comma-separated for argv ergonomics
        if trimmed.contains(",") {
            return trimmed.split(separator: ",").map { String($0) as Any }
        }
        return [trimmed as Any]
    }

    // MARK: - Formatting

    static func toCamelCase(_ kebab: String) -> String {
        let parts = kebab.split(separator: "-")
        if parts.count <= 1 { return kebab }
        return String(parts[0]) + parts.dropFirst().map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined()
    }

    /// Print a tool's result using the requested OutputOptions.
    /// Accepts either a Swift value (from direct callTool) or a pre-serialized
    /// JSON string (from the daemon path).
    static func emit(_ value: Any, options: OutputOptions) {
        if options.quiet { return }

        // Normalise to a Swift value so we can format consistently.
        let normalised: Any = {
            if let str = value as? String,
               let data = str.data(using: .utf8),
               let parsed = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) {
                return parsed
            }
            return value
        }()

        if options.ndjson {
            if let arr = normalised as? [Any] {
                for item in arr {
                    if let line = compactJSON(item) { print(line) }
                }
            } else if let line = compactJSON(normalised) {
                print(line)
            }
            return
        }

        if options.compact {
            if let line = compactJSON(normalised) { print(line); return }
        }

        // Default: pretty-printed JSON with sorted keys (existing behavior).
        print(prettyJSON(normalised))
    }

    private static func compactJSON(_ value: Any) -> String? {
        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
           let s = String(data: data, encoding: .utf8) {
            return s
        }
        // Fragments (string/number/bool/null) — JSONSerialization only accepts
        // top-level array/object, so wrap, encode, then unwrap.
        if let data = try? JSONSerialization.data(withJSONObject: [value], options: []),
           let arrText = String(data: data, encoding: .utf8) {
            // strip leading [ and trailing ]
            return String(arrText.dropFirst().dropLast())
        }
        return nil
    }

    private static func prettyJSON(_ value: Any) -> String {
        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]),
           let s = String(data: data, encoding: .utf8) {
            return s
        }
        if let str = value as? String { return str }
        return "\(value)"
    }

    /// Legacy helper retained for daemon paths that still expect a single string.
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
        print("Output flags (any command):")
        print("  --compact                      Single-line JSON output")
        print("  --ndjson                       One JSON object per line (for list results)")
        print("  --quiet, -q                    Suppress stdout; rely on exit code")
        print("")
        print("Input conventions (any flag):")
        print("  --foo @path                    Read flag value from file")
        print("  --foo -                        Read flag value from stdin")
        print("  --args-json '{...}'|@file|-    Set the entire arguments object as JSON")
        print("")
        print("Pipelines:")
        print("  omnifocus-cli list-untagged --ndjson | jq -r .id \\")
        print("    | omnifocus-cli update-tasks-batch --updates -")
        print("  omnifocus-cli list-overdue --compact | jq '.[].name'")
        print("  echo '{\"name\":\"Buy milk\"}' | omnifocus-cli create-task --args-json -")
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

        print("")
        print("  Any flag accepts '@path' to load the value from a file, or '-' to read stdin.")
        print("  Add --compact, --ndjson, or --quiet to control output format.")
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

    static func escapeXML(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
         .replacingOccurrences(of: "'", with: "&apos;")
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
