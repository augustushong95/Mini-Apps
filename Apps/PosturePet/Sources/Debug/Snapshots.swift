#if DEBUG
import AppKit
import SwiftUI

/// Renders galleries of Mochi and the UI to PNGs in the debug folder, so the
/// visuals can be reviewed without screen capture.
/// `"Posture Pet.app/Contents/MacOS/Posture Pet" -RenderSnapshots YES`
enum Snapshots {
    static func renderAll() {
        renderMoods()
        renderStages()
        renderPostures()
        renderMenuBarIcons()
        renderUI()
        renderSimulatedAirPods()
    }

    // MARK: Simulated AirPods sequence

    /// Feeds simulated AirPods through the real engine and captures what Mochi
    /// (in colour and in the menu bar) looks like at each step, with the
    /// engine's own readings, for the test report.
    private static func renderSimulatedAirPods() {
        let folder = FileManager.default.temporaryDirectory.appending(path: "PosturePetSim-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = StateStore(folder: folder)
        store.update { state in
            state.onboarding.completed = true
            state.pet.stage = .sprout
            state.pet.adoptedOn = PetDay(containing: .now)
        }
        let suite = "PosturePetSim"
        UserDefaults.standard.removePersistentDomain(forName: suite)
        let preferences = Preferences(defaults: UserDefaults(suiteName: suite) ?? .standard)
        preferences.windDownMinutes = 3 * 60 + 59
        let motion = MotionHub(streamingEnabled: false)
        let engine = PetEngine(settings: preferences, motion: motion, store: store, quietSignals: { nil }, idleSeconds: { 0 })

        var clock: TimeInterval = 20_000
        func hold(_ pitch: Double, _ roll: Double, seconds: Double) {
            var t = 0.0
            while t < seconds {
                clock += 0.04
                motion.debugInject(.synthetic(pitch: pitch, roll: roll, timestamp: clock))
                t += 0.04
            }
        }

        var frames: [[String: String]] = []
        func capture(_ file: String, _ title: String, _ input: String) {
            engine.tick()
            frames.append([
                "file": file,
                "title": title,
                "input": input,
                "posture": "\(engine.posture.state)",
                "mood": engine.mood.title,
                "uprightness": String(format: "%.2f", engine.pose.uprightness),
                "tilt": String(format: "%+.0f°", engine.pose.tilt),
                "measured": Duration.seconds(engine.today.measuredSeconds).compact,
            ])
            writeFrame(engine.pose, badge: engine.breaks.phase != .sitting, to: file)
        }

        motion.debugStartSimulation()
        hold(0, 0, seconds: 2.5)
        _ = engine.captureBaseline()
        hold(0, 0, seconds: 3)
        capture("sim-01.png", "바르게 앉기", "숙임 0°, 기울기 0°")
        hold(0, 14, seconds: 4)
        capture("sim-02.png", "고개를 오른쪽으로", "기울기 +14°")
        hold(0, -14, seconds: 4)
        capture("sim-03.png", "고개를 왼쪽으로", "기울기 −14°")
        hold(-26, 0, seconds: 4)
        capture("sim-04.png", "고개를 숙임 (잠깐)", "숙임 −26°, 4초")
        hold(-26, 0, seconds: 126)
        capture("sim-05.png", "2분 넘게 숙이고 있음", "숙임 −26°, 130초")
        hold(0, 0, seconds: 8)
        capture("sim-06.png", "다시 바르게", "숙임 0°")
        engine.debugAddSitting(minutes: 51)
        capture("sim-07.png", "50분 앉아 있음: 휴식할 때", "앉은 시간 +51분")
        engine.debugAddSitting(minutes: 50)
        capture("sim-08.png", "100분 동안 쉬지 않음", "앉은 시간 +50분")
        engine.recordBreak(.manual)
        capture("sim-09.png", "휴식 후", "휴식 1회")
        motion.debugStopSimulation()
        capture("sim-10.png", "AirPods 빼기", "연결 끊김")

        if let json = try? JSONSerialization.data(withJSONObject: frames, options: [.prettyPrinted]) {
            DebugFiles.write(json, to: "sim-frames.json")
        }
        UserDefaults.standard.removePersistentDomain(forName: suite)
    }

    /// Mochi in colour on the left, the menu bar icon (enlarged) on the right.
    private static func writeFrame(_ pose: PetPose, badge: Bool, to name: String) {
        let size = CGSize(width: 360, height: 200)
        let scale: CGFloat = 2
        guard let context = CGContext(
            data: nil, width: Int(size.width * scale), height: Int(size.height * scale),
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return }
        context.scaleBy(x: scale, y: scale)
        context.setFillColor(NSColor(hex: 0xFFF6EA).cgColor)
        context.fill(CGRect(origin: .zero, size: size))

        let view = PetLayerView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
        view.idleAnimationsEnabled = false
        view.apply(pose, animated: false)
        view.layer?.render(in: context)

        // Menu bar strip with the icon, as it appears at the top of the screen.
        let bar = CGRect(x: 220, y: 80, width: 120, height: 44)
        context.setFillColor(NSColor(hex: 0xE9E9EB).cgColor)
        context.addPath(CGPath(roundedRect: bar, cornerWidth: 10, cornerHeight: 10, transform: nil))
        context.fillPath()
        let icon = MenuBarIconRenderer.image(for: pose, badge: badge)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        let iconRect = CGRect(x: bar.midX - 36, y: bar.midY - 27, width: 72, height: 54)
        let tinted = NSImage(size: iconRect.size, flipped: false) { rect in
            icon.draw(in: rect)
            NSColor.black.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        tinted.draw(in: iconRect)
        NSGraphicsContext.restoreGraphicsState()

        if let image = context.makeImage(),
           let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) {
            DebugFiles.write(png, to: name)
        }
    }

    // MARK: App icon

    /// `-RenderAppIcon YES`: writes every AppIcon size to Debug/AppIcon.
    static func renderAppIcon() {
        let sizes: [(String, Int)] = [
            ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
            ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
            ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
            ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
            ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
        ]
        for (name, pixels) in sizes {
            guard let png = appIcon(pixels: pixels) else { continue }
            DebugFiles.write(png, to: "AppIcon/\(name)")
        }
    }

    /// Mochi on a hill under a soft sky, on the macOS icon grid (an 824 pt
    /// rounded square inside a 1024 pt canvas, with room for the shadow).
    private static func appIcon(pixels: Int) -> Data? {
        let canvas: CGFloat = 1024
        guard let context = CGContext(
            data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        let scale = CGFloat(pixels) / canvas
        context.scaleBy(x: scale, y: scale)

        let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
        let shape = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)

        // Drop shadow under the tile.
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: NSColor.black.withAlphaComponent(0.28).cgColor)
        context.addPath(shape)
        context.setFillColor(NSColor.white.cgColor)
        context.fillPath()
        context.restoreGState()

        context.saveGState()
        context.addPath(shape)
        context.clip()
        let sky = CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
            colors: [NSColor(hex: 0xD9F1FF).cgColor, NSColor(hex: 0xFFF3E0).cgColor] as CFArray,
            locations: [0, 1]
        )!
        context.drawLinearGradient(sky, start: CGPoint(x: 0, y: tile.maxY), end: CGPoint(x: 0, y: tile.minY + 200), options: [.drawsAfterEndLocation])

