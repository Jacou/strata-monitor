import Foundation

/// The small strings the chat screen shows under an answer, ported from `send()` /
/// `updateAssistant()` in docs/reference-app.js.
public enum ChatMeta {
    /// "128 tokens · 41.2 tok/s", "128 tokens · 41.2 tok/s · stopped", "128 tokens", "Stopped".
    ///
    /// `firstTokenAt` / `endedAt` are monotonic seconds (the web page's `performance.now()`);
    /// nil `firstTokenAt` means no token ever arrived. Below 0.25 s the speed is noise, so the
    /// web page prints the count alone.
    public static func line(
        tokens: Int?,
        firstTokenAt: TimeInterval?,
        endedAt: TimeInterval,
        stopped: Bool,
        locale: Locale = .autoupdatingCurrent
    ) -> String? {
        if let tokens, tokens > 0, let firstTokenAt {
            let seconds = max(0, endedAt - firstTokenAt)
            let speed = seconds > 0.25 ? " · \(fmt(Double(tokens) / seconds, 1, locale: locale)) tok/s" : ""
            return "\(fmt(Double(tokens), 0, locale: locale)) tokens" + speed + (stopped ? " · stopped" : "")
        }
        return stopped ? "Stopped" : nil
    }

    /// The "Thinking…" block's title: "Thinking…" while it is still thinking, "Thought for 3.4 s"
    /// afterwards, "Thoughts" when the seconds were never measured.
    public static func thinkTitle(reasoning: String, thinkSecs: Double?, streaming: Bool) -> String? {
        if reasoning.isEmpty { return nil }
        if streaming { return "Thinking…" }
        if let thinkSecs { return "Thought for \(fmt(thinkSecs, 1)) s" }
        return "Thoughts"
    }
}
