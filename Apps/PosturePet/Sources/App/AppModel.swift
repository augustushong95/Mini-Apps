import AppKit
import MenuBarKit
import Observation
import SwiftUI

/// The composition root: creates the app's long-lived objects, wires them
/// together, and decides which window is on screen.
///
/// At most one of the panel, a game and onboarding is open at a time, and
/// bubbles wait while any of them is.
final class AppModel {
    let preferences: Preferences
    let motion = MotionHub()
    let engine: PetEngine
    let pro = ProStore()
    let router = PanelRouter()

    private let statusItem = StatusItemController()
    private let bubbles = BubbleController()
    private let desktopPet: DesktopPetController
    private lazy var panel = makePanel()
    private var arcade: ArcadeController?
    private var onboarding: OnboardingController?
    private var observers: [NSObjectProtocol] = []
    private var lastReaction: PetReaction?

    #if DEBUG
    private lazy var debug = DebugTools(model: self)
    #endif

    private enum Source {
        case menuBar, desktop
    }

    init() {
        #if DEBUG
        // `-EphemeralState YES`: a throwaway data folder and settings, so a
        // second copy (smoke test, AirPods demo) can't touch the real Mochi.
        if UserDefaults.standard.bool(forKey: "EphemeralState") {
            let suite = "PosturePetEphemeral"
            UserDefaults.standard.removePersistentDomain(forName: suite)
            preferences = Preferences(defaults: UserDefaults(suiteName: suite) ?? .standard)
            let folder = FileManager.default.temporaryDirectory.appending(path: "PosturePetEphemeral-\(UUID().uuidString)")
            engine = PetEngine(settings: preferences, motion: motion, store: StateStore(folder: folder))
        } else {
            preferences = Preferences()
            engine = PetEngine(settings: preferences, motion: motion)
        }
        #else
        preferences = Preferences()
        engine = PetEngine(settings: preferences, motion: motion)
        #endif
        desktopPet = DesktopPetController(preferences: preferences)
        wire()

        #if DEBUG
        let smokeTest = UserDefaults.standard.bool(forKey: "SmokeTest")
            || UserDefaults.standard.bool(forKey: "AirPodsDemo")
        #else
        let smokeTest = false
        #endif
        if !engine.isOnboarded, !smokeTest {
            showOnboarding()
        }

        #if DEBUG
        debug.handleLaunchArguments()
        #endif
    }

    // MARK: Wiring

    private func wire() {
        statusItem.onPrimaryClick = { [unowned self] in togglePanel(from: .menuBar) }
        statusItem.menuProvider = { [unowned self] in makeMenu() }
        desktopPet.onClick = { [unowned self] in togglePanel(from: .desktop) }
        desktopPet.menuProvider = { [unowned self] in makeMenu() }

        engine.onPoseChange = { [unowned self] pose, due in
            let label = "\(AppInfo.name): \(engine.pet.name) is \(engine.mood.title.lowercased())"
            statusItem.setImage(MenuBarIconRenderer.image(for: pose, badge: due), accessibilityLabel: label)
            desktopPet.apply(pose)
        }
        engine.onNudge = { [unowned self] kind in showBubble(kind) }
        engine.publishPose()

        bubbles.onAction = { [unowned self] nudge, action in
            switch action {
            case .play: play(suggestedGame())
            case .snooze: engine.snoozeBreak()
            case .tookBreak: engine.recordBreak(.manual)
            case .dismiss, .timedOut: break
            }
        }

        observers.append(NotificationCenter.default.addObserver(forName: .openPanelSettings, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.openPanel(tab: .settings) }
        })

