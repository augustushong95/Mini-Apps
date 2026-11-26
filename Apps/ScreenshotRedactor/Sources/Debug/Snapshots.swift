#if DEBUG
import AppKit
import MenuBarKit
import SwiftUI

/// `-RenderSnapshots YES`: renders every screen and state to PNGs in the
/// container's `Debug/Snapshots` folder, so the UI can be reviewed without
/// screen capture. Uses throwaway settings and never touches the real ones.
enum Snapshots {
    static func renderAll(model: AppModel) async {
        let defaults = UserDefaults(suiteName: "ScreenshotRedactorSnapshots") ?? .standard
        defaults.removePersistentDomain(forName: "ScreenshotRedactorSnapshots")
        let preferences = Preferences(defaults: defaults)
        let allowance = DailyAllowance(defaults: defaults)
        let library = Library(preferences: preferences, includesCustomRules: { false })

        // A scanned sample, and one in each other state.
        let sample = SampleScreenshot.demo()
        let ready = library.add(ImageLoader.load(sample.image, dpi: 144), origin: .file(URL(fileURLWithPath: "/tmp/Screenshot.png")), name: "Screenshot 2026-11-26 at 10.42.07")
        let clean = library.add(ImageLoader.load(SampleScreenshot.render(.clean).image, dpi: 144), origin: .capture, name: "Clean")
        await library.waitForScans()
        _ = await ready.exportImage()
        _ = await clean.exportImage()
        let scanning = RedactionDocument(image: sample.image, dpi: 144, origin: .capture, name: "Scanning", style: preferences.renderStyle)
        let failed = RedactionDocument(image: sample.image, dpi: 144, origin: .capture, name: "Failed", style: preferences.renderStyle)
        failed.failScan("This file isn't an image the app can read.")

        if let redacted = ready.rendered, let png = RedactionRenderer.pngData(redacted, dpi: 144) {
            DebugFiles.write(png, to: "Snapshots/sample-redacted.png")
        }

        // Preview card states.
        func card(_ documents: [RedactionDocument], flash: PreviewModel.Flash? = nil, allowance: DailyAllowance = allowance) -> some View {
            let model = PreviewModel(allowance: allowance)
            model.documents = documents
            model.flash = flash
            return PreviewCardView(model: model).padding(20)
        }
        let cardSize = { (document: RedactionDocument) in
            let size = PreviewModel.size(for: document)
            return NSSize(width: size.width + 40, height: size.height + 40)
        }
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let suffix = appearance == .aqua ? "light" : "dark"
            await render(card([ready]), size: cardSize(ready), name: "card-ready-\(suffix)", appearance: appearance)
            await render(card([scanning]), size: cardSize(scanning), name: "card-scanning-\(suffix)", appearance: appearance)
        }
        await render(card([clean]), size: cardSize(clean), name: "card-nothing-found", appearance: .aqua)
        await render(card([ready], flash: .copied), size: cardSize(ready), name: "card-copied", appearance: .aqua)
        await render(card([failed]), size: cardSize(failed), name: "card-failed", appearance: .aqua)
        await render(card([ready, clean]), size: cardSize(ready), name: "card-two-displays", appearance: .aqua)
        let usedUp = DailyAllowance(defaults: defaults)
        defaults.set(DailyAllowance.freePerDay, forKey: "AllowanceUsed")
        usedUp.refresh()
        let locked = library.add(ImageLoader.load(sample.image, dpi: 144), origin: .capture, name: "Locked")
        await library.waitForScans()
        _ = await locked.exportImage()
        await render(card([locked], allowance: usedUp), size: cardSize(locked), name: "card-limit-reached", appearance: .aqua)
        defaults.set(0, forKey: "AllowanceUsed")

