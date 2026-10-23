import SwiftUI
import StrataCore

public struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(MetricsPoller.self) private var poller
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.theme) private var theme

    @State private var tester = ConnectionTester()
    /// Which server the fields below edit — not necessarily the one the app is showing.
    @State private var editingSlot: ServerSlot = .primary
    @State private var nameDraft = ""
    @State private var urlDraft = ""
    @State private var keyDraft = ""
    @State private var showKey = false
    @State private var draftsLoaded = false
    @State private var confirmRemove = false

    public init() {}

    private var draftURL: URL? { AppSettings.validURL(urlDraft) }
    private var canSave: Bool { draftURL != nil }
    private var busy: Bool { tester.state == .testing }
    private var editingShown: Bool { editingSlot == settings.selectedSlot }

    public var body: some View {
        NavigationStack {
            Form {
                // The title lives inside the form so the themed background runs through it
                // without a band of form background between the two.
                ScreenTitle("Settings")
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                Section {
                    Picker("Server", selection: $editingSlot) {
                        ForEach(ServerSlot.allCases) { slot in
                            Text(settings.displayName(for: slot)).tag(slot)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: editingSlot) { _, _ in reloadDrafts() }
                } footer: {
                    Text(editingSlot == .secondary && !settings.isConfigured(.secondary)
                         ? "Give a second server an address to switch between the two from any tab."
                         : "Edit one server at a time; the dropdown beside each title picks the one shown.")
                }
                .listRowBackground(Color.clear)

                Section {
                    TextField(editingSlot.defaultName, text: $nameDraft)
                        .autocorrectionDisabled()
                        .foregroundStyle(theme.textPrimary)
                } header: {
                    Text("Name")
                } footer: {
                    Text("Shown in the server menu.")
                }

                Section("Server address") {
                    TextField("http://192.168.1.10:8081", text: $urlDraft)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .monospacedDigit()
                        .foregroundStyle(canSave ? theme.textPrimary : theme.dangerText)

                    if !canSave {
                        Label("Needs http:// or https:// and a host — for example http://192.168.1.10:8081",
                              systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(theme.dangerText)
                    }

                    if editingSlot == .primary {
                        Button("Use the default") { urlDraft = AppSettings.defaultBaseURLString }
                            .font(.footnote)
                            .foregroundStyle(theme.accentText)
                            .disabled(urlDraft == AppSettings.defaultBaseURLString)
                    }
                }

                Section("API key") {
                    HStack(spacing: 8) {
                        if showKey {
                            TextField("API key", text: $keyDraft)
                        } else {
                            SecureField("API key", text: $keyDraft)
                        }

                        Button {
                            showKey.toggle()
                        } label: {
                            Image(systemName: showKey ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(theme.accentText)
                        .accessibilityLabel(showKey ? "Hide the key" : "Show the key")
                    }
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.body.monospaced())
                    .foregroundStyle(theme.textPrimary)

                    Text("Kept in the Keychain — not in UserDefaults, not in the app's files.")
                        .font(.footnote)
                        .foregroundStyle(theme.textSecondary)

                    if editingShown, poller.status == .unauthorized {
                        Label(
                            settings.hasAPIKey
                                ? "This server rejected the saved key."
                                : "This server needs an API key. Add it above.",
                            systemImage: "key.slash"
                        )
                            .font(.footnote)
                            .foregroundStyle(theme.dangerText)
                    }
                }

                Section {
                    Button("Save") { save() }
                        .disabled(!canSave || busy)
                    Button {
                        testConnection()
                    } label: {
                        if busy {
                            ProgressView()
                        } else {
                            Text("Test connection")
                        }
                    }
                    .disabled(!canSave || busy)

                    if tester.state != .idle {
                        Label(tester.state.text,
                              systemImage: tester.state.isOK ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.footnote)
                            .foregroundStyle(tester.state.isOK ? theme.accentText : theme.dangerText)
                    }
                } footer: {
                    Text(editingShown
                         ? "Save points the live poller at the new address and key."
                         : "Save stores this server; pick it from the dropdown to see it.")
                }

                Section("Saved") {
                    LabeledContent("Name", value: settings.displayName(for: editingSlot))
                    LabeledContent("Address", value: savedAddressText)
                    LabeledContent("API key", value: settings.hasAPIKey(for: editingSlot) ? "stored in the Keychain" : "not set")
                }

                if editingSlot == .secondary, settings.isConfigured(.secondary) {
                    Section {
                        Button("Remove \(settings.displayName(for: .secondary))", role: .destructive) {
                            confirmRemove = true
                        }
                    }
                    .confirmationDialog("Remove \(settings.displayName(for: .secondary))?",
                                        isPresented: $confirmRemove, titleVisibility: .visible) {
                        Button("Remove", role: .destructive) { removeSecondary() }
                    } message: {
                        Text("Its address, name and API key are forgotten.")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(ThemeBackground())
            .readableFormWidth(horizontalSizeClass)
            .navigationTitle("Settings")
            .toolbar(.hidden, for: .navigationBar)
            .onAppear(perform: loadDrafts)
        }
    }

    // MARK: - actions

    private var savedAddressText: String {
        let address = settings.baseURLString(for: editingSlot)
        if address.isEmpty { return "not set" }
        return settings.baseURL(for: editingSlot) != nil ? address : "invalid — not used"
    }

    private func loadDrafts() {
        guard !draftsLoaded else { return }
        draftsLoaded = true
        editingSlot = settings.selectedSlot
        reloadDrafts()
    }

    private func reloadDrafts() {
        nameDraft = settings.name(for: editingSlot)
        urlDraft = settings.baseURLString(for: editingSlot)
        keyDraft = settings.apiKey(for: editingSlot)
        tester.reset()
    }

    private func save() {
        guard canSave else { return }
        settings.setName(nameDraft, for: editingSlot)
        settings.setBaseURLString(trimmed(urlDraft), for: editingSlot)
        settings.setAPIKey(keyDraft, for: editingSlot)
        nameDraft = settings.name(for: editingSlot)
        if editingShown, let client = settings.makeClient() {
            poller.update(client: client)
        }
        tester.reset()
    }

    /// The selection falls back to the primary server, and RootView moves the poller with it.
    private func removeSecondary() {
        settings.removeSecondary()
        editingSlot = .primary
        reloadDrafts()
    }

    private func testConnection() {
        guard let url = draftURL else {
            tester.fail("Fix the server address first")
            return
        }
        let client = StrataClient(baseURL: url, apiKey: trimmed(keyDraft))
        Task { await tester.run(client: client) }
    }

    private func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