        // Two soft hills.
        context.setFillColor(NSColor(hex: 0xB9E2AC).cgColor)
        context.fillEllipse(in: CGRect(x: 20, y: -10, width: 620, height: 330))
        context.fillEllipse(in: CGRect(x: 420, y: -30, width: 640, height: 320))
        context.setFillColor(NSColor(hex: 0xCDEBC0).cgColor)
        context.fillEllipse(in: CGRect(x: -60, y: -260, width: 1140, height: 560))

        // A little cloud.
        context.setFillColor(NSColor.white.withAlphaComponent(0.9).cgColor)
        context.fillEllipse(in: CGRect(x: 650, y: 735, width: 90, height: 70))
        context.fillEllipse(in: CGRect(x: 700, y: 755, width: 110, height: 85))
        context.fill(CGRect(x: 660, y: 735, width: 190, height: 40).insetBy(dx: 0, dy: 0))
        context.fillEllipse(in: CGRect(x: 800, y: 735, width: 70, height: 55))

        // Mochi, happy, with a two-leaf sprout.
        var pose = PetMood.happy.pose(stage: .sprout, posture: nil)
        pose.eyes = .open
        pose.mouth = .smile
        pose.blush = 1
        let side: CGFloat = 760
        let view = PetLayerView(frame: NSRect(x: 0, y: 0, width: side, height: side))
        view.idleAnimationsEnabled = false
        view.apply(pose, animated: false)
        if let layer = view.layer {
            context.saveGState()
            context.translateBy(x: (canvas - side) / 2, y: 112)
            layer.render(in: context)
            context.restoreGState()
        }
        context.restoreGState()

