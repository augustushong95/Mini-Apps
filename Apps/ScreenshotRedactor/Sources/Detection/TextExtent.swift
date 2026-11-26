import CoreGraphics

/// Where part of a word sits horizontally.
///
/// Vision's `boundingBox(for:)` snaps any range to whole words (measured on
/// this Mac: the box for "AKIA…" inside "KEY_ID=AKIA…" is the whole word),
/// so a key glued to its variable name would cover the name too. This
/// estimates the part's extent inside the word's box instead, twice: once
/// as if the font were monospaced and once with typical proportional
/// widths. It keeps the wider of the two and adds a margin, so it errs
/// towards covering a character too many, never too few. The ink check
/// then grows the box over any glyph it still cuts.
nonisolated enum TextExtent {
    /// The x-range of characters `range` (offsets) of `word` drawn across
    /// `wordSpan`, widened by `margin` average characters on each side and
    /// kept inside the word.
    static func span(of range: Range<Int>, inWord word: String, wordSpan: ClosedRange<CGFloat>, margin: CGFloat = 0.75) -> ClosedRange<CGFloat> {
        let characters = Array(word)
        let count = characters.count
        let width = wordSpan.upperBound - wordSpan.lowerBound
        guard count > 0, width > 0, range.lowerBound >= 0, range.upperBound <= count, !range.isEmpty else { return wordSpan }
        if range.lowerBound == 0 && range.upperBound == count { return wordSpan }

        let weights = characters.map(relativeWidth)
        let total = weights.reduce(0, +)
        func proportional(_ offset: Int) -> CGFloat {
            wordSpan.lowerBound + width * weights[..<offset].reduce(0, +) / total
        }
        func uniform(_ offset: Int) -> CGFloat {
            wordSpan.lowerBound + width * CGFloat(offset) / CGFloat(count)
        }
        let average = width / CGFloat(count)
        let start = min(proportional(range.lowerBound), uniform(range.lowerBound)) - margin * average
        let end = max(proportional(range.upperBound), uniform(range.upperBound)) + margin * average
        let lower = max(wordSpan.lowerBound, start)
        let upper = min(wordSpan.upperBound, end)
        return lower <= upper ? lower...upper : wordSpan
    }

    /// Approximate advance widths (in ems) of a proportional system font.
    static func relativeWidth(_ character: Character) -> CGFloat {
        switch character {
        case "i", "j", "l", ".", ",", ":", ";", "'", "|", "!", "`": return 0.26
        case "f", "r", "t", "I", "(", ")", "[", "]", "{", "}", "\"", "/", "\\", "-": return 0.36
        case "m", "w": return 0.82
        case "M", "W", "@": return 0.88
        case "_", "=", "+", "<", ">", "~", "*", "^": return 0.56
        case "#", "$", "%", "&", "?": return 0.62
        default:
            if character.isNumber { return 0.6 }
            if character.isUppercase { return 0.68 }
            return 0.54
        }
    }
}
