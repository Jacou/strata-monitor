import SwiftUI
import StrataCore

public struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(MetricsPoller.self) private var poller
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.theme) private var theme

    @State private var tester = ConnectionTester()
    @State private var urlDraft = ""
    @State private var keyDraft = ""
    @State private var showKey = false
    @State private var draftsLoaded = false

    public init() {}

    private var draftURL: URL? { AppSettings.validURL(urlDraft) }
    private var canSave: Bool { draftURL != nil }
    private var busy: Bool { tester.state == .testing }

    public var body: some View {
        NavigationStack {
            Form {
                // The title lives inside the form so the themed background runs through it
                // without a band of form background between the two.
                ScreenTitle("Settings")
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

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

                    Button("Use the default") { urlDraft = AppSettings.defaultBaseURLString }
                        .font(.footnote)
                        .foregroundStyle(theme.accentText)
                        .disabled(urlDraft == AppSettings.defaultBaseURLString)
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

                    if poller.status == .unauthorized {
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
                    Text("Save points the live poller at the new address and key.")
                }

                Section("Saved") {
                    LabeledContent("Address", value: settings.isValidBaseURL ? settings.baseURLString : "invalid — not used")
                    LabeledContent("API key", value: settings.hasAPIKey ? "stored in the Keychain" : "not set")
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

    private func loadDrafts() {
        guard !draftsLoaded else { return }
        draftsLoaded = true
        urlDraft = settings.baseURLString
        keyDraft = settings.apiKey
    }

    private func save() {
        guard canSave else { return }
        settings.baseURLString = trimmed(urlDraft)
        settings.apiKey = keyDraft
        if let client = settings.makeClient() {
            poller.update(client: client)
        }
        tester.reset()
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