        // A hairline edge so the tile reads on light backgrounds.
        context.addPath(shape)
        context.setStrokeColor(NSColor.black.withAlphaComponent(0.06).cgColor)
        context.setLineWidth(2)
        context.strokePath()

        guard let image = context.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    // MARK: SwiftUI screens

    /// Renders the real SwiftUI screens against a throwaway state folder.
    private static func renderUI() {
        let folder = FileManager.default.temporaryDirectory.appending(path: "PosturePetSnapshots-\(UUID().uuidString)")
        let store = StateStore(folder: folder)
        store.update { state in
            state.onboarding.completed = true
            state.pet.name = "Mochi"
            state.pet.stage = .sprout
            state.pet.treats = 12
            state.pet.adoptedOn = PetDay(containing: .now).adding(days: -9)
            for offset in 1...6 {
                let day = PetDay(containing: .now).adding(days: -offset)
                state.withRecord(for: day) { record in
                    record.activeSeconds = 5 * 3600
                    record.breaks = [4, 2, 5, 3, 1, 4][offset - 1]
                    record.measuredSeconds = 4 * 3600
                    record.goodPostureSeconds = Double([3.1, 2.2, 3.5, 2.8, 1.9, 3.3][offset - 1]) * 3600
                    record.happiness = [88, 64, 93, 79, 52, 86][offset - 1]
                }
            }
            state.withRecord(for: PetDay(containing: .now)) { record in
                record.activeSeconds = 3 * 3600
                record.breaks = 3
                record.measuredSeconds = 2.5 * 3600
                record.goodPostureSeconds = 2.05 * 3600
                record.gamesPlayed = 2
                record.treatsEarned = 41
            }
            state.bestScores = ["leafGlide": 34]
        }
        let preferences = Preferences(defaults: UserDefaults(suiteName: "PosturePetSnapshots") ?? .standard)
        // Daytime screens whenever snapshots run (late only 03:59–04:00).
        preferences.windDownMinutes = 3 * 60 + 59
        let engine = PetEngine(settings: preferences, motion: MotionHub(streamingEnabled: false), store: store, quietSignals: { nil }, idleSeconds: { 0 })
        engine.debugAddSitting(minutes: 27)
        let pro = ProStore()
        let router = PanelRouter()
        let actions = PanelActions(play: { _ in }, snooze: {}, tookBreak: {}, recenter: {}, quit: {})
        let panel = PanelRootView(engine: engine, pro: pro, router: router, actions: actions)

        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            let suffix = appearance == .aqua ? "light" : "dark"
            for tab in PanelTab.allCases {
                router.tab = tab
                render(panel, size: PanelRootView.size, name: "panel-\(tab.rawValue)-\(suffix).png", appearance: appearance)
            }
        }
        router.tab = .home
        router.showsPaywall = true
        render(panel, size: PanelRootView.size, name: "panel-paywall.png", appearance: .aqua)
        router.showsPaywall = false

