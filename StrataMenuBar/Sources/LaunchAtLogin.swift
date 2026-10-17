import Foundation
import ServiceManagement

/// "Launch at login" through the modern login-item API. Needs a properly signed app that is not
/// running from a translocated location — the view shows the error when macOS says no.
enum LaunchAtLogin {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
