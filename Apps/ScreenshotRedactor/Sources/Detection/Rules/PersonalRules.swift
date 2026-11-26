import Foundation

/// Emails, phone numbers and payment card numbers.
nonisolated enum PersonalRules {
    // MARK: Email

    /// Practical email shape, also accepting the "(at)" and "[at]" spellings.
    static let email = Pattern(
        #"(?<![A-Za-z0-9._%+\-])[A-Za-z0-9](?:[A-Za-z0-9._%+\-]*[A-Za-z0-9_%+\-])?(?:@|\s?[\(\[]at[\)\]]\s?)(?:[A-Za-z0-9](?:[A-Za-z0-9\-]*[A-Za-z0-9])?\.)+[A-Za-z]{2,24}(?![A-Za-z0-9\-])"#,
        caseInsensitive: true
    )

    /// Asset names such as "icon@2x.png" have an email's shape.
    private static let fileExtensionEndings: Set<String> = [
        "png", "jpg", "jpeg", "gif", "svg", "pdf", "webp", "heic", "tif", "tiff", "bmp", "ico", "icns",
        "json", "js", "ts", "css", "html", "txt", "md", "swift", "py", "rb", "zip", "mov", "mp4",
    ]

    static func emailMatches(in line: String) -> [TextMatch] {
        email.matches(in: line).compactMap { result in
            guard let range = line.range(result.range) else { return nil }
            let ending = line[range].split(separator: ".").last.map { $0.lowercased() } ?? ""
            guard !fileExtensionEndings.contains(ending) else { return nil }
            return TextMatch(range: range, label: "Email", category: .personal, detector: .emails)
        }
    }

    // MARK: Phone

    private static let phoneDetector: DataDetector = DataDetector(types: .phoneNumber)
    private static let datePattern = Pattern(#"^(?:\d{4}[-/.]\d{1,2}[-/.]\d{1,2}|\d{1,2}[-/.]\d{1,2}[-/.]\d{2,4})(?:[ T]\d{1,2}:\d{2}(?::\d{2})?)?$"#)
    private static let timePattern = Pattern(#"\d{1,2}:\d{2}"#)
    private static let dottedPhone = Pattern(#"^\+?\d{0,3}[ .]?\(?\d{3}\)?\.\d{3}\.\d{4}$"#)
    private static let versionContext = Pattern(#"(?i)(?:\bv|version|build|release|ver\.?)\s*$"#)

    /// Phone numbers from `NSDataDetector`, checked one line at a time.
    /// Dates, times, versions and bare digit runs (timestamps, IDs) are dropped.
    static func phoneMatches(in line: String) -> [TextMatch] {
        phoneDetector.matches(in: line).compactMap { result in
            guard let range = line.range(result.range) else { return nil }
            let text = String(line[range]).trimmingCharacters(in: .whitespaces)
            let digits = text.filter(\.isNumber)
            guard (7...15).contains(digits.count) else { return nil }
            if datePattern.isFullMatch(text) || timePattern.firstMatch(in: text) != nil { return nil }
            if text.contains("."), !dottedPhone.isFullMatch(text) { return nil }
            let before = String(line[line.startIndex..<range.lowerBound])
            if versionContext.firstMatch(in: before) != nil { return nil }
            let hasSeparator = text.contains(where: { " -().+/".contains($0) })
            if !hasSeparator && !isPlausibleBareNumber(digits) { return nil }
            return TextMatch(range: range, label: "Phone number", category: .personal, detector: .phoneNumbers)
        }
    }

    /// A phone number written without any separator. Only a North American
    /// ten-digit number is believable; anything else is more likely a
    /// timestamp or an ID.
    static func isPlausibleBareNumber(_ digits: String) -> Bool {
        let values = digits.compactMap(\.wholeNumberValue)
        guard values.count == 10 else { return false }
        return values[0] >= 2 && values[3] >= 2
    }

    // MARK: Cards

    /// 13–19 digits with optional single spaces or dashes. OCR look-alikes
    /// (O, I, l, |, S, B) are allowed and checked below.
    private static let cardCandidate = Pattern(#"(?<![0-9A-Za-z])(?:[0-9OIlSB|][ \-]?){12,18}[0-9OIlSB|](?![0-9A-Za-z])"#)
    private static let groupedSixteen = Pattern(#"^\d{4}([ \-])\d{4}\1\d{4}\1\d{4}$"#)
    private static let groupedAmex = Pattern(#"^\d{4}([ \-])\d{6}\1\d{5}$"#)

    static func cardMatches(in line: String) -> [TextMatch] {
        cardCandidate.matches(in: line).compactMap { result in
            guard let range = line.range(result.range) else { return nil }
            let raw = String(line[range])
            guard let mapped = CardNumber.mapLookAlikes(raw) else { return nil }
            let digits = mapped.filter(\.isNumber)
            guard CardNumber.isCard(digits: digits, formatted: mapped) else { return nil }
            return TextMatch(range: range, label: "Card number", category: .personal, detector: .cardNumbers)
        }
    }

    enum CardNumber {
        /// Replaces OCR look-alikes with digits, or returns nil when the text
        /// has too few real digits or too many look-alikes to be a number.
        static func mapLookAlikes(_ text: String) -> String? {
            var lookAlikes = 0
            var realDigits = 0
            let mapped = String(text.map { character -> Character in
                switch character {
                case "O": lookAlikes += 1; return "0"
                case "I", "l", "|": lookAlikes += 1; return "1"
                case "S": lookAlikes += 1; return "5"
                case "B": lookAlikes += 1; return "8"
                default:
                    if character.isNumber { realDigits += 1 }
                    return character
                }
            })
            guard realDigits >= 11, lookAlikes <= 2 else { return nil }
            return mapped
        }

        static func isCard(digits: String, formatted: String) -> Bool {
            guard (13...19).contains(digits.count), let network = network(for: digits) else { return false }
            guard network.lengths.contains(digits.count) else { return false }
            if luhnIsValid(digits) { return true }
            // OCR can misread one digit and break the checksum; a number laid
            // out like a card with a real card prefix is still covered.
            if network.name == "Amex" { return groupedAmex.isFullMatch(formatted) }
            return groupedSixteen.isFullMatch(formatted)
        }

        struct Network {
            let name: String
            let lengths: ClosedRange<Int>
        }

        static func network(for digits: String) -> Network? {
            let values = digits.compactMap(\.wholeNumberValue)
            guard values.count >= 6 else { return nil }
            func prefix(_ count: Int) -> Int { values.prefix(count).reduce(0) { $0 * 10 + $1 } }
            let p1 = prefix(1), p2 = prefix(2), p3 = prefix(3), p4 = prefix(4), p6 = prefix(6)
            if p1 == 4 { return Network(name: "Visa", lengths: 13...19) }
            if (51...55).contains(p2) || (2221...2720).contains(p4) { return Network(name: "Mastercard", lengths: 16...16) }
            if p2 == 34 || p2 == 37 { return Network(name: "Amex", lengths: 15...15) }
            if p4 == 6011 || p2 == 65 || (644...649).contains(p3) || (622126...622925).contains(p6) {
                return Network(name: "Discover", lengths: 16...19)
            }
            if (3528...3589).contains(p4) { return Network(name: "JCB", lengths: 16...19) }
            if (300...305).contains(p3) || p2 == 36 || p2 == 38 || p2 == 39 { return Network(name: "Diners", lengths: 14...19) }
            if p2 == 62 { return Network(name: "UnionPay", lengths: 16...19) }
            if (2200...2204).contains(p4) { return Network(name: "Mir", lengths: 16...19) }
            if [5018, 5020, 5038, 5893, 6304, 6759, 6761, 6762, 6763].contains(p4) {
                return Network(name: "Maestro", lengths: 12...19)
            }
            return nil
        }

        static func luhnIsValid(_ digits: String) -> Bool {
            let values = digits.compactMap(\.wholeNumberValue)
            guard values.count == digits.count, !values.isEmpty else { return false }
            var sum = 0
            for (offset, value) in values.reversed().enumerated() {
                if offset % 2 == 1 {
                    let doubled = value * 2
                    sum += doubled > 9 ? doubled - 9 : doubled
                } else {
                    sum += value
                }
            }
            return sum % 10 == 0
        }
    }
}

/// `NSDataDetector` wrapped for sharing across threads (it is immutable and
/// thread-safe, like `NSRegularExpression`).
nonisolated struct DataDetector: @unchecked Sendable {
    let detector: NSDataDetector

    init(types: NSTextCheckingResult.CheckingType) {
        do {
            detector = try NSDataDetector(types: types.rawValue)
        } catch {
            preconditionFailure("NSDataDetector unavailable: \(error)")
        }
    }

    func matches(in text: String) -> [NSTextCheckingResult] {
        detector.matches(in: text, range: text.fullNSRange)
    }
}
