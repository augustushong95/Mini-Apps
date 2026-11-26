import AppKit
import SwiftUI

/// The editor's image area: an AppKit view for exact mouse handling,
/// inside a scroll view for actual-size viewing.
struct RedactionCanvas: NSViewRepresentable {
    let model: EditorModel
    /// Changes whenever anything drawn changes, so SwiftUI redraws the view.
    let revision: Int

    func makeNSView(context: Context) -> CanvasScrollView {
        let scrollView = CanvasScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.documentView = RedactionCanvasView(model: model)
        return scrollView
    }

    func updateNSView(_ scrollView: CanvasScrollView, context: Context) {
        guard let canvas = scrollView.documentView as? RedactionCanvasView else { return }
        canvas.relayout()
        canvas.needsDisplay = true
    }
}

/// Re-fits the canvas whenever the visible area changes size.
final class CanvasScrollView: NSScrollView {
    override func layout() {
        super.layout()
        (documentView as? RedactionCanvasView)?.relayout()
    }
}

final class RedactionCanvasView: NSView {
    private let model: EditorModel
    private var document: RedactionDocument { model.document }
    private let originalImage: NSImage
    private(set) var geometry: CanvasGeometry

    private enum Gesture {
        /// Pressed on a found box: a click toggles it; a drag draws a new box.
        case pressBox(RedactionBox.ID, start: CGPoint)
        /// Moving a box you drew.
        case move(RedactionBox.ID, start: CGPoint, original: CGRect, current: CGRect)
        case resize(RedactionBox.ID, CanvasGeometry.Handle, current: CGRect)
        /// Drawing a new box from `start` (image pixels).
        case draw(start: CGPoint, current: CGRect)
    }

    private var gesture: Gesture?
    private var trackingArea: NSTrackingArea?

