import Foundation

// Ports of the web app's formatting helpers (docs/reference-app.js), so the native screens
// show exactly the same strings: fmt, gb, kfmt, ctxfmt, since.

/// The web app's "no value" marker.
public let notAvailable = "–"

/// `fmt(n, d)`: grouped digits with exactly `d` decimals, "–" for nil / NaN / infinite.
public func fmt(_ value: Double?, _ digits: Int = 0, locale: Locale = .autoupdatingCurrent) -> String {
    guard let value, value.isFinite else { return notAvailable }
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.locale = locale
    formatter.usesGroupingSeparator = true
    formatter.minimumFractionDigits = digits
    formatter.maximumFractionDigits = digits
    return formatter.string(from: NSNumber(value: value)) ?? notAvailable
}

/// `gb(b, d)`: bytes as binary GB (1024³), the way Windows shows memory.
public func gb(_ bytes: Double?, _ digits: Int = 1, locale: Locale = .autoupdatingCurrent) -> String {
    guard let bytes else { return notAvailable }
    return fmt(bytes / 1_073_741_824, digits, locale: locale)
}

/// `kfmt(n)`: 1234 → "1.2k", 12345 → "12k".
public func kfmt(_ value: Double?, locale: Locale = .autoupdatingCurrent) -> String {
    guard let value else { return notAvailable }
    if value >= 1_000 { return fmt(value / 1_000, value >= 10_000 ? 0 : 1, locale: locale) + "k" }
    return fmt(value, 0, locale: locale)
}

/// `ctxfmt(n)`: a context size — 32768 → "32K" (powers of two), otherwise like `kfmt`.
public func ctxfmt(_ value: Double?, locale: Locale = .autoupdatingCurrent) -> String {
    guard let value else { return notAvailable }
    if value != 0, value.truncatingRemainder(dividingBy: 1_024) == 0 {
        return fmt(value / 1_024, 0, locale: locale) + "K"
    }
    return kfmt(value, locale: locale)
}

/// `since(t)`: "just now" / "12 min ago" / "2.5 h ago" from a unix timestamp in seconds.
public func since(_ timestamp: Double?, now: Date = .now, locale: Locale = .autoupdatingCurrent) -> String {
    guard let timestamp, timestamp > 0 else { return "" }
    let seconds = max(0, now.timeIntervalSince1970 - timestamp)
    if seconds < 60 { return "just now" }
    if seconds < 3_600 { return fmt(seconds / 60, 0, locale: locale) + " min ago" }
    return fmt(seconds / 3_600, 1, locale: locale) + " h ago"
}

/// How long something has been running, from a duration in seconds: "42 s", "12 min",
/// "3 h 12 m", "2 d 4 h".
public func uptimeText(_ seconds: Double?, locale: Locale = .autoupdatingCurrent) -> String {
    guard let seconds, seconds.isFinite, seconds >= 0 else { return notAvailable }
    let total = Int(seconds.rounded(.down))
    if total < 60 { return "\(total) s" }
    let minutes = total / 60
    if minutes < 60 { return "\(minutes) min" }
    let hours = minutes / 60
    if hours < 24 { return "\(hours) h \(minutes % 60) m" }
    return "\(hours / 24) d \(hours % 24) h"
}

/// The web app's `pct(a, b)`: "0%" when there is no denominator.
public func fractionPercent(_ value: Double?, _ total: Double?, locale: Locale = .autoupdatingCurrent) -> String {
    guard let total, total > 0, let value else { return "0%" }
    return fmt(min(100, (100 * value) / total), 0, locale: locale) + "%"
}

/// A request's clock time, like `toLocaleTimeString([], {hour, minute, second})`.
public func timeString(_ timestamp: Double?, locale: Locale = .autoupdatingCurrent) -> String {
    guard let timestamp, timestamp > 0 else { return notAvailable }
    let formatter = DateFormatter()
    formatter.locale = locale
    formatter.dateStyle = .none
    formatter.timeStyle = .medium
    return formatter.string(from: Date(timeIntervalSince1970: timestamp))
}

/// "Wed, 06:18" — the totals line's "Since …", like `toLocaleTimeString([], {weekday: 'short', hour: '2-digit', minute: '2-digit'})`.
public func sinceDateLine(_ timestamp: Double?, locale: Locale = .autoupdatingCurrent) -> String {
    guard let timestamp, timestamp > 0 else { return notAvailable }
    let formatter = DateFormatter()
    formatter.locale = locale
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter.string(from: Date(timeIntervalSince1970: timestamp))
}

/// "updated just now" while the poller is healthy; "last data 3 min ago" while it is failing.
public func updatedCaption(status: MonitorStatus, lastUpdated: Date?, now: Date = .now) -> String {
    guard let lastUpdated else { return "no data yet" }
    let ago = since(lastUpdated.timeIntervalSince1970, now: now)
    switch status {
    case .unauthorized, .unreachable: return "last data \(ago)"
    default: return "updated \(ago)"
    }
}
