import SwiftUI
import StrataCore

/// The Chat tab: the conversation, the composer, and the sampling settings a request carries.
public struct ChatView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(MetricsPoller.self) private var poller
    @Environment(ChatViewModel.self) private var chat
    @Environment(\.theme) private var theme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var showSettings = false
    @State private var pendingPrompt: String?

    public init() {}

    public var body: some View {
        NavigationStack {
            VStack(spacing: 10) {
                header

                messages

                if settings.baseURL == nil {
                    Label("Set a server address under Settings before asking.", systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(theme.dangerText)
                        .padding(.horizontal, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                ChatComposer(chat: chat) { send() }
                    .padding(.bottom, 8)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(ThemeBackground())
            .navigationTitle("Chat")
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showSettings) {
                ChatSettingsSheet(settings: chat.settings)
            }
            #if DEBUG
            .onAppear {
                // simctl cannot type in the composer, so `--ask="…"` asks that question — which is
                // how a screenshot gets a real exchange. It waits for /health so the request
                // carries the model name. `--open-chat-settings` opens the sheet.
                if DebugLaunch.opensChatSettings { showSettings = true }
                guard let prompt = DebugLaunch.chatPrompt, pendingPrompt == nil else { return }
                pendingPrompt = prompt
                DebugLaunch.retryUntilOpened { [self] in
                    guard poller.health?.model != nil, let question = pendingPrompt else { return false }
                    pendingPrompt = nil
                    chat.draft = question
                    send()
                    return true
                }
            }
            #endif
        }
    }

    // MARK: - header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScreenTitleRow("Chat")

            HStack(spacing: 10) {
                statusLine
                Spacer(minLength: 8)
                chatsMenu
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .accessibilityLabel("Chat settings")
            }
        }
        .padding(.top, 4)
    }

    private var statusLine: some View {
        HStack(spacing: 8) {
            if chat.isStreaming {
                Label("Answering", systemImage: "waveform")
                    .foregroundStyle(theme.accentText)
            } else if let model = poller.health?.model, !model.isEmpty {
                Text(model)
                    .foregroundStyle(theme.textTertiary)
            }
        }
        .font(.footnote)
        .monospacedDigit()
        .lineLimit(1)
    }

    private var chatsMenu: some View {
        Menu {
            Button("New chat") { chat.newChat() }

            if chat.conversations.count > 1 {
                Divider()
                ForEach(chat.conversations.reversed()) { conversation in
                    Button(conversation.title) { chat.open(conversation.id) }
                }
            }

            if !chat.conversations.isEmpty {
                Divider()
                Button("Delete all chats", role: .destructive) { chat.deleteAll() }
            }
        } label: {
            Image(systemName: "bubble.left.and.bubble.right")
        }
        .accessibilityLabel("Chats")
    }

    // MARK: - the conversation

    private var messages: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if chat.isEmpty {
                        emptyState
                    } else {
                        ForEach(chat.messages) { message in
                            ChatMessageRow(
                                message: message,
                                isStreaming: message.id == chat.streamingMessageID,
                                showsThinking: chat.settings.sampling.showsThinking
                            )
                            .id(message.id)
                        }
                    }
                }
                .padding(.bottom, 8)
                .frame(maxWidth: horizontalSizeClass == .regular ? 900 : .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: chat.messages.count) { _, _ in
                if let last = chat.messages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            .onChange(of: chat.streamingMessage?.text) { _, _ in
                // Follow the answer as it arrives, the way the web page keeps the scroll pinned low.
                if let id = chat.streamingMessageID { proxy.scrollTo(id, anchor: .bottom) }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ask something")
                .font(.title3.weight(.semibold))
                .foregroundStyle(theme.textPrimary)
            Text(notes)
                .font(.footnote)
                .foregroundStyle(theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .strataCard(theme)
        .padding(.top, 4)
    }

    /// v1 sends text only. The web page can attach images, and this server says it takes them.
    private var notes: String {
        var lines = ["Text only in this app for now — no images, files or tool calls."]
        if poller.health?.images == true {
            lines.append("The server does take images; the web Monitor page can send them.")
        }
        if let model = poller.health?.model, !model.isEmpty {
            lines.append("Thinking, temperature and the rest are under the slider icon.")
        }
        return lines.joined(separator: " ")
    }

    // MARK: - sending

    private func send() {
        guard let client = settings.makeClient() else { return }   // the banner above says why
        Task {
            await chat.send(client: client, model: poller.health?.model)
        }
    }
}

/// The bar at the bottom: the multi-line field, and Send / Stop.
private struct ChatComposer: View {
    @Environment(\.theme) private var theme

    @Bindable var chat: ChatViewModel
    let onSend: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Ask", text: $chat.draft, axis: .vertical)
                .lineLimit(1...6)
                .textFieldStyle(.plain)
                .font(.body)
                .foregroundStyle(theme.textPrimary)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(theme.cardFill)
                        .overlay(RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(theme.cardBorder, lineWidth: theme.hairline))
                )
                .onSubmit(onSend)
                .submitLabel(.send)
                .accessibilityLabel("Message")

            if chat.canStop {
                Button(action: chat.stop) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 40, height: 40)
                }
                .foregroundStyle(theme.dangerText)
                .background(Circle().fill(theme.track))
                .accessibilityLabel("Stop")
            } else {
                Button(action: onSend) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 40, height: 40)
                }
                .foregroundStyle(chat.canSend ? theme.background : theme.textTertiary)
                .background(Circle().fill(chat.canSend ? theme.accent : theme.track))
                .disabled(!chat.canSend)
                .accessibilityLabel("Send")
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 6)
    }
}