    init(model: EditorModel) {
        self.model = model
        originalImage = NSImage(cgImage: model.document.image, size: model.document.pixelSize)
        geometry = CanvasGeometry(imageSize: model.document.pixelSize, canvasSize: .zero, scale: 1)
        super.init(frame: .zero)
        setAccessibilityRole(.image)
        setAccessibilityLabel("Screenshot with boxes. Use the list on the right to cover or uncover each item.")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Points per image pixel at "actual size": the image at its point size.
    private var actualScale: CGFloat { 72 / max(document.dpi, 1) }

    /// Sizes the canvas to the visible area (fit) or the image (actual size).
    func relayout() {
        guard let clipView = enclosingScrollView?.contentView else { return }
        let available = clipView.bounds.size
        let margin: CGFloat = 24
        let scale: CGFloat
        switch model.zoom {
        case .fit:
            scale = CanvasGeometry.fitScale(
                imageSize: document.pixelSize,
                available: CGSize(width: available.width - margin * 2, height: available.height - margin * 2),
                maximum: actualScale * 2
            )
        case .actual:
            scale = actualScale
        }
        let shown = CGSize(width: document.pixelSize.width * scale + margin * 2, height: document.pixelSize.height * scale + margin * 2)
        let size = CGSize(width: max(available.width, shown.width), height: max(available.height, shown.height))
        if frame.size != size { setFrameSize(size) }
        let updated = CanvasGeometry(imageSize: document.pixelSize, canvasSize: size, scale: scale)
        if updated != geometry {
            geometry = updated
            needsDisplay = true
            window?.invalidateCursorRects(for: self)
        }
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        let imageRect = geometry.imageRectInCanvas
        NSGraphicsContext.current?.imageInterpolation = geometry.scale < 1 ? .high : .none

        // A soft shadow under the image, like a page.
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowBlurRadius = 8
        shadow.shadowOffset = NSSize(width: 0, height: -2)
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
        shadow.set()
        NSColor.windowBackgroundColor.setFill()
        imageRect.fill(using: .sourceOver)
        NSGraphicsContext.restoreGraphicsState()

        originalImage.draw(in: imageRect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)

        let fill = NSColor(cgColor: document.style.color.fill) ?? .black
        for box in displayedBoxes() {
            let rect = geometry.toCanvas(box.rect).integral
            if box.isCovered {
                if model.isPeeking {
                    fill.withAlphaComponent(0.25).setFill()
                    rect.fill(using: .sourceOver)
                    stroke(rect, color: categoryColor(box), dashed: false, width: 1.5)
                } else {
                    fill.setFill()
                    rect.fill(using: .sourceOver)
                    if document.style.showsLabels { drawLabelInside(box, rect: rect) }
                }
            } else {
                stroke(rect.insetBy(dx: 0.5, dy: 0.5), color: categoryColor(box), dashed: true, width: 1.5)
                drawTag(box.label, above: rect, color: categoryColor(box))
            }
            if box.id == model.selectedID {
                stroke(rect.insetBy(dx: -2, dy: -2), color: .controlAccentColor, dashed: false, width: 2)
                if box.source == .manual { drawHandles(rect) }
            } else if box.id == model.hoveredID {
                stroke(rect.insetBy(dx: -1.5, dy: -1.5), color: .controlAccentColor, dashed: false, width: 1.5)
                if box.isCovered, !model.isPeeking { drawTag(box.label, above: rect, color: .controlAccentColor) }
            }
        }

        if case .draw(_, let current)? = gesture {
            let rect = geometry.toCanvas(current)
            NSColor.controlAccentColor.withAlphaComponent(0.15).setFill()
            rect.fill(using: .sourceOver)
            stroke(rect, color: .controlAccentColor, dashed: true, width: 1.5)
        }
    }

    /// The document's boxes, with the one being moved or resized shown where it's going.
    private func displayedBoxes() -> [RedactionBox] {
        var boxes = document.boxes
        switch gesture {
        case .move(let id, _, _, let current)?, .resize(let id, _, let current)?:
            if let index = boxes.firstIndex(where: { $0.id == id }) { boxes[index].rect = current }
        default:
            break
        }
        return boxes
    }

    private func categoryColor(_ box: RedactionBox) -> NSColor {
        NSColor(Theme.color(for: box.category))
    }

    private func stroke(_ rect: NSRect, color: NSColor, dashed: Bool, width: CGFloat) {
        let path = NSBezierPath(rect: rect)
        path.lineWidth = width
        if dashed { path.setLineDash([5, 3], count: 2, phase: 0) }
        color.setStroke()
        path.stroke()
    }

    private func drawHandles(_ rect: NSRect) {
        for handle in CanvasGeometry.Handle.allCases {
            let center = CanvasGeometry.corner(handle, of: rect)
            let size = CanvasGeometry.handleSize
            let knob = NSRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size)
            NSColor.white.setFill()
            NSBezierPath(ovalIn: knob).fill()
            NSColor.controlAccentColor.setStroke()
            let outline = NSBezierPath(ovalIn: knob.insetBy(dx: 0.5, dy: 0.5))
            outline.lineWidth = 1.5
            outline.stroke()
        }
    }

