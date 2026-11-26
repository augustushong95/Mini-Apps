import Observation
import OSLog
import ServiceManagement
import SwiftUI

/// The app's login item, registered through `SMAppService` — the sandbox-safe
/// API the Mac App Store accepts. Off until the user turns it on (App Review
/// rejects apps that enable launch at login without asking).
@MainActor
@Observable
public final class LaunchAtLogin {
    public static let shared = LaunchAtLogin()

    private var status: SMAppService.Status

    private init() {
        status = SMAppService.mainApp.status
    }

    public var isEnabled: Bool {
        get { status == .enabled }
        set {
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                Logger.menuBarKit.error("Couldn't change launch at login: \(error)")
            }
            refresh()
        }
    }

    /// Re-reads the status, which the user can also change in
    /// System Settings › General › Login Items.
    public func refresh() {
        status = SMAppService.mainApp.status
    }
}

/// A "Launch at login" toggle for an app's Settings window.
public struct LaunchAtLoginToggle: View {
    @Bindable private var launchAtLogin = LaunchAtLogin.shared

    public init() {}

    public var body: some View {
        Toggle("Launch at login", isOn: $launchAtLogin.isEnabled)
            .onAppear { launchAtLogin.refresh() }
    }
}

extension Logger {
    static let menuBarKit = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "MenuBarKit",
        category: "MenuBarKit"
    )
}
