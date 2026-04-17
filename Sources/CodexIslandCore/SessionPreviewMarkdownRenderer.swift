import Foundation

public enum SessionPreviewMarkdownRenderer {
    public static func render(_ markdown: String) -> AttributedString? {
        let normalized = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        guard normalized.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return nil
        }

        let renderedLines = renderLines(from: normalized)
        var output = AttributedString()

        for (index, line) in renderedLines.enumerated() {
            if index > 0 {
                output.append(AttributedString("\n"))
            }
            output.append(line)
        }

        return output
    }

    private static func renderLines(from markdown: String) -> [AttributedString] {
        var renderedLines: [AttributedString] = []
        var isInsideCodeBlock = false
        var bufferedCodeLines: [String] = []

        for line in markdown.components(separatedBy: "\n") {
            if isFenceMarker(line) {
                if isInsideCodeBlock {
                    renderedLines.append(contentsOf: renderCodeBlockLines(bufferedCodeLines))
                    bufferedCodeLines.removeAll(keepingCapacity: true)
                }
                isInsideCodeBlock.toggle()
                continue
            }

            if isInsideCodeBlock {
                bufferedCodeLines.append(line)
                continue
            }

            renderedLines.append(renderDisplayLine(line))
        }

        if isInsideCodeBlock {
            renderedLines.append(contentsOf: renderCodeBlockLines(bufferedCodeLines))
        }

        return renderedLines
    }

    private static func renderDisplayLine(_ line: String) -> AttributedString {
        if line.isEmpty {
            return AttributedString("")
        }

        if let unordered = parseUnorderedListItem(line) {
            var rendered = AttributedString(unordered.prefix + "• ")
            rendered.append(renderInlineMarkdown(unordered.content))
            return rendered
        }

        if let ordered = parseOrderedListItem(line) {
            var rendered = AttributedString(ordered.prefix + ordered.marker + " ")
            rendered.append(renderInlineMarkdown(ordered.content))
            return rendered
        }

        return renderInlineMarkdown(line)
    }

    private static func renderCodeBlockLines(_ lines: [String]) -> [AttributedString] {
        lines.map { line in
            var rendered = AttributedString(line)
            rendered.inlinePresentationIntent = .code
            return rendered
        }
    }

    private static func renderInlineMarkdown(_ text: String) -> AttributedString {
        if let rendered = try? AttributedString(
            markdown: text,
            options: .init(
                interpretedSyntax: .inlineOnlyPreservingWhitespace,
                failurePolicy: .returnPartiallyParsedIfPossible
            )
        ) {
            return rendered
        }

        return AttributedString(text)
    }

    private static func isFenceMarker(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).hasPrefix("```")
    }

    private static func parseUnorderedListItem(_ line: String) -> (prefix: String, content: String)? {
        let prefix = String(line.prefix { $0 == " " || $0 == "\t" })
        let trimmed = String(line.dropFirst(prefix.count))

        for marker in ["- ", "* ", "+ "] {
            guard trimmed.hasPrefix(marker) else {
                continue
            }
            return (prefix, String(trimmed.dropFirst(marker.count)))
        }

        return nil
    }

    private static func parseOrderedListItem(_ line: String) -> (prefix: String, marker: String, content: String)? {
        let prefix = String(line.prefix { $0 == " " || $0 == "\t" })
        let trimmed = String(line.dropFirst(prefix.count))

        guard let dotIndex = trimmed.firstIndex(of: "."),
              trimmed[..<dotIndex].allSatisfy(\.isNumber) else {
            return nil
        }

        let marker = String(trimmed[..<trimmed.index(after: dotIndex)])
        let remainderStart = trimmed.index(after: dotIndex)
        guard remainderStart < trimmed.endIndex, trimmed[remainderStart] == " " else {
            return nil
        }

        return (
            prefix,
            marker,
            String(trimmed[trimmed.index(after: remainderStart)...])
        )
    }
}
