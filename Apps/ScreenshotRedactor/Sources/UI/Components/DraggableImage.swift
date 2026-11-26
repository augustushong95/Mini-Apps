import AppKit
import SwiftUI

/// Shows an image that can be clicked (to open it) or dragged into another
/// app as a file. Used for the redacted thumbnail in the preview card and
/// the recent list; it only ever shows redacted pixels.
struct DraggableImage: NSViewRepresentable {
    let image: CGImage?
    var cornerRadius: CGFloat = Theme.thumbnailRadius
    /// Makes the file to drag, or nil when dragging isn't allowed right now.
    let dragFile: () -> URL?
    /// Called when a drag ends; true if it was dropped somewhere.
    let dragEnded: (Bool) -> Void
    let onClick: () -> Void
    let accessibilityLabel: String

    func makeNSView(context: Context) -> DraggableImageView {
        let view = DraggableImageView()
        update(view)
        return view
    }

    func updateNSView(_ view: DraggableImageView, context: Context) {
        update(view)
    }

    private func update(_ view: DraggableImageView) {
        view.image = image
        view.cornerRadius = cornerRadius
        view.dragFile = dragFile
        view.dragEnded = dragEnded
        view.onClick = onClick
        view.setAccessibilityLabel(accessibilityLabel)
    }
}

final class DraggableImageView: NSView, NSDraggingSource {
    var image: CGImage? {
        didSet { if image !== oldValue { layer?.contents = image } }
    }
    var cornerRadius: CGFloat = 8 {
        didSet { layer?.cornerRadius = cornerRadius }
    }
    var dragFile: (() -> URL?)?
    var dragEnded: ((Bool) -> Void)?
    var onClick: (() -> Void)?

    private var mouseDownPoint: NSPoint?
    private var dragStarted = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.contentsGravity = .resizeAspect
        layer?.masksToBounds = true
        layer?.cornerRadius = cornerRadius
        layer?.magnificationFilter = .linear
        layer?.minificationFilter = .trilinear
        setAccessibilityRole(.image)
        setAccessibilityElement(true)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = convert(event.locationInWindow, from: nil)
        dragStarted = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownPoint, !dragStarted else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard hypot(point.x - start.x, point.y - start.y) > 4 else { return }
        dragStarted = true
        guard let url = dragFile?(), let image else { return }

        let item = NSPasteboardItem()
        item.setString(url.absoluteString, forType: .fileURL)
        if let data = try? Data(contentsOf: url) {
            item.setData(data, forType: .png)
        }
        let draggingItem = NSDraggingItem(pasteboardWriter: item)
        draggingItem.setDraggingFrame(imageFrame(), contents: NSImage(cgImage: image, size: imageFrame().size))
        beginDraggingSession(with: [draggingItem], event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        defer { mouseDownPoint = nil }
        if !dragStarted, mouseDownPoint != nil { onClick?() }
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? .copy : []
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        dragEnded?(operation != [])
    }

    override func accessibilityPerformPress() -> Bool {
        onClick?()
        return true
    }

    /// Where the aspect-fitted image sits inside the view.
    private func imageFrame() -> NSRect {
        guard let image, image.width > 0, image.height > 0 else { return bounds }
        let scale = min(bounds.width / CGFloat(image.width), bounds.height / CGFloat(image.height))
        let size = NSSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
        return NSRect(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2, width: size.width, height: size.height)
    }
}
