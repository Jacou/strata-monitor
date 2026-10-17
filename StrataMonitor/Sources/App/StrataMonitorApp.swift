import SwiftUI
import StrataCore

@main
public struct StrataMonitorApp: App {
    private let settings: AppSettings
    private let poller: MetricsPoller
    private let chat: ChatViewModel

    @Environment(\.scenePhase) private var scenePhase

    public init() {
        let settings = AppSettings()
        #if DEBUG
        settings.adoptAPIKeyFromEnvironment()
        #endif
        self.settings = settings
        // An address saved before this build (or hand-edited into UserDefaults) can be unusable;
        // the Settings screen says so, and the poller falls back to the documented default.
        self.poller = MetricsPoller(client: settings.makeClient() ?? StrataClient(baseURL: AppSettings.defaultBaseURL))
        // Conversations live in Application Support; the sampling settings in UserDefaults.
        self.chat = ChatViewModel(store: ChatStore(), settings: ChatSettings())
    }

    public var body: some Scene {
        WindowGroup {
            RootView(initialTab: AppTab.initialTab(hasAPIKey: settings.hasAPIKey))
                .environment(settings)
                .environment(poller)
                .environment(chat)
                .strataTheme()
                .task { poller.start() }
                .onChange(of: scenePhase) { _, phase in
                    // 1 s polling only in the foreground, like the web page's tab.
                    poller.setActive(phase == .active)
                }
        }
    }
}
