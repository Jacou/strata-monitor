import SwiftUI

/// "Basalt server" / "Strata server" with the engine's mark, in the accent of its palette: the
/// line above each screen title and at the top of the menu bar popover.
public struct EngineBadge: View {
    public let engine: ServerEngine

    @Environment(\.theme) private var theme

    public init(engine: ServerEngine) {
        self.engine = engine
    }

    public var body: some View {
        HStack(spacing: 5) {
            mark
            Text("\(engine.name) server")
                .tracking(0.6)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(theme.accentText)
        .accessibilityElement(children: .combine)
    }

    /// Basalt's logo is a cluster of hexagonal columns with an ember one in the middle; Strata's
    /// name is layers of rock.
    @ViewBuilder
    private var mark: some View {
        switch engine {
        case .basalt:
            Image(systemName: "hexagon.fill")
                .foregroundStyle(LinearGradient(colors: [theme.warn, theme.accent, theme.accentDim],
                                                startPoint: .topLeading, endPoint: .bottomTrailing))
        case .strata:
            Image(systemName: "square.stack.3d.up.fill")
        }
    }
}
