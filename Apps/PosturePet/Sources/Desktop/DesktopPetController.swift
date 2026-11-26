import AppKit

/// Mochi on the desktop: a small transparent panel the user can drag
/// anywhere, on any display. Its position is remembered per screen setup
/// and always kept on a visible screen.
final class DesktopPetController {
    var onClick: (() -> Void)?
    var menuProvider: (() -> NSMenu)?

    private let panel: FloatingPanel
    private let petView: DesktopPetView
    private let preferences: Preferences
    private var screenObserver: NSObjectProtocol?
    private var moveObserver: NSObjectProtocol?
    private var settleWork: DispatchWorkItem?

    static let size = NSSize(width: 112, height: 112)

    init(preferences: Preferences) {
        self.preferences = preferences
        panel = FloatingPanel(size: Self.size, canBecomeKey: false, level: .floating)
        panel.hasShadow = false
        petView = DesktopPetView(frame: NSRect(origin: .zero, size: Self.size))
        panel.contentView = petView

        petView.onClick = { [weak self] in self?.onClick?() }
        petView.onRightClick = { [weak self] event in
            guard let self, let menu = menuProvider?() else { return }
            NSMenu.popUpContextMenu(menu, with: event, for: petView)
        }
        petView.onDragEnded = { [weak self] in self?.scheduleSettle() }
        // Saves once the window stops moving, whether or not the drag call
        // returned before the drag finished.
        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleSettle() }
        }

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.panel.isVisible else { return }
                self.panel.setFrameOrigin(self.restoredOrigin())
            }
        }
    }

    var isVisible: Bool { panel.isVisible }
    var frame: NSRect { panel.frame }

    /// Where Mochi's body actually is (the panel has room around it).
    var petFrame: NSRect {
        panel.frame.insetBy(dx: 14, dy: 10)
    }

    func apply(_ pose: PetPose) {
        petView.basePose = pose
    }

    func react(_ reaction: PetReaction) {
        petView.react(reaction)
    }

    func setVisible(_ visible: Bool, animated: Bool = true) {
        if visible, !panel.isVisible {
            panel.setFrameOrigin(restoredOrigin())
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                panel.animator().alphaValue = 1
            }
            petView.react(PetReaction(kind: .hop))
        } else if !visible, panel.isVisible {
            panel.dismiss(animated: animated)
        }
    }

    // MARK: Position

    private func restoredOrigin() -> NSPoint {
        let arrangement = DisplayArrangement.current()
        if let saved = preferences.desktopPetOrigin(for: arrangement) {
            return clamped(saved)
        }
        // First time on this setup: bottom-right of the main screen.
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return panel.frame.origin }
        let visible = screen.visibleFrame
        return NSPoint(x: visible.maxX - Self.size.width - 40, y: visible.minY + 24)
    }

    /// Keeps the whole pet on whichever screen holds most of it.
    private func clamped(_ origin: NSPoint) -> NSPoint {
        let frame = NSRect(origin: origin, size: Self.size)
        let screen = NSScreen.screens.max { a, b in
            a.visibleFrame.intersection(frame).area < b.visibleFrame.intersection(frame).area
        }
        let visible = (screen?.visibleFrame.intersects(frame) == true ? screen : NSScreen.main)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return NSPoint(
            x: min(max(origin.x, visible.minX), visible.maxX - Self.size.width),
            y: min(max(origin.y, visible.minY), visible.maxY - Self.size.height)
        )
    }

    private func scheduleSettle() {
        settleWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.settle() }
        }
        settleWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    private func settle() {
        guard panel.isVisible, NSEvent.pressedMouseButtons == 0 else {
            if panel.isVisible { scheduleSettle() }
            return
        }
        let target = clamped(panel.frame.origin)
        if target != panel.frame.origin {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrameOrigin(target)
            }
        }
        let saved = preferences.desktopPetOrigin(for: DisplayArrangement.current())
        preferences.setDesktopPetOrigin(target, for: DisplayArrangement.current())
        if saved != target {
            petView.react(PetReaction(kind: .hop))
        }
    }
}

private extension NSRect {
    var area: CGFloat { isNull ? 0 : width * height }
}

/// Hosts Mochi and turns mouse input into click, drag and context menu.
final class DesktopPetView: NSView {
    var onClick: (() -> Void)?
    var onRightClick: ((NSEvent) -> Void)?
    var onDragEnded: (() -> Void)?

    /// The pose from the engine; hovering adds a glance at the cursor.
    var basePose = PetPose() {
        didSet { updatePose() }
    }

    private let pet: PetLayerView
    private var mouseDownLocation: NSPoint?
    private var isDragging = false
    private var hoverGaze: CGVector?

    override init(frame frameRect: NSRect) {
        pet = PetLayerView(frame: NSRect(origin: .zero, size: frameRect.size))
        super.init(frame: frameRect)
        pet.autoresizingMask = [.width, .height]
        addSubview(pet)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("Posture Pet")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self
        ))
    }

    func react(_ reaction: PetReaction) {
        switch reaction.kind {
        case .hop: pet.hop()
        case .celebrate: pet.celebrate()
        case .wobble: pet.wobble()
        case .chew: pet.chew()
        }
    }

    private func updatePose() {
        var pose = basePose
        if let hoverGaze, pose.eyes == .open {
            pose.gaze = hoverGaze
        }
        if pose != pet.pose {
            pet.apply(pose, animated: true)
        }
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        mouseDownLocation = event.locationInWindow
        isDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownLocation, !isDragging else { return }
        let location = event.locationInWindow
        if hypot(location.x - start.x, location.y - start.y) > 3 {
            isDragging = true
            // The system moves the window, smoothly and across displays.
            window?.performDrag(with: event)
            isDragging = false
            mouseDownLocation = nil
            onDragEnded?()
        }
    }

    override func mouseUp(with event: NSEvent) {
        defer { mouseDownLocation = nil }
        guard mouseDownLocation != nil, !isDragging else { return }
        pet.hop(height: 0.08)
        onClick?()
    }

    override func rightMouseDown(with event: NSEvent) {
        onRightClick?(event)
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let dx = (point.x - bounds.midX) / (bounds.width / 2)
        let dy = (point.y - bounds.midY) / (bounds.height / 2)
        hoverGaze = CGVector(dx: max(-1, min(1, dx)), dy: max(-1, min(1, dy)))
        updatePose()
    }

    override func mouseExited(with event: NSEvent) {
        hoverGaze = nil
        updatePose()
    }
}
