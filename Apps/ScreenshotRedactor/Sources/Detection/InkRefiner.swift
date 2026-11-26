import CoreGraphics
import Foundation

/// An 8-bit sRGB copy of an image for reading pixels, flattened onto white
/// (a window screenshot's transparent shadow reads as background).
nonisolated final class PixelBuffer {
    let width: Int
    let height: Int
    private let bytes: [UInt8]

    init?(image: CGImage) {
        let width = image.width
        let height = image.height
        self.width = width
        self.height = height
        guard width > 0, height > 0, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var storage = [UInt8](repeating: 255, count: width * height * 4)
        let drawn = storage.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: space,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ) else { return false }
            context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        bytes = storage
    }

    /// The colour at (x, y), with y counted from the top.
    @inline(__always)
    func rgb(_ x: Int, _ y: Int) -> (UInt8, UInt8, UInt8) {
        let offset = (y * width + x) * 4
        return (bytes[offset], bytes[offset + 1], bytes[offset + 2])
    }
}

/// Grows a text box until no ink touches its edges.
///
/// Vision's boxes for part of a line can stop short of the first or last
/// glyph. This checks the pixels just outside the box and extends it while
/// they still hold ink, across the small gaps between letters of one word
/// but never across a space, and never more than a line height per side.
nonisolated struct InkRefiner {
    let pixels: PixelBuffer

    /// How different from the background a pixel must be to count as ink
    /// (largest channel difference, 0–255). Faint antialiasing below this is
    /// invisible and is covered by the padding instead.
    static let inkThreshold = 28

    /// - Parameters:
    ///   - acrossGapsLeft/Right: whether that edge may jump the small gaps
    ///     between letters (for edges Vision placed, which can stop a glyph
    ///     short). Edges estimated inside a word already have a margin, so
    ///     they only finish a glyph they cut.
    func refine(_ rect: CGRect, lineHeight: CGFloat, acrossGapsLeft: Bool = true, acrossGapsRight: Bool = true) -> CGRect {
        let h = max(lineHeight, 1)
        var minX = max(0, Int(floor(rect.minX)))
        var maxX = min(pixels.width, Int(ceil(rect.maxX)))
        var minY = max(0, Int(floor(rect.minY)))
        var maxY = min(pixels.height, Int(ceil(rect.maxY)))
        guard minX < maxX, minY < maxY else { return rect }

        let background = backgroundColor(minX: minX - Int(h), maxX: maxX + Int(h), minY: minY, maxY: maxY)
        let tolerantGap = max(2, Int(h * 0.12))
        let horizontalCap = Int(h)
        let verticalCap = Int(h * 0.45)

        func isInk(_ x: Int, _ y: Int) -> Bool {
            let (r, g, b) = pixels.rgb(x, y)
            let difference = max(abs(Int(r) - Int(background.0)), abs(Int(g) - Int(background.1)), abs(Int(b) - Int(background.2)))
            return difference > Self.inkThreshold
        }
        func columnHasInk(_ x: Int) -> Bool {
            (minY..<maxY).contains { isInk(x, $0) }
        }
        func rowHasInk(_ y: Int) -> Bool {
            (minX..<maxX).contains { isInk($0, y) }
        }

        // Right edge.
        var horizontalGap = acrossGapsRight ? tolerantGap : 0
        var gap = 0
        var lastInk = maxX - 1
        var x = maxX
        while x < min(pixels.width, maxX + horizontalCap) {
            if columnHasInk(x) { lastInk = x; gap = 0 } else { gap += 1; if gap > horizontalGap { break } }
            x += 1
        }
        let newMaxX = lastInk + 1

        // Left edge.
        horizontalGap = acrossGapsLeft ? tolerantGap : 0
        gap = 0
        var firstInk = minX
        x = minX - 1
        while x >= max(0, minX - horizontalCap) {
            if columnHasInk(x) { firstInk = x; gap = 0 } else { gap += 1; if gap > horizontalGap { break } }
            x -= 1
        }
        minX = firstInk
        maxX = max(newMaxX, maxX)

        // Bottom and top: only ink that touches the box (descenders, accents).
        var y = maxY
        while y < min(pixels.height, maxY + verticalCap), rowHasInk(y) { y += 1 }
        let newMaxY = y
        y = minY - 1
        while y >= max(0, minY - verticalCap), rowHasInk(y) { y -= 1 }
        minY = y + 1
        maxY = newMaxY

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Grows `rect` by up to `padding` on each side, through background
    /// only: it stops at the next glyph, so a box never slices a
    /// neighbouring letter in half (and the faint antialiased edge of its
    /// own text is still inside).
    func pad(_ rect: CGRect, by padding: CGFloat, lineHeight: CGFloat) -> CGRect {
        var minX = max(0, Int(floor(rect.minX)))
        var maxX = min(pixels.width, Int(ceil(rect.maxX)))
        var minY = max(0, Int(floor(rect.minY)))
        var maxY = min(pixels.height, Int(ceil(rect.maxY)))
        guard minX < maxX, minY < maxY else { return rect }
        let step = Int(ceil(padding))
        let h = max(lineHeight, 1)
        let background = backgroundColor(minX: minX - Int(h), maxX: maxX + Int(h), minY: minY, maxY: maxY)
        func isInk(_ x: Int, _ y: Int) -> Bool {
            let (r, g, b) = pixels.rgb(x, y)
            return max(abs(Int(r) - Int(background.0)), abs(Int(g) - Int(background.1)), abs(Int(b) - Int(background.2))) > Self.inkThreshold
        }
        for _ in 0..<step {
            guard minX > 0, !(minY..<maxY).contains(where: { isInk(minX - 1, $0) }) else { break }
            minX -= 1
        }
        for _ in 0..<step {
            guard maxX < pixels.width, !(minY..<maxY).contains(where: { isInk(maxX, $0) }) else { break }
            maxX += 1
        }
        for _ in 0..<step {
            guard minY > 0, !(minX..<maxX).contains(where: { isInk($0, minY - 1) }) else { break }
            minY -= 1
        }
        for _ in 0..<step {
            guard maxY < pixels.height, !(minX..<maxX).contains(where: { isInk($0, maxY) }) else { break }
            maxY += 1
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// The most common colour around the box, quantized to 16 levels per channel.
    private func backgroundColor(minX: Int, maxX: Int, minY: Int, maxY: Int) -> (UInt8, UInt8, UInt8) {
        let x0 = max(0, minX), x1 = min(pixels.width, maxX)
        let y0 = max(0, minY), y1 = min(pixels.height, maxY)
        var counts: [Int: Int] = [:]
        var y = y0
        while y < y1 {
            var x = x0
            while x < x1 {
                let (r, g, b) = pixels.rgb(x, y)
                let key = (Int(r) >> 4) << 8 | (Int(g) >> 4) << 4 | (Int(b) >> 4)
                counts[key, default: 0] += 1
                x += 2
            }
            y += 2
        }
        guard let mode = counts.max(by: { $0.value < $1.value })?.key else { return (255, 255, 255) }
        let r = UInt8(((mode >> 8) & 0xF) << 4 | 8)
        let g = UInt8(((mode >> 4) & 0xF) << 4 | 8)
        let b = UInt8((mode & 0xF) << 4 | 8)
        return (r, g, b)
    }
}
