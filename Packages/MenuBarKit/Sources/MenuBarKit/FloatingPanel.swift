import AppKit
import SwiftUI

/// A borderless, transparent panel for SwiftUI content: menu bar panels,
/// bubbles, preview cards and other floating surfaces.
///
/// Non-activating, so opening it never pulls the user out of the app
/// they're in. Whether it can ever take keyboard focus is fixed at creation;
/// whether it takes focus when shown is chosen each time (`present`).
@MainActor
public final class FloatingPanel: NSPanel {
    private let allowsKey: Bool
    /// Bumped by every present and dismiss, so a fade-out that finishes after
    /// the window was shown again (or dismissed again) does nothing.
    private var transition = 0

    /// Called when Esc is pressed while the panel has focus.
    public var onCancel: (() -> Void)?

    /// Gets every key equivalent (⌘C, ⌘S…) first while the panel has focus.
    /// Return true when handled. A menu bar app has no Edit menu, so this is
    /// how a panel answers ⌘C without registering anything global.
    public var keyEquivalentHandler: ((NSEvent) -> Bool)?

    /// Gets plain key presses (Return, arrows, Space) while the panel has
    /// focus, before the content does. Return true when handled.
    public var keyDownHandler: ((NSEvent) -> Bool)?

    public init(size: NSSize, canBecomeKey: Bool, level: NSWindow.Level = .statusBar) {
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

    public override var canBecomeKey: Bool { allowsKey }
    public override var canBecomeMain: Bool { false }

    public override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    public override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if keyEquivalentHandler?(event) == true { return true }
        return super.performKeyEquivalent(with: event)
    }

    public override func keyDown(with event: NSEvent) {
        if keyDownHandler?(event) == true { return }
        super.keyDown(with: event)
    }

    /// Hosts a SwiftUI view, sized by the view.
    public func setContent<Content: View>(_ view: Content) {
        let hosting = FirstMouseHostingView(rootView: view)
        hosting.sizingOptions = [.preferredContentSize]
        contentView = hosting
    }

    /// Fades in from slightly above, the way menus appear.
    ///
    /// - Parameter takesFocus: whether the panel becomes key (gets the
    ///   keyboard) as it appears. Pass false for surfaces that appear on
    ///   their own, so they never take keystrokes meant for another app;
    ///   a click on the panel still gives it focus.
    public func present(at origin: NSPoint, animated: Bool, takesFocus: Bool = true) {
        transition += 1
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if animated {
            setFrameOrigin(reduceMotion ? origin : NSPoint(x: origin.x, y: origin.y + 6))
            alphaValue = 0
        }
        if allowsKey, takesFocus {
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
    public func dismiss(animated: Bool, completion: (@MainActor () -> Void)? = nil) {
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

/// Hosts SwiftUI and takes the first click, so buttons in panels that aren't
/// key respond to the first click while another app is active.
@MainActor
public final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Where floating panels go on screen.
@MainActor
public enum PanelPlacement {
    /// The origin that puts a window of `size` just below `anchor` (a screen
    /// rect such as the status item), centred on it and kept inside the
    /// visible part of the anchor's screen.
    public static func below(_ anchor: NSRect, size: NSSize, gap: CGFloat = 6) -> NSPoint {
        let screen = NSScreen.screens.first { $0.frame.intersects(anchor) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        var x = anchor.midX - size.width / 2
        var y = anchor.minY - gap - size.height
        x = min(max(x, visible.minX + 8), visible.maxX - size.width - 8)
        y = min(max(y, visible.minY + 8), visible.maxY - size.height)
        return NSPoint(x: x, y: y)
    }

    /// Beside `anchor`, preferring the side with more room.
    public static func beside(_ anchor: NSRect, size: NSSize, gap: CGFloat = 8) -> NSPoint {
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
    public static func centered(size: NSSize) -> NSPoint {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return NSPoint(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2 + visible.height * 0.06)
    }

    /// The top-right corner of `screen`'s visible area (under the menu bar),
    /// inset by `inset`. Used for cards that appear on their own, away from
    /// the system's own bottom-right screenshot thumbnail.
    public static func topTrailing(on screen: NSScreen?, size: NSSize, inset: CGFloat = 14) -> NSPoint {
        let visible = (screen ?? NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return NSPoint(x: visible.maxX - size.width - inset, y: visible.maxY - size.height - inset)
    }

    /// The top-right corner under the menu bar, for when the status item
    /// can't be seen (hidden behind the notch or by the user).
    public static func fallbackAnchor() -> NSRect {
        let screen = NSScreen.main ?? NSScreen.screens.first
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return NSRect(x: visible.maxX - 120, y: visible.maxY, width: 24, height: 1)
    }
}
