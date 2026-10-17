import SwiftUI
import StrataCore

/// Recent requests, newest first, plus the Show all toggle. Tapping a row opens its detail sheet.
public struct RequestsCard: View {
    public let rows: [MonitorViewModel.RequestRow]
    public let emptyText: String?
    public let showAllLabel: String?
    public let showingAll: Bool
    public let showFewerLabel: String
    /// Regular width gets the web page's table; compact width keeps the two-line rows.
    public let isTable: Bool
    /// The request picked on the trends chart, if there is one.
    public let highlightedID: String?
    public let onToggleShowAll: () -> Void

    @Environment(\.theme) private var theme
    /// Owned by the screen so a debug launch argument can open it too.
    @Binding private var presented: MonitorViewModel.RequestDetail?

    public init(
        rows: [MonitorViewModel.RequestRow],
        emptyText: String?,
        showAllLabel: String?,
        showingAll: Bool,
        showFewerLabel: String = "Show fewer",
        isTable: Bool = false,
        highlightedID: String? = nil,
        presented: Binding<MonitorViewModel.RequestDetail?>,
        onToggleShowAll: @escaping () -> Void
    ) {
        self.rows = rows
        self.emptyText = emptyText
        self.showAllLabel = showAllLabel
        self.showingAll = showingAll
        self.showFewerLabel = showFewerLabel
        self.isTable = isTable
        self.highlightedID = highlightedID
        self._presented = presented
        self.onToggleShowAll = onToggleShowAll
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Recent requests")
                    .font(.headline)
                    .foregroundStyle(theme.textPrimary)
                Spacer()
                if showAllLabel != nil {
                    Button(showingAll ? showFewerLabel : (showAllLabel ?? "Show all")) {
                        onToggleShowAll()
                    }
                    .font(.callout)
                    .foregroundStyle(theme.accentText)
                }
            }

            if let emptyText {
                Text(emptyText)
                    .font(.subheadline)
                    .foregroundStyle(theme.textSecondary)
                    .padding(.vertical, 6)
            } else if isTable {
                RequestsTable(rows: rows, highlightedID: highlightedID) { presented = $0 }
            } else {
                // Lazy: "Show all" can be a hundred rows, and only the visible ones should cost layout.
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(rows) { row in
                        RequestRowButton(row: row, isHighlighted: row.id == highlightedID) { presented = $0 }
                            .id(row.id)   // so the chart's tap can scroll to this row
                        if row.id != rows.last?.id {
                            theme.separator.frame(height: theme.hairline)
                        }
                    }
                }
            }
        }
        .strataCard(theme)
        .sheet(item: $presented) { detail in
            RequestDetailSheet(detail: detail)
        }
    }
}

/// A row is a button: VoiceOver gets "Open details for …", a tap opens the sheet.
private struct RequestRowButton: View {
    let row: MonitorViewModel.RequestRow
    let isHighlighted: Bool
    let onSelect: (MonitorViewModel.RequestDetail) -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        Button {
            onSelect(row.detail)
        } label: {
            RequestRowView(row: row)
                .padding(.horizontal, isHighlighted ? 8 : 0)
                .padding(.vertical, isHighlighted ? 6 : 0)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isHighlighted ? theme.accent.opacity(0.12) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(isHighlighted ? theme.accent : Color.clear, lineWidth: 1)
                )
                .accessibilityHint(
                    isHighlighted
                        ? "Selected on the trends chart. Opens the details for this request"
                        : "Opens the details for this request"
                )
        }
        .buttonStyle(.plain)
    }
}

/// The web page's request table: Time, Status, Prompt, Reused, Output, tok/s, Hit rate (+PCIe),
/// Duration. Numbers right-aligned, all digits monospaced so the columns line up.
private struct RequestsTable: View {
    static let columnCount = 8

