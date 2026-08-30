import Foundation

public struct ToolDefinition {
    public static let jsonSchemaDialect = "https://json-schema.org/draft/2020-12/schema"

    /// Loose output schema: every tool returns a JSON value (object, array, or scalar).
    public static let defaultOutputSchema: [String: Any] = [
        "$schema": jsonSchemaDialect,
        "description": "JSON value returned by the OmniFocus tool"
    ]

    public let name: String
    public let title: String
    public let description: String
    public let inputSchema: [String: Any]
    public let outputSchema: [String: Any]
    public var annotations: [String: Any]?

    public init(
        name: String,
        description: String,
        inputSchema: [String: Any],
        annotations: [String: Any]? = nil,
        title: String? = nil,
        outputSchema: [String: Any]? = nil
    ) {
        self.name = name
        self.title = title ?? Self.displayTitle(for: name)
        self.description = description
        self.inputSchema = inputSchema
        self.outputSchema = outputSchema ?? Self.defaultOutputSchema
        self.annotations = annotations
    }

    /// `omnifocus_list_tasks` → `List Tasks`
    public static func displayTitle(for toolName: String) -> String {
        let stem = toolName.hasPrefix("omnifocus_")
            ? String(toolName.dropFirst("omnifocus_".count))
            : toolName
        return stem
            .split(separator: "_")
            .map { part in
                let word = String(part)
                guard let first = word.first else { return word }
                return first.uppercased() + word.dropFirst()
            }
            .joined(separator: " ")
    }

    public func mcpListEntry() -> [String: Any] {
        var schema = inputSchema
        if schema["$schema"] == nil {
            schema["$schema"] = Self.jsonSchemaDialect
        }
        var entry: [String: Any] = [
            "name": name,
            "title": title,
            "description": description,
            "inputSchema": schema,
            "outputSchema": outputSchema
        ]
        if let annotations {
            entry["annotations"] = annotations
        }
        return entry
    }
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
