import Testing
import Foundation
@testable import OmniFocusCore

@Suite("OFEngine.destructiveScriptRegex")
struct DenyListRegexTests {
    private func matches(_ script: String) -> Bool {
        let regex = OFEngine.destructiveScriptRegex
        let range = NSRange(script.startIndex..., in: script)
        return regex.firstMatch(in: script, options: [], range: range) != nil
    }

    // MARK: - Patterns that must be blocked

    @Test func blocksDotDelete() { #expect(matches("task.delete()")) }

    @Test func blocksDotDeleteWithWhitespace() { #expect(matches("task.delete  ()")) }

    @Test func blocksDotRemove() { #expect(matches("task.remove()")) }

    @Test func blocksDotDrop() { #expect(matches("task.drop(false)")) }

    @Test func blocksMarkComplete() { #expect(matches("task.markComplete()")) }

    @Test func blocksMarkIncomplete() { #expect(matches("task.markIncomplete()")) }

    @Test func blocksDotCleanUp() { #expect(matches("doc.cleanUp()")) }

    @Test func blocksBracketDelete() { #expect(matches("task['delete']()")) }

    @Test func blocksBracketDeleteDoubleQuotes() { #expect(matches(#"task["delete"]()"#)) }

    @Test func blocksBracketDrop() { #expect(matches("task['drop']()")) }

    @Test func blocksDeleteObject() { #expect(matches("deleteObject(task)")) }

    @Test func blocksTopLevelCleanUp() { #expect(matches("cleanUp()")) }

    @Test func blocksConvertTasksToProjects() { #expect(matches("convertTasksToProjects(items)")) }

    @Test func blocksMoveSections() { #expect(matches("moveSections(stuff)")) }

    @Test func blocksMoveTags() { #expect(matches("moveTags(stuff)")) }

    @Test func blocksDuplicateSections() { #expect(matches("duplicateSections(stuff)")) }

    @Test func blocksByParsingTransportText() { #expect(matches("Task.byParsingTransportText('foo')")) }

    @Test func blocksCopyTasksToPasteboard() { #expect(matches("copyTasksToPasteboard(arr)")) }

    @Test func blocksPasteTasksFromPasteboard() { #expect(matches("pasteTasksFromPasteboard()")) }

    // MARK: - Patterns that must NOT be blocked

    @Test func allowsJSONStringify() { #expect(!matches("JSON.stringify({ok:1})")) }

    @Test func allowsTaskIdAccess() { #expect(!matches("task.id")) }

    @Test func allowsFlattenedTasksAccess() { #expect(!matches("database.flattenedTasks.length")) }

    @Test func allowsCommentMentioningDelete() {
        // The comment text contains 'delete' but no method-call form.
        #expect(!matches("// would delete this task"))
    }

    @Test func allowsPropertyContainingDeleteSubstring() {
        // 'isDeleted' or 'deletable' substrings should not match — we look for ".<keyword>(".
        #expect(!matches("var x = task.isDeleted"))
    }

    @Test func allowsSafeDatabaseRead() {
        #expect(!matches("var p = database.projectNamed('Inbox')"))
    }

    /// Verifies the regex requires `\(` immediately after the keyword (modulo
    /// whitespace), so superset names like `markCompletely(` are NOT a false
    /// positive. Also rules out `deletes(` and similar near-miss tokens.
    @Test func allowsKeywordSupersetTokens() {
        #expect(!matches("task.markCompletely()"))
        #expect(!matches("task.deletes()"))
        #expect(!matches("task.dropTarget()"))
    }
}
