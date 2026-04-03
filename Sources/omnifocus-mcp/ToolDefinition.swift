import Foundation

struct ToolDefinition {
    let name: String
    let description: String
    let inputSchema: [String: Any]
    var annotations: [String: Any]?
}

nonisolated(unsafe) let readOnlyAnnotation: [String: Any] = [
    "readOnlyHint": true, "destructiveHint": false, "idempotentHint": true, "openWorldHint": false
]
nonisolated(unsafe) let mutatingAnnotation: [String: Any] = [
    "readOnlyHint": false, "destructiveHint": false, "idempotentHint": false, "openWorldHint": false
]
nonisolated(unsafe) let destructiveAnnotation: [String: Any] = [
    "readOnlyHint": false, "destructiveHint": true, "idempotentHint": false, "openWorldHint": false
]