        observeChanges { [weak self] in self?.updateDesktopPet() }
        observeChanges { [weak self] in self?.forwardReaction() }
    }

    /// Re-runs `body` whenever anything it read from an `@Observable` changes.
    private func observeChanges(_ body: @escaping @MainActor () -> Void) {
        withObservationTracking(body) { [weak self] in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.observeChanges(body) }
            }
        }
    }

    private func updateDesktopPet() {
        let hiddenForQuiet = preferences.hideDesktopPetWhenQuiet && engine.quiet.isQuiet
        let visible = preferences.desktopPetEnabled
            && engine.isOnboarded
            && !hiddenForQuiet
            && arcadeIsOpen == false
        desktopPet.setVisible(visible)
    }

    private func forwardReaction() {
        guard let reaction = engine.reaction, reaction != lastReaction else { return }
        lastReaction = reaction
        desktopPet.react(reaction)
    }

    private var arcadeIsOpen: Bool { arcade != nil }

    private func updateBusy() {
        engine.isBusy = panel.isVisible || arcade != nil || onboarding != nil
    }

    // MARK: Panel

    private func makePanel() -> PanelController {
        let actions = PanelActions(
            play: { [unowned self] game in play(game) },
            snooze: { [unowned self] in engine.snoozeBreak() },
            tookBreak: { [unowned self] in engine.recordBreak(.manual) },
            recenter: { [unowned self] in recenter() },
            quit: { NSApp.terminate(nil) }
        )
        let controller = PanelController(
            size: PanelRootView.size,
            content: PanelRootView(engine: engine, pro: pro, router: router, actions: actions)
        )
        controller.onClose = { [unowned self] in
            router.showsPaywall = false
            updateBusy()
            updateDesktopPet()
        }
        return controller
    }

    private func togglePanel(from source: Source) {
        if panel.isVisible {
            panel.close()
            return
        }
        openPanel(tab: nil, from: source)
    }

    /// Opens the panel (on `tab`, or where it was). Games and onboarding
    /// take precedence: they're brought forward instead.
    func openPanel(tab: PanelTab? = nil) {
        openPanel(tab: tab, from: desktopPet.isVisible && statusItem.screenFrame == nil ? .desktop : .menuBar)
    }

    private func openPanel(tab: PanelTab?, from source: Source) {
        if let arcade {
            arcade.bringToFront()
            return
        }
        if let onboarding {
            onboarding.bringToFront()
            return
        }
        bubbles.hide()
        if let tab {
            router.tab = tab
        } else if !panel.isVisible {
            router.tab = .home
        }
        let size = PanelRootView.size
        let origin: NSPoint
        if source == .desktop, desktopPet.isVisible {
            origin = PanelPlacement.beside(desktopPet.petFrame, size: size)
        } else {
            origin = PanelPlacement.below(statusItem.screenFrame ?? PanelPlacement.fallbackAnchor(), size: size)
        }
        panel.show(at: origin)
        updateBusy()
    }

    /// Relaunching the app (Finder, Spotlight) opens the panel.
    func showMain() {
        if engine.isOnboarded {
            openPanel(tab: nil, from: .menuBar)
        } else {
            showOnboarding()
        }
    }

    // MARK: Bubbles

    func showBubble(_ kind: NudgeKind) {
        guard arcade == nil, onboarding == nil, !panel.isVisible else { return }
        let nudge = Nudge(kind: kind, petName: engine.pet.name)
        if desktopPet.isVisible {
            bubbles.show(nudge, pose: engine.pose, anchor: desktopPet.petFrame, fromMenuBar: false)
        } else {
            bubbles.show(nudge, pose: engine.pose, anchor: statusItem.screenFrame ?? PanelPlacement.fallbackAnchor(), fromMenuBar: true)
        }
        if kind == .breakInvite {
            engine.pet(react: .wobble)
        }
    }

    // MARK: Games

    /// The game a bubble's "Play" starts: a different unlocked game each day.
    private func suggestedGame() -> ArcadeGame {
        let unlocked = ArcadeGame.allCases.filter { !$0.isPro || pro.isPro }
        let index = (engine.today.day.day + engine.today.gamesPlayed) % unlocked.count
        return unlocked[index]
    }

    func play(_ game: ArcadeGame) {
        if let arcade {
            arcade.bringToFront()
            return
        }
        if let onboarding {
            onboarding.bringToFront()
            return
        }
        if game.isPro, !pro.isPro {
            openPanel(tab: .arcade)
            router.showsPaywall = true
            return
        }

        let controller = ArcadeController(game: game, engine: engine)
        controller.onRoundFinished = { [unowned self] game, result in
            finishGame(game, result: result)
        }
        controller.onClose = { [unowned self] in
            arcade = nil
            engine.isPostureSuspended = false
            updateBusy()
            updateDesktopPet()
        }
        // Registered before the panel closes, so the handoff never looks
        // "not busy" long enough for a bubble to slip in.
        arcade = controller
        engine.isPostureSuspended = true
        updateBusy()
        panel.close(animated: false)
        bubbles.hide()
        updateDesktopPet()
        controller.show()
    }

    private func finishGame(_ game: ArcadeGame, result: GameResult) {
        engine.addTreats(result.treats)
        if result.completed {
            engine.recordBreak(.game)
        }
        engine.recordScore(result.score, for: game.rawValue)
        engine.pet(react: .celebrate)
    }

    // MARK: Onboarding

    private func showOnboarding() {
        guard onboarding == nil else {
            onboarding?.bringToFront()
            return
        }
        let controller = OnboardingController(engine: engine, preferences: preferences)
        controller.onFinish = { [unowned self] in
            onboarding = nil
            updateBusy()
            updateDesktopPet()
            engine.pet(react: .celebrate)
        }
        onboarding = controller
        updateBusy()
        panel.close(animated: false)
        bubbles.hide()
        controller.show()
    }

    private func recenter() {
        if let onboarding {
            onboarding.bringToFront()
            return
        }
        let controller = OnboardingController(engine: engine, preferences: preferences, recenterOnly: true)
        controller.onFinish = { [unowned self] in
            onboarding = nil
            updateBusy()
        }
        onboarding = controller
        updateBusy()
        panel.close(animated: false)
        bubbles.hide()
        controller.show()
    }

    // MARK: Menu

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        let name = engine.pet.name

        let header = NSMenuItem(title: "\(name) is \(engine.mood.title.lowercased())", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        menu.addItem(ClosureMenuItem("Open \(name)") { [unowned self] in openPanel(tab: .home) })
        menu.addItem(ClosureMenuItem("Neck Arcade…") { [unowned self] in openPanel(tab: .arcade) })
        menu.addItem(.separator())

        if case .manual = engine.quiet.reason {
            menu.addItem(ClosureMenuItem("Resume Nudges") { [unowned self] in engine.setQuiet(until: nil) })
        } else {
            menu.addItem(ClosureMenuItem("Quiet for 1 Hour") { [unowned self] in
                engine.setQuiet(until: .now.addingTimeInterval(3600))
            })
            menu.addItem(ClosureMenuItem("Quiet Until Tomorrow") { [unowned self] in
                engine.setQuiet(until: PetDay(containing: .now).adding(days: 1).start())
            })
        }
        if preferences.desktopPetEnabled {
            menu.addItem(ClosureMenuItem("Send \(name) Home") { [unowned self] in
                preferences.desktopPetEnabled = false
            })
        } else {
            menu.addItem(ClosureMenuItem("Show \(name) on Desktop") { [unowned self] in
                preferences.desktopPetEnabled = true
            })
        }
        menu.addItem(.separator())

        menu.addItem(ClosureMenuItem("Settings…", key: ",") { [unowned self] in openPanel(tab: .settings) })
        menu.addItem(ClosureMenuItem("About \(AppInfo.name)") {
            NSApp.activate()
            NSApp.orderFrontStandardAboutPanel(nil)
        })
        #if DEBUG
        menu.addItem(debug.menuItem())
        #endif
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("Quit \(AppInfo.name)", key: "q") {
            NSApp.terminate(nil)
        })
        return menu
    }

    func prepareForTermination() {
        engine.flush()
    }

    #if DEBUG
    var debugStatusItemFrame: NSRect? { statusItem.screenFrame }
    var debugPanelVisible: Bool { panel.isVisible }
    var debugBubbleVisible: Bool { bubbles.isVisible }
    var debugArcade: ArcadeController? { arcade }
    func debugClosePanel() { panel.close(animated: false) }
    func debugHideBubble() { bubbles.hide() }
    func debugShowOnboarding() {
        engine.debugResetOnboarding()
        showOnboarding()
    }
    #endif
}
