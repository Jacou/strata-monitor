import SwiftUI
import UIKit
import StrataCore

/// Engine / hardware / API facts, mirroring `renderAbout` in docs/reference-app.js.
/// The copy buttons put the value on the pasteboard, like the web page's copy icons.
public struct AboutView: View {
    @Environment(MetricsPoller.self) private var poller
    @Environment(AppSettings.self) private var settings
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.theme) private var theme
    @State private var copiedLabel: String?

    public init() {}

    public var body: some View {
        NavigationStack {
            let model = AboutViewModel(metrics: poller.metrics, baseURL: settings.baseURL, health: poller.health)

            ScrollViewReader { proxy in
                List {
                    // The title lives inside the list so the themed background runs through it
                    // instead of leaving a band of list background between the two.
                    ScreenTitleRow("About")
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)

                    if model.isEmpty {
                        Section {
                            Text("No server data yet. Set the address and API key in Settings — this screen reads the same /metrics payload the Monitor polls.")
                                .font(.callout)
                                .foregroundStyle(theme.textSecondary)
                        }
                    }

                    ForEach(model.sections) { section in
                        Section(section.title) {
                            ForEach(Array(section.facts.enumerated()), id: \.element.id) { index, fact in
                                row(fact)
                            }
                        }
                        .id(section.id.lowercased())
                    }

                    Section {
                        if let repository = model.repositoryURL {
                            Link(destination: repository) {
                                Label("github.com/Niko1221/Strata", systemImage: "arrow.up.right.square")
                                    .foregroundStyle(theme.accentText)
                            }
                        }
                    } footer: {
                        Text("This app reads the same endpoints as the \(poller.engine.name) server's own web page.")
                    }
                }
                #if DEBUG
                .onAppear { DebugLaunch.scroll(proxy, to: "api", anchor: .center) }
                #endif
                // Capping the list width would otherwise leave a band of list background down the
                // middle of the screen; hiding it lets the window background run edge to edge.
                .scrollContentBackground(.hidden)
                .background(ThemeBackground())
                .readableFormWidth(horizontalSizeClass)
                .navigationTitle("About")
                .toolbar(.hidden, for: .navigationBar)
            }
        }
    }

    // MARK: - rows

    @ViewBuilder
    private func row(_ fact: AboutFact) -> some View {
        if fact.value.count > 60 {
            // Long prose (the speed projection note) needs the full width.
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(fact.label)
                        .font(theme.subFont)
                        .foregroundStyle(theme.textSecondary)
                    Spacer(minLength: 4)
                    if fact.copyValue != nil { copyButton(fact) }
                }
                Text(fact.value)
                    .font(.callout)
                    .foregroundStyle(theme.textPrimary)
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(fact.label)
                    .foregroundStyle(theme.textPrimary)
                Spacer(minLength: 8)
                Text(fact.value)
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(theme.textSecondary)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)   // a capped column should wrap, not truncate
                    .textSelection(.enabled)
                if fact.copyValue != nil { copyButton(fact) }
            }
        }
    }

    @ViewBuilder
    private func copyButton(_ fact: AboutFact) -> some View {
        Button {
            UIPasteboard.general.string = fact.copyValue
            copiedLabel = fact.id
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1.5))
                if copiedLabel == fact.id { copiedLabel = nil }
            }
        } label: {
            Image(systemName: copiedLabel == fact.id ? "checkmark" : "doc.on.doc")
                .font(.callout)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(theme.accentText)
        .accessibilityLabel("Copy \(fact.label)")
    }
}
