import AppKit
import StrataCore
import SwiftUI

/// The Settings window: the same fields and the same connection test as the iOS Settings tab — one
/// server at a time, each with its own menu bar item — plus "Launch at login" and how often to
/// refresh while nothing is on screen.
struct MenuBarSettingsView: View {
    let model: MenuBarModel

    @Environment(\.theme) private var theme

    /// Which server the fields below edit.
    @State private var editingSlot: ServerSlot = .primary
    @State private var nameDraft = ""
    @State private var urlDraft = ""
    @State private var keyDraft = ""
    @State private var tester = ConnectionTester()
    @State private var launchAtLogin = false
    @State private var loginNote: String?
    @State private var cadenceDraft = AppSettings.defaultClosedPollInterval
    @State private var draftsLoaded = false
    @State private var confirmRemove = false

    private var draftURL: URL? { AppSettings.validURL(urlDraft) }
    private var canSave: Bool { draftURL != nil }
    private var busy: Bool { tester.state == .testing }

    var body: some View {
        Form {
            Section {
                Picker("Server", selection: $editingSlot) {
                    ForEach(ServerSlot.allCases) { slot in
                        Text(model.settings.displayName(for: slot)).tag(slot)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .onChange(of: editingSlot) { _, _ in reloadServerDrafts() }

                TextField("Name", text: $nameDraft, prompt: Text(editingSlot.defaultName))
                    .textFieldStyle(.roundedBorder)

                Text(editingSlot == .secondary && !model.settings.isConfigured(.secondary)
                     ? "Give a second server an address and it gets its own menu bar item."
                     : "With two servers, the start of each name (or 1 / 2) sits in front of its menu bar item.")
                    .font(.footnote)
                    .foregroundStyle(theme.textSecondary)
            }

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

                HStack {
                    if editingSlot == .primary {
                        Button("Use the default") { urlDraft = AppSettings.defaultBaseURLString }
                            .disabled(urlDraft == AppSettings.defaultBaseURLString)
                    } else if model.settings.isConfigured(.secondary) {
                        Button("Remove \(model.settings.displayName(for: .secondary))…") { confirmRemove = true }
                            .foregroundStyle(theme.dangerText)
                    }
                }
                .font(.footnote)
                .foregroundStyle(theme.accentText)
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
                    LabeledContent("Address", value: savedAddressText)
                    LabeledContent("API key",
                                   value: model.settings.hasAPIKey(for: editingSlot) ? "stored in the Keychain" : "not set")
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
        .frame(width: 460, height: 600)
        .background(ThemeBackground())
        .onAppear(perform: loadDrafts)
        .confirmationDialog("Remove \(model.settings.displayName(for: .secondary))?",
                            isPresented: $confirmRemove) {
            Button("Remove", role: .destructive) { removeSecondary() }
        } message: {
            Text("Its address, name and API key are forgotten, and its menu bar item goes away.")
        }
    }

    // MARK: - actions

    private var savedAddressText: String {
        let address = model.settings.baseURLString(for: editingSlot)
        if address.isEmpty { return "not set" }
        return model.settings.baseURL(for: editingSlot) != nil ? address : "invalid — not used"
    }

    private func loadDrafts() {
        guard !draftsLoaded else { return }
        draftsLoaded = true
        reloadServerDrafts()
        cadenceDraft = model.settings.closedPollInterval
        launchAtLogin = LaunchAtLogin.isEnabled
    }

    private func reloadServerDrafts() {
        nameDraft = model.settings.name(for: editingSlot)
        urlDraft = model.settings.baseURLString(for: editingSlot)
        keyDraft = model.settings.apiKey(for: editingSlot)
        tester.reset()
    }

    /// Saves the server being edited and the cadence; a newly set-up second server gets its item.
    private func save() {
        guard canSave else { return }
        model.settings.setName(nameDraft, for: editingSlot)
        model.settings.setBaseURLString(trimmed(urlDraft), for: editingSlot)
        model.settings.setAPIKey(keyDraft, for: editingSlot)
        model.settings.closedPollInterval = cadenceDraft
        nameDraft = model.settings.name(for: editingSlot)
        model.reconnect()
        tester.reset()
    }

    private func removeSecondary() {
        model.settings.removeSecondary()
        model.reconnect()
        editingSlot = .primary
        reloadServerDrafts()
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
