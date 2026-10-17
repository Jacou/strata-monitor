import AppKit
import StrataCore
import SwiftUI

/// The Settings window: the same fields and the same connection test as the iOS Settings tab, plus
/// "Launch at login" and how often to refresh while nothing is on screen.
struct MenuBarSettingsView: View {
    let model: MenuBarModel

    @Environment(\.theme) private var theme

    @State private var urlDraft = ""
    @State private var keyDraft = ""
    @State private var tester = ConnectionTester()
    @State private var launchAtLogin = false
    @State private var loginNote: String?
    @State private var cadenceDraft = AppSettings.defaultClosedPollInterval
    @State private var draftsLoaded = false

    private var draftURL: URL? { AppSettings.validURL(urlDraft) }
    private var canSave: Bool { draftURL != nil }
    private var busy: Bool { tester.state == .testing }

    var body: some View {
        Form {
            Section("Server address") {
                TextField("http://192.168.1.10:8081", text: $urlDraft)
                    .textFieldStyle(.roundedBorder)
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
                SecureField("API key", text: $keyDraft)
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())

                Text("Kept in this Mac's Keychain under \(MenuBarModel.keychainService).")
                    .font(.footnote)
                    .foregroundStyle(theme.textSecondary)
            }

            Section("Polling") {
                Picker("Refresh when closed", selection: $cadenceDraft) {
                    ForEach(AppSettings.closedPollIntervalChoices, id: \.self) { interval in
                        Text(AppSettings.closedPollIntervalLabel(interval)).tag(interval)
                    }
                }
                .pickerStyle(.segmented)

                Text("While the hover card or the popover is on screen the app always refreshes every 1 s.")
                    .font(.footnote)
                    .foregroundStyle(theme.textSecondary)
            }

            Section {
                HStack(spacing: 12) {
                    Toggle("Launch at login", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { _, want in setLaunchAtLogin(want) }

                    Button("Test connection") { testConnection() }
                        .disabled(!canSave || busy)
                }

                if tester.state != .idle {
                    Label(tester.state.text,
                          systemImage: tester.state.isOK ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(tester.state.isOK ? theme.accentText : theme.dangerText)
                }

                if let loginNote {
                    Text(loginNote)
                        .font(.footnote)
                        .foregroundStyle(theme.warnText)
                }

                HStack {
                    LabeledContent("Address",
                                   value: model.settings.isValidBaseURL ? model.settings.baseURLString : "invalid — not used")
                    LabeledContent("API key",
                                   value: model.settings.hasAPIKey ? "stored in the Keychain" : "not set")
                }

                HStack {
                    LabeledContent("Refresh when closed",
                                   value: AppSettings.closedPollIntervalLabel(model.settings.closedPollInterval))
                    LabeledContent("Refresh on screen", value: "1 s")
                }

                Spacer(minLength: 0)

                HStack {
                    Button("Save") { save() }
                        .disabled(!canSave || busy)
                        .keyboardShortcut("s")
                    Spacer()
                    Button("Quit") { NSApplication.shared.terminate(nil) }
                        .keyboardShortcut("q")
                        .foregroundStyle(theme.dangerText)
                }
            }
        }
        .formStyle(.grouped)
        .padding(12)
        .frame(width: 460, height: 480)
        .background(ThemeBackground())
        .onAppear(perform: loadDrafts)
    }

    // MARK: - actions

    private func loadDrafts() {
        guard !draftsLoaded else { return }
        draftsLoaded = true
        urlDraft = model.settings.baseURLString
        keyDraft = model.settings.apiKey
        cadenceDraft = model.settings.closedPollInterval
        launchAtLogin = LaunchAtLogin.isEnabled
    }

    private func save() {
        guard canSave else { return }
        model.settings.baseURLString = trimmed(urlDraft)
        model.settings.apiKey = keyDraft
        model.settings.closedPollInterval = cadenceDraft
        model.reconnect()
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

    private func setLaunchAtLogin(_ want: Bool) {
        do {
            try LaunchAtLogin.set(want)
            loginNote = nil
        } catch {
            // Login items need a properly signed, non-translocated app; say so instead of failing quietly.
            loginNote = "Could not \(want ? "register" : "remove") the login item: \(error.localizedDescription)"
            launchAtLogin = LaunchAtLogin.isEnabled
        }
    }

    private func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
