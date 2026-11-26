import CoreGraphics
import Foundation

/// One observation from Vision, already in full-image pixels.
nonisolated struct OCRLine {
    var candidates: [String]
    var rect: CGRect
    var rangeRect: (_ candidate: Int, _ range: Range<String.Index>) -> CGRect?

    var text: String { candidates.first ?? "" }

    var scanned: ScannedLine {
        ScannedLine(candidates: candidates, rect: rect, rangeRect: rangeRect)
    }
}

/// How a large image is cut into tiles for recognition.
///
/// Vision reads nothing once text is smaller than roughly 1/120 of the
/// image's longest side (measured on this Mac: 13 pt text at 1× stops being
/// read beyond ~1,920 px; 12 pt at 2× beyond ~3,000 px). Downscaling keeps
/// that ratio, so it can't help; tiles do. Each tile is at most `tileSize`
/// on a side, and neighbours overlap so every line is whole in some tile
/// vertically. Lines cut at a side seam are stitched back by `LineStitcher`.
nonisolated struct TileLayout: Equatable {
    let imageSize: CGSize
    /// Tile rects in image pixels (top-left origin), row by row.
    let tiles: [CGRect]
    let columns: Int
    let rows: Int

    static let overlap: CGFloat = 200

    /// The largest tile for text drawn at `scale` (1 for 72 dpi, 2 for 144).
    /// Measured on this Mac: 1× text is lost entirely in tiles of 1,792 px
    /// and up; 2× text is read but broken into fragments near 2,560 px.
    static func tileSize(scale: CGFloat) -> CGFloat {
        scale >= 1.5 ? 2048 : 1280
    }

    /// Images up to this much larger than a tile are still read in one piece.
    static let tolerance: CGFloat = 1.15

    init(imageSize: CGSize, tileSize: CGFloat, overlap: CGFloat = TileLayout.overlap) {
        self.imageSize = imageSize
        /// Evenly spaced starts along one side, each tile `tileSize` long and
        /// overlapping its neighbours by at least `overlap`.
        func starts(_ length: CGFloat) -> (starts: [CGFloat], size: CGFloat) {
            guard length > tileSize * Self.tolerance else { return ([0], length) }
            let count = Int(ceil((length - overlap) / (tileSize - overlap)))
            let step = (length - tileSize) / CGFloat(count - 1)
            return ((0..<count).map { (CGFloat($0) * step).rounded(.down) }, tileSize)
        }
        let (xs, width) = starts(imageSize.width)
        let (ys, height) = starts(imageSize.height)
        columns = xs.count
        rows = ys.count
        tiles = ys.flatMap { y in xs.map { x in CGRect(x: x, y: y, width: width, height: height) } }
    }

    /// A layout given tile by tile (tests).
    init(imageSize: CGSize, tiles: [CGRect], columns: Int, rows: Int) {
        self.imageSize = imageSize
        self.tiles = tiles
        self.columns = columns
        self.rows = rows
    }

    /// One tile covering the whole image: no tiling needed.
    var isSingleTile: Bool { tiles.count == 1 }
}

