import Testing
@testable import OmniFocusCore

@Suite("OFEngine.serializeToolResult")
struct SerializeToolResultTests {
    @Test func stringPassesThroughVerbatim() throws {
        #expect(try OFEngine.serializeToolResult("already-json") == "already-json")
    }

    @Test func stringPreservesQuotesAndBackslashes() throws {
        let raw = "{\"a\":\"b\\\"c\"}"
        #expect(try OFEngine.serializeToolResult(raw) == raw)
    }

    @Test func dictionarySerializesToJSON() throws {
        let result = try OFEngine.serializeToolResult(["a": 1, "b": "two"])
        // sortedKeys is enabled so the order is deterministic
        #expect(result == #"{"a":1,"b":"two"}"#)
    }

    @Test func arraySerializesToJSON() throws {
        let result = try OFEngine.serializeToolResult([1, 2, 3])
        #expect(result == "[1,2,3]")
    }

    @Test func nestedStructureSerializesToJSON() throws {
        let payload: [String: Any] = ["items": [["id": "x"], ["id": "y"]], "count": 2]
        let result = try OFEngine.serializeToolResult(payload)
        #expect(result == #"{"count":2,"items":[{"id":"x"},{"id":"y"}]}"#)
    }

    @Test func emptyDictionarySerializesToBraces() throws {
        let result = try OFEngine.serializeToolResult([String: Any]())
        #expect(result == "{}")
    }

    @Test func nonSerializableValueThrowsToolError() {
        struct Opaque {}
        #expect(throws: MCPError.self) {
            _ = try OFEngine.serializeToolResult(Opaque())
        }
    }
}
