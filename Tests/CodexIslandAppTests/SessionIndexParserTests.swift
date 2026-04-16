import Foundation
import Testing
@testable import CodexIslandCore

@Test
func sessionIndexParserReadsThreadTitleAndTimestamp() throws {
    let line = #"{"id":"thread-1","thread_name":"Build floating island","updated_at":"2026-04-15T08:00:00Z"}"#

    let entry = try SessionIndexParser().parse(line: line)

    #expect(entry.threadID == "thread-1")
    #expect(entry.title == "Build floating island")
    #expect(abs(entry.updatedAt.timeIntervalSince1970 - 1_776_240_000) < 1)
}

@Test
func sessionIndexReaderBuildsTitleOverrides() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let fileURL = directory.appendingPathComponent("session_index.jsonl")
    let contents = [
        #"{"id":"thread-1","thread_name":"真实会话名","updated_at":"2026-04-15T08:00:00Z"}"#,
        #"{"id":"thread-2","thread_name":"另一个会话名","updated_at":"2026-04-15T09:00:00Z"}"#
    ].joined(separator: "\n")
    try contents.write(to: fileURL, atomically: true, encoding: .utf8)

    let reader = SessionIndexReader()
    let overrides = try reader.readTitleOverrides(
        from: fileURL,
        threadIDs: ["thread-1", "missing-thread"]
    )

    #expect(overrides["thread-1"] == "真实会话名")
    #expect(overrides["missing-thread"] == nil)
}
