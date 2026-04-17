import Foundation
import Testing
@testable import CodexIslandCore

@Test
func codeBuddySessionBuilderSummarizesInProgressTodosAsToolActivity() throws {
    let builder = CodeBuddySessionBuilder()
    let session = CodeBuddySessionRecord(
        conversationID: "buddy-1",
        cwd: "/Users/demo/project",
        title: "Fix auth bug",
        status: "Running",
        createdAt: Date(timeIntervalSince1970: 100),
        updatedAt: Date(timeIntervalSince1970: 180)
    )
    let todos = CodeBuddyTodos(
        conversationID: "buddy-1",
        items: [
            CodeBuddyTodo(id: "1", status: "completed", content: "Inspect auth flow"),
            CodeBuddyTodo(id: "2", status: "in_progress", content: "Patch refresh token bug")
        ],
        updatedAt: Date(timeIntervalSince1970: 190)
    )

    let parsed = try #require(builder.build(session: session, todos: todos, historyUpdatedAt: nil))

    #expect(parsed.threadSnapshot.provider == .codeBuddy)
    #expect(parsed.threadSnapshot.title == "Fix auth bug")
    #expect(parsed.assistantPreview?.text == "Working on: Patch refresh token bug")
    #expect(parsed.event?.kind == .toolUpdated)
}
