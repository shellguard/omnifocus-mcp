import Testing
@testable import OmniFocusCore

@Suite("MCPError description formatting")
struct MCPErrorTests {
    @Test func invalidRequestUsesPassedMessage() {
        #expect(MCPError.invalidRequest("missing method").description == "missing method")
    }

    @Test func methodNotFoundUsesPassedMessage() {
        #expect(MCPError.methodNotFound("Unknown method: foo").description == "Unknown method: foo")
    }

    @Test func invalidParamsUsesPassedMessage() {
        #expect(MCPError.invalidParams("Missing script").description == "Missing script")
    }

    @Test func toolNotFoundFormatsName() {
        #expect(MCPError.toolNotFound("omnifocus_bogus").description == "Unknown tool: omnifocus_bogus")
    }

    @Test func toolErrorUsesPassedMessage() {
        #expect(MCPError.toolError("backend exploded").description == "backend exploded")
    }

    @Test func scriptErrorUsesPassedMessage() {
        #expect(MCPError.scriptError("osascript timeout").description == "osascript timeout")
    }
}
