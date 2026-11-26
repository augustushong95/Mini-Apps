#if DEBUG
import AppKit
import SwiftUI
import MenuBarKit

/// Debug-only tools in the right-click menu, and launch arguments for
/// driving the app from the command line.
final class DebugTools {
    private unowned let model: AppModel
    private lazy var sensorLab = SensorLabRecorder(hub: model.motion)
    private var windows: [String: NSWindow] = [:]
    private let simulator = PostureSimulator()
    private var demo: AirPodsDemo?
    private var demoPanel: FloatingPanel?

    init(model: AppModel) {
        self.model = model
        simulator.engine = model.engine
    }

    /// `--args -OpenSensorLab YES`, `-LabReportAfter 8`, `-OpenPanel home|today|arcade|settings`,
    /// `-ShowNudge breakInvite|posture|windDown`, `-Play leafGlide|puddleHop|starFloat`.
    func handleLaunchArguments() {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: "SmokeTest") {
            runSmokeTest()
            return
        }
        // `--args -AirPodsDemo YES` (with `-EphemeralState YES` to keep the
        // real data out of it): runs the demo, writes AirPodsDemo.txt, quits.
        if defaults.bool(forKey: "AirPodsDemo") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.runAirPodsDemo(quitWhenDone: true)
            }
            return
        }
        if defaults.bool(forKey: "OpenSensorLab") {
            showSensorLab()
        }
        let reportDelay = defaults.double(forKey: "LabReportAfter")
        if reportDelay > 0 {
            sensorLab.start()
            DispatchQueue.main.asyncAfter(deadline: .now() + reportDelay) { [weak self] in
                guard let self else { return }
                DebugFiles.write(sensorLab.report, to: "SensorLabReport.txt")
            }
        }
        if let tab = defaults.string(forKey: "OpenPanel").flatMap(PanelTab.init(rawValue:)) {
            DispatchQueue.main.async { [weak self] in self?.model.openPanel(tab: tab) }
        }
        if let kind = defaults.string(forKey: "ShowNudge").flatMap(NudgeKind.init(rawValue:)) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.model.showBubble(kind) }
        }
        if let game = defaults.string(forKey: "Play").flatMap(ArcadeGame.init(rawValue:)) {
            DispatchQueue.main.async { [weak self] in self?.model.play(game) }
        }
    }

    func menuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Debug", action: nil, keyEquivalent: "")
        let menu = NSMenu()
        let engine = model.engine

        menu.addItem(ClosureMenuItem("AirPods Simulation Demo…") { [unowned self] in runAirPodsDemo() })
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("Sensor Lab…") { [unowned self] in showSensorLab() })
        menu.addItem(ClosureMenuItem("Posture Simulator…") { [unowned self] in showSimulator() })
        menu.addItem(.separator())

        let fast = ClosureMenuItem("Time ×60") {
            engine.setTimeScale(engine.clock.scale == 1 ? 60 : 1)
        }
        fast.state = engine.clock.scale == 1 ? .off : .on
        menu.addItem(fast)
        menu.addItem(ClosureMenuItem("Add 30 Minutes Sitting") { engine.debugAddSitting(minutes: 30) })
        menu.addItem(ClosureMenuItem("Take a Break") { engine.recordBreak(.manual) })
        menu.addItem(ClosureMenuItem("Add 10 Treats") { engine.addTreats(10) })

        let nudges = NSMenu()
        for kind in [NudgeKind.breakInvite, .posture, .windDown] {
            nudges.addItem(ClosureMenuItem(kind.rawValue) { [unowned self] in model.showBubble(kind) })
        }
        let nudgeItem = NSMenuItem(title: "Show Nudge", action: nil, keyEquivalent: "")
        nudgeItem.submenu = nudges
        menu.addItem(nudgeItem)

        let stages = NSMenu()
        for stage in GrowthStage.allCases {
            let stageItem = ClosureMenuItem(stage.name) { engine.debugSetStage(stage) }
            stageItem.state = engine.pet.stage == stage ? .on : .off
            stages.addItem(stageItem)
        }
        let stageItem = NSMenuItem(title: "Growth Stage", action: nil, keyEquivalent: "")
        stageItem.submenu = stages
        menu.addItem(stageItem)

        let pro = ClosureMenuItem("Pro (debug unlock)") { [unowned self] in model.pro.debugTogglePro() }
        pro.state = model.pro.isPro ? .on : .off
        menu.addItem(pro)
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("Show Onboarding") { [unowned self] in model.debugShowOnboarding() })
        menu.addItem(ClosureMenuItem("Reveal Debug Folder") {
            NSWorkspace.shared.activateFileViewerSelecting([DebugFiles.folder])
        })

        item.submenu = menu
        return item
    }

    // MARK: AirPods demo

    /// Plays the scripted simulated-AirPods session with its checklist window.
    func runAirPodsDemo(quitWhenDone: Bool = false) {
        guard demo == nil else {
            demoPanel?.orderFrontRegardless()
            return
        }
        let demo = AirPodsDemo(model: model)
        let panel = FloatingPanel(size: NSSize(width: 340, height: 600), canBecomeKey: false, level: .floating)
        panel.setContent(AirPodsDemoView(demo: demo) { [weak self] in self?.closeDemo() })
        let visible = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        panel.contentView?.layoutSubtreeIfNeeded()
        let height = panel.contentView?.fittingSize.height ?? 600
        panel.setContentSize(NSSize(width: 340, height: height))
        panel.present(at: NSPoint(x: visible.minX + 20, y: visible.maxY - height - 20), animated: true)

        demo.onFinish = { report in
            DebugFiles.write(report, to: "AirPodsDemo.txt")
            if quitWhenDone {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { NSApp.terminate(nil) }
            }
        }
        self.demo = demo
        demoPanel = panel
        demo.start()
    }

    private func closeDemo() {
        demo?.stop()
        demoPanel?.dismiss(animated: true)
        demo = nil
        demoPanel = nil
    }

    // MARK: Smoke test

    /// `--args -SmokeTest YES`: drives the live app through its main
    /// surfaces, logging each step to SmokeTest.txt, then quits. A crash
    /// shows up as a log that stops early.
    private func runSmokeTest() {
        var log: [String] = []
        func note(_ line: String) {
            log.append("\(Date.now.formatted(date: .omitted, time: .standard))  \(line)")
            DebugFiles.write(log.joined(separator: "\n"), to: "SmokeTest.txt")
        }
        let model = self.model
        let steps: [(TimeInterval, String, () -> Bool)] = [
            (0.5, "status item on screen", { model.debugStatusItemFrame != nil }),
            (0.5, "open panel", { model.openPanel(tab: .home); return model.debugPanelVisible }),
            (0.6, "today tab", { model.openPanel(tab: .today); return model.debugPanelVisible }),
            (0.6, "arcade tab", { model.openPanel(tab: .arcade); return true }),
            (0.6, "settings tab", { model.openPanel(tab: .settings); return true }),
            (0.6, "paywall", { model.router.showsPaywall = true; return true }),
            (0.6, "close panel", { model.debugClosePanel(); return true }),
            (0.6, "engine busy cleared", { !model.engine.isBusy }),
            (0.4, "show bubble", { model.showBubble(.breakInvite); return model.debugBubbleVisible }),
            (1.0, "hide bubble", { model.debugHideBubble(); return true }),
            (0.6, "play Leaf Glide", { model.play(.leafGlide); return model.debugArcade != nil }),
            (3.5, "game running", {
                guard let arcade = model.debugArcade else { return false }
                return arcade.session.phase == .playing && arcade.session.sim.elapsed > 0
            }),
            (0.3, "end round", {
                model.debugArcade?.session.endRound()
                if case .finished = model.debugArcade?.session.phase { return true }
                return false
            }),
            (0.8, "close arcade", { model.debugArcade?.close(); return true }),
            (0.8, "arcade gone, posture resumed", { model.debugArcade == nil && !model.engine.isPostureSuspended }),
            (0.2, "engine tick", { model.engine.tick(); return true }),
        ]
        var delay: TimeInterval = 1
        for (wait, name, check) in steps {
            delay += wait
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                note("\(check() ? "ok  " : "FAIL") \(name)")
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay + 0.5) {
            note("done")
            NSApp.terminate(nil)
        }
    }

    // MARK: Windows

    func showSensorLab() {
        show("lab", title: "Sensor Lab", size: NSSize(width: 780, height: 720)) {
            SensorLabView(recorder: self.sensorLab)
        }
    }

    func showSimulator() {
        show("simulator", title: "Posture Simulator", size: NSSize(width: 340, height: 240)) {
            PostureSimulatorView(simulator: self.simulator)
        }
    }

    private func show<Content: View>(_ key: String, title: String, size: NSSize, content: () -> Content) {
        if windows[key] == nil {
            let window = NSWindow(
                contentRect: NSRect(origin: .zero, size: size),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = title
            window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(rootView: content())
            window.center()
            windows[key] = window
        }
        NSApp.activate()
        windows[key]?.makeKeyAndOrderFront(nil)
    }
}

