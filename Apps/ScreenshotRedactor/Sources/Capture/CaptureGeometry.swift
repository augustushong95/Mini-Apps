import CoreGraphics

/// Conversions between the three screen coordinate systems capture uses:
/// - Cocoa (NSScreen, NSEvent): points, origin at the bottom-left of the
///   main display, y up.
/// - Core Graphics global (SCDisplay, window lists, screenshot attributes):
///   points, origin at the top-left of the main display, y down.
/// - A display's captured image: pixels, origin at its top-left.
nonisolated enum CaptureGeometry {
    /// A Cocoa rect in global CG coordinates. `mainHeight` is the main
    /// display's height in points (the flip axis for both systems).
    static func cgGlobal(fromCocoa rect: CGRect, mainHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: mainHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    static func cocoa(fromCGGlobal rect: CGRect, mainHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: mainHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// The pixels of a display's captured image under `selection`.
    /// - Parameters:
    ///   - selection: Cocoa global points.
    ///   - screenFrame: that display's frame, Cocoa global points.
    ///   - scale: pixels per point of the captured image.
    static func pixelRect(selection: CGRect, screenFrame: CGRect, scale: CGFloat) -> CGRect {
        let clipped = selection.intersection(screenFrame)
        guard !clipped.isNull else { return .zero }
        let x = (clipped.minX - screenFrame.minX) * scale
        let y = (screenFrame.maxY - clipped.maxY) * scale
        let rect = CGRect(x: x, y: y, width: clipped.width * scale, height: clipped.height * scale)
        // Whole pixels, never outside the image.
        let integral = CGRect(x: rect.minX.rounded(), y: rect.minY.rounded(), width: rect.width.rounded(), height: rect.height.rounded())
        return integral.intersection(CGRect(x: 0, y: 0, width: (screenFrame.width * scale).rounded(), height: (screenFrame.height * scale).rounded()))
    }

    /// A selection from two Cocoa points, kept on one display.
    static func selection(from start: CGPoint, to end: CGPoint, on screenFrame: CGRect) -> CGRect {
        let clamp = { (point: CGPoint) in
            CGPoint(x: min(max(point.x, screenFrame.minX), screenFrame.maxX), y: min(max(point.y, screenFrame.minY), screenFrame.maxY))
        }
        let a = clamp(start), b = clamp(end)
        return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }
}
