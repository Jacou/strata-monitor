import SwiftUI
import StrataCore

/// The server dropdown beside a screen title: which server every tab is showing. Draws
/// nothing until a second server is set up in Settings.
public struct ServerPicker: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.theme) private var theme

    public init() {}

    public var body: some View {
        if settings.hasMultipleServers {
            let selected = settings.selectedSlot

            Menu {
                ForEach(settings.configuredSlots) { slot in
                    Button {
                        settings.selectedSlot = slot
                    } label: {
                        if slot == selected {
                            Label(settings.displayName(for: slot), systemImage: "checkmark")
                        } else {
                            Text(settings.displayName(for: slot))
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(settings.displayName(for: selected))
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .imageScale(.small)
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(theme.accentText)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(theme.accentText.opacity(0.12), in: Capsule())
            }
            .accessibilityLabel("Server: \(settings.displayName(for: selected))")
        }
    }
}

/// A screen title with the server dropdown on its trailing side, under the engine's badge.
public struct ScreenTitleRow: View {
    public let text: String

    @Environment(MetricsPoller.self) private var poller

    public init(_ text: String) { self.text = text }

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            EngineBadge(engine: poller.engine)
            HStack(alignment: .center, spacing: 10) {
                ScreenTitle(text)
                ServerPicker()
            }
        }
    }
}
