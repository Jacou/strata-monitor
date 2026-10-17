import Foundation

/// Splitting an answer into prose and fenced code, the way `markdown()` does in
/// docs/reference-app.js (~line 541): a fence only counts at the start of a line, the info
/// string is the language, and an unterminated fence is code — the answer is still streaming.
public enum ChatMarkdownBlock: Sendable, Equatable {
    case text(String)
    case code(String, language: String?)
}

public enum ChatMarkdown {
    private static let fence = "```"

    public static func blocks(_ text: String) -> [ChatMarkdownBlock] {
        var out: [ChatMarkdownBlock] = []
        var rest = text[...]

        while true {
            guard let open = findOpenFence(in: rest) else {
                appendText(&out, rest)
                break
            }
            appendText(&out, rest[..<open.textEnd])
            rest = rest[open.codeStart...]

            guard let close = findCloseFence(in: rest) else {
                appendCode(&out, String(rest), language: open.language)
                return out
            }
            appendCode(&out, String(rest[..<close.codeEnd]), language: open.language)
            rest = rest[close.after...]
        }

        return out
    }

    /// `(^|\n)```([^\n`]*)\n` — the fence line, its language, and where the code starts.
    private struct OpenFence {
        var textEnd: String.Index
        var codeStart: String.Index
        var language: String?
    }

    /// `(^|\n)```[ \t]*(\n|$)` — where the code ends and what follows the closing fence.
    private struct CloseFence {
        var codeEnd: String.Index
        var after: String.Index
    }

    private static func findOpenFence(in text: Substring) -> OpenFence? {
        var search = text.startIndex
        while search < text.endIndex, let found = text.range(of: fence, range: search..<text.endIndex) {
            let at = found.lowerBound
            if isAtLineStart(at, in: text), let newline = lineEnd(from: found.upperBound, in: text) {
                let info = text[found.upperBound..<newline]
                if !info.contains("`") {
                    let language = info.trimmingCharacters(in: .whitespaces)
                    return OpenFence(
                        textEnd: at == text.startIndex ? text.startIndex : text.index(before: at),
                        codeStart: text.index(after: newline),
                        language: language.isEmpty ? nil : language
                    )
                }
            }
            search = found.upperBound
        }
        return nil
    }

    private static func findCloseFence(in text: Substring) -> CloseFence? {
        var search = text.startIndex
        while search < text.endIndex, let found = text.range(of: fence, range: search..<text.endIndex) {
            let at = found.lowerBound
            if isAtLineStart(at, in: text) {
                var i = found.upperBound
                while i < text.endIndex, text[i] == " " || text[i] == "\t" { i = text.index(after: i) }
                if i == text.endIndex || text[i] == "\n" {
                    return CloseFence(
                        codeEnd: at == text.startIndex ? text.startIndex : text.index(before: at),
                        after: i == text.endIndex ? text.endIndex : text.index(after: i)
                    )
                }
            }
            search = found.upperBound
        }
        return nil
    }

    private static func isAtLineStart(_ index: String.Index, in text: Substring) -> Bool {
        index == text.startIndex || text[text.index(before: index)] == "\n"
    }

    /// The index of the newline that ends this line, nil when the line never ends.
    private static func lineEnd(from index: String.Index, in text: Substring) -> String.Index? {
        var i = index
        while i < text.endIndex {
            if text[i] == "\n" { return i }
            i = text.index(after: i)
        }
        return nil
    }

    private static func appendText(_ blocks: inout [ChatMarkdownBlock], _ text: Substring) {
        guard !text.isEmpty else { return }
        blocks.append(.text(String(text)))
    }

    private static func appendCode(_ blocks: inout [ChatMarkdownBlock], _ code: String, language: String?) {
        guard !code.isEmpty else { return }
        blocks.append(.code(code, language: language))
    }
}
