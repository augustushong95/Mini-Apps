import Foundation

/// Finds long, random-looking strings that are probably keys even without a
/// known prefix or a keyword nearby.
///
/// A token counts when it has 20+ characters from the base64url set, mixes
/// character classes, has high Shannon entropy, and isn't mostly made of
/// pronounceable words. That last test keeps identifiers such as
/// `kCGImageSourceShouldCacheImmediately` out. Hex-only strings (git SHAs,
/// hashes) and UUIDs are left to the keyword rules.
nonisolated enum RandomStrings {
    static let minimumLength = 20

    static func matches(in line: String) -> [TextMatch] {
        var found: [TextMatch] = []
        for token in tokens(in: line) {
            for range in candidateRanges(of: token, in: line) where isRandom(String(line[range])) {
                found.append(TextMatch(range: range, label: "Random string", category: .secret, detector: .randomStrings))
            }
        }
        return found
    }

    // MARK: Tokens

    private static let separators: Set<Character> = ["\"", "'", "`", "(", ")", "[", "]", "{", "}", "<", ">", ",", ";", "|"]

    /// Whitespace- and bracket-separated tokens, trimmed of sentence punctuation.
    static func tokens(in line: String) -> [Range<String.Index>] {
        var result: [Range<String.Index>] = []
        var start: String.Index?
        var index = line.startIndex
        while index < line.endIndex {
            let character = line[index]
            let isSeparator = character.isWhitespace || separators.contains(character)
            if isSeparator {
                if let tokenStart = start { result.append(tokenStart..<index) }
                start = nil
            } else if start == nil {
                start = index
            }
            index = line.index(after: index)
        }
        if let tokenStart = start { result.append(tokenStart..<line.endIndex) }
        return result.compactMap { trimPunctuation($0, in: line) }
    }

    private static func trimPunctuation(_ range: Range<String.Index>, in line: String) -> Range<String.Index>? {
        var lower = range.lowerBound
        var upper = range.upperBound
        while lower < upper, ":.!?".contains(line[lower]) { lower = line.index(after: lower) }
        while upper > lower {
            let previous = line.index(before: upper)
            guard ".,:!?".contains(line[previous]) else { break }
            upper = previous
        }
        return lower < upper ? lower..<upper : nil
    }

    /// The parts of a token worth testing: URL and path segments separately,
    /// the value of `KEY=VALUE`, and word-separated parts when the token
    /// contains real words ("payments-worker-7d9f8b6c5d").
    static func candidateRanges(of token: Range<String.Index>, in line: String) -> [Range<String.Index>] {
        let text = line[token]
        guard text.count >= minimumLength else { return [] }

        if text.contains("://") || looksLikePath(text) {
            return split(token, in: line, on: "/?&=#:@").filter { line.distance(from: $0.lowerBound, to: $0.upperBound) >= minimumLength }
        }

        var candidates: [Range<String.Index>] = []
        if let separator = text.firstIndex(where: { $0 == "=" || $0 == ":" }), separator > text.startIndex {
            // KEY=VALUE or key:value: test the value on its own…
            let value = line.index(after: separator)..<token.upperBound
            if line.distance(from: value.lowerBound, to: value.upperBound) >= minimumLength { candidates.append(value) }
            // …and the whole token only when the name part isn't a word.
            let name = String(line[token.lowerBound..<separator])
            if !containsWord(name) { candidates.append(token) }
            return candidates
        }

        let parts = split(token, in: line, on: "-_.")
        if parts.count > 1, parts.contains(where: { containsWord(String(line[$0])) && line[$0].allSatisfy(\.isLetter) }) {
            return parts.filter { line.distance(from: $0.lowerBound, to: $0.upperBound) >= minimumLength }
        }
        return [token]
    }

    private static func split(_ range: Range<String.Index>, in line: String, on characters: String) -> [Range<String.Index>] {
        var parts: [Range<String.Index>] = []
        var start = range.lowerBound
        var index = range.lowerBound
        while index < range.upperBound {
            if characters.contains(line[index]) {
                if start < index { parts.append(start..<index) }
                start = line.index(after: index)
            }
            index = line.index(after: index)
        }
        if start < range.upperBound { parts.append(start..<range.upperBound) }
        return parts
    }

    /// "/usr/local/bin", "~/Library/…", "src/components/App.tsx".
    private static func looksLikePath(_ text: Substring) -> Bool {
        guard text.contains("/") else { return false }
        if text.hasPrefix("/") || text.hasPrefix("~") || text.hasPrefix("./") || text.hasPrefix("../") { return true }
        let segments = text.split(separator: "/")
        guard segments.count >= 2 else { return false }
        let wordy = segments.filter { containsWord(String($0)) }
        return wordy.count * 2 >= segments.count
    }

    // MARK: Randomness

    static func isRandom(_ text: String) -> Bool {
        var text = Substring(text)
        while text.last == "=" { text.removeLast() }
        let count = text.count
        guard count >= minimumLength else { return false }
        guard text.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "+/_-.~".contains($0)) }) else { return false }

        let hasLower = text.contains(where: \.isLowercase)
        let hasUpper = text.contains(where: \.isUppercase)
        let digits = text.filter(\.isNumber).count
        let letters = text.filter(\.isLetter).count

        // Hex (hashes, git SHAs) and UUIDs are only secret next to a keyword.
        if text.allSatisfy({ $0.isHexDigit || $0 == "-" }) { return false }
        // Letters of a single case and no digits: a word or a constant.
        if !(hasLower && hasUpper) && digits == 0 { return false }
        // Single-case with digits (base32, lowercase IDs) needs a real mix.
        if !(hasLower && hasUpper), letters < 4 || digits < 4 { return false }
        if ISODate.isFullMatch(String(text)) { return false }

        let threshold = count < 32 ? 3.5 : 3.9
        guard entropy(of: text) >= threshold else { return false }
        return wordLetterShare(String(text)) < 0.6
    }

    private static let ISODate = Pattern(#"^\d{4}-\d{2}-\d{2}(?:[T ]\d{2}:\d{2}(?::\d{2}(?:\.\d+)?)?(?:Z|[+\-]\d{2}:?\d{2})?)?$"#)

    /// Shannon entropy in bits per character.
    static func entropy<S: StringProtocol>(of text: S) -> Double {
        var counts: [Character: Int] = [:]
        for character in text { counts[character, default: 0] += 1 }
        let total = Double(text.count)
        return counts.values.reduce(0) { sum, count in
            let p = Double(count) / total
            return sum - p * log2(p)
        }
    }

    // MARK: Words

    private static let wordPattern = Pattern(#"[A-Z]+(?![a-z])|[A-Z]?[a-z]+"#)
    private static let vowels: Set<Character> = ["a", "e", "i", "o", "u", "y"]

    /// The share of letters that belong to pronounceable words of 4+ letters.
    /// Identifiers are mostly words; random strings almost never are.
    static func wordLetterShare(_ text: String) -> Double {
        let letters = text.filter(\.isLetter).count
        guard letters > 0 else { return 0 }
        let wordLetters = wordPattern.matches(in: text).reduce(0) { sum, result in
            guard let range = text.range(result.range) else { return sum }
            let word = text[range]
            return isPronounceable(word) ? sum + word.count : sum
        }
        return Double(wordLetters) / Double(letters)
    }

    /// True if `text` contains at least one pronounceable word of 4+ letters.
    static func containsWord(_ text: String) -> Bool {
        wordPattern.matches(in: text).contains { result in
            guard let range = text.range(result.range) else { return false }
            return isPronounceable(text[range])
        }
    }

    static func isPronounceable(_ word: Substring) -> Bool {
        guard word.count >= 4 else { return false }
        let lower = word.lowercased()
        let vowelCount = lower.filter { vowels.contains($0) }.count
        let ratio = Double(vowelCount) / Double(lower.count)
        guard (0.2...0.7).contains(ratio) else { return false }
        var run = 0
        for character in lower {
            run = vowels.contains(character) ? 0 : run + 1
            if run > 3 { return false }
        }
        return true
    }
}