        engine.debugAddSitting(minutes: 30)
        render(panel, size: PanelRootView.size, name: "panel-home-due.png", appearance: .aqua)

        for kind in [NudgeKind.breakInvite, .posture, .windDown] {
            let bubble = BubbleView(nudge: Nudge(kind: kind, petName: "Mochi"), pose: engine.pose, tail: .top) { _ in }
                .padding(14)
            render(bubble, size: NSSize(width: 310, height: 160), name: "bubble-\(kind.rawValue).png", appearance: .aqua)
        }

        for game in ArcadeGame.allCases {
            let session = GameSession(game: game, engine: engine)
            // Past the countdown and a few seconds in, with some steering.
            for frame in 0..<(60 * 8) {
                session.frame(dt: 1.0 / 60)
                if game == .puddleHop, frame % 100 == 50 { _ = session.key(.space, down: true) }
                _ = session.key(.up, down: game == .starFloat && (frame / 90) % 2 == 0)
                _ = session.key(.right, down: game == .leafGlide && (frame / 120) % 2 == 0)
            }
            render(ArcadeView(session: session, engine: engine, close: {}), size: ArcadeView.size,
                   name: "arcade-\(game.rawValue).png", appearance: .aqua)
            session.endRound()
            render(ArcadeView(session: session, engine: engine, close: {}), size: ArcadeView.size,
                   name: "arcade-\(game.rawValue)-results.png", appearance: .aqua)
            session.end()
        }

        let onboarding = OnboardingModel(engine: engine, preferences: preferences, recenterOnly: false)
        for step in [OnboardingModel.Step.hello, .airPods, .calibrate, .rhythm, .home, .finish] {
            onboarding.step = step
            render(OnboardingView(model: onboarding), size: OnboardingView.size, name: "onboarding-\(step.rawValue)-\(step).png", appearance: .aqua)
        }
        onboarding.stop()
        try? FileManager.default.removeItem(at: folder)

