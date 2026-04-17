import Foundation
import Testing
@testable import CodexIslandCore

@Test
func claudeTranscriptParserExtractsNamedSessionAndPreviews() throws {
    let parser = ClaudeTranscriptParser()
    let transcript = """
    {"sessionName":"Auth refactor"}
    {"message":{"role":"user","content":[{"type":"text","text":"Please fix the auth token refresh flow."}]}}
    {"message":{"role":"assistant","content":[{"type":"text","text":"I found the refresh bug and I am patching it now."}]}}
    """

    let parsed = try #require(
        parser.parse(
            sessionID: "auth-refactor",
            transcript: transcript,
            updatedAt: Date(timeIntervalSince1970: 200)
        )
    )

    #expect(parsed.threadSnapshot.provider == .claudeCode)
    #expect(parsed.threadSnapshot.title == "Auth refactor")
    #expect(parsed.userPreview?.text == "Please fix the auth token refresh flow.")
    #expect(parsed.assistantPreview?.text == "I found the refresh bug and I am patching it now.")
    #expect(parsed.event?.kind == .responseCompleted)
}