/// Feeds synthetic head samples into the engine, as if wearing AirPods.
@Observable
final class PostureSimulator {
    var pitch: Double = 0
    var roll: Double = 0
    var isRunning = false {
        didSet { isRunning ? start() : stop() }
    }

    @ObservationIgnored weak var engine: PetEngine?
    @ObservationIgnored private var timer: Timer?

    private func start() {
        let timer = Timer(timeInterval: 1.0 / 25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let engine = self.engine else { return }
                let time = engine.clock.now.timeIntervalSinceReferenceDate
                engine.debugSimulate(.synthetic(pitch: self.pitch, roll: self.roll, timestamp: time))
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
    }
}

private struct PostureSimulatorView: View {
    @Bindable var simulator: PostureSimulator

    var body: some View {
        Form {
            Toggle("Wearing simulated AirPods", isOn: $simulator.isRunning)
            LabeledContent("Pitch \(Int(simulator.pitch))°") {
                Slider(value: $simulator.pitch, in: -45...25)
            }
            LabeledContent("Roll \(Int(simulator.roll))°") {
                Slider(value: $simulator.roll, in: -25...25)
            }
            Text("Pitch below about −18° for 2 minutes is a slump (Normal). Use Time ×60 to speed it up.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .padding(8)
    }
}
#endif
