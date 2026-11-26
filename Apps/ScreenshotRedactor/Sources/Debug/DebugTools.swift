#if DEBUG
import AppKit
import MenuBarKit
import OSLog

/// Debug-only helpers: launch arguments for automated checks, and a Debug
/// menu in the status item's menu.
///
/// | Argument | Does |
/// | --- | --- |
/// | `-RenderSnapshots YES` | Renders every card state, the editor, panel, settings, onboarding and icons to PNGs in the container's `Debug` folder, then quits. |
/// | `-RenderAppIcon YES` | Writes the AppIcon images to `Debug/AppIcon`, then quits. |
/// | `-SmokeTest YES` | Drives the live app (sample → scan → copy → pasteboard → edit → export) and logs to `Debug/SmokeTest.txt`, then quits. |
/// | `-RedactInbox YES` | Runs the real pipeline on images in `Debug/Inbox`, writes the redacted images and a findings list to `Debug/Outbox`, then quits. |
/// | `-OpenSample YES` | Opens the sample in the editor at launch. |
/// | `-EphemeralState YES` | Throwaway settings, so a test run can't touch the real ones. |
final class DebugTools {
    private unowned let model: AppModel

    init(model: AppModel) {
        self.model = model
    }

    private static let defaults = UserDefaults.standard

    var isAutomated: Bool {
        ["RenderSnapshots", "RenderAppIcon", "SmokeTest", "RedactInbox"].contains { Self.defaults.bool(forKey: $0) }
    }

    func handleLaunchArguments() {
        let defaults = Self.defaults
        if defaults.bool(forKey: "RenderAppIcon") {
            AppIconRenderer.renderAll()
            NSApp.terminate(nil)
        } else if defaults.bool(forKey: "RenderSnapshots") {
            Task {
                await Snapshots.renderAll(model: model)
                NSApp.terminate(nil)
            }
        } else if defaults.bool(forKey: "RedactInbox") {
            Task {
                await DebugInbox.run(model: model)
                NSApp.terminate(nil)
            }
        } else if defaults.bool(forKey: "SmokeTest") {
            Task {
                await SmokeTest.run(model: model)
                NSApp.terminate(nil)
            }
        } else if defaults.bool(forKey: "OpenSample") {
            model.openSample()
        }
    }

    func menuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Debug", action: nil, keyEquivalent: "")
        let menu = NSMenu()
        let pro = ClosureMenuItem("Pro (debug unlock)") { [unowned self] in model.pro.debugTogglePro() }
        pro.state = model.pro.isPro ? .on : .off
        menu.addItem(pro)
        menu.addItem(ClosureMenuItem("Reset Today's Count") {
            UserDefaults.standard.removeObject(forKey: "AllowanceDay")
            UserDefaults.standard.removeObject(forKey: "AllowanceUsed")
            UserDefaults.standard.removeObject(forKey: "AllowanceLastSeen")
        })
        menu.addItem(ClosureMenuItem("Use Up Today's Count") { [unowned self] in
            UserDefaults.standard.set(DailyAllowance.freePerDay, forKey: "AllowanceUsed")
            model.allowance.refresh()
        })
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("Open Sample in Editor") { [unowned self] in model.openSample() })
        menu.addItem(ClosureMenuItem("Show Sample Preview") { [unowned self] in
            let sample = SampleScreenshot.demo()
            let document = model.library.add(ImageLoader.load(sample.image), origin: .sample, name: "Sample")
            model.preview.show([document])
        })
        menu.addItem(ClosureMenuItem("Show Onboarding") { [unowned self] in model.showOnboarding() })
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("Reveal Debug Folder") {
            try? FileManager.default.createDirectory(at: DebugFiles.folder, withIntermediateDirectories: true)
            NSWorkspace.shared.activateFileViewerSelecting([DebugFiles.folder])
        })
        item.submenu = menu
        return item
    }
}

/// `-RedactInbox YES`: real screenshots copied into `Debug/Inbox` are read
/// with the real pipeline; the redacted PNG and a findings list (labels and
/// boxes only, never the text) go to `Debug/Outbox`.
enum DebugInbox {
    static func run(model: AppModel) async {
        let inbox = DebugFiles.folder.appending(path: "Inbox", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        let files = (try? FileManager.default.contentsOfDirectory(at: inbox, includingPropertiesForKeys: nil)) ?? []
        var report: [String] = []
        for url in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) where !url.lastPathComponent.hasPrefix(".") {
            do {
                let loaded = try ImageLoader.load(contentsOf: url)
                let result = try await RedactionScanner.scan(loaded.image, dpi: loaded.dpi, settings: model.preferences.detection, includeCustomRules: true)
                let name = url.deletingPathExtension().lastPathComponent
                if let image = RedactionRenderer.render(loaded.image, boxes: result.boxes, style: RenderStyle(color: .black, showsLabels: true)),
                   let png = RedactionRenderer.pngData(image, dpi: loaded.dpi) {
                    DebugFiles.write(png, to: "Outbox/\(name) (redacted).png")
                }
                report.append("\(url.lastPathComponent): \(loaded.image.width)×\(loaded.image.height) @\(Int(loaded.dpi))dpi, \(result.lineCount) lines, \(result.boxes.count) boxes, \(result.duration.formatted(.units(allowed: [.milliseconds])))")
                for box in result.boxes {
                    report.append("  \(box.label) [\(box.category.rawValue)] at \(Int(box.rect.minX)),\(Int(box.rect.minY)) \(Int(box.rect.width))×\(Int(box.rect.height))")
                }
            } catch {
                report.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        if files.isEmpty { report.append("Inbox is empty: copy screenshots to \(inbox.path)") }
        DebugFiles.write(report.joined(separator: "\n"), to: "Outbox/findings.txt")
    }
}
#endif
