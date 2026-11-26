import Foundation
import Testing
@testable import ScreenshotRedactor

/// The text rules, line by line. Each table lists lines and exactly what
/// must be covered in them; the negative tables list lines where nothing
/// may be covered. Token-shaped test values are assembled from pieces so
/// the repository never contains a string a secret scanner would flag.
@Suite nonisolated struct RuleTests {
    private func covered(_ line: String, _ detectors: Set<Detector> = Set(Detector.allCases), rules: [CustomRule] = []) -> [String] {
        TextRules(settings: DetectionSettings(enabled: detectors, customRules: rules))
            .matches(in: line)
            .map { String(line[$0.range]) }
    }

    private func labels(_ line: String) -> [String] {
        TextRules(settings: DetectionSettings()).matches(in: line).map(\.label)
    }

    // MARK: Provider tokens

    static let tokenCases: [(line: String, covered: String, label: String)] = [
        ("export AWS_ACCESS_KEY_ID=" + "AKIA" + "IOSFODNN7EXAMPLE", "AKIA" + "IOSFODNN7EXAMPLE", "AWS access key"),
        ("key id AK1A" + "IOSFODNN7EXAMPLE (as OCR read it)", "AK1A" + "IOSFODNN7EXAMPLE", "AWS access key"),
        ("const key = \"AIza" + "SyD-9tSrke72PouQMnMX-a7eZSW0jkFMBWY\";", "AIza" + "SyD-9tSrke72PouQMnMX-a7eZSW0jkFMBWY", "Google API key"),
        ("token ghp_" + "1A2b3C4d5E6f7G8h9I0jK1L2m3N4o5P6q7R8", "ghp_" + "1A2b3C4d5E6f7G8h9I0jK1L2m3N4o5P6q7R8", "GitHub token"),
        ("github_pat_" + "11ABCDEFG0123456789_abcdefghijklmnopqrstuvwxyzABCDEF", "github_pat_" + "11ABCDEFG0123456789_abcdefghijklmnopqrstuvwxyzABCDEF", "GitHub token"),
        ("SLACK=xoxb-" + "123456789012-1234567890123-AbCdEfGhIjKlMnOpQrStUvWx", "xoxb-" + "123456789012-1234567890123-AbCdEfGhIjKlMnOpQrStUvWx", "Slack token"),
        ("stripe.api_key = 'sk_" + "live_" + "51H8xYzABCDEFGHIJKLMNOPQRSTuvwxyz0123'", "sk_" + "live_" + "51H8xYzABCDEFGHIJKLMNOPQRSTuvwxyz0123", "Stripe key"),
        ("ANTHROPIC_API_KEY=sk-ant-" + "api03-AbCdEfGhIjKlMnOpQrStUvWxYz0123456789", "sk-ant-" + "api03-AbCdEfGhIjKlMnOpQrStUvWxYz0123456789", "Anthropic key"),
        ("openai key: sk-proj-" + "AbCdEfGhIjKlMnOpQrStUvWxYz012345", "sk-proj-" + "AbCdEfGhIjKlMnOpQrStUvWxYz012345", "OpenAI key"),
        ("npm_" + "aBcD1234eFgH5678iJkL9012mNoP3456qRsT", "npm_" + "aBcD1234eFgH5678iJkL9012mNoP3456qRsT", "npm token"),
        ("glpat-" + "xYz12AbC34dEf56GhI78", "glpat-" + "xYz12AbC34dEf56GhI78", "GitLab token"),
    ]

    @Test(arguments: tokenCases)
    func providerTokensAreCovered(_ testCase: (line: String, covered: String, label: String)) {
        #expect(covered(testCase.line, [.apiKeys]) == [testCase.covered])
        #expect(labels(testCase.line).first == testCase.label)
    }

    @Test func slackWebhookPathIsCovered() {
        let path = "T00000000/B00000000/" + "XXXXXXXXXXXXXXXXXXXXXXXX"
        let line = "POST https://hooks.slack.com/services/" + path
        let found = covered(line, [.apiKeys])
        #expect(found.count == 1)
        #expect(found.first?.hasSuffix(path) == true)
    }

    @Test func jwtIsCoveredWholeAndInPart() {
        let jwt = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9" + ".eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIn0" + ".SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"
        #expect(covered("Authorization header: " + jwt, [.apiKeys]) == [jwt])
        // Cut off at the edge of the screenshot: still covered.
        let cut = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9"
        #expect(covered("id_token=" + cut, [.apiKeys]) == [cut])
    }

    @Test func privateKeyHeaderCoversTheRestOfTheLine() {
        let line = #""private_key": "-----BEGIN PRIVATE KEY-----\nMIIEvQIBADANBgkqhkiG9w0BAQEFAASC""#
        let found = covered(line, [.privateKeys])
        #expect(found.count == 1)
        #expect(found.first?.hasPrefix("-----BEGIN PRIVATE KEY") == true)
        #expect(found.first?.hasSuffix("AASC\"") == true)
        #expect(SecretRules.isPrivateKeyHeader("-----BEGIN OPENSSH PRIVATE KEY-----"))
        #expect(SecretRules.isPrivateKeyHeader("BEGIN RSA PRIVATE KEY"))
        #expect(SecretRules.isPrivateKeyFooter("-----END EC PRIVATE KEY-----"))
        #expect(!SecretRules.isPrivateKeyHeader("-----BEGIN PUBLIC KEY-----"))
        #expect(!SecretRules.isPrivateKeyHeader("-----BEGIN CERTIFICATE-----"))
    }

    // MARK: Credentials

    static let credentialCases: [(line: String, covered: String)] = [
        ("password=hunter2", "hunter2"),
        ("DB_PASSWORD: s3cr3t!", "s3cr3t!"),
        (#""apiKey": "abc123def456","#, "abc123def456"),
        ("GITHUB_TOKEN=abcdef1234567890", "abcdef1234567890"),
        ("client_secret = Xy9_pQ2-rS7tU", "Xy9_pQ2-rS7tU"),
        ("db_pass=correcthorse", "correcthorse"),
        ("Authorization: Bearer abc.def-ghi_jkl123456", "abc.def-ghi_jkl123456"),
        ("https://admin:pa55word@db.example.com/prod", "admin:pa55word"),
        ("GET /v1/items?api_key=AbC123xyz789&page=2", "AbC123xyz789"),
        ("mysql --password S3cretPass -h localhost", "S3cretPass"),
        ("password: sunshine", "sunshine"),
        ("Passcode: 482913", "482913"),
    ]

    @Test(arguments: credentialCases)
    func credentialsAreCovered(_ testCase: (line: String, covered: String)) {
        #expect(covered(testCase.line, [.credentials]) == [testCase.covered])
    }

    static let codeThatIsNotASecret: [String] = [
        "let token: String",
        "func login(password: String) -> Bool",
        "var password: String?",
        "max_tokens: 4096",
        "Token: expires in 3 days",
        "bypass = enabled",
        "passed: 12 tests",
        "password: ********",
        "token = getToken()",
        "apiKey = config.apiKey",
        "password: Password",
        "secret = process.env.SECRET",
        "TOKEN=${GITHUB_TOKEN}",
        "isSecret: true",
        "tokenizer = AutoTokenizer.from_pretrained(name)",
        "password: <your password>",
        "Forgot password?",
        "Enter your password to continue",
        "The secret to good coffee is patience.",
        "api_key: string (required)",
        "tokens: 1500",
    ]

    @Test(arguments: codeThatIsNotASecret)
    func codeAndProseAreLeftAlone(_ line: String) {
        #expect(covered(line, [.credentials]).isEmpty, "Covered something in: \(line)")
    }

    @Test func tableCellsPairAKeywordWithTheNextCell() {
        let next = "hunter2   (rotated monthly)"
        let range = CredentialRules.pairedValue(label: "Password", next: next)
        #expect(range.map { String(next[$0]) } == "hunter2")
        #expect(CredentialRules.pairedValue(label: "API key:", next: "AbCdEf123456") != nil)
        #expect(CredentialRules.pairedValue(label: "Token", next: "expires") == nil)
        #expect(CredentialRules.pairedValue(label: "Name", next: "hunter2") == nil)
    }

    // MARK: Personal

    static let emailCases: [(line: String, covered: String)] = [
        ("Contact jane.doe+qa@example.co.uk today", "jane.doe+qa@example.co.uk"),
        ("From: Bob <bob@acme.io>", "bob@acme.io"),
        ("write to jane(at)example.com", "jane(at)example.com"),
        ("support@corp.example.com.", "support@corp.example.com"),
    ]

    @Test(arguments: emailCases)
    func emailsAreCovered(_ testCase: (line: String, covered: String)) {
        #expect(covered(testCase.line, [.emails]) == [testCase.covered])
    }

    @Test(arguments: ["icon_16x16@2x.png", "@Published var name", "user@localhost", "Assets/logo@3x.jpg", "@MainActor"])
    func thingsThatLookLikeEmailsAreLeftAlone(_ line: String) {
        #expect(covered(line, [.emails]).isEmpty, "Covered something in: \(line)")
    }

    static let phoneCases: [(line: String, covered: String)] = [
        ("Call +1 (415) 555-0132 now", "+1 (415) 555-0132"),
        ("Mobile: 415-555-0132", "415-555-0132"),
        ("UK office +44 20 7946 0958", "+44 20 7946 0958"),
        ("tel 415.555.0132", "415.555.0132"),
        ("cell 4155550132", "4155550132"),
    ]

    @Test(arguments: phoneCases)
    func phoneNumbersAreCovered(_ testCase: (line: String, covered: String)) {
        #expect(covered(testCase.line, [.phoneNumbers]) == [testCase.covered])
    }

    @Test(arguments: [
        "Released 2026-11-26", "at 18:37:29", "Version 10.15.7", "ts=1732612345", "v1.2.3", "Total: $1,234.56",
        "Build 24A335", "macOS 14.0 (23A344)", "PID 48213", "Downloaded 1,048,576 bytes", "Error code -1009",
    ])
    func numbersThatArentPhonesAreLeftAlone(_ line: String) {
        #expect(covered(line, [.phoneNumbers]).isEmpty, "Covered something in: \(line)")
    }

    static let cardCases: [(line: String, covered: String)] = [
        ("Card: 4242 4242 4242 4242 exp 12/28", "4242 4242 4242 4242"),
        ("4111-1111-1111-1111", "4111-1111-1111-1111"),
        ("amex 378282246310005", "378282246310005"),
        ("MC 5555555555554444", "5555555555554444"),
        // One digit misread by OCR: the checksum fails, the layout still says card.
        ("4242 4242 4242 4241", "4242 4242 4242 4241"),
        // Look-alikes read instead of digits.
        ("4242 4242 4242 42O2", "4242 4242 4242 42O2"),
    ]

    @Test(arguments: cardCases)
    func cardNumbersAreCovered(_ testCase: (line: String, covered: String)) {
        #expect(covered(testCase.line, [.cardNumbers]) == [testCase.covered])
    }

    @Test(arguments: ["1234 5678 9012 3456", "Invoice 4242424242424241", "Tracking 1Z999AA10123456784", "ISBN 978-3-16-148410-0"])
    func numbersThatArentCardsAreLeftAlone(_ line: String) {
        #expect(covered(line, [.cardNumbers]).isEmpty, "Covered something in: \(line)")
    }

    @Test func luhn() {
        #expect(PersonalRules.CardNumber.luhnIsValid("4242424242424242"))
        #expect(PersonalRules.CardNumber.luhnIsValid("79927398713"))
        #expect(!PersonalRules.CardNumber.luhnIsValid("4242424242424241"))
        #expect(!PersonalRules.CardNumber.luhnIsValid(""))
    }

    // MARK: Internal

    static let internalCases: [(line: String, covered: String)] = [
        ("Connecting to 10.0.4.17:5432", "10.0.4.17:5432"),
        ("allow 192.168.1.0/24", "192.168.1.0/24"),
        ("inet6 fe80::1c2b:3aff:fe4d:12%en0", "fe80::1c2b:3aff:fe4d:12%en0"),
        ("host 2001:db8:85a3::8a2e:370:7334 up", "2001:db8:85a3::8a2e:370:7334"),
        ("ssh deploy@build.corp.example.com", "build.corp.example.com"),
        ("postgres://db.internal:5432/app", "db.internal:5432"),
        ("ip-10-0-1-23.ec2.internal", "ip-10-0-1-23.ec2.internal"),
        ("printer.local is offline", "printer.local"),
        ("Server at 8.8.4.4.", "8.8.4.4"),
    ]

    @Test(arguments: internalCases)
    func internalInfoIsCovered(_ testCase: (line: String, covered: String)) {
        #expect(covered(testCase.line, [.ipAddresses, .internalHosts]) == [testCase.covered])
    }

    @Test(arguments: [
        "macOS 14.0.1", "v1.2.3.4", "Version 1.0.0.1", "127.0.0.1", "listen 0.0.0.0", "at 12:30:45",
        "std::vector<int>", "ether aa:bb:cc:dd:ee:ff", "1.2.3.4.5", "example.com", "settings.local.json",
        "api.github.com", "01.02.03.04", "a::b", "Foo::Bar", "com.apple.metadata", "build 10.0.19045.3693",
    ])
    func versionsAndPublicNamesAreLeftAlone(_ line: String) {
        #expect(covered(line, [.ipAddresses, .internalHosts]).isEmpty, "Covered something in: \(line)")
    }

    // MARK: Random strings

    @Test(arguments: [
        "huG8GP38g4o5MNJAYKJ1",
        "UXXFWXLCpaNfhs0gCa05RFRu",
        "nzqw7wZyVGOeUvfJIssDj4PTTKtb2Txx",
        "DBfz5LJF3hBGZW3M4Fz6Hq2AK7EGHZbKoXi0d9TH",
        "g14j4oh348q9zt964z1msrac",
        "j375xmq536519csu3g26q2l14er5xgm0",
        "s5bla5kzFpfITtaO+rC8qLk1urN0XtzWbnXjgSTdd8PM=",
    ])
    func randomStringsAreCovered(_ token: String) {
        #expect(covered("value \(token) end", [.randomStrings]) == [token])
    }

    @Test(arguments: [
        "kCGImageSourceShouldCacheImmediately",
        "/Users/apple/Library/Developer/Xcode/DerivedData",
        "3f9a2c4e8b7d6f1a0e5c9b8a7d6e5f4a3b2c1d0e",
        "123e4567-e89b-12d3-a456-426614174000",
        "https://github.com/apple/swift-collections/blob/main/README.md",
        "SWIFT_DEFAULT_ACTOR_ISOLATION",
        "payments-worker-7d9f8b6c5d-x2k4j",
        "2026-11-26T18:37:29.335Z",
        "com.apple.metadata:kMDItemIsScreenCapture",
        "NSPrivacyAccessedAPICategoryUserDefaults",
        "supportedRecognitionLanguagesAndReturnError",
        "testOwningProUnlocksItAndARefundTakesItAway",
        "x86_64-apple-darwin23",
        "Apps/ScreenshotRedactor/Sources/Detection/Rules/RandomStrings.swift",
        "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAA",
        "--enable-experimental-feature=StrictConcurrency",
    ])
    func identifiersPathsAndHashesAreLeftAlone(_ token: String) {
        #expect(covered(token, [.randomStrings]).isEmpty, "Covered something in: \(token)")
    }

    // MARK: Custom rules

    @Test func domainRuleCoversSubdomainsAndEmails() {
        let rule = CustomRule(kind: .domain, value: "https://*.Corp.Acme.com/")
        #expect(covered("ssh build.corp.acme.com", [], rules: [rule]) == ["build.corp.acme.com"])
        #expect(covered("mail bob@corp.acme.com", [], rules: [rule]) == ["bob@corp.acme.com"])
        #expect(covered("visit acme.com or notcorp.acme.com", [], rules: [rule]).isEmpty)
    }

    @Test func phraseRuleIgnoresCaseAndAccentsButNeedsWholeWords() {
        let rule = CustomRule(kind: .phrase, value: "Project Falcon")
        #expect(covered("Roadmap for project falcon, Q3", [], rules: [rule]) == ["project falcon"])
        #expect(covered("Projéct Falcon kickoff", [], rules: [rule]) == ["Projéct Falcon"])
        #expect(covered("ProjectFalcon and Project Falconry", [], rules: [rule]).isEmpty)
    }

    @Test func patternRule() {
        let rule = CustomRule(kind: .pattern, value: #"CUST-\d{6}"#)
        #expect(covered("Customer CUST-004211 opened a ticket", [], rules: [rule]) == ["CUST-004211"])
        let disabled = CustomRule(kind: .pattern, value: #"CUST-\d{6}"#, isEnabled: false)
        #expect(covered("CUST-004211", [], rules: [disabled]).isEmpty)
    }

    @Test func invalidRulesCantBeSaved() {
        #expect(CustomRule.problem(kind: .pattern, value: "") != nil)
        #expect(CustomRule.problem(kind: .pattern, value: "(") != nil)
        #expect(CustomRule.problem(kind: .pattern, value: ".*") != nil)
        #expect(CustomRule.problem(kind: .pattern, value: #"\w+"#) != nil)
        #expect(CustomRule.problem(kind: .pattern, value: "(a+)+$") != nil)
        #expect(CustomRule.problem(kind: .pattern, value: #"(\w+\s?)+"#) != nil)
        #expect(CustomRule.problem(kind: .pattern, value: #"CUST-\d{6}"#) == nil)
        #expect(CustomRule.problem(kind: .domain, value: "not a domain") != nil)
        #expect(CustomRule.problem(kind: .domain, value: "corp.acme.com") == nil)
        #expect(CustomRule.problem(kind: .phrase, value: "x") != nil)
        #expect(CustomRule.normalizedDomain("https://*.Corp.Acme.com/path") == "corp.acme.com")
    }

    /// A pattern that slips past the save-time checks but backtracks
    /// exponentially must still give up quickly and be reported.
    @Test func runawayPatternIsStoppedAndReported() {
        let rule = CustomRule(kind: .pattern, value: "(a|aa)+$")
        #expect(CustomRule.problem(kind: rule.kind, value: rule.value) == nil)
        let rules = TextRules(settings: DetectionSettings(enabled: [], customRules: [rule]))
        let clock = CustomRuleClock()
        let line = String(repeating: "a", count: 36) + "b"
        let start = ContinuousClock.now
        _ = rules.matches(in: line, clock: clock)
        _ = rules.matches(in: line, clock: clock)
        #expect(ContinuousClock.now - start < .milliseconds(400))
        #expect(clock.timedOut.contains(rule.id))
    }

    // MARK: Merging

    @Test func overlappingMatchesBecomeOneLabelledByTheMostSensitive() {
        // Credentials, an email-shaped "pa55word@db.internal" and the host
        // all overlap: one box covers them, labelled as the secret it holds.
        let line = "postgres://admin:pa55word@db.internal:5432"
        let matches = TextRules(settings: DetectionSettings()).matches(in: line)
        #expect(matches.count == 1)
        #expect(matches.first?.category == .secret)
        #expect(matches.first.map { String(line[$0.range]) } == "admin:pa55word@db.internal:5432")
    }

    @Test func separateMatchesStaySeparate() {
        let line = "jane@example.com connected from 10.0.0.8"
        let found = covered(line)
        #expect(found == ["jane@example.com", "10.0.0.8"])
    }

    @Test func disabledDetectorsFindNothing() {
        let line = "jane@example.com 10.0.0.8 password=hunter2"
        #expect(covered(line, []).isEmpty)
    }

    @Test func emptyAndPlainLinesAreCheap() {
        #expect(covered("").isEmpty)
        #expect(covered("Hello, world! This is an ordinary sentence with nothing to hide.").isEmpty)
    }
}
