import Foundation

/// Secrets recognised by their shape: provider tokens with known prefixes,
/// JWTs, private key headers and credentials written next to a keyword.
///
/// OCR can misread a character or two, so prefixes accept the usual
/// look-alikes (I/1/l/|, O/0) and bodies accept a few characters more or
/// less than the real format. Matches always point into the line as read.
nonisolated enum SecretRules {
    struct PrefixRule: Sendable {
        let label: String
        let pattern: Pattern
        /// The capture group to cover; 0 covers the whole match.
        let group: Int
    }

    /// Ordered so the most specific rule labels a match (Anthropic before OpenAI).
    static let tokenRules: [PrefixRule] = [
        rule("AWS access key", #"(?<![A-Za-z0-9])(?:AK[I1l|]A|AS[I1l|]A|AB[I1l|]A|ACCA)[A-Za-z0-9]{14,18}(?![A-Za-z0-9])"#),
        rule("AWS secret key", #"(?i)aws_?secret_?access_?key["']?\s*[:=]\s*["']?([A-Za-z0-9/+=]{30,44})"#, group: 1),
        rule("Google API key", #"(?<![A-Za-z0-9])A[I1l|]za[0-9A-Za-z_\-]{33,37}(?![A-Za-z0-9_\-])"#),
        rule("Google OAuth secret", #"GOCSPX-[0-9A-Za-z_\-]{20,}"#),
        rule("Google OAuth token", #"(?<![A-Za-z0-9])ya29\.[0-9A-Za-z_\-]{20,}"#),
        rule("GitHub token", #"(?<![A-Za-z0-9])gh[pousr][_\-][A-Za-z0-9]{20,}"#),
        rule("GitHub token", #"(?<![A-Za-z0-9])gh[pousr] [A-Za-z0-9]{30,}"#),
        rule("GitHub token", #"(?<![A-Za-z0-9])github[_\-]pat[_\-][A-Za-z0-9_]{20,}"#),
        rule("GitLab token", #"(?<![A-Za-z0-9])gl(?:pat|dt|rt|ft|soat|cbt|ptt)-[A-Za-z0-9_\-]{18,}"#),
        rule("Slack token", #"(?<![A-Za-z0-9])xox[abposrce]-[A-Za-z0-9\-]{10,}"#),
        rule("Slack token", #"(?<![A-Za-z0-9])xapp-[A-Za-z0-9\-]{10,}"#),
        rule("Slack webhook", #"hooks\.slack\.com/(?:services|workflows|triggers)/([A-Za-z0-9/_\-]{8,})"#, group: 1),
        rule("Stripe key", #"(?<![A-Za-z0-9])(?:sk|rk|pk)_(?:live|test)_[A-Za-z0-9]{10,}"#),
        rule("Stripe webhook secret", #"(?<![A-Za-z0-9])whsec_[A-Za-z0-9]{10,}"#),
        rule("Anthropic key", #"(?<![A-Za-z0-9])sk-ant-[A-Za-z0-9_\-]{20,}"#),
        rule("OpenAI key", #"(?<![A-Za-z0-9])sk-(?:proj-|svcacct-|admin-)?[A-Za-z0-9_\-]{20,}"#),
        rule("npm token", #"(?<![A-Za-z0-9])npm_[A-Za-z0-9]{30,}"#),
        rule("PyPI token", #"(?<![A-Za-z0-9])pypi-[A-Za-z0-9_\-]{40,}"#),
        rule("Hugging Face token", #"(?<![A-Za-z0-9])hf_[A-Za-z0-9]{30,}"#),
        rule("SendGrid key", #"(?<![A-Za-z0-9])SG\.[A-Za-z0-9_\-]{16,}\.[A-Za-z0-9_\-]{16,}"#),
        rule("Twilio key", #"(?<![A-Za-z0-9])SK[0-9a-fA-F]{32}(?![A-Za-z0-9])"#),
        rule("Mailgun key", #"(?<![A-Za-z0-9])key-[0-9a-zA-Z]{32}(?![A-Za-z0-9])"#),
        rule("DigitalOcean token", #"(?<![A-Za-z0-9])do[opr]_v1_[a-f0-9]{60,68}"#),
        rule("Shopify token", #"(?<![A-Za-z0-9])shp(?:at|ca|pa|ss)_[a-fA-F0-9]{30,34}"#),
        rule("Square token", #"(?<![A-Za-z0-9])sq0(?:atp|csp)-[0-9A-Za-z_\-]{22,}"#),
        rule("Atlassian token", #"(?<![A-Za-z0-9])ATATT3[A-Za-z0-9_\-=]{20,}"#),
        rule("Linear key", #"(?<![A-Za-z0-9])lin_api_[A-Za-z0-9]{30,}"#),
        rule("Postman key", #"(?<![A-Za-z0-9])PMAK-[A-Za-z0-9]{20,}-[A-Za-z0-9]{20,}"#),
        rule("Databricks token", #"(?<![A-Za-z0-9])dapi[a-f0-9]{32}(?![A-Za-z0-9])"#),
        rule("Doppler token", #"(?<![A-Za-z0-9])dp\.(?:pt|st|sa|ct|scim|audit)\.[A-Za-z0-9]{20,}"#),
        rule("Vault token", #"(?<![A-Za-z0-9])hv[sb]\.[A-Za-z0-9_\-]{20,}"#),
        rule("Heroku key", #"(?<![A-Za-z0-9])HRKU-[A-Za-z0-9_\-]{20,}"#),
        rule("Telegram bot token", #"(?<![0-9])[0-9]{8,10}:AA[A-Za-z0-9_\-]{30,}"#),
        rule("Azure storage key", #"(?i)AccountKey=([A-Za-z0-9+/=]{20,})"#, group: 1),
        rule("Azure SAS signature", #"(?i)[?&]sig=([A-Za-z0-9%+/=]{10,})"#, group: 1),
        // Base64-encoded JSON: a JWT (header.payload.signature) or any part of one.
        rule("JWT", #"(?<![A-Za-z0-9])eyJ[A-Za-z0-9_\-]{10,}(?:\.[A-Za-z0-9_\-]{4,}){1,2}"#),
        rule("Encoded token", #"(?<![A-Za-z0-9])eyJ[A-Za-z0-9_\-]{20,}"#),
    ]

    /// The header line of a PEM private key. Everything after it on the line
    /// is covered too (keys pasted on one line, as in JSON service accounts).
    static let privateKeyHeader = Pattern(#"-{0,5}\s*BEGIN\s+(?:[A-Z0-9]+\s+){0,3}PRIVATE\s+KEY(?:\s+BLOCK)?\s*-{0,5}.*"#, caseInsensitive: true)
    static let privateKeyFooter = Pattern(#"END\s+(?:[A-Z0-9]+\s+){0,3}PRIVATE\s+KEY"#, caseInsensitive: true)

    private static func rule(_ label: String, _ pattern: String, group: Int = 0) -> PrefixRule {
        PrefixRule(label: label, pattern: Pattern(pattern), group: group)
    }

    static func tokenMatches(in line: String) -> [TextMatch] {
        var found: [TextMatch] = []
        for rule in tokenRules {
            for result in rule.pattern.matches(in: line) {
                guard let range = line.range(result.range(at: rule.group)) else { continue }
                found.append(TextMatch(
                    range: TokenBounds.widen(range, in: line),
                    label: rule.label, category: .secret, detector: .apiKeys
                ))
            }
        }
        return found
    }

    static func privateKeyMatches(in line: String) -> [TextMatch] {
        privateKeyHeader.matches(in: line).compactMap { result in
            guard let range = line.range(result.range) else { return nil }
            return TextMatch(range: range, label: "Private key", category: .secret, detector: .privateKeys)
        }
    }

    static func isPrivateKeyHeader(_ line: String) -> Bool {
        privateKeyHeader.firstMatch(in: line) != nil
    }

    static func isPrivateKeyFooter(_ line: String) -> Bool {
        privateKeyFooter.firstMatch(in: line) != nil
    }
}

// MARK: - Credentials in context

nonisolated enum CredentialRules {
    /// The words that make the value after them a secret.
    static let keywordAlternatives =
        #"passwd|password|passphrase|passcode|pass|pwd|secret|token|api[_\- ]?key|apikey|access[_\- ]?key|auth[_\- ]?key|private[_\- ]?key|client[_\- ]?secret|credentials?|session[_\- ]?(?:id|key|token)|cookie|signing[_\- ]?key|encryption[_\- ]?key|master[_\- ]?key|license[_\- ]?key"#

    /// `name = value`, `name: value`, `"name": "value"`, `name => value`.
    /// Groups: 1 the whole name, 2 its keyword, 3 the opening quote, 4 the value.
    static let keyValue = Pattern(
        #"(?i)(?<![A-Za-z0-9])([A-Za-z0-9_.\-]*?("# + keywordAlternatives + #")[A-Za-z0-9_.\-]*)["']?\s*(?:=>|:=|[:=])\s*(["'`]?)([^\s"'`,;&]+)"#
    )

    /// A cell that ends with a keyword (a table or form label), for pairing
    /// with the next cell on the same row.
    static let trailingKeyword = Pattern(
        #"(?i)(?<![A-Za-z0-9])([A-Za-z0-9_.\-]*?("# + keywordAlternatives + #")[A-Za-z0-9_.\-]*)["']?\s*[:=]?\s*$"#
    )

    static let authorization = Pattern(
        #"(?i)\b(?:proxy-)?authorization["']?\s*[:=]\s*["']?(?:bearer|basic|token|digest|negotiate|apikey|sso-key)?\s*([A-Za-z0-9_\-.=+/~]{8,})"#
    )
    static let bearer = Pattern(#"(?i)\bbearer\s+([A-Za-z0-9_\-.=+/~]{12,})"#)
    static let urlUserInfo = Pattern(#"(?i)\b[a-z][a-z0-9+.\-]{1,15}://([^\s:/@]+:[^\s/@]+)@"#)
    static let urlQuery = Pattern(
        #"(?i)[?&;](?:access_?token|refresh_?token|id_?token|auth_?token|token|api_?key|apikey|key|secret|client_?secret|sig|signature|password|passwd|pwd|auth|code|session|session_?id|sid|x-amz-signature|x-amz-credential|x-amz-security-token|x-goog-signature|x-goog-credential)=([^&\s#"'<>]{4,})"#
    )
    static let cliFlag = Pattern(
        #"(?i)(?<![A-Za-z0-9])--?(?:password|passwd|pass|token|secret|api-?key|auth-?token|access-?key|client-?secret)\s+(?!-)["']?([^\s"']{3,})"#
    )

    /// Values that are types, keywords or placeholders, not secrets.
    static let nonSecretValues: Set<String> = [
        "string", "str", "number", "int", "integer", "int32", "int64", "uint", "float", "double", "bool", "boolean",
        "any", "object", "none", "null", "nil", "undefined", "true", "false", "yes", "no", "on", "off",
        "required", "optional", "data", "bytes", "text", "varchar", "char", "secret", "password", "token",
        "value", "hidden", "redacted", "empty", "unknown", "self", "this", "new", "void", "unset",
        "securestring", "secretstr", "secretstring", "nsstring", "uuid", "url", "date", "list", "dict", "map",
        "array", "set", "enum", "struct", "class", "type", "default", "env", "process.env", "os.environ",
    ]

    static let dottedIdentifier = Pattern(#"^[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)+$"#)
    /// "SecureString", "AccessToken2": a type name, not a value. Its humps
    /// are real words, unlike a key that happens to start with capitals.
    static let typeLikeIdentifier = Pattern(#"^[A-Z][a-z]+(?:[A-Z][a-z]+)+\d{0,2}[?!]?$"#)
    static let envReference = Pattern(#"^\$\{?[A-Za-z_][A-Za-z0-9_]*\}?$"#)

    static func matches(in line: String) -> [TextMatch] {
        var found: [TextMatch] = []
        func add(_ nsRange: NSRange, label: String) {
            guard let range = line.range(nsRange), !range.isEmpty else { return }
            found.append(TextMatch(range: range, label: label, category: .secret, detector: .credentials))
        }

        for result in keyValue.matches(in: line) {
            guard let nameRange = line.range(result.range(at: 1)),
                  let keywordRange = line.range(result.range(at: 2)),
                  let valueRange = line.range(result.range(at: 4))
            else { continue }
            let quoted = result.range(at: 3).length > 0
            let trimmed = trimValue(valueRange, in: line)
            guard !trimmed.isEmpty else { continue }
            let name = String(line[nameRange])
            let keyword = String(line[keywordRange])
            if acceptsValue(String(line[trimmed]), keyword: keyword, name: name, quoted: quoted) {
                add(NSRange(trimmed, in: line), label: label(forKeyword: keyword))
            }
        }
        for result in authorization.matches(in: line) {
            add(result.range(at: 1), label: "Authorization token")
        }
        for result in bearer.matches(in: line) {
            add(result.range(at: 1), label: "Bearer token")
        }
        for result in urlUserInfo.matches(in: line) {
            add(result.range(at: 1), label: "URL credentials")
        }
        for result in urlQuery.matches(in: line) {
            add(result.range(at: 1), label: "Secret in URL")
        }
        for result in cliFlag.matches(in: line) {
            add(result.range(at: 1), label: "Password")
        }
        return found
    }

    /// For a row split into cells: if `label` ends with a keyword, the first
    /// token of `next` is the secret ("Password | hunter2").
    static func pairedValue(label: String, next: String) -> Range<String.Index>? {
        guard let result = trailingKeyword.firstMatch(in: label),
              let keywordRange = label.range(result.range(at: 2)),
              let nameRange = label.range(result.range(at: 1))
        else { return nil }
        let keyword = String(label[keywordRange])
        let name = String(label[nameRange])
        guard let first = next.firstToken() else { return nil }
        var token = first
        var quoted = false
        if let start = next[token].first, "\"'`".contains(start) {
            quoted = true
            token = next.index(after: token.lowerBound)..<token.upperBound
        }
        let trimmed = trimValue(token, in: next)
        guard !trimmed.isEmpty,
              acceptsValue(String(next[trimmed]), keyword: keyword, name: name, quoted: quoted)
        else { return nil }
        return trimmed
    }

    static func label(forKeyword keyword: String) -> String {
        let lower = keyword.lowercased()
        if lower.hasPrefix("pass") || lower == "pwd" { return "Password" }
        if lower.contains("cookie") || lower.contains("session") { return "Session secret" }
        if lower.contains("token") { return "Token" }
        if lower.contains("key") { return "Key" }
        return "Secret"
    }

    /// Decides whether `value`, written after `keyword`, is a secret worth covering.
    static func acceptsValue(_ rawValue: String, keyword: String, name: String, quoted: Bool) -> Bool {
        let keyword = keyword.lowercased()
        let name = name.lowercased()
        let isPasswordWord = keyword.hasPrefix("pass") || keyword == "pwd"

        // A bare "pass" must be the whole name or end it after a separator
        // ("db_pass"), so "bypass" and "passed" don't count.
        if keyword == "pass" {
            guard name.hasSuffix("pass"), name == "pass" || name.dropLast(4).last.map({ !$0.isLetter }) == true else { return false }
        }

        var value = rawValue
        while let last = value.last, "?!".contains(last) { value.removeLast() }
        guard !value.isEmpty else { return false }
        let lower = value.lowercased()

        if nonSecretValues.contains(lower) { return false }
        // Already masked: ******** or ••••
        if value.allSatisfy({ "*•●·x.#-_".contains($0) }) { return false }
        if value.hasPrefix("<") || value.hasPrefix("{{") || value.hasPrefix("%") || value.hasPrefix("[") { return false }
        if envReference.isFullMatch(value) { return false }
        if !quoted {
            if value.contains("(") || value.contains(")") { return false }
            if dottedIdentifier.isFullMatch(value) { return false }
            if typeLikeIdentifier.isFullMatch(rawValue), RandomStrings.wordLetterShare(value) >= 0.6 { return false }
        }

        let isAllDigits = value.allSatisfy(\.isNumber)
        if isPasswordWord {
            return value.count >= 3
        }
        if isAllDigits, value.count <= 6 { return false }
        if quoted {
            return value.count >= 6
        }
        return looksLikeSecretValue(value)
    }

    /// At least 8 characters with a digit, mixed case or a symbol: random
    /// enough to be a key, unlike "expires" or "enabled".
    static func looksLikeSecretValue(_ value: String) -> Bool {
        guard value.count >= 8 else { return false }
        let hasDigit = value.contains(where: \.isNumber)
        let hasUpper = value.contains(where: \.isUppercase)
        let hasLower = value.contains(where: \.isLowercase)
        let hasSymbol = value.contains(where: { "_-+/=.~$!@#%^&*".contains($0) })
        return hasDigit || (hasUpper && hasLower) || hasSymbol
    }

    /// Drops closing punctuation that belongs to the sentence or the code.
    static func trimValue(_ range: Range<String.Index>, in line: String) -> Range<String.Index> {
        var upper = range.upperBound
        while upper > range.lowerBound {
            let previous = line.index(before: upper)
            guard ")]}>.,;:\"'`".contains(line[previous]) else { break }
            upper = previous
        }
        return range.lowerBound..<upper
    }
}

// MARK: - Token bounds

nonisolated enum TokenBounds {
    /// Characters that end a token when widening backwards.
    private static let backwardStops: Set<Character> = ["\"", "'", "`", "(", "[", "{", "<", ",", ";", "=", ":", "|", ">", "&", "?"]
    /// Characters that end a token when widening forwards ('=' is base64 padding, so it stays).
    private static let forwardStops: Set<Character> = ["\"", "'", "`", ")", "]", "}", ">", ",", ";", ":", "|", "<", "&", "#", "?"]

    /// Grows `range` to the whole token it sits in, so a partly recognised
    /// secret is still covered from end to end.
    static func widen(_ range: Range<String.Index>, in line: String) -> Range<String.Index> {
        var lower = range.lowerBound
        while lower > line.startIndex {
            let previous = line.index(before: lower)
            let character = line[previous]
            if character.isWhitespace || backwardStops.contains(character) { break }
            lower = previous
        }
        var upper = range.upperBound
        while upper < line.endIndex {
            let character = line[upper]
            if character.isWhitespace || forwardStops.contains(character) { break }
            upper = line.index(after: upper)
        }
        return lower..<upper
    }
}

extension String {
    /// The range of the first run of non-whitespace characters.
    nonisolated func firstToken() -> Range<String.Index>? {
        guard let start = firstIndex(where: { !$0.isWhitespace }) else { return nil }
        let end = self[start...].firstIndex(where: \.isWhitespace) ?? endIndex
        return start..<end
    }
}
