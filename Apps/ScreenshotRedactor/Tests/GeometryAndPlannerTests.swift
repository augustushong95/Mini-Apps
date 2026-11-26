import CoreGraphics
import Foundation
import Testing
@testable import ScreenshotRedactor

@Suite nonisolated struct GeometryTests {
    let size = CGSize(width: 1000, height: 500)

    @Test func visionRectsBecomeTopLeftPixels() {
        let rect = BoxGeometry.pixelRect(fromNormalized: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4), imageSize: size)
        #expect(abs(rect.minX - 100) < 0.001 && abs(rect.minY - 200) < 0.001)
        #expect(abs(rect.width - 300) < 0.001 && abs(rect.height - 200) < 0.001)
    }

    @Test func rotatedQuadsUseTheirFullExtent() {
        let corners = [CGPoint(x: 0.1, y: 0.5), CGPoint(x: 0.5, y: 0.6), CGPoint(x: 0.12, y: 0.4), CGPoint(x: 0.52, y: 0.5)]
        let rect = BoxGeometry.pixelRect(fromNormalizedCorners: corners, imageSize: size)
        #expect(abs(rect.minX - 100) < 0.001 && abs(rect.maxX - 520) < 0.001)
        #expect(abs(rect.minY - 200) < 0.001 && abs(rect.maxY - 300) < 0.001)
    }

    @Test func coreGraphicsRectsFlipOnce() {
        let topLeft = CGRect(x: 10, y: 20, width: 30, height: 40)
        let cg = BoxGeometry.cgRect(fromTopLeft: topLeft, imageHeight: 500)
        #expect(cg == CGRect(x: 10, y: 440, width: 30, height: 40))
        #expect(BoxGeometry.cgRect(fromTopLeft: cg, imageHeight: 500) == topLeft)
    }

    @Test func matchBoxesTakeTheLinesHeight() {
        let line = CGRect(x: 0, y: 100, width: 800, height: 30)
        let match = CGRect(x: 200, y: 104, width: 120, height: 20)
        #expect(BoxGeometry.matchBox(matchRect: match, lineRect: line) == CGRect(x: 200, y: 100, width: 120, height: 30))
        #expect(BoxGeometry.matchBox(matchRect: nil, lineRect: line) == line)
        #expect(BoxGeometry.matchBox(matchRect: .null, lineRect: line) == line)
    }

    @Test func finalizePadsRoundsOutwardAndClamps() {
        let rect = BoxGeometry.finalize(CGRect(x: 10.4, y: 20.6, width: 50.2, height: 9.1), padding: 2, imageSize: size)
        #expect(rect == CGRect(x: 8, y: 18, width: 55, height: 14))
        let edge = BoxGeometry.finalize(CGRect(x: 995, y: -3, width: 20, height: 10), padding: 4, imageSize: size)
        #expect(edge == CGRect(x: 991, y: 0, width: 9, height: 11))
        #expect(BoxGeometry.textPadding(lineHeight: 5) == 2)
        #expect(BoxGeometry.textPadding(lineHeight: 30) == 6)
    }

    @Test func facesArePaddedByAQuarter() {
        let face = BoxGeometry.faceBox(CGRect(x: 100, y: 100, width: 40, height: 40), imageSize: size)
        #expect(face == CGRect(x: 90, y: 90, width: 60, height: 60))
    }

    @Test func dragRectsWorkInAnyDirection() {
        #expect(BoxGeometry.rect(from: CGPoint(x: 50, y: 60), to: CGPoint(x: 10, y: 20)) == CGRect(x: 10, y: 20, width: 40, height: 40))
    }

    @Test func substantialOverlap() {
        let a = CGRect(x: 0, y: 0, width: 100, height: 20)
        #expect(BoxGeometry.overlapsSubstantially(a, CGRect(x: 10, y: 0, width: 100, height: 20)))
        #expect(!BoxGeometry.overlapsSubstantially(a, CGRect(x: 90, y: 0, width: 100, height: 20)))
        #expect(!BoxGeometry.overlapsSubstantially(a, CGRect(x: 200, y: 0, width: 10, height: 10)))
    }
}

