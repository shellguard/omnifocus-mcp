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
    let serverVersion = "0.2.0"
    let supportedProtocolVersions = ["2025-11-25", "2025-06-18", "2024-11-05"]
    let defaultToolsPageSize = 100

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
            let params = message["params"] as? [String: Any] ?? [:]
            let requestedVersion = params["protocolVersion"] as? String
            let negotiatedVersion = negotiateProtocolVersion(requestedVersion)
            let result: [String: Any] = [
                "protocolVersion": negotiatedVersion,
                "capabilities": ["tools": [String: Any]()],
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
            do {
                let resultValue = try engine.callTool(named: toolName, arguments: arguments)
                let jsonText = try OFEngine.serializeToolResult(resultValue)
                let response: [String: Any] = [
                    "content": [["type": "text", "text": jsonText]]
                ]
                sendResult(id: id, result: response)
            } catch let error as MCPError {
                switch error {
                case .toolNotFound:
                    throw error
                case .invalidParams, .toolError, .scriptError:
                    sendToolErrorResult(id: id, message: error.description)
                case .invalidRequest, .methodNotFound:
                    throw error
                }
            } catch {
                sendToolErrorResult(id: id, message: "Internal tool execution error: \(error.localizedDescription)")
            }
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
