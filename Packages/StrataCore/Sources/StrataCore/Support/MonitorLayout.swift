import SwiftUI

/// How the Monitor screen arranges itself for the current width and text size.
///
/// Compact (iPhone, iPad Split View, narrow Stage Manager) keeps the phone layout.
/// Regular width (iPad) gets a 4-column tile grid, a real request table and the resource
/// cards side by side. Accessibility text sizes always fall back to one column.
public struct MonitorLayout: Sendable, Equatable {
    /// The tile grid's comfortable minimum, the same number the old adaptive grid used.
    public static let tileMinimum: CGFloat = 160
    public static let gridSpacing: CGFloat = 12
    /// Cards stop growing here, so a 13" landscape screen does not stretch them absurdly.
    public static let contentMaxWidth: CGFloat = 1_200
    /// Readable width for the About and Settings forms.
    public static let formMaxWidth: CGFloat = 720

    public let isRegularWidth: Bool
    /// Wide enough for the request table and the side-by-side cards.
    public let isWide: Bool
    public let columns: Int
    public let sparklineHeight: CGFloat

    public init(horizontalSizeClass: UserInterfaceSizeClass?, width: CGFloat, isAccessibilityText: Bool) {
        let regular = horizontalSizeClass == .regular
        self.isRegularWidth = regular
        self.isWide = regular && !isAccessibilityText
        self.columns = Self.metricColumns(
            compact: !regular, width: width, isAccessibilityText: isAccessibilityText
        )
        self.sparklineHeight = isWide ? 48 : 34
    }

    public var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: Self.gridSpacing), count: columns)
    }

    /// 4 columns on a regular-width screen, 2 on a compact one, and 1 when the screen is too
    /// narrow for two tiles (Split View) or the text is an accessibility size.
    public static func metricColumns(compact: Bool, width: CGFloat, isAccessibilityText: Bool) -> Int {
        guard width > 0 else { return 1 }
        if isAccessibilityText { return 1 }
        let wanted = compact ? 2 : 4
        let fits = ((width + gridSpacing) / (tileMinimum + gridSpacing)).rounded(.down)
        return max(1, min(wanted, Int(fits)))
    }
}

extension View {
    /// Forms and lists read better capped than full-bleed on iPad; iPhone keeps the full width.
    @ViewBuilder
    public func readableFormWidth(_ horizontalSizeClass: UserInterfaceSizeClass?) -> some View {
        if horizontalSizeClass == .regular {
            self.frame(maxWidth: MonitorLayout.formMaxWidth)
        } else {
            self
        }
    }
}
