import SwiftUI

/// The finish reason as a small outlined capsule: neutral for a clean stop, warn for a cut-off,
/// danger for an error. Shared by the iOS request list and the macOS popover.
public struct FinishBadge: View {
    public let text: String
    public let style: MonitorViewModel.BadgeStyle

    @Environment(\.theme) private var theme

    public init(text: String, style: MonitorViewModel.BadgeStyle) {
        self.text = text
        self.style = style
    }

    public var body: some View {
        Text(text)
            .font(theme.badgeFont)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .foregroundStyle(color)
            .background(Capsule().fill(color.opacity(0.08)))
            .overlay(Capsule().strokeBorder(color.opacity(0.35), lineWidth: 1))
    }

    private var color: Color {
        switch style {
        case .neutral: theme.accentText
        case .warning: theme.warnText
        case .danger: theme.dangerText
        }
    }
}