/// Joins the per-tile readings into whole lines.
///
/// Tiles overlap, so most text is read more than once, and a reading near a
/// tile's edge can be cut or broken into fragments. Per row of text:
/// - The longest readings are kept; a reading lying mostly inside a kept
///   one is a duplicate or a fragment and is dropped.
/// - Readings left over that overlap side by side are pieces of one line cut
///   at different tile edges: they're cut at the same x, character by
///   character, and joined, so a key that crosses a seam is matched whole.
/// - Readings from the whole-image pass (large text) win over tile readings.
nonisolated enum LineStitcher {
    static func combine(full: [OCRLine], tiles tileLines: [[OCRLine]]) -> [ScannedLine] {
        var lines: [OCRLine] = []
        for row in rows(tileLines.flatMap { $0 }) {
            // Longest first; drop readings mostly inside one already kept.
            var kept: [OCRLine] = []
            for reading in row.sorted(by: { $0.text.count > $1.text.count }) {
                if kept.contains(where: { containedFraction(reading.rect, in: $0.rect) >= 0.7 }) { continue }
                kept.append(reading)
            }
            // Join pieces that overlap side by side, left to right.
            var current: OCRLine?
            for reading in kept.sorted(by: { $0.rect.minX < $1.rect.minX }) {
                guard let previous = current else { current = reading; continue }
                if horizontalOverlap(previous.rect, reading.rect) > 0, let joined = join(previous, reading) {
                    current = joined
                } else {
                    lines.append(previous)
                    current = reading
                }
            }
            if let current { lines.append(current) }
        }

        var result = full
        for line in lines where !full.contains(where: { BoxGeometry.overlapsSubstantially($0.rect, line.rect, fraction: 0.5) }) {
            result.append(line)
        }
        return result.map(\.scanned)
    }

    /// Readings grouped into rows of text: vertical centres within half a
    /// line height of the row's first reading.
    static func rows(_ readings: [OCRLine]) -> [[OCRLine]] {
        var rows: [[OCRLine]] = []
        var anchors: [CGRect] = []
        for reading in readings.sorted(by: { $0.rect.midY < $1.rect.midY }) {
            if let anchor = anchors.last, sameRow(anchor, reading.rect) {
                rows[rows.count - 1].append(reading)
            } else {
                rows.append([reading])
                anchors.append(reading.rect)
            }
        }
        return rows
    }

    static func sameRow(_ a: CGRect, _ b: CGRect) -> Bool {
        let overlap = min(a.maxY, b.maxY) - max(a.minY, b.minY)
        return overlap >= min(a.height, b.height) * 0.6
    }

    static func horizontalOverlap(_ a: CGRect, _ b: CGRect) -> CGFloat {
        min(a.maxX, b.maxX) - max(a.minX, b.minX)
    }

    /// How much of `inner`'s area lies inside `outer` (0…1).
    static func containedFraction(_ inner: CGRect, in outer: CGRect) -> CGFloat {
        let area = inner.width * inner.height
        guard area > 0 else { return 0 }
        let intersection = inner.intersection(outer)
        guard !intersection.isNull else { return 0 }
        return intersection.width * intersection.height / area
    }

    /// Cuts `left` and `right` at the middle of where they overlap and
    /// joins the parts. Nil if character positions can't be found.
    static func join(_ left: OCRLine, _ right: OCRLine) -> OCRLine? {
        let overlapStart = max(left.rect.minX, right.rect.minX)
        let overlapEnd = min(left.rect.maxX, right.rect.maxX)
        guard overlapEnd > overlapStart else { return nil }
        let cut = (overlapStart + overlapEnd) / 2

        guard let leftEnd = firstCharacter(in: left, centeredAtOrAfter: cut),
              let rightStart = firstCharacter(in: right, centeredAtOrAfter: cut)
        else { return nil }

        let leftText = left.text
        let rightText = right.text
        let leftPart = leftText.startIndex..<leftText.index(leftText.startIndex, offsetBy: leftEnd)
        var rightPart = rightText.index(rightText.startIndex, offsetBy: rightStart)..<rightText.endIndex
        // One space where the cut fell between words, not two.
        if leftText[leftPart].last?.isWhitespace == true, rightText[rightPart].first?.isWhitespace == true {
            rightPart = rightText.index(after: rightPart.lowerBound)..<rightPart.upperBound
        }
        // One reading lies entirely on one side of the cut: the other has it all.
        if leftPart.isEmpty { return right }
        if rightPart.isEmpty { return left }

        let leftString = String(leftText[leftPart])
        let rightString = String(rightText[rightPart])
        let joined = leftString + rightString
        let split = leftString.count
        let rect = left.rect.union(right.rect)
        let leftLine = left, rightLine = right
        let rightOffset = rightText.distance(from: rightText.startIndex, to: rightPart.lowerBound)

        return OCRLine(candidates: [joined], rect: rect) { _, range in
            let start = joined.distance(from: joined.startIndex, to: range.lowerBound)
            let end = joined.distance(from: joined.startIndex, to: range.upperBound)
            var rects: [CGRect] = []
            if start < split {
                let a = leftText.index(leftText.startIndex, offsetBy: start)
                let b = leftText.index(leftText.startIndex, offsetBy: min(end, split))
                rects.append(leftLine.rangeRect(0, a..<b) ?? leftLine.rect)
            }
            if end > split {
                let a = rightText.index(rightText.startIndex, offsetBy: rightOffset + max(start, split) - split)
                let b = rightText.index(rightText.startIndex, offsetBy: rightOffset + end - split)
                rects.append(rightLine.rangeRect(0, a..<b) ?? rightLine.rect)
            }
            guard let first = rects.first else { return nil }
            return rects.dropFirst().reduce(first) { $0.union($1) }
        }
    }

    /// The offset of the first character whose centre is at or right of `x`
    /// (`count` if none). Characters run left to right, so a binary search
    /// needs only a few box lookups. Spaces with no box borrow a neighbour's.
    static func firstCharacter(in line: OCRLine, centeredAtOrAfter x: CGFloat) -> Int? {
        let text = line.text
        let count = text.count
        guard count > 0 else { return nil }
        func center(_ offset: Int) -> CGFloat? {
            for probe in [offset, offset - 1, offset + 1, offset - 2, offset + 2] where probe >= 0 && probe < count {
                let start = text.index(text.startIndex, offsetBy: probe)
                if let rect = line.rangeRect(0, start..<text.index(after: start)), !rect.isNull, rect.width > 0 {
                    // A neighbour's box stands in; shift by one character's width.
                    return rect.midX + CGFloat(offset - probe) * rect.width
                }
            }
            return nil
        }
        var low = 0, high = count
        while low < high {
            let mid = (low + high) / 2
            guard let value = center(mid) else { return nil }
            if value >= x { high = mid } else { low = mid + 1 }
        }
        return low
    }
}
