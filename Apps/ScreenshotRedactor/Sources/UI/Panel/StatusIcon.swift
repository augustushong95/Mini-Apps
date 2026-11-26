import AppKit

/// The menu bar icon, drawn in code as a template image so it matches the
/// menu bar in light, dark and tinted modes: a screenshot frame with a
/// solid redaction bar across it.
enum StatusIcon {
    enum State: Equatable {
        case watching
        /// Watching is off: just the frame.
        case paused
        /// A scan is running; `phase` alternates the bar's length.
        case scanning(phase: Int)
        /// Folder access is lost or a permission is missing.
        case attention
    }

    static func image(_ state: State) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            let frame = NSRect(x: 1.75, y: 3.25, width: 14.5, height: 11.5)
            let outline = NSBezierPath(roundedRect: frame, xRadius: 2.6, yRadius: 2.6)
            outline.lineWidth = 1.5
            NSColor.black.setStroke()
            NSColor.black.setFill()

            switch state {
            case .paused:
                outline.setLineDash([2.2, 1.6], count: 2, phase: 0)
                outline.stroke()
            case .watching, .attention:
                outline.stroke()
                NSBezierPath(roundedRect: NSRect(x: 4.5, y: 7.25, width: 9, height: 3.5), xRadius: 1, yRadius: 1).fill()
            case .scanning(let phase):
                outline.stroke()
                let width: CGFloat = phase % 2 == 0 ? 9 : 5
                NSBezierPath(roundedRect: NSRect(x: 4.5, y: 7.25, width: width, height: 3.5), xRadius: 1, yRadius: 1).fill()
            }

            if state == .attention {
                // A dot at the top-right corner, cut out of the frame.
                let dot = NSRect(x: 12.5, y: 0.5, width: 5.5, height: 5.5)
                NSGraphicsContext.current?.compositingOperation = .clear
                NSBezierPath(ovalIn: dot.insetBy(dx: -1.2, dy: -1.2)).fill()
                NSGraphicsContext.current?.compositingOperation = .sourceOver
                NSBezierPath(ovalIn: dot).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