    let rows: [MonitorViewModel.RequestRow]
    let highlightedID: String?
    let onSelect: (MonitorViewModel.RequestDetail) -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        Grid(alignment: .trailing, horizontalSpacing: 12, verticalSpacing: 8) {
            GridRow {
                Text("Time").gridColumnAlignment(.leading)
                Text("Status").gridColumnAlignment(.leading)
                Text("Prompt")
                Text("Reused")
                Text("Output")
                Text("tok/s")
                Text("Hit rate")
                Text("Duration")
            }
            .font(theme.badgeFont)
            .foregroundStyle(theme.textSecondary)

            GridRow {
                theme.separator
                    .frame(height: theme.hairline)
                    .gridCellColumns(Self.columnCount)
            }

            ForEach(rows) { row in
                let isHighlighted = row.id == highlightedID

                GridRow {
                    HStack(spacing: 6) {
                        // A GridRow forwards modifiers to each cell, so a background would box
                        // every cell. The table marks the row instead: a dot and accent text.
                        if isHighlighted {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 6))
                                .foregroundStyle(theme.warnText)
                        }
                        Text(row.timeText)
                    }
                    .gridColumnAlignment(.leading)
                    .monospacedDigit()

                    HStack(spacing: 6) {
                        FinishBadge(text: row.finishText, style: row.badge)
                        if let projection = row.projectionText {
                            Text(projection)
                                .font(theme.badgeFont)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .foregroundStyle(theme.accentText)
                                .background(Capsule().fill(theme.accent.opacity(0.08)))
                                .overlay(Capsule().strokeBorder(theme.accent.opacity(0.35), lineWidth: 1))
                        }
                    }
                    .gridColumnAlignment(.leading)

                    Text(row.promptText).monospacedDigit()
                    Text(row.reusedText).monospacedDigit()
                    Text(row.outputText).monospacedDigit()
                    Text(row.tokSText).monospacedDigit()

                    VStack(alignment: .trailing, spacing: 1) {
                        Text(row.hitText).monospacedDigit()
                        if let pcie = row.pcieText {
                            Text(pcie)
                                .font(.caption2)
                                .foregroundStyle(theme.textTertiary)
                                .monospacedDigit()
                        }
                    }

                    Text(row.durationText).monospacedDigit()
                }
                .font(.callout)
                .fontWeight(isHighlighted ? .semibold : .regular)
                .foregroundStyle(isHighlighted ? theme.accentText : theme.textPrimary)
                .contentShape(Rectangle())
                .id(row.id)   // so the chart's tap can scroll to this row
                .onTapGesture { onSelect(row.detail) }
                .accessibilityHint(
                    isHighlighted
                        ? "Selected on the trends chart. Opens the details for this request"
                        : "Opens the details for this request"
                )
            }
        }
    }
}

private struct RequestRowView: View {
    let row: MonitorViewModel.RequestRow

    @Environment(\.theme) private var theme

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(row.timeText)
                        .font(.callout)
                        .monospacedDigit()
                        .foregroundStyle(theme.textPrimary)
                    FinishBadge(text: row.finishText, style: row.badge)
                    if let projection = row.projectionText {
                        Text(projection)
                            .font(theme.badgeFont)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .foregroundStyle(theme.accentText)
                            .background(Capsule().fill(theme.accent.opacity(0.08)))
                            .overlay(Capsule().strokeBorder(theme.accent.opacity(0.35), lineWidth: 1))
                    }
                }
                Text("prompt \(row.promptText) · reused \(row.reusedText) · out \(row.outputText)")
                    .font(theme.subFont)
                    .monospacedDigit()
                    .foregroundStyle(theme.textTertiary)
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 3) {
                Text("\(row.tokSText) t/s")
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(theme.textPrimary)
                HStack(spacing: 4) {
                    Text(row.hitText)
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(theme.textSecondary)
                    if let pcie = row.pcieText {
                        Text(pcie)
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(theme.textTertiary)
                    }
                }
                Text(row.durationText)
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(theme.textTertiary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