        // The same pills through SwiftUI's own renderer, to tell real
        // drawing problems from layer-capture artifacts.
        let pills = HStack(spacing: 8) {
            Button("Later") {}.buttonStyle(.pill(.plain))
            Button("I took a break") {}.buttonStyle(.pill(.plain))
            Button("Play") {}.buttonStyle(.pill)
        }
        .padding(16)
        .background(Color.white)
        let renderer = ImageRenderer(content: pills)
        renderer.scale = 3
        if let image = renderer.nsImage, let tiff = image.tiffRepresentation,
           let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            DebugFiles.write(png, to: "pills-imagerenderer.png")
        }
    }

    /// Lays a SwiftUI view out in an offscreen window, lets it settle, and
    /// renders its layers over a plain background (vibrancy can't be captured).
    private static func render<V: View>(_ view: V, size: NSSize, name: String, appearance: NSAppearance.Name) {
        let window = NSWindow(
            contentRect: NSRect(x: -30000, y: -30000, width: size.width, height: size.height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: appearance)
        window.isOpaque = false
        window.backgroundColor = .clear
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: size)
        window.contentView = hosting
        window.orderFrontRegardless()
        RunLoop.main.run(until: .now + 0.9)
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()
        RunLoop.main.run(until: .now + 0.2)

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
        let backdrop = appearance == .aqua ? NSColor(hex: 0xEDEAE4) : NSColor(hex: 0x2A2A2E)
        context.setFillColor(backdrop.cgColor)
        context.fill(CGRect(origin: .zero, size: size))
        // SwiftUI's layers are geometry-flipped; draw them the right way up.
        if layer.isGeometryFlipped || hosting.isFlipped {
            context.translateBy(x: 0, y: size.height)
            context.scaleBy(x: 1, y: -1)
        }
        layer.render(in: context)
        if let image = context.makeImage(),
           let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) {
            DebugFiles.write(png, to: name)
        }
        window.orderOut(nil)
    }

    private static func gallery(_ poses: [PetPose], cell: CGFloat = 220, name: String, background: NSColor) {
        // Outside a window AppKit doesn't attach subview layers to their
        // parent, so the gallery composes the pet layers itself.
        let root = CALayer()
        root.frame = CGRect(x: 0, y: 0, width: cell * CGFloat(poses.count), height: cell)
        root.backgroundColor = background.cgColor
        var views: [PetLayerView] = []
        for (index, pose) in poses.enumerated() {
            let view = PetLayerView(frame: NSRect(x: 0, y: 0, width: cell, height: cell))
            view.idleAnimationsEnabled = false
            view.apply(pose, animated: false)
            if let layer = view.layer {
                layer.frame = CGRect(x: CGFloat(index) * cell, y: 0, width: cell, height: cell)
                root.addSublayer(layer)
            }
            views.append(view)
        }
        DebugFiles.writePNG(of: root, to: name)
        withExtendedLifetime(views) {}
    }

    private static func renderMoods() {
        let poses = PetMood.allCases.map { $0.pose(stage: .sprout, posture: nil) }
        gallery(poses, name: "moods-light.png", background: NSColor(hex: 0xFFF6EA))
        gallery(poses, name: "moods-dark.png", background: NSColor(hex: 0x24262B))
    }

    private static func renderStages() {
        var poses = GrowthStage.allCases.map { PetMood.happy.pose(stage: $0, posture: nil) }
        var royal = PetMood.happy.pose(stage: .bloom, posture: nil)
        royal.accessories = [.crown, .sparkles]
        royal.eyes = .happy
        royal.mouth = .grin
        poses.append(royal)
        gallery(poses, name: "stages.png", background: NSColor(hex: 0xEAF6EE))
    }

    private static func renderPostures() {
        let mirrors = [
            PostureMirror(uprightness: 1, tilt: 0),
            PostureMirror(uprightness: 0.6, tilt: 0),
            PostureMirror(uprightness: 0.2, tilt: 0),
            PostureMirror(uprightness: 1, tilt: 14),
            PostureMirror(uprightness: 1, tilt: -14),
        ]
        let poses = mirrors.map { PetMood.happy.pose(stage: .bud, posture: $0) }
        gallery(poses, name: "postures.png", background: NSColor(hex: 0xFFF6EA))
    }

    private static func renderMenuBarIcons() {
        var poses = PetMood.allCases.map { ($0.pose(stage: .sprout, posture: nil), false) }
        poses.append((PetMood.happy.pose(stage: .bloom, posture: nil), true))
        poses.append((PetMood.happy.pose(stage: .sprout, posture: PostureMirror(uprightness: 1, tilt: 15)), false))

        let scale: CGFloat = 8
        let iconSize = MenuBarIconRenderer.size
        let cell = NSSize(width: iconSize.width + 8, height: iconSize.height + 8)
        let width = cell.width * CGFloat(poses.count)
        let height = cell.height * 2
        let image = NSImage(size: NSSize(width: width * scale, height: height * scale), flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.scaleBy(x: scale, y: scale)
            for (row, dark) in [false, true].enumerated() {
                let y = CGFloat(1 - row) * cell.height
                context.setFillColor(dark ? NSColor(hex: 0x2B2B2F).cgColor : NSColor(hex: 0xECECEC).cgColor)
                context.fill(CGRect(x: 0, y: y, width: width, height: cell.height))
                for (index, (pose, badge)) in poses.enumerated() {
                    let icon = MenuBarIconRenderer.image(for: pose, badge: badge)
                    let origin = CGPoint(x: CGFloat(index) * cell.width + 4, y: y + 4)
                    let tinted = NSImage(size: iconSize, flipped: false) { iconRect in
                        icon.draw(in: iconRect)
                        (dark ? NSColor.white : NSColor.black).set()
                        iconRect.fill(using: .sourceAtop)
                        return true
                    }
                    tinted.draw(in: CGRect(origin: origin, size: iconSize))
                }
            }
            return true
        }
        if let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            DebugFiles.write(png, to: "menubar-icons.png")
        }
    }
}
#endif
