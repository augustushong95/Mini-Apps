import Foundation

/// Which detectors run, and the user's own rules. Saved in Preferences and
/// copied into each scan.
nonisolated struct DetectionSettings: Codable, Equatable, Sendable {
    var enabled: Set<Detector> = Set(Detector.allCases)
    var customRules: [CustomRule] = []
}

/// Runs every enabled text rule over one line of recognised text.
nonisolated struct TextRules: Sendable {
    let enabled: Set<Detector>
    let custom: CompiledCustomRules

    init(settings: DetectionSettings, includeCustomRules: Bool = true) {
        enabled = settings.enabled
        custom = CompiledCustomRules(includeCustomRules ? settings.customRules : [])
    }

    /// All matches in `line`, merged so no two overlap. When matches overlap
    /// they become one covering both, labelled by the more sensitive kind.
    func matches(in line: String, clock: CustomRuleClock = CustomRuleClock()) -> [TextMatch] {
        guard !line.isEmpty else { return [] }
        var found: [TextMatch] = []
        if enabled.contains(.privateKeys) { found += SecretRules.privateKeyMatches(in: line) }
        if enabled.contains(.apiKeys) { found += SecretRules.tokenMatches(in: line) }
        if enabled.contains(.credentials) { found += CredentialRules.matches(in: line) }
        if enabled.contains(.cardNumbers) { found += PersonalRules.cardMatches(in: line) }
        if enabled.contains(.emails) { found += PersonalRules.emailMatches(in: line) }
        if enabled.contains(.ipAddresses) { found += InternalRules.ipv4Matches(in: line) + InternalRules.ipv6Matches(in: line) }
        if enabled.contains(.internalHosts) { found += InternalRules.hostnameMatches(in: line) }
        if !custom.isEmpty { found += custom.matches(in: line, clock: clock) }
        if enabled.contains(.randomStrings) { found += RandomStrings.matches(in: line) }
        if enabled.contains(.phoneNumbers) {
            // A "phone number" inside an address, card or key is a false reading.
            let phones = PersonalRules.phoneMatches(in: line).filter { phone in
                !found.contains { $0.range.overlaps(phone.range) }
            }
            found += phones
        }
        return Self.merge(found)
    }

    static func merge(_ matches: [TextMatch]) -> [TextMatch] {
        let sorted = matches.sorted {
            $0.range.lowerBound != $1.range.lowerBound ? $0.range.lowerBound < $1.range.lowerBound : $0.range.upperBound > $1.range.upperBound
        }
        var merged: [TextMatch] = []
        for match in sorted {
            guard var last = merged.last, match.range.lowerBound < last.range.upperBound else {
                merged.append(match)
                continue
            }
            let upper = max(last.range.upperBound, match.range.upperBound)
            if match.category.priority < last.category.priority {
                last.label = match.label
                last.category = match.category
                last.detector = match.detector
            }
            last.range = last.range.lowerBound..<upper
            merged[merged.count - 1] = last
        }
        return merged
    }
}
