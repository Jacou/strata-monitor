import SwiftUI
import StrataCore

/// One message: the user's on the right in an accent-tinted bubble, the answer on the left in a
/// card, with its thoughts above it and the token line under it.
struct ChatMessageRow: View {
    @Environment(\.theme) private var theme

    let message: ChatMessage
    let isStreaming: Bool
    /// The chat setting: open the "Thinking…" block while the model is still thinking.
    let showsThinking: Bool

    var body: some View {
        if message.isUser {
            userBubble
        } else if !message.isEmpty || isStreaming {
            assistantCard
        }
    }

    // MARK: - user

    private var userBubble: some View {
        HStack {
            Spacer(minLength: 40)
            Text(message.text)
                .font(.body)
                .foregroundStyle(theme.textPrimary)
                .textSelection(.enabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: theme.cardRadius)
                        .fill(theme.accent.opacity(0.12))
                        .overlay(
                            RoundedRectangle(cornerRadius: theme.cardRadius)
                                .strokeBorder(theme.accent.opacity(0.35), lineWidth: theme.hairline)
                        )
                )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("You: \(message.text)")
    }

    // MARK: - assistant

    private var assistantCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if message.hasReasoning {
                ThinkingBlock(
                    message: message,
                    isStreaming: isStreaming,
                    autoOpen: showsThinking && isStreaming && !message.hasAnswer
                )
            }

            if message.hasAnswer {
                ChatMarkdownText(text: message.text, streaming: isStreaming)
            } else if isStreaming, !message.hasReasoning {
                waitingDots
            }

            if let error = message.error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(theme.dangerText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let meta = message.meta {
                Text(meta)
                    .font(theme.subFont)
                    .monospacedDigit()
                    .foregroundStyle(theme.textTertiary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .strataCard(theme)
    }

    /// The request is out but nothing has come back yet: the prompt is being read.
    private var waitingDots: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
                .tint(theme.accent)
            Text("Reading the prompt…")
                .font(.footnote)
                .foregroundStyle(theme.textTertiary)
        }
        .accessibilityLabel("Waiting for the answer")
    }
}

/// `delta.reasoning_content`, folded under a one-line title: "Thinking…" while it streams,
/// "Thought for 3.4 s" afterwards. Opens itself while the model thinks (if the setting says so)
/// and folds once the answer starts — unless the reader toggled it by hand.
private struct ThinkingBlock: View {
    @Environment(\.theme) private var theme

    let message: ChatMessage
    let isStreaming: Bool
    let autoOpen: Bool

    @State private var open = false
    @State private var touched = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                touched = true
                withAnimation(.easeInOut(duration: 0.15)) { open.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "brain")
                    Text(title)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .rotationEffect(.degrees(open ? 90 : 0))
                }
                .font(.footnote.weight(.medium))
                .foregroundStyle(isStreaming && !message.hasAnswer ? theme.accentText : theme.textSecondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            .accessibilityHint(open ? "Hides the thoughts" : "Shows the thoughts")

            if open {
                Text(message.reasoning)
                    .font(.footnote)
                    .foregroundStyle(theme.textSecondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 4)
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(theme.separator)
                            .frame(width: 2)
                            .offset(x: -6)
                    }
                    .padding(.leading, 6)
            }
        }
        .onAppear { if !touched { open = autoOpen } }
        .onChange(of: autoOpen) { _, newValue in
            if !touched { withAnimation(.easeInOut(duration: 0.15)) { open = newValue } }
        }
    }

    private var title: String {
        ChatMeta.thinkTitle(reasoning: message.reasoning, thinkSecs: message.thinkSecs, streaming: isStreaming && !message.hasAnswer) ?? "Thoughts"
    }
}

/// The answer: prose as inline Markdown, fenced code in a monospaced box, a cursor while it streams.
struct ChatMarkdownText: View {
    @Environment(\.theme) private var theme

    let text: String
    let streaming: Bool

    var body: some View {
        let blocks = ChatMarkdown.blocks(text)
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                switch block {
                case .text(let prose):
                    proseView(prose, cursor: streaming && index == blocks.count - 1)
                case .code(let code, let language):
                    codeView(code, language: language)
                }
            }
        }
    }

    private func proseView(_ prose: String, cursor: Bool) -> some View {
        (Text(attributed(prose)) + (cursor ? Text(" ▍").foregroundColor(theme.accent) : Text("")))
            .font(.body)
            .foregroundStyle(theme.textPrimary)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func codeView(_ code: String, language: String?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let language, !language.isEmpty {
                Text(language)
                    .font(theme.badgeFont)
                    .foregroundStyle(theme.textTertiary)
                    .padding(.horizontal, 10)
                    .padding(.top, 6)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code.hasSuffix("\n") ? String(code.dropLast()) : code)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(theme.textPrimary)
                    .textSelection(.enabled)
                    .padding(10)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(theme.track.opacity(0.6))
        )
    }

    /// Inline Markdown (bold, italics, code, links) with the line breaks kept; anything that does
    /// not parse is shown as typed.
    private func attributed(_ prose: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: prose, options: options)) ?? AttributedString(prose)
    }
}
