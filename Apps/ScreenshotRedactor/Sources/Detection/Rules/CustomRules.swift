import Foundation

/// A rule the user adds in Settings › Your Rules (Pro).
nonisolated struct CustomRule: Codable, Identifiable, Equatable, Hashable, Sendable {
    enum Kind: String, Codable, CaseIterable, Sendable {
        /// A domain and all its subdomains, in hosts, URLs and emails.
        case domain
        /// A word or phrase, matched whole, ignoring case and accents.
        case phrase
        /// A regular expression.
        case pattern

        var title: String {
            switch self {
            case .domain: "Domain"
            case .phrase: "Word or phrase"
            case .pattern: "Pattern"
            }
        }

        var placeholder: String {
            switch self {
            case .domain: "corp.company.com"
            case .phrase: "Project Falcon"
            case .pattern: #"CUST-\d{6}"#
            }
        }

        var help: String {
            switch self {
            case .domain: "Covers the domain and every subdomain, in hostnames, links and email addresses."
            case .phrase: "Covers the whole word or phrase, ignoring case and accents."
            case .pattern: "A regular expression (ICU syntax). Case-sensitive unless it starts with (?i)."
            }
        }
    }

    var id = UUID()
    var kind: Kind
    var value: String
    var isEnabled = true

    /// What the box says it hides.
    var label: String {
        switch kind {
        case .domain: "Domain"
        case .phrase: "Phrase"
        case .pattern: "Pattern"
        }
    }

    /// Why `value` can't be saved for `kind`, or nil when it can.
    static func problem(kind: Kind, value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Enter a value." }
        switch kind {
        case .domain:
            return normalizedDomain(trimmed) == nil ? "Enter a domain such as corp.company.com." : nil
        case .phrase:
            return trimmed.count < 2 ? "Enter at least two characters." : nil
        case .pattern:
            let regex: NSRegularExpression
            do {
                regex = try NSRegularExpression(pattern: trimmed)
            } catch {
                return "This isn't a valid regular expression."
            }
            if regex.firstMatch(in: "", range: NSRange(location: 0, length: 0)) != nil {
                return "This pattern matches empty text, so it would match everywhere."
            }
            let sample = "The quick brown fox jumps over the lazy dog 0123456789"
            let covered = regex.matches(in: sample, range: sample.fullNSRange).reduce(0) { $0 + $1.range.length }
            if covered * 2 >= sample.utf16.count {
                return "This pattern matches almost any text. Make it more specific."
            }
            if hasNestedQuantifier(trimmed) {
                return "Nested repeats like (a+)+ can take forever to run. Simplify the pattern."
            }
            return nil
        }
    }

    /// "https://*.Corp.Company.com/path" → "corp.company.com".
    static func normalizedDomain(_ value: String) -> String? {
        var text = value.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if let scheme = text.range(of: "://") { text = String(text[scheme.upperBound...]) }
        if let slash = text.firstIndex(of: "/") { text = String(text[..<slash]) }
        if let at = text.lastIndex(of: "@") { text = String(text[text.index(after: at)...]) }
        while text.hasPrefix("*.") || text.hasPrefix(".") { text.removeFirst(text.hasPrefix("*.") ? 2 : 1) }
        while text.hasSuffix(".") { text.removeLast() }
        let labels = text.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2,
              labels.allSatisfy({ !$0.isEmpty && $0.count <= 63 && $0.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") } })
        else { return nil }
        return text
    }

    /// A quantified group that itself contains a quantifier: `(a+)+`, `(x*)*`,
    /// `(\w+\s?)+`. These backtrack exponentially on near-misses.
    static func hasNestedQuantifier(_ pattern: String) -> Bool {
        let nested = Pattern(#"\((?:[^()\\]|\\.)*[+*}](?:[^()\\]|\\.)*\)(?:[+*]|\{\d*,\d*\})"#)
        return nested.firstMatch(in: pattern) != nil
    }
}

/// The user's enabled rules, compiled once per scan.
nonisolated struct CompiledCustomRules: @unchecked Sendable {
    private enum Matcher {
        case regex(NSRegularExpression)
        case phrase(String)
    }

    private struct Entry {
        let rule: CustomRule
        let matcher: Matcher
    }

    private let entries: [Entry]

    /// The longest a single pattern may run on one image before it is
    /// stopped (and reported, so the user can fix it).
    static let budgetPerRule: Duration = .milliseconds(100)

    init(_ rules: [CustomRule]) {
        entries = rules.filter(\.isEnabled).compactMap { rule in
            guard CustomRule.problem(kind: rule.kind, value: rule.value) == nil else { return nil }
            let value = rule.value.trimmingCharacters(in: .whitespacesAndNewlines)
            switch rule.kind {
            case .domain:
                guard let domain = CustomRule.normalizedDomain(value) else { return nil }
                let escaped = NSRegularExpression.escapedPattern(for: domain)
                let pattern = #"(?<![A-Za-z0-9\-.])(?:[A-Za-z0-9._%+\-]+@)?(?:[A-Za-z0-9](?:[A-Za-z0-9\-]*[A-Za-z0-9])?\.)*"# + escaped + #"(?![A-Za-z0-9\-]|\.[A-Za-z0-9])"#
                guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
                return Entry(rule: rule, matcher: .regex(regex))
            case .phrase:
                return Entry(rule: rule, matcher: .phrase(value))
            case .pattern:
                guard let regex = try? NSRegularExpression(pattern: value) else { return nil }
                return Entry(rule: rule, matcher: .regex(regex))
            }
        }
    }

    var isEmpty: Bool { entries.isEmpty }

    /// Matches in `line`. A pattern that uses up its time budget is skipped
    /// from then on, and its id is added to `clock.timedOut`.
    func matches(in line: String, clock: CustomRuleClock) -> [TextMatch] {
        // Lines from OCR are short; a cap keeps a hostile pattern's worst case small.
        let line = line.utf16.count > 1_000 ? String(line.utf16.prefix(1_000)) ?? line : line
        var found: [TextMatch] = []
        for entry in entries where !clock.timedOut.contains(entry.rule.id) {
            switch entry.matcher {
            case .phrase(let phrase):
                for range in phraseRanges(of: phrase, in: line) {
                    found.append(TextMatch(range: range, label: entry.rule.label, category: .custom, detector: nil))
                }
            case .regex(let regex):
                let start = ContinuousClock.now
                let budget = CompiledCustomRules.budgetPerRule - clock.spent(entry.rule.id)
                var timedOut = false
                regex.enumerateMatches(in: line, options: [.reportProgress], range: line.fullNSRange) { result, _, stop in
                    if ContinuousClock.now - start > budget {
                        timedOut = true
                        stop.pointee = true
                        return
                    }
                    guard let result, result.range.length > 0, let range = line.range(result.range) else { return }
                    found.append(TextMatch(range: range, label: entry.rule.label, category: .custom, detector: nil))
                }
                clock.add(ContinuousClock.now - start, to: entry.rule.id)
                if timedOut || clock.spent(entry.rule.id) > CompiledCustomRules.budgetPerRule {
                    clock.timedOut.insert(entry.rule.id)
                }
            }
        }
        return found
    }

    /// Whole-word occurrences of `phrase`, ignoring case and accents.
    private func phraseRanges(of phrase: String, in line: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var searchStart = line.startIndex
        while searchStart < line.endIndex,
              let range = line.range(of: phrase, options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], range: searchStart..<line.endIndex) {
            let beforeIsWord = range.lowerBound > line.startIndex && line[line.index(before: range.lowerBound)].isWordCharacter
            let afterIsWord = range.upperBound < line.endIndex && line[range.upperBound].isWordCharacter
            if !beforeIsWord && !afterIsWord { ranges.append(range) }
            searchStart = range.upperBound > range.lowerBound ? range.upperBound : line.index(after: range.lowerBound)
        }
        return ranges
    }
}

/// Time each custom pattern has used during one scan. Lives only inside
/// that scan, so it is never shared between threads.
nonisolated final class CustomRuleClock {
    private var spentByRule: [UUID: Duration] = [:]
    var timedOut: Set<UUID> = []

    func spent(_ id: UUID) -> Duration { spentByRule[id] ?? .zero }

    func add(_ duration: Duration, to id: UUID) {
        spentByRule[id, default: .zero] += duration
    }
}

extension Character {
    nonisolated var isWordCharacter: Bool { isLetter || isNumber || self == "_" }
}
