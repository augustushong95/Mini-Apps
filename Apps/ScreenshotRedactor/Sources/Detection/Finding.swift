import Foundation

/// How findings are grouped in the editor's sidebar and the preview's chips.
nonisolated enum FindingCategory: String, CaseIterable, Codable, Sendable {
    case secret
    case personal
    case internalInfo
    case custom
    case face
    case manual

    var title: String {
        switch self {
        case .secret: "Secrets"
        case .personal: "Personal"
        case .internalInfo: "Internal"
        case .custom: "Your Rules"
        case .face: "Faces"
        case .manual: "Drawn by You"
        }
    }

    /// The short singular used on chips ("Secret 2 · Email 1").
    var chipTitle: String {
        switch self {
        case .secret: "Secret"
        case .personal: "Personal"
        case .internalInfo: "Internal"
        case .custom: "Rule"
        case .face: "Face"
        case .manual: "Manual"
        }
    }

    var symbolName: String {
        switch self {
        case .secret: "key.fill"
        case .personal: "person.fill"
        case .internalInfo: "network"
        case .custom: "list.bullet.rectangle"
        case .face: "face.smiling"
        case .manual: "rectangle.dashed"
        }
    }

    /// Display order, most sensitive first. Also decides which label wins
    /// when two matches overlap.
    var priority: Int {
        switch self {
        case .secret: 0
        case .personal: 1
        case .internalInfo: 2
        case .custom: 3
        case .face: 4
        case .manual: 5
        }
    }
}

/// One switch in Settings › Detection. Every automatic finding belongs to one.
nonisolated enum Detector: String, CaseIterable, Codable, Sendable {
    case apiKeys
    case privateKeys
    case credentials
    case randomStrings
    case emails
    case phoneNumbers
    case cardNumbers
    case faces
    case ipAddresses
    case internalHosts

    var category: FindingCategory {
        switch self {
        case .apiKeys, .privateKeys, .credentials, .randomStrings: .secret
        case .emails, .phoneNumbers, .cardNumbers: .personal
        case .faces: .face
        case .ipAddresses, .internalHosts: .internalInfo
        }
    }

    /// Which label wins when boxes of one category merge: the most
    /// specific finding first ("Private key" over "Random string").
    var mergeRank: Int {
        switch self {
        case .privateKeys: 0
        case .apiKeys: 1
        case .credentials: 2
        case .cardNumbers: 3
        case .emails: 4
        case .phoneNumbers: 5
        case .ipAddresses: 6
        case .internalHosts: 7
        case .faces: 8
        case .randomStrings: 9
        }
    }

    var title: String {
        switch self {
        case .apiKeys: "API keys and tokens"
        case .privateKeys: "Private keys"
        case .credentials: "Passwords and secrets in text"
        case .randomStrings: "Long random strings"
        case .emails: "Email addresses"
        case .phoneNumbers: "Phone numbers"
        case .cardNumbers: "Card numbers"
        case .faces: "Faces"
        case .ipAddresses: "IP addresses"
        case .internalHosts: "Internal hostnames"
        }
    }

    /// A one-line example for Settings.
    var example: String {
        switch self {
        case .apiKeys: "AWS, GitHub, Slack, Stripe, OpenAI and other tokens; JWTs"
        case .privateKeys: "-----BEGIN PRIVATE KEY----- blocks"
        case .credentials: "password=…, Authorization: Bearer …, user:pass@ in URLs"
        case .randomStrings: "High-entropy text that looks like a key"
        case .emails: "jane@example.com"
        case .phoneNumbers: "+1 415 555 0132"
        case .cardNumbers: "Checked with the Luhn algorithm"
        case .faces: "Best effort; small avatars can be missed"
        case .ipAddresses: "10.0.4.17, fe80::1c2b:3aff:fe4d:12"
        case .internalHosts: "build.corp.example.com, db.internal"
        }
    }
}

/// A sensitive run of text found in one line, before it becomes a box.
nonisolated struct TextMatch: Equatable, Sendable {
    var range: Range<String.Index>
    /// What the box says it hides, e.g. "GitHub token".
    var label: String
    var category: FindingCategory
    /// Nil for the user's own rules.
    var detector: Detector?
}

extension String {
    /// Converts an `NSRange` from Foundation APIs to a range in this string.
    nonisolated func range(_ nsRange: NSRange) -> Range<String.Index>? {
        guard nsRange.location != NSNotFound else { return nil }
        return Range(nsRange, in: self)
    }

    nonisolated var fullNSRange: NSRange {
        NSRange(startIndex..., in: self)
    }
}

/// A compiled regular expression that can be shared across threads.
/// `NSRegularExpression` is immutable and documented as thread-safe.
nonisolated struct Pattern: @unchecked Sendable {
    let regex: NSRegularExpression

    /// For the app's own fixed patterns; tests compile every one of them.
    init(_ pattern: String, caseInsensitive: Bool = false) {
        do {
            regex = try NSRegularExpression(pattern: pattern, options: caseInsensitive ? [.caseInsensitive] : [])
        } catch {
            preconditionFailure("Invalid built-in pattern \(pattern): \(error)")
        }
    }

    init(regex: NSRegularExpression) {
        self.regex = regex
    }

    func matches(in text: String) -> [NSTextCheckingResult] {
        regex.matches(in: text, range: text.fullNSRange)
    }

    func firstMatch(in text: String) -> NSTextCheckingResult? {
        regex.firstMatch(in: text, range: text.fullNSRange)
    }

    func isFullMatch(_ text: String) -> Bool {
        guard let match = firstMatch(in: text) else { return false }
        return match.range == text.fullNSRange
    }
}