    private func drawTag(_ text: String, above rect: NSRect, color: NSColor) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let string = NSAttributedString(string: text, attributes: attributes)
        let size = string.size()
        var tag = NSRect(x: rect.minX, y: rect.minY - size.height - 5, width: size.width + 10, height: size.height + 3)
        if tag.minY < geometry.imageRectInCanvas.minY - 2 { tag.origin.y = rect.maxY + 2 }
        color.setFill()
        NSBezierPath(roundedRect: tag, xRadius: 4, yRadius: 4).fill()
        string.draw(at: NSPoint(x: tag.minX + 5, y: tag.minY + 1.5))
    }

    private func drawLabelInside(_ box: RedactionBox, rect: NSRect) {
        let fontSize = min(rect.height * 0.5, 13)
        guard fontSize >= 7 else { return }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .medium),
            .foregroundColor: NSColor(cgColor: document.style.color.labelColor) ?? .white,
        ]
        let string = NSAttributedString(string: box.label.lowercased(), attributes: attributes)
        let size = string.size()
        guard size.width + fontSize <= rect.width else { return }
        string.draw(at: NSPoint(x: rect.minX + fontSize * 0.5, y: rect.midY - size.height / 2))
    }

    // MARK: Mouse

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect, .cursorUpdate], owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let hovered = geometry.box(at: point, in: document.boxes)?.id
        if hovered != model.hoveredID {
            model.hoveredID = hovered
            needsDisplay = true
        }
        updateCursor(at: point)
    }

    override func mouseExited(with event: NSEvent) {
        if model.hoveredID != nil {
            model.hoveredID = nil
            needsDisplay = true
        }
    }

    override func cursorUpdate(with event: NSEvent) {
        updateCursor(at: convert(event.locationInWindow, from: nil))
    }

    private func updateCursor(at point: NSPoint) {
        if let selected = model.selectedBox, selected.source == .manual, geometry.handle(at: point, of: selected.rect) != nil {
            NSCursor.crosshair.set()
        } else if let box = geometry.box(at: point, in: document.boxes) {
            (box.source == .manual ? NSCursor.openHand : NSCursor.pointingHand).set()
        } else if geometry.imageRectInCanvas.contains(point) {
            NSCursor.crosshair.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        let imagePoint = geometry.toImage(point)

        if let selected = model.selectedBox, selected.source == .manual, let handle = geometry.handle(at: point, of: selected.rect) {
            gesture = .resize(selected.id, handle, current: selected.rect)
            return
        }
        if let box = geometry.box(at: point, in: document.boxes) {
            model.selectedID = box.id
            if box.source == .manual {
                NSCursor.closedHand.set()
                gesture = .move(box.id, start: imagePoint, original: box.rect, current: box.rect)
            } else {
                gesture = .pressBox(box.id, start: geometry.clampToImage(imagePoint))
            }
            needsDisplay = true
            return
        }
        model.selectedID = nil
        guard geometry.imageRectInCanvas.insetBy(dx: -8, dy: -8).contains(point) else {
            gesture = nil
            needsDisplay = true
            return
        }
        let start = geometry.clampToImage(imagePoint)
        gesture = .draw(start: start, current: CGRect(origin: start, size: .zero))
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let imagePoint = geometry.toImage(point)
        switch gesture {
        case .pressBox(_, let start)?:
            // Dragging from a found box draws a new box instead of toggling.
            guard hypot(imagePoint.x - start.x, imagePoint.y - start.y) * geometry.scale > 4 else { return }
            model.selectedID = nil
            gesture = .draw(start: start, current: BoxGeometry.rect(from: start, to: geometry.clampToImage(imagePoint)))
        case .draw(let start, _)?:
            gesture = .draw(start: start, current: BoxGeometry.rect(from: start, to: geometry.clampToImage(imagePoint)))
        case .move(let id, let start, let original, _)?:
            let delta = CGSize(width: imagePoint.x - start.x, height: imagePoint.y - start.y)
            gesture = .move(id, start: start, original: original, current: CanvasGeometry.move(original, by: delta, imageSize: document.pixelSize))
        case .resize(let id, let handle, let current)?:
            gesture = .resize(id, handle, current: CanvasGeometry.resize(current, handle: handle, to: imagePoint, imageSize: document.pixelSize))
        default:
            return
        }
        autoscroll(with: event)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            gesture = nil
            needsDisplay = true
            updateCursor(at: convert(event.locationInWindow, from: nil))
        }
        switch gesture {
        case .pressBox(let id, _)?:
            document.toggle(id)
        case .draw(_, let rect)?:
            if let id = document.addManualBox(rect) { model.selectedID = id }
        case .move(let id, _, let original, let current)?:
            if current != original { document.moveBox(id, to: current) }
        case .resize(let id, _, let current)?:
            document.moveBox(id, to: current)
        case nil:
            break
        }
    }

    // MARK: Keys

    override func keyDown(with event: NSEvent) {
        let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
        switch Int(event.keyCode) {
        case 51, 117: // Delete, Forward Delete
            model.deleteSelected()
        case 53: // Esc
            if model.selectedID != nil { model.selectedID = nil } else { model.actions.close() }
        case 123: model.nudgeSelected(dx: -step, dy: 0)
        case 124: model.nudgeSelected(dx: step, dy: 0)
        case 125: model.nudgeSelected(dx: 0, dy: step)
        case 126: model.nudgeSelected(dx: 0, dy: -step)
        case 49: // Space toggles the selected found box
            if let box = model.selectedBox { document.toggle(box.id) }
        default:
            super.keyDown(with: event)
        }
        needsDisplay = true
    }
}
