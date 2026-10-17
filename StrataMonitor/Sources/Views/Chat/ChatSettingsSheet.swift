import SwiftUI
import StrataCore

/// The sampling settings a chat request carries — the web page's settings drawer. Defaults are
/// its `DEFAULTS`; "Reset" puts them back.
struct ChatSettingsSheet: View {
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    @Bindable var settings: ChatSettings

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Thinking", selection: $settings.sampling.effort) {
                        ForEach(ReasoningEffort.allCases, id: \.self) { effort in
                            Text(effort.label).tag(effort)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Thinking")
                } footer: {
                    Text("\(settings.sampling.effort.label): \(settings.sampling.effort.hint). Sent as reasoning_effort.")
                }

                Section {
                    LabeledContent("Temperature", value: settings.sampling.temperatureLabel)
                        .monospacedDigit()
                    Slider(value: $settings.sampling.temperature, in: 0...2, step: 0.05)
                        .tint(theme.accent)
                        .accessibilityLabel("Temperature")

                    LabeledContent("top_p", value: String(format: "%.2f", settings.sampling.topP))
                        .monospacedDigit()
                    Slider(value: $settings.sampling.topP, in: 0.05...1, step: 0.01)
                        .tint(theme.accent)
                        .accessibilityLabel("top_p")
                        .disabled(settings.sampling.isGreedy)

                    Stepper("top_k: \(settings.sampling.topK)", value: $settings.sampling.topK, in: 1...100)
                        .monospacedDigit()
                        .disabled(settings.sampling.isGreedy)
                } header: {
                    Text("Sampling")
                } footer: {
                    Text(settings.sampling.isGreedy
                         ? "Temperature 0 is greedy: only temperature is sent, top_p and top_k stay out."
                         : "Sent with every request. The web page's defaults are 0.60 · 0.95 · 20.")
                }

                Section {
                    LabeledContent("Max tokens") {
                        TextField("server default", value: $settings.sampling.maxTokens, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                    }
                    LabeledContent("Seed") {
                        TextField("random", value: $settings.sampling.seed, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                    }
                } header: {
                    Text("Limits")
                } footer: {
                    Text("Empty means the server decides. A seed makes the same question give the same answer.")
                }

                Section {
                    TextField("None", text: $settings.sampling.systemPrompt, axis: .vertical)
                        .lineLimit(2...8)
                        .autocorrectionDisabled()
                } header: {
                    Text("System prompt")
                } footer: {
                    Text("Sent first in every request of every chat.")
                }

                Section {
                    Toggle("Show thinking while it answers", isOn: $settings.sampling.showsThinking)
                        .tint(theme.accent)
                } footer: {
                    Text("Opens the thoughts block while the model thinks; it folds once the answer starts.")
                }

                Section {
                    Button("Reset to defaults", role: .destructive) { settings.reset() }
                }
            }
            .scrollContentBackground(.hidden)
            .background(ThemeBackground())
            .navigationTitle("Chat settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }
}
