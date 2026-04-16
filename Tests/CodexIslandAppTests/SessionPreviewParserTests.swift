import Foundation
import Testing
@testable import CodexIslandCore

@Test
func sessionPreviewParserExtractsAssistantPreviewFromCompletedMessage() throws {
    let row = LogRow(
        id: 101,
        timestamp: 1_776_251_161,
        level: "TRACE",
        target: "log",
        body: #"Received message {"type":"response.output_item.done","item":{"id":"msg_1","type":"message","status":"completed","content":[{"type":"output_text","text":"我已经确认到目前的瓶颈了：线程列表本身有，但我们现在只保留了最后一个事件。"}],"phase":"commentary","role":"assistant"}}"#,
        threadID: "thread-1",
        processUUID: "proc-1"
    )

    let preview = try #require(SessionPreviewParser().parse(row: row))

    #expect(preview.threadID == "thread-1")
    #expect(preview.author == .assistant)
    #expect(preview.text.contains("线程列表本身有"))
}

@Test
func sessionPreviewParserExtractsLatestUserPromptFromResponseCreate() throws {
    let row = LogRow(
        id: 102,
        timestamp: 1_776_251_200,
        level: "TRACE",
        target: "log",
        body: ##"websocket request: {"type":"response.create","model":"gpt-5.4","input":[{"role":"user","content":[{"type":"input_text","text":"# AGENTS.md instructions\n\n<INSTRUCTIONS>\n...\n</INSTRUCTIONS>\n\n## My request for Codex:\n参考这个，可以大致的看到每个session的内容"}]}]}"##,
        threadID: "thread-2",
        processUUID: "proc-2"
    )

    let preview = try #require(SessionPreviewParser().parse(row: row))

    #expect(preview.threadID == "thread-2")
    #expect(preview.author == .user)
    #expect(preview.text == "参考这个，可以大致的看到每个session的内容")
}

@Test
func sessionPreviewParserRedactsSensitiveValues() throws {
    let row = LogRow(
        id: 103,
        timestamp: 1_776_251_210,
        level: "TRACE",
        target: "log",
        body: #"Received message {"type":"response.output_item.done","item":{"id":"msg_2","type":"message","status":"completed","content":[{"type":"output_text","text":"手机号 15081633966，身份证号 130403199306022722，邮箱 foo@example.com"}],"phase":"commentary","role":"assistant"}}"#,
        threadID: "thread-3",
        processUUID: "proc-3"
    )

    let preview = try #require(SessionPreviewParser().parse(row: row))

    #expect(preview.text.contains("1**********"))
    #expect(preview.text.contains("******************"))
    #expect(preview.text.contains("***@***"))
    #expect(!preview.text.contains("15081633966"))
    #expect(!preview.text.contains("130403199306022722"))
    #expect(!preview.text.contains("foo@example.com"))
}
