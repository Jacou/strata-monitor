import SwiftUI
import StrataCore

/// The Config tab: the run-config keys this server will edit, grouped by prefix, with the file's
/// own value shown until you change one.
public struct ConfigView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.theme) private var theme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var store = ConfigStore()
    @State private var editing: ConfigKey?

    public init() {}

    public var body: some View {
        NavigationStack {
            List {
                ScreenTitleRow("Config")
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                if store.model.isEmpty {
                    Section {
                        Text(store.errorText ?? "This server does not expose its run config.")
                            .font(.subheadline)
                            .foregroundStyle(store.isUnavailable ? theme.dangerText : theme.textSecondary)
                    } footer: {
                        Text("An older server, one with no run config, or one that has not been given its key yet.")
                    }
                } else {
                    Section {
                        LabeledContent("File", value: store.model.file.isEmpty ? notAvailable : store.model.file)
                        LabeledContent("Keys", value: "\(store.model.keyCount)")
                    } footer: {
                        Text("Changes apply from the next time the model starts. Tap a key to change it.")
                    }

                    ForEach(store.model.groups) { group in
                        Section(group.title) {
                            ForEach(group.rows) { row in
                                if let key = store.model.keys.first(where: { $0.key == row.id }) {
                                    ConfigRowView(
                                        key: key,
                                        value: store.value(for: key),
                                        edited: store.pendingChanges[key.key] != nil
                                    ) { editing = key }
                                }
                            }
                        }
                    }

                    Section {
                        HStack(spacing: 12) {
                            Button("Save") {
                                Task { await store.save(client: settings.makeClient()) }
                            }
                            .disabled(!store.hasChanges || store.isBusy)
                            .foregroundStyle(theme.accentText)

                            Button("Discard") { store.discardEdits() }
                                .disabled(!store.hasChanges)
                                .foregroundStyle(theme.accentText)

                            Spacer(minLength: 0)

                            if store.isBusy { ProgressView() }
                        }

                        if let message = store.message {
                            Text(message)
                                .font(.footnote)
                                .foregroundStyle(theme.accentText)
                        }

                        if let error = store.errorText {
                            Text(error)
                                .font(.footnote)
                                .foregroundStyle(theme.dangerText)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(ThemeBackground())
            .readableFormWidth(horizontalSizeClass)
            .navigationTitle("Config")
            .toolbar(.hidden, for: .navigationBar)
            .task { await store.load(client: settings.makeClient()) }
            .refreshable { await store.load(client: settings.makeClient()) }
            // The run config belongs to the server, so a new address or key — or the other server picked — means read it again.
            .onChange(of: settings.baseURLString) { _, _ in Task { await store.load(client: settings.makeClient()) } }
            .onChange(of: settings.apiKey) { _, _ in Task { await store.load(client: settings.makeClient()) } }
            .sheet(item: $editing) { key in
                ConfigEditorSheet(key: key, current: store.value(for: key)) { value in
                    store.setEdit(value, for: key.key)
                }
            }
            #if DEBUG
            .onAppear {
                // simctl cannot tap a row, so `--open-config` opens the first key's editor sheet.
                if DebugLaunch.opensConfigSheet {
                    // simctl cannot tap a row: `--open-config` opens a key's editor sheet, the
                    // first one or the one `--open-config=<key>` names.
                    DebugLaunch.retryUntilOpened {
                        if editing != nil { return true }
                        let wanted = DebugLaunch.configKeyToOpen
                        guard let key = store.model.keys.first(where: { wanted == nil || $0.key == wanted }) else { return false }
                        editing = key
                        return true
                    }
                }
            }
            #endif
        }
    }
}

/// One key: name, current value (or "default"), kind, and Strata's own help text underneath.
private struct ConfigRowView: View {
    let key: ConfigKey
    let value: ConfigValue?
    let edited: Bool
    let onEdit: () -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        Button(action: onEdit) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(key.key)
                        .font(.body.monospaced())
                        .foregroundStyle(theme.textPrimary)
                    Spacer(minLength: 4)
                    HStack(spacing: 4) {
                        if edited {
                            Image(systemName: "circle.fill")
                                .font(.system(size: 6))
                                .foregroundStyle(theme.warnText)
                                .accessibilityLabel("changed")
                        }
                        Text(value?.text ?? "default")
                            .font(.body.monospacedDigit())
                            .foregroundStyle(value == nil ? theme.textTertiary : theme.accentText)
                    }
                }

                HStack(spacing: 6) {
                    Text(key.kind.label)
                        .font(theme.badgeFont)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .foregroundStyle(theme.textSecondary)
                        .background(Capsule().fill(theme.track.opacity(0.5)))
                    if let help = key.help, !help.isEmpty {
                        Text(help)
                            .font(theme.subFont)
                            .foregroundStyle(theme.textTertiary)
                            .multilineTextAlignment(.leading)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Change \(key.key)")
    }
}
