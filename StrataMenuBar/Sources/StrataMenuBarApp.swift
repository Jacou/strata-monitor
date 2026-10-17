import AppKit
import StrataCore
import SwiftUI

/// Strata in the menu bar. The item itself is AppKit (see `StatusItemController`) because a hover
/// card needs a mouse-enter hook; the Settings window is a normal SwiftUI scene.
@main
struct StrataMenuBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            MenuBarSettingsView(model: appDelegate.model)
                .strataTheme()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = MenuBarModel()
    private var controller: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = StatusItemController(model: model)
        controller.install()
        self.controller = controller
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}

/// The menu bar item's content: the number that matters, then the SF Symbol for the state.
///
/// The symbol goes on the **right**. macOS lays status items out from the right edge of the bar, so
/// with the icon pinned to that edge the item grows leftward when the text changes: the icon — which
/// both cards are anchored to — keeps its screen position while `idle` becomes `104 t/s`.
struct MenuBarStatusLabel: View {
    let model: MenuBarModel
    /// False while a card is open and the item's width is pinned too narrow for the digits: the card
    /// says all of it anyway, so show the icon rather than clipped text.
    var showsText = true

    var body: some View {
        let status = model.status
        let text = showsText ? MenuBarLabel.text(for: status) : ""

        HStack(spacing: 5) {
            if !text.isEmpty {
                Text(text).monospacedDigit()
            }
            Image(systemName: MenuBarLabel.symbol(for: status))
        }
        .font(.system(size: 12))
        .foregroundStyle(.primary)
        .fixedSize()
        // The hover card is the real answer; this is the fallback VoiceOver and slow hovers get.
        .help(MenuBarLabel.tooltip(model: model.modelName, lastRow: model.monitor?.requests.first))
    }
}
