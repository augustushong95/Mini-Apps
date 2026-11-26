import AppKit
import MenuBarKit
import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, detection, rules, privacy, pro

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .detection: "Detection"
        case .rules: "Your Rules"
        case .privacy: "Privacy"
        case .pro: "Pro"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .detection: "eye.slash"
        case .rules: "list.bullet.rectangle"
        case .privacy: "lock.shield"
        case .pro: "star"
        }
    }
}

/// The Settings window, with toolbar tabs like the system's own apps.
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private var window: NSWindow?
    private var tabs: NSTabViewController?

    static let size = NSSize(width: 600, height: 560)

    init(model: AppModel) {
        self.model = model
    }

    func show(tab: SettingsTab = .general) {
        if window == nil { makeWindow() }
        select(tab)
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    private func select(_ tab: SettingsTab) {
        guard let index = SettingsTab.allCases.firstIndex(of: tab) else { return }
        tabs?.selectedTabViewItemIndex = index
    }

    private func makeWindow() {
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        for tab in SettingsTab.allCases {
            let content = SettingsTabContent(model: model, tab: tab, upgrade: { [weak self] in self?.select(.pro) })
                .frame(width: Self.size.width, height: Self.size.height)
            let controller = NSHostingController(rootView: content)
            let item = NSTabViewItem(viewController: controller)
            item.label = tab.title
            item.image = NSImage(systemSymbolName: tab.symbol, accessibilityDescription: tab.title)
            item.identifier = tab.rawValue
            tabs.addTabViewItem(item)
        }
        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.delegate = self
        window.setContentSize(Self.size)
        window.center()
        self.tabs = tabs
        self.window = window
    }

    func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async {
            if !NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeMain }) { NSApp.deactivate() }
        }
    }
}

/// One tab's content.
struct SettingsTabContent: View {
    let model: AppModel
    let tab: SettingsTab
    let upgrade: () -> Void

    var body: some View {
        switch tab {
        case .general: GeneralSettings(model: model, preferences: model.preferences, folder: model.folder)
        case .detection: DetectionSettingsView(preferences: model.preferences)
        case .rules: RulesSettings(preferences: model.preferences, pro: model.pro, upgrade: upgrade)
        case .privacy: PrivacySettings()
        case .pro: ProView(pro: model.pro).padding(24)
        }
    }
}

// MARK: - General

private struct GeneralSettings: View {
    let model: AppModel
    @Bindable var preferences: Preferences
    let folder: FolderAccess

    var body: some View {
        Form {
            Section {
                LabeledContent("Screenshot folder") {
                    HStack(spacing: 8) {
                        folderLabel
                        Button(folder.url == nil ? "Choose…" : "Change…") { model.chooseFolder() }
                    }
                }
                Toggle("Watch for new screenshots", isOn: Binding(
                    get: { preferences.watchesFolder },
                    set: { model.setWatching($0) }
                ))
                .disabled(folder.url == nil)
                Tip(symbol: "bolt.fill", text: "For instant previews, turn off the system's floating thumbnail: press ⇧⌘5, click Options, and uncheck Show Floating Thumbnail. While it shows, macOS waits about 5 seconds before saving the file.")
            } header: {
                Text("Screenshots")
            }

            Section("When a screenshot is ready") {
                Picker("When a screenshot is ready", selection: $preferences.readyAction) {
                    ForEach(ReadyAction.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                Toggle("Close the preview after copying", isOn: $preferences.closesPreviewAfterCopy)
            }

            Section("After you copy, drag or save") {
                Picker("After you copy, drag or save", selection: $preferences.originalHandling) {
                    ForEach(OriginalHandling.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                Text("The original is only ever moved to the Trash, so you can get it back. If your Desktop syncs with iCloud, macOS uploads screenshots as soon as they're saved; the capture shortcut below never writes a file.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Capture shortcut") {
                LabeledContent("Capture an area") {
                    ShortcutRecorder(combo: Binding(
                        get: { preferences.hotKey },
                        set: { newValue in
                            preferences.hotKey = newValue
                            model.registerHotKey()
                        }
                    ), problem: model.hotKeys.problem)
                }
                Text("Drag over an area or click a window, with no file and no waiting. macOS asks for Screen Recording permission the first time you use it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                LaunchAtLoginToggle()
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var folderLabel: some View {
        switch folder.status {
        case .available(let url):
            Label(FolderAccess.displayName(for: url), systemImage: "folder.fill")
                .help(url.path)
        case .unavailable:
            Label("\(folder.displayName) (can't be reached)", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        case .notChosen:
            Text("None").foregroundStyle(.secondary)
        }
    }
}

private struct Tip: View {
    let symbol: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol).foregroundStyle(.yellow)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Detection

private struct DetectionSettingsView: View {
    @Bindable var preferences: Preferences

    var body: some View {
        Form {
            ForEach([FindingCategory.secret, .personal, .internalInfo, .face], id: \.self) { category in
                Section {
                    ForEach(Detector.allCases.filter { $0.category == category }, id: \.self) { detector in
                        Toggle(isOn: binding(for: detector)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(detector.title)
                                Text(detector.example)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Label(category.title, systemImage: category.symbolName)
                        .foregroundStyle(Theme.color(for: category))
                }
            }

            Section("Boxes") {
                Picker("Colour", selection: $preferences.boxColor) {
                    ForEach(BoxColor.allCases, id: \.self) { color in
                        Text(color.title).tag(color)
                    }
                }
                .pickerStyle(.segmented)
                Toggle("Label boxes with what they hide", isOn: $preferences.showsLabels)
                Text("Boxes are always solid. Blurred or pixelated text can sometimes be reconstructed; a filled box can't.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func binding(for detector: Detector) -> Binding<Bool> {
        Binding(
            get: { preferences.detection.enabled.contains(detector) },
            set: { on in
                var detection = preferences.detection
                if on { detection.enabled.insert(detector) } else { detection.enabled.remove(detector) }
                preferences.detection = detection
            }
        )
    }
}

// MARK: - Privacy

private struct PrivacySettings: View {
    static let verifyCommand = #"codesign -d --entitlements - "/Applications/Screenshot Redactor.app""#
    @State private var copied = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 14) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Works 100% offline").font(.title2.weight(.semibold))
                        Text("Your screenshots never leave this Mac.").foregroundStyle(.secondary)
                    }
                }
                section("No network access at all", "Screenshot Redactor has no permission to use the network: the macOS sandbox blocks every connection it might try to make. Reading text and finding faces happens on this Mac with Apple's Vision framework.")
                section("What's kept", "Only your settings and rules. Screenshots are read in memory and forgotten when you quit. Files made for dragging are deleted the next time the app starts. Nothing is logged about what's in your screenshots.")
                section("Purchases", "Pro is bought through the App Store, which macOS handles for the app. No account, no tracking, no analytics.")
                VStack(alignment: .leading, spacing: 6) {
                    Text("Check it yourself").font(.headline)
                    Text("In Terminal, this lists everything the app is allowed to do. You'll see the sandbox and access to files you choose, and nothing about the network.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Text(Self.verifyCommand)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
                        Button(copied ? "Copied" : "Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(Self.verifyCommand, forType: .string)
                            copied = true
                        }
                    }
                }
            }
            .padding(24)
        }
    }

    private func section(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            Text(text)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
