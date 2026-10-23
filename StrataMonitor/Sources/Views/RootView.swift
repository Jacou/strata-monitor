import SwiftUI
import StrataCore

/// The five tabs.
public enum AppTab: String, CaseIterable, Identifiable, Sendable {
    case monitor
    case chat
    case config
    case about
    case settings

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .monitor: "Monitor"
        case .chat: "Chat"
        case .config: "Config"
        case .about: "About"
        case .settings: "Settings"
        }
    }

    public var systemImage: String {
        switch self {
        case .monitor: "waveform.path.ecg"
        case .chat: "bubble.left.and.text.bubble.right"
        case .config: "slider.horizontal.3"
        case .about: "info.circle"
        case .settings: "gearshape"
        }
    }

    /// A server that needs a key is useless until the key is in, so first launch opens Settings.
    public static func initialTab(hasAPIKey: Bool) -> AppTab {
        #if DEBUG
        // Debug builds only: `--tab=about|monitor|settings` opens the app on that tab, which is how
        // screenshots get taken without a hand on the display.
        for argument in ProcessInfo.processInfo.arguments where argument.hasPrefix("--tab=") {
            if let tab = AppTab(rawValue: String(argument.dropFirst(6))) { return tab }
        }
        #endif
        return hasAPIKey ? .monitor : .settings
    }
}

public struct RootView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(MetricsPoller.self) private var poller
    // RootView sits above `.strataTheme()`, so it resolves the palette from the scheme itself.
    @Environment(\.colorScheme) private var colorScheme

    @State private var tab: AppTab

    public init(initialTab: AppTab) {
        _tab = State(initialValue: initialTab)
    }

    public var body: some View {
        TabView(selection: $tab) {
            MonitorView()
                .tabItem { Label(AppTab.monitor.label, systemImage: AppTab.monitor.systemImage) }
                .tag(AppTab.monitor)

            ChatView()
                .tabItem { Label(AppTab.chat.label, systemImage: AppTab.chat.systemImage) }
                .tag(AppTab.chat)

            ConfigView()
                .tabItem { Label(AppTab.config.label, systemImage: AppTab.config.systemImage) }
                .tag(AppTab.config)

            AboutView()
                .tabItem { Label(AppTab.about.label, systemImage: AppTab.about.systemImage) }
                .tag(AppTab.about)

            SettingsView()
                .tabItem { Label(AppTab.settings.label, systemImage: AppTab.settings.systemImage) }
                .tag(AppTab.settings)
        }
        .tint(Theme(scheme: colorScheme).accent)
        .minimizesTabBarOnScroll()
        // The server dropdown on any tab: the poller follows, and drops what the last server said.
        .onChange(of: settings.selectedSlot) { _, _ in
            poller.switchServer(to: settings.makeClient() ?? StrataClient(baseURL: AppSettings.defaultBaseURL))
        }
        // One overlay for all five tabs: scrolled content must not run under the status bar.
        .themeTopScrim()
    }
}

private extension View {
    /// iOS 26: scrolling down shrinks the tab bar to a single pill for the current tab; scrolling
    /// back up brings it back. iPhone only — iPad keeps its bar. Earlier systems keep the full bar.
    @ViewBuilder
    func minimizesTabBarOnScroll() -> some View {
        if #available(iOS 26.0, *) {
            tabBarMinimizeBehavior(.onScrollDown)
        } else {
            self
        }
    }
}
