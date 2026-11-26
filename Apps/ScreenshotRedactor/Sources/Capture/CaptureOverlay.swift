import AppKit

/// A full-screen window over one display showing its frozen picture, dimmed
/// except where the user is selecting.
final class CaptureOverlayWindow: NSWindow {
    var onFinish: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?

    init(screen: NSScreen, image: CGImage, windows: [CGRect]) {
        super.init(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        setFrame(screen.frame, display: false)
        level = .screenSaver
        isOpaque = true
        backgroundColor = .black
        hasShadow = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        let view = CaptureOverlayView(image: image, screenFrame: screen.frame, windows: windows)
        view.onFinish = { [weak self] rect in self?.onFinish?(rect) }
        view.onCancel = { [weak self] in self?.onCancel?() }
        contentView = view
        makeFirstResponder(view)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

/// Draws the frozen display, the dim, the selection and its size. Drag to
/// select an area; click (without dragging) to take the window under the
/// pointer, or the whole display if there's none; Esc cancels.
final class CaptureOverlayView: NSView {
    var onFinish: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?

    private let image: CGImage
    private let screenFrame: CGRect
    /// On-screen windows (Cocoa global points), front to back.
    private let windows: [CGRect]
    private var start: CGPoint?
    private var selection: CGRect?
    private var hoveredWindow: CGRect?
    private var trackingArea: NSTrackingArea?

    init(image: CGImage, screenFrame: CGRect, windows: [CGRect]) {
        self.image = image
        self.screenFrame = screenFrame
        self.windows = windows
        super.init(frame: NSRect(origin: .zero, size: screenFrame.size))
        setAccessibilityLabel("Drag to select an area to capture, click a window, or press Escape to cancel.")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways, .inVisibleRect, .cursorUpdate], owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    override func cursorUpdate(with event: NSEvent) { NSCursor.crosshair.set() }

    /// Event location (window points) as Cocoa global points.
    private func globalPoint(_ event: NSEvent) -> CGPoint {
        let local = convert(event.locationInWindow, from: nil)
        return CGPoint(x: local.x + screenFrame.minX, y: local.y + screenFrame.minY)
    }

    private func local(_ rect: CGRect) -> CGRect {
        rect.offsetBy(dx: -screenFrame.minX, dy: -screenFrame.minY)
    }

    override func mouseMoved(with event: NSEvent) {
        guard start == nil else { return }
        let point = globalPoint(event)
        let window = windows.first { $0.contains(point) }?.intersection(screenFrame)
        if window != hoveredWindow {
            hoveredWindow = window
            needsDisplay = true
        }
        NSCursor.crosshair.set()
    }

    override func mouseDown(with event: NSEvent) {
        start = globalPoint(event)
        selection = nil
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start else { return }
        selection = CaptureGeometry.selection(from: start, to: globalPoint(event), on: screenFrame)
        hoveredWindow = nil
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer { start = nil }
        if let selection, selection.width >= 4, selection.height >= 4 {
            onFinish?(selection)
            return
        }
        // A click: the window under the pointer, or the whole display.
        let point = globalPoint(event)
        let window = windows.first { $0.contains(point) }?.intersection(screenFrame)
        onFinish?(window ?? screenFrame)
    }

    override func rightMouseDown(with event: NSEvent) {
        onCancel?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onCancel?() } else { super.keyDown(with: event) }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.interpolationQuality = .none
        context.draw(image, in: bounds)

        let highlight = selection ?? hoveredWindow
        let dim = NSBezierPath(rect: bounds)
        if let highlight {
            dim.append(NSBezierPath(rect: local(highlight)))
            dim.windingRule = .evenOdd
        }
        NSColor.black.withAlphaComponent(0.4).setFill()
        dim.fill()

        guard let highlight else {
            drawHint("Drag to select an area · Click a window · Esc to cancel")
            return
        }
        let rect = local(highlight)
        let border = NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5))
        border.lineWidth = 1
        NSColor.white.withAlphaComponent(0.9).setStroke()
        border.stroke()

        let scale = CGFloat(image.width) / bounds.width
        let label = "\(Int((highlight.width * scale).rounded())) × \(Int((highlight.height * scale).rounded()))"
        drawBadge(label, near: rect)
    }

    private func drawBadge(_ text: String, near rect: CGRect) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let string = NSAttributedString(string: text, attributes: attributes)
        let size = string.size()
        var badge = NSRect(x: rect.maxX - size.width - 12, y: rect.minY - size.height - 10, width: size.width + 12, height: size.height + 6)
        if badge.minY < 4 { badge.origin.y = rect.minY + 6 }
        badge.origin.x = max(4, min(badge.minX, bounds.maxX - badge.width - 4))
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: badge, xRadius: 5, yRadius: 5).fill()
        string.draw(at: NSPoint(x: badge.minX + 6, y: badge.minY + 3))
    }

    private func drawHint(_ text: String) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let string = NSAttributedString(string: text, attributes: attributes)
        let size = string.size()
        let pill = NSRect(x: bounds.midX - size.width / 2 - 14, y: bounds.maxY - size.height - 64, width: size.width + 28, height: size.height + 12)
        NSColor.black.withAlphaComponent(0.65).setFill()
        NSBezierPath(roundedRect: pill, xRadius: pill.height / 2, yRadius: pill.height / 2).fill()
        string.draw(at: NSPoint(x: pill.minX + 14, y: pill.minY + 6))
    }
}
