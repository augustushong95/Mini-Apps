import AppKit
import CoreGraphics
import CoreText

/// Fake screenshots drawn in code: the onboarding sample, the App Review
/// demo and the test fixtures. Every planted secret records exactly which
/// pixels its glyphs use, so tests can prove each one is fully covered.
///
/// All "secrets" here are made up. Token-shaped ones are assembled from
/// pieces so no complete token appears in the source.
nonisolated struct SampleScreenshot: @unchecked Sendable {
    struct Planted: Sendable {
        let text: String
        /// Where the text was drawn, in image pixels (top-left origin).
        let rect: CGRect
        /// Every pixel the glyphs touch, packed as `x << 16 | y`.
        let ink: [UInt32]
    }

    let image: CGImage
    let planted: [Planted]
    let fixture: Fixture
    let style: Style

    enum Fixture: String, CaseIterable, Sendable {
        case terminal, codeEditor, chat, webForm, log, clean
        /// Long lines placed across where a 1× image is cut into tiles.
        case wide
    }

    enum Font: String, CaseIterable, Sendable {
        case sfMono, menlo, sfPro
    }

    struct Style: Sendable, CustomStringConvertible {
        var dark = false
        var font: Font = .sfMono
        var pointSize: CGFloat = 13
        var scale: CGFloat = 2
        /// Width of the canvas in points.
        var width: CGFloat = 860

        var description: String { "\(dark ? "dark" : "light") \(font.rawValue) \(Int(pointSize))pt @\(Int(scale))x" }
    }

    enum Role {
        case plain, dim, keyword, string, comment, prompt, title
    }

    struct Segment {
        var text: String
        var role: Role = .plain
        var secret = false
        /// Starts the segment at this x (points) instead of after the last one.
        var column: CGFloat?
    }

    /// - Parameter repeating: draws the content this many times, one copy
    ///   under the other, for large-image tests.
    static func render(_ fixture: Fixture, style: Style = Style(), repeating: Int = 1) -> SampleScreenshot {
        let lines = Array(repeating: content(for: fixture), count: max(1, repeating)).flatMap { $0 }
        return draw(lines: lines, fixture: fixture, style: style)
    }

    /// The sample shown in onboarding and on "Try with a sample": a chat and
    /// a terminal full of believable, made-up secrets.
    static func demo() -> SampleScreenshot {
        let lines = content(for: .chat) + [[Segment(text: " ")]] + content(for: .terminal).prefix(5)
        return draw(lines: Array(lines), fixture: .chat, style: Style(dark: false, font: .sfMono, pointSize: 13, scale: 2, width: 820))
    }

    // MARK: Content

    /// Made-up values, assembled so the source never holds a whole token.
    enum Fake {
        static let awsKeyID = "AKIA" + "IOSFODNN7" + "EXAMPLE"
        static let awsSecret = "kq3Rz7Vw" + "T2mXb9Lp" + "C5nYd8Hs" + "F1jGt4Qe" + "U6aKw0Zr"
        static let bearer = "tk_" + "9hW2qLx7" + "Pz4mRv8N" + "c3Jy6Bd1"
        static let openAI = "sk-proj-" + "Q7mZ2xRt" + "9LwV4nBc" + "8KpY3dHs"
        static let stripeWebhook = "whsec_" + "Mz4Qr8Tx" + "2Lv7Nc9B"
        static let github = "ghp_" + "R4tY8uI2" + "oP6aS9dF" + "1gH5jK3l" + "Z7xC0vB2"
        static let logToken = "q8Zr2LwT" + "9vKx4NpB" + "7sYd3HmF"
        static let password = "Tr0ub4dor" + "&3x"
        static let email = "jane.doe@example.com"
        static let shortEmail = "jane@example.com"
        static let phone = "+1 (415) 555-0132"
        static let card = "4242 4242 4242 4242"
        static let host = "build.corp.example.com"
        static let dbHost = "db.internal:5432"
        static let ip = "10.0.4.17"
        static let logIP = "10.1.2.3"
    }

    static func content(for fixture: Fixture) -> [[Segment]] {
        typealias S = Segment
        switch fixture {
        case .terminal:
            return [
                [S(text: "$ ", role: .prompt), S(text: "export AWS_ACCESS_KEY_ID="), S(text: Fake.awsKeyID, secret: true)],
                [S(text: "$ ", role: .prompt), S(text: "export AWS_SECRET_ACCESS_KEY="), S(text: Fake.awsSecret, secret: true)],
                [S(text: "$ ", role: .prompt), S(text: "curl -H \"Authorization: Bearer "), S(text: Fake.bearer, secret: true), S(text: "\" api.example.com")],
                [S(text: "$ ", role: .prompt), S(text: "ssh deploy@"), S(text: Fake.host, secret: true)],
                [S(text: "Connecting to "), S(text: Fake.ip, secret: true), S(text: " port 22…", role: .dim)],
                [S(text: "$ ", role: .prompt), S(text: "git log --oneline -2")],
                [S(text: "3f9a2c4 ", role: .dim), S(text: "Fix the login redirect")],
                [S(text: "8b7d6f1 ", role: .dim), S(text: "Bump version to 2.4.1")],
            ]
        case .codeEditor:
            return [
                [S(text: "let ", role: .keyword), S(text: "client = APIClient(")],
                [S(text: "    apiKey: "), S(text: "\"", role: .string), S(text: Fake.openAI, role: .string, secret: true), S(text: "\",", role: .string)],
                [S(text: "    webhookSecret: "), S(text: "\"", role: .string), S(text: Fake.stripeWebhook, role: .string, secret: true), S(text: "\",", role: .string)],
                [S(text: "    owner: "), S(text: "\"", role: .string), S(text: Fake.email, role: .string, secret: true), S(text: "\"", role: .string)],
                [S(text: ")")],
                [S(text: "// Rotate keys before the 2.4 release", role: .comment)],
                [S(text: "let ", role: .keyword), S(text: "timeout: TimeInterval = 30")],
            ]
        case .chat:
            return [
                [S(text: "Jane Cooper", role: .title), S(text: "   10:42 AM", role: .dim)],
                [S(text: "Here's the staging token: "), S(text: Fake.github, secret: true)],
                [S(text: "Call me at "), S(text: Fake.phone, secret: true), S(text: " if the deploy fails.")],
                [S(text: "Card on file: "), S(text: Fake.card, secret: true)],
                [S(text: "Thanks! Deploying now.")],
            ]
        case .webForm:
            return [
                [S(text: "Email", role: .dim), S(text: Fake.shortEmail, secret: true, column: 240)],
                [S(text: "Password", role: .dim), S(text: Fake.password, secret: true, column: 240)],
                [S(text: "Server", role: .dim), S(text: Fake.dbHost, secret: true, column: 240)],
                [S(text: "Region", role: .dim), S(text: "us-east-1", column: 240)],
                [S(text: "Customer", role: .dim), S(text: "Acme Corporation", column: 240)],
            ]
        case .log:
            return [
                [S(text: "2026-11-26 18:37:29.335 ", role: .dim), S(text: "INFO request_id=123e4567-e89b-12d3-a456-426614174000")],
                [S(text: "2026-11-26 18:37:29.512 ", role: .dim), S(text: "INFO user="), S(text: Fake.shortEmail, secret: true), S(text: " ip="), S(text: Fake.logIP, secret: true)],
                [S(text: "2026-11-26 18:37:30.004 ", role: .dim), S(text: "WARN retrying with token="), S(text: Fake.logToken, secret: true)],
                [S(text: "2026-11-26 18:37:30.230 ", role: .dim), S(text: "INFO GET /v1/orders?page=2 200 41ms")],
            ]
        case .wide:
            // At 1× a 2400 pt canvas is read in tiles 0–1280, 560–1840 and
            // 1120–2400 px; these lines run across those seams.
            return [
                [S(text: "2026-11-26 18:37:29.512 INFO checkout completed for user=", role: .dim, column: 820), S(text: Fake.shortEmail, secret: true), S(text: " from ip="), S(text: Fake.logIP, secret: true)],
                [S(text: "$ ", role: .prompt, column: 900), S(text: "export AWS_SECRET_ACCESS_KEY="), S(text: Fake.awsSecret, secret: true), S(text: "  # rotate monthly", role: .comment)],
                [S(text: "Here's the staging token, please keep it to yourself: ", column: 1000), S(text: Fake.github, secret: true)],
                [S(text: "Billing contact ", column: 1500), S(text: Fake.phone, secret: true), S(text: ", card "), S(text: Fake.card, secret: true)],
                [S(text: "Deploy finished on "), S(text: Fake.host, secret: true), S(text: " after 41 seconds with no errors reported by the health check.")],
            ]
        case .clean:
            return [
                [S(text: "import ", role: .keyword), S(text: "SwiftUI")],
                [S(text: "struct ", role: .keyword), S(text: "ContentView: View {")],
                [S(text: "    @State private var count = 0")],
                [S(text: "    var ", role: .keyword), S(text: "body: some View {")],
                [S(text: "        Button("), S(text: "\"Tapped \\(count) times\"", role: .string), S(text: ") { count += 1 }")],
                [S(text: "    }")],
                [S(text: "}")],
                [S(text: "commit 3f9a2c4e8b7d6f1a0e5c9b8a7d6e5f4a3b2c1d0e", role: .dim)],
                [S(text: "Date:   Thu Nov 26 18:37:29 2026 +0800", role: .dim)],
                [S(text: "    Fix layout on macOS 14.0 and 15.2")],
                [S(text: "Version 2.4.1 (build 241) · 1,234 downloads · $9.99")],
                [S(text: "See developer.apple.com/documentation/vision for details.")],
            ]
        }
    }

    // MARK: Drawing

    private struct Palette {
        let background, plain, dim, keyword, string, comment, prompt: CGColor

        init(dark: Bool) {
            func c(_ hex: UInt32) -> CGColor {
                CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
            }
            if dark {
                background = c(0x1E1F22); plain = c(0xE6E6E6); dim = c(0x8E8E93); keyword = c(0xFF7AB2)
                string = c(0xFC6A5D); comment = c(0x7F8C98); prompt = c(0x84D88A)
            } else {
                background = c(0xFFFFFF); plain = c(0x1D1D1F); dim = c(0x6E6E73); keyword = c(0xAD3DA4)
                string = c(0xC41A16); comment = c(0x6E7781); prompt = c(0x2E7D32)
            }
        }

        func color(_ role: Role) -> CGColor {
            switch role {
            case .plain, .title: plain
            case .dim: dim
            case .keyword: keyword
            case .string: string
            case .comment: comment
            case .prompt: prompt
            }
        }
    }

    private static func font(_ font: Font, size: CGFloat, bold: Bool = false) -> CTFont {
        switch font {
        case .sfMono: NSFont.monospacedSystemFont(ofSize: size, weight: bold ? .semibold : .regular) as CTFont
        case .menlo: CTFontCreateWithName((bold ? "Menlo-Bold" : "Menlo-Regular") as CFString, size, nil)
        case .sfPro: NSFont.systemFont(ofSize: size, weight: bold ? .semibold : .regular) as CTFont
        }
    }

    private static func draw(lines: [[Segment]], fixture: Fixture, style: Style) -> SampleScreenshot {
        let scale = style.scale
        let size = style.pointSize * scale
        let regular = font(style.font, size: size)
        let bold = font(style.font, size: size, bold: true)
        let ascent = CTFontGetAscent(regular), descent = CTFontGetDescent(regular)
        let lineHeight = ceil((ascent + descent) * 1.5)
        let margin = ceil(24 * scale)
        let width = Int(ceil(style.width * scale))
        let height = Int(margin * 2 + lineHeight * CGFloat(lines.count))
        let palette = Palette(dark: style.dark)

        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(palette.background)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setShouldAntialias(true)
        context.setShouldSmoothFonts(false)

        var planted: [Planted] = []
        for (index, line) in lines.enumerated() {
            let baseline = margin + CGFloat(index) * lineHeight + ascent
            var x = margin
            for segment in line {
                if let column = segment.column { x = margin + column * scale }
                let attributes: [NSAttributedString.Key: Any] = [
                    NSAttributedString.Key(kCTFontAttributeName as String): segment.role == .title ? bold : regular,
                    NSAttributedString.Key(kCTForegroundColorAttributeName as String): palette.color(segment.role),
                ]
                let ctLine = CTLineCreateWithAttributedString(NSAttributedString(string: segment.text, attributes: attributes))
                let advance = CGFloat(CTLineGetTypographicBounds(ctLine, nil, nil, nil))
                context.textPosition = CGPoint(x: x, y: CGFloat(height) - baseline)
                CTLineDraw(ctLine, context)
                if segment.secret {
                    let rect = CGRect(x: x, y: baseline - ascent, width: advance, height: ascent + descent)
                    planted.append(Planted(text: segment.text, rect: rect, ink: ink(of: ctLine, at: CGPoint(x: x, y: baseline), ascent: ascent, descent: descent, imageSize: CGSize(width: width, height: height))))
                }
                x += advance
            }
        }
        return SampleScreenshot(image: context.makeImage()!, planted: planted, fixture: fixture, style: style)
    }

    /// The pixels `line` touches when drawn with its baseline at `origin`
    /// (top-left image coordinates): drawn alone into an alpha mask.
    private static func ink(of line: CTLine, at origin: CGPoint, ascent: CGFloat, descent: CGFloat, imageSize: CGSize) -> [UInt32] {
        let glyphBounds = CTLineGetImageBounds(line, nil)
        let pad: CGFloat = 4
        let regionX = floor(origin.x + glyphBounds.minX - pad)
        let regionTop = floor(origin.y - max(ascent, glyphBounds.maxY) - pad)
        let regionWidth = Int(ceil(glyphBounds.width + pad * 2 + 2))
        let regionHeight = Int(ceil(max(ascent, glyphBounds.maxY) + max(descent, -glyphBounds.minY) + pad * 2 + 2))
        guard regionWidth > 0, regionHeight > 0,
              let mask = CGContext(data: nil, width: regionWidth, height: regionHeight, bitsPerComponent: 8, bytesPerRow: regionWidth,
                                   space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return [] }
        mask.setFillColor(gray: 0, alpha: 1)
        mask.fill(CGRect(x: 0, y: 0, width: regionWidth, height: regionHeight))
        mask.setShouldAntialias(true)
        mask.setShouldSmoothFonts(false)
        // Draw white text on black: the gray value is the glyph coverage.
        let runs = CTLineGetGlyphRuns(line) as? [CTRun] ?? []
        let baselineInMask = CGFloat(regionHeight) - (origin.y - regionTop)
        for run in runs {
            let count = CTRunGetGlyphCount(run)
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
            let attributes = CTRunGetAttributes(run) as NSDictionary
            guard let runFontValue = attributes[kCTFontAttributeName], CFGetTypeID(runFontValue as CFTypeRef) == CTFontGetTypeID() else { continue }
            let runFont = runFontValue as! CTFont
            let shifted = positions.map { CGPoint(x: $0.x + origin.x - regionX, y: baselineInMask + $0.y) }
            mask.setFillColor(gray: 1, alpha: 1)
            CTFontDrawGlyphs(runFont, glyphs, shifted, count, mask)
        }
        guard let data = mask.data else { return [] }
        let bytes = data.bindMemory(to: UInt8.self, capacity: regionWidth * regionHeight)
        var ink: [UInt32] = []
        for row in 0..<regionHeight {
            for column in 0..<regionWidth where bytes[row * regionWidth + column] >= 32 {
                let x = Int(regionX) + column
                let y = Int(regionTop) + row
                guard x >= 0, y >= 0, x < Int(imageSize.width), y < Int(imageSize.height) else { continue }
                ink.append(UInt32(x) << 16 | UInt32(y))
            }
        }
        return ink
    }
}
