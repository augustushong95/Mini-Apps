import AppKit
import SwiftUI

/// The Settings…, About and Quit items that end every app's menu.
/// Use inside a `MenuBarExtra` whose app also declares a `Settings` scene;
/// put a `Divider()` before it when the app has items of its own.
public struct StandardMenuItems: View {
    @Environment(\.openSettings) private var openSettings

    public init() {}

    public var body: some View {
        Button("Settings…") {
            // A menu bar app isn't active, so bring it forward or the window opens behind others.
            NSApp.activate()
            openSettings()
        }
        .keyboardShortcut(",")

        Button("About \(AppInfo.name)") {
            NSApp.activate()
            NSApp.orderFrontStandardAboutPanel(nil)
        }

        Divider()

        Button("Quit \(AppInfo.name)") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}

public enum AppInfo {
    /// The app's user-facing name from its Info.plist.
    public static var name: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? ProcessInfo.processInfo.processName
    }
}
