import SwiftUI

@main
struct ScreenshotRedactorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The menu bar item and every window are AppKit-managed (see AppModel).
        // A SwiftUI App needs at least one scene; Settings open from the
        // menu bar, so this one only points there.
        Settings {
            SettingsPointerView()
        }
    }
}

private struct SettingsPointerView: View {
    var body: some View {
        Text("Open Settings from the Screenshot Redactor icon in the menu bar.")
            .padding(24)
            .frame(width: 360)
    }
}
