import AppKit
import QuartzCore

/// The Neck Arcade window: centred on the current screen, driven by the
/// display's refresh, paused whenever it loses focus.
final class ArcadeController {
    var onRoundFinished: ((ArcadeGame, GameResult) -> Void)?
    var onClose: (() -> Void)?

    let session: GameSession
    private let panel: FloatingPanel
    private let driver = FrameDriver()
    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval?
    private var keyMonitor: Any?
    private var resignObserver: NSObjectProtocol?
    private var isClosing = false

    init(game: ArcadeGame, engine: PetEngine) {
        session = GameSession(game: game, engine: engine)
        panel = FloatingPanel(size: ArcadeView.size, canBecomeKey: true, level: .floating)
        let close: () -> Void = { [weak self] in self?.close() }
        panel.setContent(ArcadeView(session: session, engine: engine, close: close))
        panel.onCancel = { [weak self] in self?.handleEscape() }
        session.onRoundFinished = { [weak self] result in
            self?.onRoundFinished?(game, result)
        }
    }

    func show() {
        NSApp.activate()
        panel.present(at: PanelPlacement.centered(size: ArcadeView.size), animated: true)
        panel.makeKey()
        startLoop()
        installKeyMonitor()
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.session.pause(.lostFocus) }
        }
    }

    func bringToFront() {
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        guard !isClosing else { return }
        isClosing = true
        displayLink?.invalidate()
        displayLink = nil
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        if let resignObserver {
            NotificationCenter.default.removeObserver(resignObserver)
        }
        session.end()
        panel.dismiss(animated: true) { [weak self] in
            self?.onClose?()
        }
    }

    private func startLoop() {
        guard let view = panel.contentView else { return }
        driver.onFrame = { [weak self] timestamp in
            guard let self else { return }
            let dt = lastTimestamp.map { timestamp - $0 } ?? 0
            lastTimestamp = timestamp
            session.frame(dt: dt)
        }
        let link = view.displayLink(target: driver, selector: #selector(FrameDriver.tick(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func handleEscape() {
        switch session.phase {
        case .playing:
            session.pause()
        case .countdown where session.hasStarted:
            // Resuming a round: Esc goes back to the pause card, never
            // throwing the round (and its treats) away.
            session.pause()
        case .paused:
            session.endRound()
        case .finished, .rangeCheck, .countdown:
            close()
        }
    }

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            let keyCode = event.keyCode
            let isDown = event.type == .keyDown
            let isRepeat = isDown && event.isARepeat
            let isOurs = event.window?.windowNumber
            let consumed = MainActor.assumeIsolated { () -> Bool in
                guard let self, isOurs == self.panel.windowNumber else { return false }
                return self.handleKey(keyCode, down: isDown, isRepeat: isRepeat)
            }
            return consumed ? nil : event
        }
    }

    /// Returns true when the key was used by the game.
    private func handleKey(_ keyCode: UInt16, down: Bool, isRepeat: Bool) -> Bool {
        switch keyCode {
        case 123: _ = session.key(.left, down: down)
        case 124: _ = session.key(.right, down: down)
        case 126: _ = session.key(.up, down: down)
        case 49:
            if !isRepeat { _ = session.key(.space, down: down) }
        case 53:
            if down { handleEscape() }
        case 36:
            if down, case .finished = session.phase { session.playAgain() }
        default:
            return false
        }
        return true
    }
}

/// Receives display-link callbacks (which need an Objective-C target).
final class FrameDriver: NSObject {
    var onFrame: ((CFTimeInterval) -> Void)?

    @objc func tick(_ link: CADisplayLink) {
        onFrame?(link.timestamp)
    }
}
