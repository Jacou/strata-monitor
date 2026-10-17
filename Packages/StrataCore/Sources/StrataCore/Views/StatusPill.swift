import SwiftUI

extension MonitorStatus {
    var symbol: String {
        switch self {
        case .unknown: "antenna.radiowaves.left.and.right"
        case .idle: "pause.circle"
        case .reading: "doc.text.magnifyingglass"
        case .generating: "bolt.fill"
        case .queued: "hourglass"
        case .modelUnloaded: "square.stack.3d.up.slash"
        case .unauthorized: "key.slash"
        case .unreachable: "wifi.slash"
        }
    }
}

/// The header pill: an outlined capsule in the state colour, with a pulsing dot while generating.
public struct StatusPill: View {
    public let status: MonitorStatus
    /// The hover card names the live phase instead of repeating the speed the pill usually prints.
    public let text: String?

    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(_ status: MonitorStatus, text: String? = nil) {
        self.status = status
        self.text = text
    }

    public var body: some View {
        let color = status.color(in: theme)
        let label = text ?? status.text

        HStack(spacing: 8) {
            if status.isGenerating {
                PulsingDot(color: color, animates: !reduceMotion)
            }
            Image(systemName: status.symbol)
                .font(.callout.weight(.semibold))
            Text(label)
                .font(.callout.weight(.semibold))
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .foregroundStyle(color)
        .background(Capsule().fill(color.opacity(0.08)))
        .overlay(Capsule().strokeBorder(color.opacity(0.35), lineWidth: theme.hairline))
        .accessibilityElement()
        .accessibilityLabel(label)
    }
}

/// The 8 pt dot and its expanding ring: 1.6 s, forever, while the engine is generating.
private struct PulsingDot: View {
    let color: Color
    let animates: Bool

    @State private var on = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .overlay(
                Circle()
                    .strokeBorder(color.opacity(0.5), lineWidth: 1)
                    .scaleEffect(on ? 1.9 : 1)
                    .opacity(on ? 0.2 : 0.9)
            )
            .scaleEffect(animates && on ? 1.15 : 1)
            .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: on)
            .onAppear { on = true }
            .accessibilityHidden(true)
    }
}
