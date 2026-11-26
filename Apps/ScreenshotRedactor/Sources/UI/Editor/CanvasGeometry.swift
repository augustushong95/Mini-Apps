import CoreGraphics

/// Maps between the editor canvas (points, top-left origin) and image
/// pixels (top-left origin), and answers what's under the pointer.
nonisolated struct CanvasGeometry: Equatable {
    /// The image in pixels.
    let imageSize: CGSize
    /// Points per image pixel.
    let scale: CGFloat
    /// Where the image's top-left corner sits in the canvas.
    let origin: CGPoint

    /// The image centred in `canvasSize` at `scale`.
    init(imageSize: CGSize, canvasSize: CGSize, scale: CGFloat) {
        self.imageSize = imageSize
        self.scale = scale
        let shown = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        origin = CGPoint(x: max(0, (canvasSize.width - shown.width) / 2).rounded(), y: max(0, (canvasSize.height - shown.height) / 2).rounded())
    }

    /// The scale that fits the image in `available`, never larger than
    /// `maximum` (so a small screenshot isn't blown up).
    static func fitScale(imageSize: CGSize, available: CGSize, maximum: CGFloat) -> CGFloat {
        guard imageSize.width > 0, imageSize.height > 0, available.width > 0, available.height > 0 else { return maximum }
        return min(available.width / imageSize.width, available.height / imageSize.height, maximum)
    }

    var imageRectInCanvas: CGRect {
        CGRect(origin: origin, size: CGSize(width: imageSize.width * scale, height: imageSize.height * scale))
    }

    func toCanvas(_ rect: CGRect) -> CGRect {
        CGRect(x: origin.x + rect.minX * scale, y: origin.y + rect.minY * scale, width: rect.width * scale, height: rect.height * scale)
    }

    func toImage(_ point: CGPoint) -> CGPoint {
        CGPoint(x: (point.x - origin.x) / scale, y: (point.y - origin.y) / scale)
    }

    func clampToImage(_ point: CGPoint) -> CGPoint {
        CGPoint(x: min(max(point.x, 0), imageSize.width), y: min(max(point.y, 0), imageSize.height))
    }

    /// The box under `point` (canvas points). Boxes drawn by the user come
    /// first, then the smallest box, so a box inside a larger one stays reachable.
    func box(at point: CGPoint, in boxes: [RedactionBox]) -> RedactionBox? {
        let imagePoint = toImage(point)
        let slop = 3 / scale
        return boxes
            .filter { $0.rect.insetBy(dx: -slop, dy: -slop).contains(imagePoint) }
            .min { a, b in
                if (a.source == .manual) != (b.source == .manual) { return a.source == .manual }
                return a.rect.width * a.rect.height < b.rect.width * b.rect.height
            }
    }

    enum Handle: CaseIterable {
        case topLeft, topRight, bottomLeft, bottomRight
    }

    static let handleSize: CGFloat = 9

    /// The corner handle of `rect` (image pixels) under `point` (canvas points).
    func handle(at point: CGPoint, of rect: CGRect) -> Handle? {
        let shown = toCanvas(rect)
        let reach = Self.handleSize
        for handle in Handle.allCases {
            let corner = Self.corner(handle, of: shown)
            if abs(point.x - corner.x) <= reach && abs(point.y - corner.y) <= reach { return handle }
        }
        return nil
    }

    static func corner(_ handle: Handle, of rect: CGRect) -> CGPoint {
        switch handle {
        case .topLeft: CGPoint(x: rect.minX, y: rect.minY)
        case .topRight: CGPoint(x: rect.maxX, y: rect.minY)
        case .bottomLeft: CGPoint(x: rect.minX, y: rect.maxY)
        case .bottomRight: CGPoint(x: rect.maxX, y: rect.maxY)
        }
    }

    /// `rect` with `handle` dragged to `point` (image pixels): the opposite
    /// corner stays put, the box keeps a minimum size and stays on the image.
    static func resize(_ rect: CGRect, handle: Handle, to point: CGPoint, imageSize: CGSize, minimum: CGFloat = 3) -> CGRect {
        let x = min(max(point.x, 0), imageSize.width)
        let y = min(max(point.y, 0), imageSize.height)
        var minX = rect.minX, maxX = rect.maxX, minY = rect.minY, maxY = rect.maxY
        switch handle {
        case .topLeft: minX = min(x, maxX - minimum); minY = min(y, maxY - minimum)
        case .topRight: maxX = max(x, minX + minimum); minY = min(y, maxY - minimum)
        case .bottomLeft: minX = min(x, maxX - minimum); maxY = max(y, minY + minimum)
        case .bottomRight: maxX = max(x, minX + minimum); maxY = max(y, minY + minimum)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// `rect` moved by `delta` (image pixels), kept fully on the image.
    static func move(_ rect: CGRect, by delta: CGSize, imageSize: CGSize) -> CGRect {
        let x = min(max(rect.minX + delta.width, 0), max(0, imageSize.width - rect.width))
        let y = min(max(rect.minY + delta.height, 0), max(0, imageSize.height - rect.height))
        return CGRect(x: x, y: y, width: rect.width, height: rect.height)
    }
}
