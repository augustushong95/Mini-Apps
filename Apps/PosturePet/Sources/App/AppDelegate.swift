import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Unit tests run inside the app; they test logic, not the live app.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        #if DEBUG
        // `"Posture Pet" -RenderSnapshots YES` renders PNGs and quits,
        // without touching the real app state.
        if UserDefaults.standard.bool(forKey: "RenderSnapshots") {
            Snapshots.renderAll()
            NSApp.terminate(nil)
            return
        }
        if UserDefaults.standard.bool(forKey: "RenderAppIcon") {
            Snapshots.renderAppIcon()
            NSApp.terminate(nil)
            return
        }
        #endif
        model = AppModel()
    }

    /// Opening the app again (from Finder, Spotlight or Launchpad) shows the
    /// panel, so the app stays reachable even if its menu bar icon is hidden.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        model?.showMain()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        model?.prepareForTermination()
    }
}
