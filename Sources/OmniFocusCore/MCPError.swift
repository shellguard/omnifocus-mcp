import Foundation

public enum MCPError: Error, CustomStringConvertible {
    case invalidRequest(String)
    case methodNotFound(String)
    case invalidParams(String)
    case toolNotFound(String)
    case toolError(String)
    case scriptError(String)

    public var description: String {
        switch self {
        case .invalidRequest(let message):
            return message
        case .methodNotFound(let message):
            return message
        case .invalidParams(let message):
            return message
        case .toolNotFound(let name):
            return "Unknown tool: \(name)"
        case .toolError(let message):
            return message
        case .scriptError(let message):
            return message
        }
    }
}