/// The planner with hand-made lines laid out on a monospace grid:
/// characters are 10 px wide, lines 20 px tall and 30 px apart.
@Suite nonisolated struct PlannerTests {
    let size = CGSize(width: 2000, height: 1000)
    let charWidth: CGFloat = 10
    let lineHeight: CGFloat = 20

    private func line(_ text: String, row: Int, column: Int = 0) -> ScannedLine {
        let x = 20 + CGFloat(column) * charWidth
        let rect = CGRect(x: x, y: 20 + CGFloat(row) * 30, width: CGFloat(text.count) * charWidth, height: lineHeight)
        return ScannedLine(candidates: [text], rect: rect) { _, range in
            let start = text.distance(from: text.startIndex, to: range.lowerBound)
            let length = text.distance(from: range.lowerBound, to: range.upperBound)
            return CGRect(x: x + CGFloat(start) * charWidth, y: rect.minY, width: CGFloat(length) * charWidth, height: lineHeight)
        }
    }

    private func plan(_ lines: [ScannedLine], faces: [CGRect] = []) -> [RedactionBox] {
        RedactionPlanner(rules: TextRules(settings: DetectionSettings()), imageSize: size, refiner: nil, clock: CustomRuleClock())
            .boxes(for: lines, faces: faces)
    }

    @Test func aPrivateKeyBlockIsCoveredFromBeginToEnd() throws {
        let lines = [
            line("-----BEGIN RSA PRIVATE KEY-----", row: 0),
            line("MIIEowIBAAKCAQEAuQ8f2XkAbc", row: 1),
            line("q8Zr2LwT9vKx4NpB7sYd3HmF6", row: 2),
            line("-----END RSA PRIVATE KEY-----", row: 3),
            line("Saved to deploy notes", row: 5),
        ]
        let boxes = plan(lines).filter { $0.detector == .privateKeys }
        #expect(boxes.count == 1)
        let block = try #require(boxes.first).rect
        #expect(block.minY <= lines[0].rect.minY && block.maxY >= lines[3].rect.maxY)
        #expect(block.maxY < lines[4].rect.minY)
    }

    @Test func aCroppedPrivateKeyIsCoveredToTheEndOfItsColumn() {
        let lines = [
            line("-----BEGIN OPENSSH PRIVATE KEY-----", row: 0),
            line("b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQ", row: 1),
            line("AAAAAAAAABAAABlwAAAAdzc2gtcnNhAAAAAwEAAQAAAY", row: 2),
        ]
        let block = plan(lines).filter { $0.detector == .privateKeys }
        #expect(block.count == 1)
        #expect(block.first.map { $0.rect.maxY >= lines[2].rect.maxY } == true)
    }

    @Test func aTokenWrappedOntoTheNextLineIsCoveredOnBoth() {
        let first = "export TOKEN=ghp_" + "R4tY8uI2oP6aS9dF1gH5"
        let lines = [
            line(first, row: 0),
            line("jK3lZ7xC0vB2Qw9", row: 1),
            line("$ echo done", row: 2),
        ]
        let boxes = plan(lines)
        #expect(boxes.contains { $0.rect.intersects(lines[0].rect) && $0.category == .secret })
        #expect(boxes.contains { $0.rect.intersects(lines[1].rect) && $0.category == .secret })
        #expect(!boxes.contains { $0.rect.intersects(lines[2].rect) })
    }

    @Test func aShortLineEndingInATokenDoesntSpillOntoTheNextLine() {
        let lines = [
            line("A much longer line that sets the width of this block of text here", row: 0),
            line("token=ghp_" + "R4tY8uI2oP6aS9dF1gH5", row: 1),
            line("Zq8Lw2Tx9vKm4NpB", row: 2),
        ]
        let boxes = plan(lines)
        #expect(!boxes.contains { $0.rect.intersects(lines[2].rect) })
    }

    @Test func aLabelCellAndItsValueCellArePaired() {
        let label = line("Password", row: 0)
        let value = line("hunter2", row: 0, column: 30)
        let other = line("Region", row: 1)
        let otherValue = line("us-east-1", row: 1, column: 30)
        let boxes = plan([label, value, other, otherValue])
        #expect(boxes.count == 1)
        #expect(boxes.first.map { $0.rect.intersects(value.rect) && !$0.rect.intersects(label.rect) } == true)
    }

    @Test func everyCandidateIsCheckedAndDuplicatesMerge() {
        let text = "mail jane@example.com"
        let rect = CGRect(x: 20, y: 20, width: CGFloat(text.count) * charWidth, height: lineHeight)
        let misread = "mail jane@examp1e.com"
        let scanned = ScannedLine(candidates: ["mail jane at example", text, misread], rect: rect) { _, range in
            let start = text.distance(from: text.startIndex, to: range.lowerBound)
            return CGRect(x: 20 + CGFloat(start) * charWidth, y: 20, width: 160, height: lineHeight)
        }
        let boxes = plan([scanned])
        #expect(boxes.count == 1)
        #expect(boxes.first?.category == .personal)
    }

    /// A worse reading ("=" read as "-") would widen the key over the
    /// variable name; the best reading's box stands.
    @Test func alternativeReadingsOnlyRescueMisses() throws {
        let best = "export KEY=AKIA" + "IOSFODNN7EXAMPLE"
        let worse = "export KEY-AKIA" + "IOSFODNN7EXAMPLE"
        let rect = CGRect(x: 20, y: 20, width: CGFloat(best.count) * charWidth, height: lineHeight)
        let scanned = ScannedLine(candidates: [best, worse], rect: rect) { candidate, range in
            let text = candidate == 0 ? best : worse
            let start = text.distance(from: text.startIndex, to: range.lowerBound)
            let length = text.distance(from: range.lowerBound, to: range.upperBound)
            return CGRect(x: 20 + CGFloat(start) * charWidth, y: 20, width: CGFloat(length) * charWidth, height: lineHeight)
        }
        let boxes = plan([scanned])
        #expect(boxes.count == 1)
        let box = try #require(boxes.first)
        // Starts at "AKIA" (offset 11), not at "KEY" (offset 7), allowing for padding.
        #expect(box.rect.minX > 20 + 9 * charWidth)

        // When the best reading misses, an alternative still rescues it.
        let misread = "token gh p R4tY8uI2oP6"
        let fixed = "token ghp_" + "R4tY8uI2oP6aS9dF1gH5jK3l"
        let rescue = ScannedLine(candidates: [misread, fixed], rect: rect.offsetBy(dx: 0, dy: 60)) { _, range in
            let start = fixed.distance(from: fixed.startIndex, to: range.lowerBound)
            return CGRect(x: 20 + CGFloat(start) * charWidth, y: 80, width: 300, height: lineHeight)
        }
        #expect(plan([rescue]).contains { $0.detector == .apiKeys })
    }

    /// Vision gives whole-word boxes; a key glued to its variable name must
    /// not take the name with it.
    @Test func aKeyGluedToItsNameIsCoveredWithoutTheName() throws {
        let text = "export AWS_ACCESS_KEY_ID=AKIA" + "IOSFODNN7EXAMPLE"
        let x: CGFloat = 20
        let rect = CGRect(x: x, y: 20, width: CGFloat(text.count) * charWidth, height: lineHeight)
        let words = RedactionPlanner.words(in: text)
        let scanned = ScannedLine(candidates: [text], rect: rect) { _, range in
            // Like Vision: the union of every whole word the range touches.
            let touched = words.filter { $0.overlaps(range) }
            guard let first = touched.first, let last = touched.last else { return nil }
            let start = text.distance(from: text.startIndex, to: first.lowerBound)
            let end = text.distance(from: text.startIndex, to: last.upperBound)
            return CGRect(x: x + CGFloat(start) * charWidth, y: 20, width: CGFloat(end - start) * charWidth, height: lineHeight)
        }
        let box = try #require(plan([scanned]).first)
        let keyStart = x + CGFloat(text.distance(from: text.startIndex, to: text.range(of: "AKIA")!.lowerBound)) * charWidth
        #expect(box.rect.minX <= keyStart, "The whole key is covered")
        #expect(box.rect.minX >= keyStart - 2 * charWidth, "The variable name stays readable")
        #expect(box.rect.maxX >= rect.maxX)
    }

    @Test func partialExtentsAreGenerousForAnyFont() {
        let span = TextExtent.span(of: 18..<38, inWord: "AWS_ACCESS_KEY_ID=" + "AKIAIOSFODNN7EXAMPLE", wordSpan: 0...380)
        #expect(span.lowerBound <= 180 && span.lowerBound >= 160)
        #expect(span.upperBound == 380)
        #expect(TextExtent.span(of: 0..<5, inWord: "hello", wordSpan: 10...60) == 10...60)
        // Narrow prefix, proportional font: starts no later than the narrow estimate.
        let narrow = TextExtent.span(of: 4..<12, inWord: "ilil" + "WWMMWWMM", wordSpan: 0...100)
        #expect(narrow.lowerBound <= 100 * (4 * 0.26) / (4 * 0.26 + 8 * 0.85))
    }

    @Test func facesBecomePaddedBoxes() {
        let boxes = plan([], faces: [CGRect(x: 100, y: 100, width: 80, height: 80)])
        #expect(boxes.count == 1)
        #expect(boxes.first?.rect == CGRect(x: 80, y: 80, width: 120, height: 120))
        #expect(boxes.first?.category == .face)
    }

    @Test func boxesArePaddedAndOrderedTopToBottom() {
        let lines = [line("ip 10.0.0.9", row: 2), line("mail jane@example.com", row: 0)]
        let boxes = plan(lines)
        #expect(boxes.count == 2)
        #expect(boxes[0].category == .personal)
        #expect(boxes[0].rect.minY < lines[1].rect.minY)
        #expect(boxes[0].rect.minX < lines[1].rect.minX + 5 * charWidth)
    }
}
