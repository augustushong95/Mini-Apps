import AppKit
import SwiftUI

/// A borderless, transparent panel for SwiftUI content: the main panel,
/// speech bubbles, the arcade and the desktop pet.
///
/// Non-activating, so opening it never pulls the user out of the app
/// they're in. Whether it can take keyboard focus is fixed at creation.
final class FloatingPanel: NSPanel {
    private let allowsKey: Bool
    /// Bumped by every present and dismiss, so a fade-out that finishes after
    /// the window was shown again (or dismissed again) does nothing.
    private var transition = 0
    /// Called when Esc is pressed while the panel has focus.
    var onCancel: (() -> Void)?

    init(size: NSSize, canBecomeKey: Bool, level: NSWindow.Level = .statusBar) {
        allowsKey = canBecomeKey
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isFloatingPanel = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovableByWindowBackground = false
        self.level = level
        // Shows on whichever Space is current, including over full-screen apps.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { allowsKey }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    /// Hosts a SwiftUI view, sized by the view.
    func setContent<Content: View>(_ view: Content) {
        let hosting = FirstMouseHostingView(rootView: view)
        hosting.sizingOptions = [.preferredContentSize]
        contentView = hosting
    }

    /// Fades in from slightly above, the way menus appear.
    func present(at origin: NSPoint, animated: Bool) {
        transition += 1
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if animated {
            setFrameOrigin(reduceMotion ? origin : NSPoint(x: origin.x, y: origin.y + 6))
            alphaValue = 0
        }
        if allowsKey {
            makeKeyAndOrderFront(nil)
        } else {
            orderFrontRegardless()
        }
        // Also replaces a fade-out that may still be running.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = animated ? 0.18 : 0
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1
            animator().setFrameOrigin(origin)
        }
    }

    /// Fades out, then orders out.
    func dismiss(animated: Bool, completion: (@MainActor () -> Void)? = nil) {
        guard isVisible else {
            completion?()
            return
        }
        transition += 1
        let token = transition
        guard animated else {
            orderOut(nil)
            alphaValue = 1
            completion?()
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.transition == token else { return }
                self.orderOut(nil)
                self.alphaValue = 1
                completion?()
            }
        }
    }
}

/// Hosts SwiftUI and takes the first click, so buttons in panels that never
/// become key (bubbles) respond while another app is active.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

enum PanelPlacement {
    /// The origin that puts a window of `size` just below `anchor` (a screen
    /// rect such as the status item), centred on it and kept inside the
    /// visible part of the anchor's screen.
    static func below(_ anchor: NSRect, size: NSSize, gap: CGFloat = 6) -> NSPoint {
        let screen = NSScreen.screens.first { $0.frame.intersects(anchor) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        var x = anchor.midX - size.width / 2
        var y = anchor.minY - gap - size.height
        x = min(max(x, visible.minX + 8), visible.maxX - size.width - 8)
        y = min(max(y, visible.minY + 8), visible.maxY - size.height)
        return NSPoint(x: x, y: y)
    }

    /// Beside `anchor` (the desktop pet), preferring the side with more room.
    static func beside(_ anchor: NSRect, size: NSSize, gap: CGFloat = 8) -> NSPoint {
        let screen = NSScreen.screens.first { $0.frame.intersects(anchor) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let roomRight = visible.maxX - anchor.maxX
        let roomLeft = anchor.minX - visible.minX
        var x = roomRight >= size.width + gap || roomRight >= roomLeft
            ? anchor.maxX + gap
            : anchor.minX - gap - size.width
        var y = anchor.midY - size.height / 2
        x = min(max(x, visible.minX + 8), visible.maxX - size.width - 8)
        y = min(max(y, visible.minY + 8), visible.maxY - size.height - 8)
        return NSPoint(x: x, y: y)
    }

    /// Centred on the screen the mouse is on.
    static func centered(size: NSSize) -> NSPoint {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return NSPoint(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2 + visible.height * 0.06)
    }

    /// The top-right corner under the menu bar, for when the status item
    /// can't be seen (hidden behind the notch or by the user).
    static func fallbackAnchor() -> NSRect {
        let screen = NSScreen.main ?? NSScreen.screens.first
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return NSRect(x: visible.maxX - 120, y: visible.maxY, width: 24, height: 1)
    }
}