        // Menu bar panel, empty and with recent captures.
        let emptyLibrary = Library(preferences: preferences, includesCustomRules: { false })
        for (name, lib) in [("panel-empty", emptyLibrary), ("panel-recent", library)] {
            let panelModel = MenuPanelModel(library: lib, allowance: allowance)
            panelModel.watchStatus = name == "panel-empty" ? .notChosen : .watching("Desktop")
            panelModel.shortcut = .defaultCapture
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                await render(MenuPanelView(model: panelModel).padding(20), size: NSSize(width: MenuPanelView.width + 40, height: 470),
                             name: "\(name)-\(appearance == .aqua ? "light" : "dark")", appearance: appearance)
            }
        }

        // Editor.
        let editorModel = EditorModel(document: ready, allowance: allowance)
        if let box = ready.boxes.dropFirst(2).first { ready.toggle(box.id); editorModel.selectedID = box.id }
        _ = await ready.exportImage()
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            await render(EditorView(model: editorModel), size: NSSize(width: 1180, height: 640),
                         name: "editor-\(appearance == .aqua ? "light" : "dark")", appearance: appearance)
        }
        editorModel.isPeeking = true
        await render(EditorView(model: editorModel), size: NSSize(width: 1180, height: 640), name: "editor-peek", appearance: .aqua)

        // Settings tabs, onboarding steps, Pro.
        for tab in SettingsTab.allCases {
            await render(SettingsTabContent(model: model, tab: tab, upgrade: {}), size: SettingsWindowController.size, name: "settings-\(tab.rawValue)", appearance: .aqua)
        }
        await render(OnboardingView(model: model, finish: {}), size: NSSize(width: 560, height: 520), name: "onboarding-1", appearance: .aqua)
        await render(ProView(pro: model.pro).padding(28).frame(width: 460, height: 480), size: NSSize(width: 460, height: 480), name: "paywall", appearance: .aqua)

        // Menu bar icons, enlarged.
        let states: [(String, StatusIcon.State)] = [("watching", .watching), ("paused", .paused), ("scanning", .scanning(phase: 1)), ("attention", .attention)]
        let icons = HStack(spacing: 24) {
            ForEach(states, id: \.0) { item in
                VStack {
                    Image(nsImage: StatusIcon.image(item.1)).renderingMode(.template).resizable().frame(width: 54, height: 54)
                    Text(item.0).font(.caption)
                }
            }
        }
        .padding(20)
        await render(icons, size: NSSize(width: 400, height: 120), name: "menubar-icons", appearance: .aqua)

        defaults.removePersistentDomain(forName: "ScreenshotRedactorSnapshots")
    }

    /// Lays a SwiftUI view out in an offscreen window, lets it settle, and
    /// renders its layers over a plain background (vibrancy can't be captured).
    private static func render<V: View>(_ view: V, size: NSSize, name: String, appearance: NSAppearance.Name) async {
        let window = NSWindow(
            contentRect: NSRect(x: -30000, y: -30000, width: size.width, height: size.height),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.appearance = NSAppearance(named: appearance)
        window.isOpaque = false
        window.backgroundColor = .clear
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: size)
        window.contentView = hosting
        window.orderFrontRegardless()
        try? await Task.sleep(for: .milliseconds(700))
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()
        try? await Task.sleep(for: .milliseconds(200))

        let scale: CGFloat = 2
        guard let layer = hosting.layer,
              let context = CGContext(
                  data: nil, width: Int(size.width * scale), height: Int(size.height * scale),
                  bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return }
        context.scaleBy(x: scale, y: scale)
        let backdrop = appearance == .aqua ? CGColor(srgbRed: 0.93, green: 0.93, blue: 0.95, alpha: 1) : CGColor(srgbRed: 0.16, green: 0.16, blue: 0.18, alpha: 1)
        context.setFillColor(backdrop)
        context.fill(CGRect(origin: .zero, size: size))
        if layer.isGeometryFlipped || hosting.isFlipped {
            context.translateBy(x: 0, y: size.height)
            context.scaleBy(x: 1, y: -1)
        }
        layer.render(in: context)
        if let image = context.makeImage(),
           let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) {
            DebugFiles.write(png, to: "Snapshots/\(name).png")
        }
        window.orderOut(nil)
    }
}

/// `-RenderAppIcon YES`: the app icon, drawn in code on the macOS icon grid
/// (an 824 pt rounded square in a 1024 pt canvas): a screenshot window
/// whose secret lines are covered by solid bars.
enum AppIconRenderer {
    static func renderAll() {
        let sizes: [(String, Int)] = [
            ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
            ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
            ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
            ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
            ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
        ]
        for (name, pixels) in sizes {
            if let png = icon(pixels: pixels) { DebugFiles.write(png, to: "AppIcon/\(name)") }
        }
    }

    static func icon(pixels: Int) -> Data? {
        let canvas: CGFloat = 1024
        guard let context = CGContext(
            data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.scaleBy(x: CGFloat(pixels) / canvas, y: CGFloat(pixels) / canvas)
        func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
            CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
        }
        let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
        let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)

        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: color(0x000000, 0.3))
        context.addPath(tilePath)
        context.setFillColor(color(0x1A3F8F))
        context.fillPath()
        context.restoreGState()

        context.saveGState()
        context.addPath(tilePath)
        context.clip()
        let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: [color(0x3D82F0), color(0x1B3E8C)] as CFArray, locations: [0, 1])!
        context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: tile.maxY), end: CGPoint(x: 0, y: tile.minY), options: [])

        // The screenshot: a white window with a title bar.
        let window = CGRect(x: 212, y: 262, width: 600, height: 500)
        let windowPath = CGPath(roundedRect: window, cornerWidth: 44, cornerHeight: 44, transform: nil)
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -14), blur: 40, color: color(0x000000, 0.35))
        context.addPath(windowPath)
        context.setFillColor(color(0xFFFFFF))
        context.fillPath()
        context.restoreGState()
        context.addPath(windowPath)
        context.clip()
        context.setFillColor(color(0xEEF1F6))
        context.fill(CGRect(x: window.minX, y: window.maxY - 82, width: window.width, height: 82))
        for (index, hex) in [0xFF5F57, 0xFEBC2E, 0x28C840].enumerated() {
            context.setFillColor(color(UInt32(hex)))
            context.fillEllipse(in: CGRect(x: window.minX + 40 + CGFloat(index) * 46, y: window.maxY - 56, width: 30, height: 30))
        }

        // Text lines; two of them are secrets, covered by solid bars.
        let lines: [(x: CGFloat, width: CGFloat, covered: Bool)] = [
            (0, 300, false), (0, 470, true), (0, 380, false), (90, 330, true), (0, 250, false),
        ]
        for (index, line) in lines.enumerated() {
            let y = window.maxY - 150 - CGFloat(index) * 70
            let rect = CGRect(x: window.minX + 56 + line.x, y: y, width: line.width, height: line.covered ? 44 : 26)
            context.setFillColor(line.covered ? color(0x0E1116) : color(0xC9D0DC))
            context.addPath(CGPath(roundedRect: rect.offsetBy(dx: 0, dy: line.covered ? -9 : 0), cornerWidth: 10, cornerHeight: 10, transform: nil))
            context.fillPath()
        }
        context.restoreGState()

        guard let image = context.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }
}
#endif
