import CoreGraphics
import Foundation

/// One line of recognised text, as the planner sees it. The scanner builds
/// these from Vision; tests build them by hand.
nonisolated struct ScannedLine {
    /// Vision's readings of the line, best first.
    let candidates: [String]
    /// The line's bounds in app pixels (top-left origin).
    let rect: CGRect
    /// The pixel rect of a range of one candidate, or nil if unknown.
    let rangeRect: (_ candidate: Int, _ range: Range<String.Index>) -> CGRect?

    var text: String { candidates.first ?? "" }
    var height: CGFloat { rect.height }
}

/// Turns recognised lines into boxes: runs the text rules on every reading
/// of every line, then the rules that need more than one line (private key
/// blocks, wrapped tokens, label/value cells), then tidies the result.
nonisolated struct RedactionPlanner {
    let rules: TextRules
    let imageSize: CGSize
    let refiner: InkRefiner?
    let clock: CustomRuleClock

    func boxes(for unsortedLines: [ScannedLine], faces: [CGRect] = []) -> [RedactionBox] {
        let lines = unsortedLines.sorted { $0.rect.minY != $1.rect.minY ? $0.rect.minY < $1.rect.minY : $0.rect.minX < $1.rect.minX }
        var boxes: [RedactionBox] = []

        for (index, line) in lines.enumerated() {
            // The best reading decides. Vision's other readings only add
            // boxes where the best one found nothing (a misread key), so an
            // odd alternative can't swallow the text around a match.
            var lineBoxes: [RedactionBox] = []
            for (candidateIndex, text) in line.candidates.enumerated() {
                var found: [RedactionBox] = []
                for match in rules.matches(in: text, clock: clock) {
                    let box = textBox(line: line, candidate: candidateIndex, range: match.range, match: match)
                    if candidateIndex > 0, lineBoxes.contains(where: { $0.rect.intersects(box.rect) }) { continue }
                    found.append(box)
                    if wrapsOntoNextLine(match, text: text, lineIndex: index, lines: lines) {
                        boxes += continuationBoxes(from: index, lines: lines, match: match)
                    }
                }
                lineBoxes += found
            }
            boxes += lineBoxes
        }
        if rules.enabled.contains(.credentials) {
            boxes += pairedCellBoxes(lines)
        }
        if rules.enabled.contains(.privateKeys) {
            boxes += privateKeyBlocks(lines)
        }
        if rules.enabled.contains(.faces) {
            boxes += faces.map { face in
                RedactionBox(rect: BoxGeometry.faceBox(face, imageSize: imageSize), label: "Face", category: .face, detector: .faces, source: .detected)
            }
        }
        return Self.merge(boxes.filter { $0.rect.width >= 1 && $0.rect.height >= 1 })
    }

    // MARK: Single lines

    private func textBox(line: ScannedLine, candidate: Int, range: Range<String.Index>, match: TextMatch) -> RedactionBox {
        let extent = matchExtent(line: line, candidate: candidate, range: range)
        var rect = BoxGeometry.matchBox(matchRect: extent.rect, lineRect: line.rect)
        let padding = BoxGeometry.textPadding(lineHeight: line.height)
        if let refiner {
            rect = refiner.refine(rect, lineHeight: line.height, acrossGapsLeft: !extent.leftEstimated, acrossGapsRight: !extent.rightEstimated)
            rect = BoxGeometry.finalize(refiner.pad(rect, by: padding, lineHeight: line.height), padding: 0, imageSize: imageSize)
        } else {
            rect = BoxGeometry.finalize(rect, padding: padding, imageSize: imageSize)
        }
        return RedactionBox(rect: rect, label: match.label, category: match.category, detector: match.detector, source: .detected)
    }

    /// The match's extent: whole words from Vision, and for a word the
    /// match only partly covers ("KEY_ID=AKIA…"), an estimate inside it.
    /// Says which edges were estimated rather than placed by Vision.
    private func matchExtent(line: ScannedLine, candidate: Int, range: Range<String.Index>) -> (rect: CGRect?, leftEstimated: Bool, rightEstimated: Bool) {
        guard candidate < line.candidates.count else { return (nil, false, false) }
        let text = line.candidates[candidate]
        var result: CGRect?
        var leftEstimated = false, rightEstimated = false
        let touched = Self.words(in: text).filter { $0.overlaps(range) }
        for (index, word) in touched.enumerated() {
            guard let wordRect = line.rangeRect(candidate, word), !wordRect.isNull, !wordRect.isEmpty else {
                return (line.rangeRect(candidate, range), false, false)
            }
            let part = max(word.lowerBound, range.lowerBound)..<min(word.upperBound, range.upperBound)
            var rect = wordRect
            if part != word {
                let start = text.distance(from: word.lowerBound, to: part.lowerBound)
                let end = text.distance(from: word.lowerBound, to: part.upperBound)
                let span = TextExtent.span(of: start..<end, inWord: String(text[word]), wordSpan: wordRect.minX...wordRect.maxX)
                rect = CGRect(x: span.lowerBound, y: wordRect.minY, width: span.upperBound - span.lowerBound, height: wordRect.height)
                if index == 0, part.lowerBound > word.lowerBound { leftEstimated = true }
                if index == touched.count - 1, part.upperBound < word.upperBound { rightEstimated = true }
            }
            result = result.map { $0.union(rect) } ?? rect
        }
        guard let result else { return (line.rangeRect(candidate, range), false, false) }
        return (result, leftEstimated, rightEstimated)
    }

    /// Whitespace-separated words of `text`.
    static func words(in text: String) -> [Range<String.Index>] {
        var words: [Range<String.Index>] = []
        var start: String.Index?
        var index = text.startIndex
        while index < text.endIndex {
            if text[index].isWhitespace {
                if let wordStart = start { words.append(wordStart..<index) }
                start = nil
            } else if start == nil {
                start = index
            }
            index = text.index(after: index)
        }
        if let wordStart = start { words.append(wordStart..<text.endIndex) }
        return words
    }

    // MARK: Wrapped tokens

    private static let wrappableDetectors: Set<Detector> = [.apiKeys, .randomStrings, .credentials]

    /// A token that runs to the end of a line that is as wide as its block
    /// (the terminal or editor width) probably continues on the next line.
    private func wrapsOntoNextLine(_ match: TextMatch, text: String, lineIndex: Int, lines: [ScannedLine]) -> Bool {
        guard let detector = match.detector, Self.wrappableDetectors.contains(detector) else { return false }
        let rest = text[match.range.upperBound...]
        guard rest.allSatisfy(\.isWhitespace) else { return false }
        let line = lines[lineIndex]
        return line.rect.maxX >= blockRightEdge(around: lineIndex, lines: lines) - 1.5 * line.height
    }

    /// The right edge of the longest nearby line that starts in the same column.
    private func blockRightEdge(around index: Int, lines: [ScannedLine]) -> CGFloat {
        let line = lines[index]
        let window = max(0, index - 12)...min(lines.count - 1, index + 12)
        return window.reduce(line.rect.maxX) { edge, other in
            let candidate = lines[other]
            guard abs(candidate.rect.minX - line.rect.minX) <= 2 * line.height || candidate.rect.minX < line.rect.minX else { return edge }
            guard abs(candidate.height - line.height) <= line.height * 0.3 else { return edge }
            return max(edge, candidate.rect.maxX)
        }
    }

    private func continuationBoxes(from index: Int, lines: [ScannedLine], match: TextMatch) -> [RedactionBox] {
        var boxes: [RedactionBox] = []
        var current = lines[index]
        var searchStart = index + 1
        for _ in 0..<8 {
            guard let nextIndex = nextLineIndex(below: current, from: searchStart, lines: lines) else { break }
            let next = lines[nextIndex]
            guard let tokenRange = next.text.firstToken() else { break }
            let token = next.text[tokenRange]
            guard isContinuationToken(token) else { break }
            let tokenMatch = TextMatch(range: tokenRange, label: match.label, category: match.category, detector: match.detector)
            boxes.append(textBox(line: next, candidate: 0, range: tokenRange, match: tokenMatch))
            // Keep going only if this line is all token and reaches the edge too.
            guard tokenRange.upperBound == next.text.endIndex,
                  next.rect.maxX >= blockRightEdge(around: nextIndex, lines: lines) - 1.5 * next.height
            else { break }
            current = next
            searchStart = nextIndex + 1
        }
        return boxes
    }

    /// The line directly below `line`: close under it, about the same height,
    /// and starting at or left of where `line` starts.
    private func nextLineIndex(below line: ScannedLine, from start: Int, lines: [ScannedLine]) -> Int? {
        guard start < lines.count else { return nil }
        for index in start..<lines.count {
            let next = lines[index]
            let gap = next.rect.minY - line.rect.maxY
            if gap > line.height { return nil }
            guard next.rect.midY > line.rect.maxY - line.height * 0.25 else { continue }
            guard abs(next.height - line.height) <= line.height * 0.3 else { continue }
            guard next.rect.minX <= line.rect.minX + line.height else { continue }
            return index
        }
        return nil
    }

    /// Looks like the rest of a key: base64url characters only, and random
    /// enough that it isn't the next shell command ("export", "cd").
    private func isContinuationToken(_ token: Substring) -> Bool {
        guard token.count >= 6,
              token.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "+/=_-.~".contains($0)) })
        else { return false }
        return (CredentialRules.looksLikeSecretValue(String(token)) && !RandomStrings.containsWord(String(token))) || token.count >= 16
    }

    // MARK: Label / value cells

    /// "Password" in one cell and "hunter2" in the next, on the same row.
    private func pairedCellBoxes(_ lines: [ScannedLine]) -> [RedactionBox] {
        var boxes: [RedactionBox] = []
        for row in rows(lines) {
            for (label, value) in zip(row, row.dropFirst()) {
                guard value.rect.minX >= label.rect.maxX - label.height * 0.25,
                      let range = CredentialRules.pairedValue(label: label.text, next: value.text)
                else { continue }
                let keyword = label.text
                let match = TextMatch(range: range, label: CredentialRules.label(forKeyword: keyword), category: .secret, detector: .credentials)
                boxes.append(textBox(line: value, candidate: 0, range: range, match: match))
            }
        }
        return boxes
    }

    /// Lines grouped into rows (vertical centres close together), each row left to right.
    private func rows(_ lines: [ScannedLine]) -> [[ScannedLine]] {
        var rows: [[ScannedLine]] = []
        for line in lines.sorted(by: { $0.rect.midY < $1.rect.midY }) {
            if let last = rows.last?.first, abs(last.rect.midY - line.rect.midY) <= min(last.height, line.height) * 0.5 {
                rows[rows.count - 1].append(line)
            } else {
                rows.append([line])
            }
        }
        return rows.map { $0.sorted { $0.rect.minX < $1.rect.minX } }
    }

    // MARK: Private key blocks

    /// From a BEGIN … PRIVATE KEY line down through its END line: every
    /// line in between that starts in the same column. Without an END line
    /// (cropped screenshot), down to the end of that column.
    private func privateKeyBlocks(_ lines: [ScannedLine]) -> [RedactionBox] {
        var boxes: [RedactionBox] = []
        var index = 0
        while index < lines.count {
            let header = lines[index]
            guard header.candidates.contains(where: SecretRules.isPrivateKeyHeader) else {
                index += 1
                continue
            }
            var block = header.rect
            var last = header
            var next = index + 1
            while next < lines.count {
                let line = lines[next]
                if line.rect.minY - last.rect.maxY > header.height * 1.2 { break }
                let aligned = abs(line.rect.minX - header.rect.minX) <= header.height * 1.5
                if aligned {
                    block = block.union(line.rect)
                    last = line
                    if line.candidates.contains(where: SecretRules.isPrivateKeyFooter) { next += 1; break }
                }
                next += 1
            }
            let rect = BoxGeometry.finalize(block, padding: BoxGeometry.textPadding(lineHeight: header.height), imageSize: imageSize)
            boxes.append(RedactionBox(rect: rect, label: "Private key", category: .secret, detector: .privateKeys, source: .detected))
            index = max(index + 1, next)
        }
        return boxes
    }

    // MARK: Tidying

    /// Merges boxes that mostly overlap (the same token read from several
    /// candidates, or two rules on one value) into one, labelled by the more
    /// sensitive kind. Sorted top to bottom, left to right.
    static func merge(_ boxes: [RedactionBox]) -> [RedactionBox] {
        var result: [RedactionBox] = []
        for box in boxes {
            var merged = box
            var changed = true
            while changed {
                changed = false
                if let index = result.firstIndex(where: { BoxGeometry.overlapsSubstantially($0.rect, merged.rect, fraction: 0.5) }) {
                    let other = result.remove(at: index)
                    let winner = outranks(other, merged) ? other : merged
                    merged = RedactionBox(
                        id: winner.id, rect: other.rect.union(merged.rect), label: winner.label,
                        category: winner.category, detector: winner.detector, source: .detected
                    )
                    changed = true
                }
            }
            result.append(merged)
        }
        return result.sorted { $0.rect.minY != $1.rect.minY ? $0.rect.minY < $1.rect.minY : $0.rect.minX < $1.rect.minX }
    }

    /// True if `a`'s label should be kept over `b`'s: the more sensitive
    /// category, then the more specific detector.
    static func outranks(_ a: RedactionBox, _ b: RedactionBox) -> Bool {
        if a.category.priority != b.category.priority { return a.category.priority < b.category.priority }
        return (a.detector?.mergeRank ?? 99) <= (b.detector?.mergeRank ?? 99)
    }
}
