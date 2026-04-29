import Testing
@testable import OmniFocusCore

/// These tests cover the routing/validation paths in OFEngine.callTool that
/// happen BEFORE any JS backend is invoked. Anything that would actually
/// execute osascript is out of scope (it requires OmniFocus running).
@Suite("OFEngine.callTool routing & validation")
struct CallToolRoutingTests {
    let engine = OFEngine()

    @Test func unknownToolThrowsToolNotFound() {
        #expect(throws: MCPError.self) {
            _ = try engine.callTool(named: "omnifocus_nonexistent", arguments: [:])
        }
    }

    @Test func unknownToolErrorCarriesName() throws {
        do {
            _ = try engine.callTool(named: "omnifocus_nonexistent", arguments: [:])
            Issue.record("expected throw")
        } catch let MCPError.toolNotFound(name) {
            #expect(name == "omnifocus_nonexistent")
        } catch {
            Issue.record("expected toolNotFound, got \(error)")
        }
    }

    @Test func toolWithoutOmnifocusPrefixThrowsToolNotFound() {
        #expect(throws: MCPError.self) {
            _ = try engine.callTool(named: "list_tasks", arguments: [:])
        }
    }

    @Test func evalAutomationMissingScriptThrowsInvalidParams() throws {
        do {
            _ = try engine.callTool(named: "omnifocus_eval_automation", arguments: [:])
            Issue.record("expected throw")
        } catch let MCPError.invalidParams(message) {
            #expect(message.contains("Missing script"))
        } catch {
            Issue.record("expected invalidParams, got \(error)")
        }
    }

    @Test func evalAutomationDestructiveScriptIsBlocked() throws {
        let args: [String: Any] = ["script": "task.delete()"]
        do {
            _ = try engine.callTool(named: "omnifocus_eval_automation", arguments: args)
            Issue.record("expected throw")
        } catch let MCPError.invalidParams(message) {
            #expect(message.contains("destructive"))
            #expect(message.contains("allowDestructive"))
        } catch {
            Issue.record("expected invalidParams (deny-list), got \(error)")
        }
    }

    @Test func evalAutomationBracketDeleteIsBlocked() {
        let args: [String: Any] = ["script": "task['delete']()"]
        #expect(throws: MCPError.self) {
            _ = try engine.callTool(named: "omnifocus_eval_automation", arguments: args)
        }
    }

    /// Tool-name → action-name aliasing. Currently only convert_task_to_project
    /// is mapped; everything else is `dropFirst("omnifocus_")`.
    @Test func toolNameToActionMapping() {
        #expect(OFEngine.toolNameToAction["omnifocus_convert_task_to_project"] == "convert_to_project")
        #expect(OFEngine.toolNameToAction["omnifocus_list_tasks"] == nil)
    }

    @Test func everyRegisteredToolIsOmnifocusPrefixed() {
        for tool in engine.tools {
            #expect(tool.name.hasPrefix("omnifocus_"), "tool \(tool.name) must start with omnifocus_")
        }
    }

    @Test func everyRegisteredToolHasInputSchema() {
        for tool in engine.tools {
            #expect(tool.inputSchema["type"] as? String == "object",
                    "tool \(tool.name) must declare type:object schema")
        }
    }

    @Test func everyRegisteredToolHasAnnotations() {
        for tool in engine.tools {
            #expect(tool.annotations != nil, "tool \(tool.name) is missing annotations")
        }
    }

    @Test func registeredToolNamesAreUnique() {
        var seen = Set<String>()
        for tool in engine.tools {
            #expect(seen.insert(tool.name).inserted, "duplicate tool name: \(tool.name)")
        }
    }
}
