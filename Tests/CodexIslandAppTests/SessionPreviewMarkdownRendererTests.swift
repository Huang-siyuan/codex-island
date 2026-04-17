import Foundation
import Testing
@testable import CodexIslandCore

@Test
func sessionPreviewMarkdownRendererPreservesInlineMarkdownSemantics() throws {
    let rendered = try #require(
        SessionPreviewMarkdownRenderer.render("**Bold** with [link](https://example.com) and `code`")
    )

    #expect(String(rendered.characters) == "Bold with link and code")
    #expect(rendered.runs.contains(where: { $0.inlinePresentationIntent?.contains(InlinePresentationIntent.stronglyEmphasized) == true }))
    #expect(rendered.runs.contains(where: { $0.inlinePresentationIntent?.contains(InlinePresentationIntent.code) == true }))
    #expect(rendered.runs.contains(where: { $0.link?.absoluteString == "https://example.com" }))
}

@Test
func sessionPreviewMarkdownRendererFormatsListsAndCodeBlocksForPreviewDisplay() throws {
    let rendered = try #require(
        SessionPreviewMarkdownRenderer.render(
            """
            Steps:
            - First item
            - Second item

            ```swift
            let value = 1
            print(value)
            ```
            """
        )
    )

    #expect(
        String(rendered.characters) ==
            """
            Steps:
            • First item
            • Second item

            let value = 1
            print(value)
            """
    )
}
