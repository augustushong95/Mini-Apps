import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Unit tests run inside the app; they test logic, not the live app.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        #if DEBUG
        // `-EphemeralState YES`: throwaway settings, so an automated run
        // (smoke test, snapshots) can't change the real ones.
        if UserDefaults.standard.bool(forKey: "EphemeralState") {
            let suite = "ScreenshotRedactorEphemeral"
            UserDefaults.standard.removePersistentDomain(forName: suite)
            model = AppModel(defaults: UserDefaults(suiteName: suite) ?? .standard)
            return
        }
        #endif
        model = AppModel()
    }

    /// Opening the app again (Finder, Spotlight, Launchpad) shows the menu bar
    /// panel, so the app stays reachable even if its icon is hidden.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        model?.showPanel()
        return false
    }

    /// Images dropped on the app's icon, or opened with it.
    func application(_ application: NSApplication, open urls: [URL]) {
        model?.open(urls)
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Drag files stay until the next launch: an app that received one
        // may still be reading it.
        model?.prepareForTermination()
    }
}
