import Foundation

public struct ToolDefinition {
    public let name: String
    public let description: String
    public let inputSchema: [String: Any]
    public var annotations: [String: Any]?
}

nonisolated(unsafe) public let readOnlyAnnotation: [String: Any] = [
    "readOnlyHint": true, "destructiveHint": false, "idempotentHint": true, "openWorldHint": false
]
nonisolated(unsafe) public let mutatingAnnotation: [String: Any] = [
    "readOnlyHint": false, "destructiveHint": false, "idempotentHint": false, "openWorldHint": false
]
nonisolated(unsafe) public let destructiveAnnotation: [String: Any] = [
    "readOnlyHint": false, "destructiveHint": true, "idempotentHint": false, "openWorldHint": false
]
