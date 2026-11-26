import CoreGraphics
import Foundation
import Testing
@testable import ScreenshotRedactor

@Suite nonisolated struct TilingTests {
    @Test func smallImagesAreOneTile() {
        let layout = TileLayout(imageSize: CGSize(width: 2880, height: 1800), tileSize: 2560)
        #expect(layout.isSingleTile)
        #expect(layout.tiles == [CGRect(x: 0, y: 0, width: 2880, height: 1800)])
    }

    @Test func a5KScreenshotIsSixOverlappingTiles() {
        let layout = TileLayout(imageSize: CGSize(width: 5120, height: 2880), tileSize: 2048)
        #expect(layout.columns == 3 && layout.rows == 2)
        #expect(Set(layout.tiles.map(\.minX)) == [0, 1536, 3072])
        #expect(Set(layout.tiles.map(\.minY)) == [0, 832])
        #expect(layout.tiles.allSatisfy { $0.width == 2048 && $0.height == 2048 })
    }

    @Test func tilesCoverTheImageAndOverlapEnough() {
        for size in [CGSize(width: 3840, height: 2160), CGSize(width: 6016, height: 3384), CGSize(width: 1800, height: 9000), CGSize(width: 2401, height: 1500)] {
            let layout = TileLayout(imageSize: size, tileSize: 1280)
            let union = layout.tiles.reduce(CGRect.null) { $0.union($1) }
            #expect(union == CGRect(origin: .zero, size: size), "\(size)")
            for tile in layout.tiles {
                #expect(tile.width <= 1280 * TileLayout.tolerance && tile.height <= 1280 * TileLayout.tolerance)
            }
            let xs = Array(Set(layout.tiles.map(\.minX))).sorted()
            for (a, b) in zip(xs, xs.dropFirst()) {
                #expect(a + 1280 - b >= TileLayout.overlap, "\(size): columns at \(a) and \(b)")
            }
        }
    }

    @Test func retinaTilesAreLarger() {
        #expect(TileLayout.tileSize(scale: 2) == 2048)
        #expect(TileLayout.tileSize(scale: 1) == 1280)
    }

    /// `CGImage.cropping(to:)` counts from the top-left, like the app.
    @Test func croppingUsesTopLeftCoordinates() throws {
        let context = CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        // Core Graphics draws bottom-left up: y 3 is the top row.
        context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 3, width: 1, height: 1))
        let image = try #require(context.makeImage())
        let topLeft = try #require(image.cropping(to: CGRect(x: 0, y: 0, width: 1, height: 1)))
        let pixels = try #require(PixelBuffer(image: topLeft))
        #expect(pixels.rgb(0, 0) == (255, 0, 0))
    }

    // MARK: Stitching

    /// A line on a 10 px grid, as Vision would read the part of it inside `tile`.
    private func reading(_ text: String, x: CGFloat, y: CGFloat = 100, in tile: ClosedRange<CGFloat>) -> OCRLine? {
        let characters = Array(text)
        let inside = characters.indices.filter { tile.contains(x + CGFloat($0) * 10 + 5) }
        guard let first = inside.first, let last = inside.last else { return nil }
        let part = String(characters[first...last])
        let partX = x + CGFloat(first) * 10
        let rect = CGRect(x: partX, y: y, width: CGFloat(part.count) * 10, height: 20)
        return OCRLine(candidates: [part], rect: rect) { _, range in
            let start = part.distance(from: part.startIndex, to: range.lowerBound)
            let length = part.distance(from: range.lowerBound, to: range.upperBound)
            return CGRect(x: partX + CGFloat(start) * 10, y: y, width: CGFloat(length) * 10, height: 20)
        }
    }

    @Test func aLineCutBySideSeamsIsJoinedExactly() throws {
        let text = "export AWS_SECRET_ACCESS_KEY=kq3Rz7VwT2mXb9LpC5nYd8HsF1jGt4QeU6aKw0Zr # rotate"
        let x: CGFloat = 50
        let tiles: [ClosedRange<CGFloat>] = [0...300, 200...500, 400...700, 600...1000]
        let readings = tiles.map { tile in [reading(text, x: x, in: tile)].compactMap { $0 } }
        let lines = LineStitcher.combine(full: [], tiles: readings)
        #expect(lines.count == 1)
        let line = try #require(lines.first)
        #expect(line.text == text)
        #expect(abs(line.rect.minX - x) < 0.5 && abs(line.rect.maxX - (x + CGFloat(text.count) * 10)) < 0.5)
        // Ranges map back to the right place across the seams.
        let key = try #require(line.text.range(of: "kq3Rz7VwT2mXb9LpC5nYd8HsF1jGt4QeU6aKw0Zr"))
        let rect = try #require(line.rangeRect(0, key))
        let offset = CGFloat(text.distance(from: text.startIndex, to: key.lowerBound))
        #expect(abs(rect.minX - (x + offset * 10)) < 0.5)
        #expect(abs(rect.width - 400) < 0.5)
    }

    @Test func separateWordsInTheOverlapArentDoubled() {
        let left = reading("alpha beta", x: 100, in: 0...300)!
        let right = reading("alpha beta", x: 100, in: 150...600)!
        #expect(LineStitcher.combine(full: [], tiles: [[left], [right]]).map(\.text) == ["alpha beta"])
    }

    @Test func linesOnOtherRowsArentJoined() {
        let left = reading("first line here", x: 100, y: 100, in: 0...300)!
        let right = reading("second line", x: 250, y: 200, in: 200...600)!
        let lines = LineStitcher.combine(full: [], tiles: [[left], [right]])
        #expect(Set(lines.map(\.text)) == ["first line here", "second line"])
    }

    @Test func aReadingCutByATileEdgeLosesToTheCompleteOne() {
        let cut = OCRLine(candidates: ["token=abc"], rect: CGRect(x: 0, y: 990, width: 90, height: 20)) { _, _ in nil }
        let whole = OCRLine(candidates: ["token=abcdef123456"], rect: CGRect(x: 0, y: 988, width: 180, height: 24)) { _, _ in nil }
        #expect(LineStitcher.combine(full: [], tiles: [[cut], [whole]]).map(\.text) == ["token=abcdef123456"])
    }

    /// Near a tile's edge Vision can break a line into pieces and drop a
    /// character; the same line read whole in another tile replaces them.
    @Test func fragmentsLoseToAWholeReadingFromAnotherTile() {
        let fragmentA = OCRLine(candidates: ["user=jane@example"], rect: CGRect(x: 476, y: 442, width: 256, height: 18)) { _, _ in nil }
        let fragmentB = OCRLine(candidates: ["com ip=10.1.2.3"], rect: CGRect(x: 747, y: 438, width: 223, height: 22)) { _, _ in nil }
        let whole = OCRLine(candidates: ["INFO user=jane@example.com ip=10.1.2.3"], rect: CGRect(x: 401, y: 437, width: 569, height: 26)) { _, _ in nil }
        let lines = LineStitcher.combine(full: [], tiles: [[fragmentA, fragmentB], [whole]])
        #expect(lines.map(\.text) == ["INFO user=jane@example.com ip=10.1.2.3"])
    }

    @Test func theWholeImagePassWinsOverTiles() {
        let big = OCRLine(candidates: ["HEADLINE"], rect: CGRect(x: 0, y: 0, width: 800, height: 120)) { _, _ in nil }
        let tilePiece = OCRLine(candidates: ["HEADL"], rect: CGRect(x: 0, y: 0, width: 500, height: 120)) { _, _ in nil }
        #expect(LineStitcher.combine(full: [big], tiles: [[tilePiece]]).map(\.text) == ["HEADLINE"])
    }
}
