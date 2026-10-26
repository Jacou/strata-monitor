import SwiftUI
import StrataCore

/// The Monitor's way into the log: a card like the others, with a chevron.
struct LogsLinkCard: View {
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "text.alignleft")
                .foregroundStyle(theme.accentText)
            VStack(alignment: .leading, spacing: 2) {
                Text("Server log")
                    .font(.headline)
                    .foregroundStyle(theme.textPrimary)
                Text("What the engine is writing, live")
                    .font(theme.subFont)
                    .foregroundStyle(theme.textSecondary)
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(theme.textTertiary)
        }
        .contentShape(Rectangle())
        .strataCard(theme)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// Basalt's server log, tailed every two seconds while on screen: newest at the bottom, a level
/// filter and a search like the web page's Logs pane. Follows the end unless you scroll up.
struct LogsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.theme) private var theme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var feed = LogFeed()
    @State private var follows = true

    var body: some View {
        let shown = feed.shown

        ScrollViewReader { proxy in
            List {
                Section {
                    if let error = feed.errorText {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(theme.dangerText)
                    } else if feed.hasLoaded, shown.isEmpty {
                        Text(feed.lines.isEmpty ? "Nothing logged yet." : "No line matches.")
                            .font(.footnote)
                            .foregroundStyle(theme.textTertiary)
                    } else if !feed.hasLoaded {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    }

                    ForEach(shown) { line in
                        LogLineRow(line: line)
                            .id(line.id)
                    }
                } footer: {
                    if !feed.lines.isEmpty {
                        Text("\(shown.count) of the last \(feed.lines.count) lines")
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(ThemeBackground())
            // Pinned above the list: the log follows its end, so a filter at the top of the
            // content would be out of reach.
            .safeAreaInset(edge: .top, spacing: 0) {
                Picker("Level", selection: $feed.filter) {
                    ForEach(LogFeed.Filter.allCases) { filter in
                        Text(filter.label).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.bar)
            }
            .searchable(text: $feed.query, placement: .navigationBarDrawer(displayMode: .automatic), prompt: "Search the log")
            .onChange(of: shown.last?.id) { _, last in
                guard follows, let last else { return }
                proxy.scrollTo(last, anchor: .bottom)
            }
            .onScrollGeometryChange(for: Bool.self) { geometry in
                // At (or within a line of) the end: keep following. Scrolled up: hold still.
                geometry.contentOffset.y + geometry.containerSize.height >= geometry.contentSize.height - 40
            } action: { _, atEnd in
                follows = atEnd
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        follows = true
                        if let last = shown.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                    } label: {
                        Image(systemName: "arrow.down.to.line")
                    }
                    .disabled(follows)
                    .accessibilityLabel("Jump to the newest line")
                }
            }
        }
        .navigationTitle("Server log")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { feed.start { settings.makeClient() } }
        .onDisappear { feed.stop() }
        .onChange(of: settings.selectedSlot) { _, _ in feed.reset() }
    }
}

/// One line: time, where it came from, the level when it is not info, and the message.
private struct LogLineRow: View {
    let line: LogLine

    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(timeText)
                    .monospacedDigit()
                if let source = line.source {
                    Text(source)
                }
                if line.level != .info {
                    Text(line.level == .err ? "ERROR" : "WARN")
                        .fontWeight(.semibold)
                        .foregroundStyle(levelColor)
                }
            }
            .font(.caption2)
            .foregroundStyle(theme.textTertiary)

            Text(line.message)
                .font(.footnote.monospaced())
                .foregroundStyle(line.level == .info ? theme.textPrimary : levelColor)
                .textSelection(.enabled)
        }
        .listRowBackground(Color.clear)
        .accessibilityElement(children: .combine)
    }

    private var levelColor: Color {
        line.level == .err ? theme.dangerText : theme.warnText
    }

    private var timeText: String {
        guard let time = line.time else { return "" }
        return Date(timeIntervalSince1970: time).formatted(date: .omitted, time: .standard)
    }
}
