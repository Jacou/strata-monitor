import SwiftUI
import StrataCore

/// The editor for one run-config key: the control that fits its kind, and a way back to the
/// file's own value (which the server reads as `null`).
public struct ConfigEditorSheet: View {
    public let key: ConfigKey
    public let current: ConfigValue?
    public let onSave: (ConfigValue?) -> Void

    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var useDefault: Bool
    @State private var numberText: String
    @State private var boolValue: Bool
    @State private var choiceIndex: Int
    @State private var textValue: String

    public init(key: ConfigKey, current: ConfigValue?, onSave: @escaping (ConfigValue?) -> Void) {
        self.key = key
        self.current = current
        self.onSave = onSave

        let isDefault = current == nil || current == .null
        _useDefault = State(initialValue: isDefault)
        _numberText = State(initialValue: isDefault ? "" : (current?.text ?? ""))
        _boolValue = State(initialValue: current?.boolValue ?? true)
        _textValue = State(initialValue: isDefault ? "" : (current?.stringValue ?? ""))

        let options = key.options
        let index = options.firstIndex { $0.text == (current?.text ?? "") }
        _choiceIndex = State(initialValue: index ?? 0)
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Key", value: key.key)
                    LabeledContent("Kind", value: key.kind.label)
                    LabeledContent("In the file", value: key.value?.text ?? "default")
                    if let help = key.help, !help.isEmpty {
                        Text(help)
                            .font(.footnote)
                            .foregroundStyle(theme.textSecondary)
                    }
                }

                Section {
                    Toggle("Use the file's default", isOn: $useDefault)

                    if !useDefault {
                        control

                        if isInvalid {
                            Label("That value will not be accepted.", systemImage: "exclamationmark.triangle")
                                .font(.footnote)
                                .foregroundStyle(theme.dangerText)
                        }
                    }
                } footer: {
                    Text("Turning this on sends null: the key goes back to what the run config file says.")
                }

                Section {
                    HStack(spacing: 12) {
                        Button("Cancel") { dismiss() }
                            .foregroundStyle(theme.accentText)
                        Spacer(minLength: 0)
                        Button("Set value") {
                            onSave(proposed)
                            dismiss()
                        }
                        .disabled(isInvalid)
                        .foregroundStyle(isInvalid ? theme.textTertiary : theme.accentText)
                    }
                }
            }
            .navigationTitle(key.key)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - the control that fits the kind

    @ViewBuilder
    private var control: some View {
        switch key.kind {
        case .number:
            TextField("Number", text: $numberText)
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
                .monospacedDigit()

        case .boolean:
            Toggle("On", isOn: $boolValue)

        case .enum where !key.options.isEmpty:
            Picker("Value", selection: $choiceIndex) {
                ForEach(Array(key.options.enumerated()), id: \.offset) { index, option in
                    Text(option.text).tag(index)
                }
            }

        case .enum, .names, .other:
            TextField(key.kind == .names ? "Names, separated by commas" : "Value", text: $textValue)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
        }
    }

    private var isInvalid: Bool {
        if useDefault { return false }
        switch key.kind {
        case .number:
            let raw = trimmed(numberText)
            return !raw.isEmpty && Double(raw) == nil
        case .enum:
            return !key.options.isEmpty && (choiceIndex < 0 || choiceIndex >= key.options.count)
        default:
            return false
        }
    }

    /// nil means "use the default", exactly like the web page's empty field.
    private var proposed: ConfigValue? {
        if useDefault { return nil }
        switch key.kind {
        case .number:
            let raw = trimmed(numberText)
            guard !raw.isEmpty, let value = Double(raw) else { return nil }
            return .number(value)
        case .boolean:
            return .bool(boolValue)
        case .enum:
            guard !key.options.isEmpty else { return trimmed(textValue).isEmpty ? nil : .string(trimmed(textValue)) }
            guard choiceIndex >= 0, choiceIndex < key.options.count else { return nil }
            return key.options[choiceIndex]
        case .names, .other:
            let raw = trimmed(textValue)
            return raw.isEmpty ? nil : .string(raw)
        }
    }

    private func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
