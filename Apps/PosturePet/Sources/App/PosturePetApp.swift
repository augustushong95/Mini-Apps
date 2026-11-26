import SwiftUI

@main
struct PosturePetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The menu bar item and every window are AppKit-managed (see AppModel).
        // A SwiftUI App needs at least one scene. Settings live in the
        // panel, so ⌘, shows a pointer to them.
        Settings {
            SettingsSceneView()
        }
    }
}
