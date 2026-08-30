import Testing
@testable import OmniFocusCore

@Suite("ToolDefinition catalog metadata")
struct ToolDefinitionTests {
    @Test func displayTitleStripsPrefixAndCapitalizes() {
        #expect(ToolDefinition.displayTitle(for: "omnifocus_list_tasks") == "List Tasks")
        #expect(ToolDefinition.displayTitle(for: "omnifocus_get_forecast") == "Get Forecast")
        #expect(ToolDefinition.displayTitle(for: "omnifocus_eval_automation") == "Eval Automation")
    }

    @Test func evalToolUsesExplicitTitle() {
        let eval = allTools.first { $0.name == "omnifocus_eval_automation" }
        #expect(eval?.title == "Evaluate Omni Automation Script")
        #expect(eval?.annotations?["title"] == nil)
    }

    @Test func everyToolHasTitleAndOutputSchema() {
        for tool in allTools {
            #expect(!tool.title.isEmpty, "tool \(tool.name) missing title")
            #expect(tool.outputSchema["$schema"] as? String == ToolDefinition.jsonSchemaDialect)
        }
    }

    @Test func mcpListEntryInjectsSchemaDialectAndTitle() {
        let entry = allTools[0].mcpListEntry()
        #expect(entry["title"] as? String == allTools[0].title)
        let schema = entry["inputSchema"] as? [String: Any]
        #expect(schema?["$schema"] as? String == ToolDefinition.jsonSchemaDialect)
        #expect(entry["outputSchema"] != nil)
        #expect(entry["name"] as? String == allTools[0].name)
    }

    @Test func catalogOrderIsDeterministic() {
        #expect(allTools.first?.name == "omnifocus_list_tasks")
        #expect(allTools.count == 90)
    }
}
