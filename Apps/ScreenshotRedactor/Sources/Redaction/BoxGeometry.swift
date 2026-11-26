import CoreGraphics
import Foundation

/// Every coordinate conversion in the app lives here, so each one is tested
/// once. App convention: image pixels, origin at the top-left, y down.
nonisolated enum BoxGeometry {
    /// A Vision rect (normalized 0…1, origin bottom-left) in app pixels.
    static func pixelRect(fromNormalized rect: CGRect, imageSize: CGSize) -> CGRect {
        CGRect(
            x: rect.minX * imageSize.width,
            y: (1 - rect.maxY) * imageSize.height,
            width: rect.width * imageSize.width,
            height: rect.height * imageSize.height
        )
    }

    /// The axis-aligned bounds of a Vision quadrilateral (normalized corners,
    /// origin bottom-left) in app pixels. Rotated text gets its full extent.
    static func pixelRect(fromNormalizedCorners corners: [CGPoint], imageSize: CGSize) -> CGRect {
        guard let first = corners.first else { return .null }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for corner in corners.dropFirst() {
            minX = min(minX, corner.x)
            maxX = max(maxX, corner.x)
            minY = min(minY, corner.y)
            maxY = max(maxY, corner.y)
        }
        return pixelRect(fromNormalized: CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY), imageSize: imageSize)
    }

    /// An app rect (top-left origin) as a Core Graphics rect for drawing
    /// into a bitmap context of `imageHeight` pixels (bottom-left origin).
    static func cgRect(fromTopLeft rect: CGRect, imageHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: imageHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// The box for a match inside a line: the match's horizontal extent with
    /// the whole line's height (Vision's substring boxes are "not guaranteed
    /// to be an exact fit", and the line's vertical extent is the reliable
    /// part). Without a match rect, the whole line.
    static func matchBox(matchRect: CGRect?, lineRect: CGRect) -> CGRect {
        guard let matchRect, !matchRect.isNull, !matchRect.isEmpty else { return lineRect }
        let minY = min(lineRect.minY, matchRect.minY)
        let maxY = max(lineRect.maxY, matchRect.maxY)
        return CGRect(x: matchRect.minX, y: minY, width: matchRect.width, height: maxY - minY)
    }

    /// The padding around text: at least 2 px, or a fifth of the line height.
    static func textPadding(lineHeight: CGFloat) -> CGFloat {
        max(2, lineHeight * 0.2)
    }

    /// Pads `rect`, rounds it outward to whole pixels and keeps it inside the image.
    static func finalize(_ rect: CGRect, padding: CGFloat, imageSize: CGSize) -> CGRect {
        let padded = rect.insetBy(dx: -padding, dy: -padding)
        return clampToImage(outwardIntegral(padded), imageSize: imageSize)
    }

    static func outwardIntegral(_ rect: CGRect) -> CGRect {
        let minX = floor(rect.minX), minY = floor(rect.minY)
        let maxX = ceil(rect.maxX), maxY = ceil(rect.maxY)
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    static func clampToImage(_ rect: CGRect, imageSize: CGSize) -> CGRect {
        let bounds = CGRect(origin: .zero, size: imageSize)
        let clipped = rect.intersection(bounds)
        return clipped.isNull ? .zero : clipped
    }

    /// A face box padded by a quarter of its size on every side, so hair,
    /// ears and chin are covered too.
    static func faceBox(_ rect: CGRect, imageSize: CGSize) -> CGRect {
        let padded = rect.insetBy(dx: -rect.width * 0.25, dy: -rect.height * 0.25)
        return clampToImage(outwardIntegral(padded), imageSize: imageSize)
    }

    /// True when the two rects overlap by at least `fraction` of the smaller one.
    static func overlapsSubstantially(_ a: CGRect, _ b: CGRect, fraction: CGFloat = 0.3) -> Bool {
        let intersection = a.intersection(b)
        guard !intersection.isNull, !intersection.isEmpty else { return false }
        let smaller = min(a.width * a.height, b.width * b.height)
        guard smaller > 0 else { return false }
        return intersection.width * intersection.height >= smaller * fraction
    }

    /// A rect from two drag points, in either order.
    static func rect(from a: CGPoint, to b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }
}
