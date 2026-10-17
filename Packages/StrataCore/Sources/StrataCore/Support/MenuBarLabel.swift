import Foundation

/// The menu bar item's own wording.
///
/// The Monitor pill spells a state out in full ("Generating · 104.3 tok/s"); a menu bar item has
/// about twenty characters, so it shows the number instead of the word.
public enum MenuBarLabel {
    /// "104 t/s" while generating, "42%" while reading, nothing while idle, the "no value" dash
    /// when the server is not answering.
    public static func text(for status: MonitorStatus) -> String {
        switch status {
        case .generating(let tokS): tokS.map { "\(Int($0.rounded())) t/s" } ?? "generating"
        case .reading(let percent): percent.map { "\($0)%" } ?? "reading"
        case .queued(let count): "\(count) queued"
        case .idle, .unknown, .modelUnloaded: ""
        case .unauthorized, .unreachable: notAvailable
        }
    }

    /// The SF Symbol that goes with the text. The menu bar gets its own set: `text.magnifyingglass`
    /// and `exclamationmark.triangle` read better at menu bar size than the pill's symbols.
    public static func symbol(for status: MonitorStatus) -> String {
        switch status {
        case .unknown: "antenna.radiowaves.left.and.right"
        case .idle: "pause.circle"
        case .reading: "text.magnifyingglass"
        case .generating: "bolt.fill"
        case .queued: "hourglass"
        case .modelUnloaded: "square.stack.3d.up.slash"
        case .unauthorized, .unreachable: "exclamationmark.triangle"
        }
    }

    /// The hover tooltip: which model is loaded, and what the last request did.
    public static func tooltip(model: String?, lastRow: MonitorViewModel.RequestRow?) -> String {
        var parts: [String] = []
        if let model, !model.isEmpty { parts.append(model) }
        if let lastRow { parts.append("last: \(lastRow.outputText) out · \(lastRow.tokSText) t/s") }
        return parts.joined(separator: " · ")
    }
}
