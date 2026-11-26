import CoreGraphics
import Foundation
import Testing
@testable import ScreenshotRedactor

/// Real Vision on generated screenshots. Each planted secret must have every
/// one of its ink pixels inside a covered box, and the clean fixture must
/// produce no boxes at all.
@Suite nonisolated struct ScannerIntegrationTests {
    static let styles: [SampleScreenshot.Style] = [
        .init(dark: false, font: .sfMono, pointSize: 12, scale: 2),
        .init(dark: true, font: .menlo, pointSize: 11, scale: 2),
        .init(dark: false, font: .sfPro, pointSize: 13, scale: 2),
        .init(dark: true, font: .sfMono, pointSize: 14, scale: 1),
        .init(dark: false, font: .sfPro, pointSize: 13, scale: 1),
    ]

    static let fixtures: [SampleScreenshot.Fixture] = [.terminal, .codeEditor, .chat, .webForm, .log]

    private func scan(_ sample: SampleScreenshot) async throws -> ScanResult {
        try await RedactionScanner.scan(sample.image, dpi: 72 * sample.style.scale, settings: DetectionSettings(), includeCustomRules: false)
    }

    /// Ink pixels of `planted` that no covered box contains.
    private func uncoveredInk(_ planted: SampleScreenshot.Planted, boxes: [RedactionBox]) -> [CGPoint] {
        let covered = boxes.filter(\.isCovered).map(\.rect)
        return planted.ink.compactMap { packed in
            let point = CGPoint(x: CGFloat(packed >> 16) + 0.5, y: CGFloat(packed & 0xFFFF) + 0.5)
            return covered.contains { $0.contains(point) } ? nil : point
        }
    }

    @Test(arguments: fixtures, styles)
    func everyPlantedSecretIsFullyCovered(_ fixture: SampleScreenshot.Fixture, _ style: SampleScreenshot.Style) async throws {
        let sample = SampleScreenshot.render(fixture, style: style)
        let result = try await scan(sample)
        for planted in sample.planted {
            #expect(!planted.ink.isEmpty)
            let missed = uncoveredInk(planted, boxes: result.boxes)
            #expect(missed.isEmpty, """
                \(fixture) \(style): "\(planted.text)" has \(missed.count) of \(planted.ink.count) ink pixels uncovered, \
                e.g. \(missed.prefix(3).map { "(\(Int($0.x)),\(Int($0.y)))" }.joined(separator: " ")); \
                text at \(planted.rect.integral); boxes: \(result.boxes.map { "\($0.label) \($0.rect)" })
                """)
        }
    }

    /// "export AWS_ACCESS_KEY_ID=AKIA…": the key is covered, the variable
    /// name stays readable. The box may start up to three characters early:
    /// inside a word, the app errs towards covering too much.
    @Test(arguments: styles)
    func variableNamesStayReadable(_ style: SampleScreenshot.Style) async throws {
        let sample = SampleScreenshot.render(.terminal, style: style)
        let result = try await scan(sample)
        for planted in sample.planted where planted.text == SampleScreenshot.Fake.awsKeyID || planted.text == SampleScreenshot.Fake.awsSecret {
            let characterWidth = planted.rect.width / CGFloat(planted.text.count)
            // The box that covers this key (padded boxes on the next line also touch it).
            let box = try #require(result.boxes.max { overlap($0.rect, planted.rect) < overlap($1.rect, planted.rect) })
            #expect(box.rect.minX >= planted.rect.minX - 3 * characterWidth,
                    "\(style): box starts \(Int((planted.rect.minX - box.rect.minX) / characterWidth)) characters before the key")
        }
    }

    private func overlap(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let intersection = a.intersection(b)
        return intersection.isNull ? 0 : intersection.width * intersection.height
    }

    @Test(arguments: styles)
    func theCleanFixtureProducesNoBoxes(_ style: SampleScreenshot.Style) async throws {
        let sample = SampleScreenshot.render(.clean, style: style)
        let result = try await scan(sample)
        #expect(result.boxes.isEmpty, "\(style): \(result.boxes.map { "\($0.label) at \($0.rect)" })")
        #expect(result.lineCount >= 10, "Vision should read the clean fixture's lines")
    }

    @Test func theDemoSampleIsFullyCovered() async throws {
        let sample = SampleScreenshot.demo()
        let result = try await scan(sample)
        #expect(sample.planted.count >= 6)
        for planted in sample.planted {
            #expect(uncoveredInk(planted, boxes: result.boxes).isEmpty, "\(planted.text)")
        }
    }

    @Test func disabledDetectorsLeaveTheirTextAlone() async throws {
        let sample = SampleScreenshot.render(.chat)
        var settings = DetectionSettings()
        settings.enabled.subtract([.phoneNumbers, .cardNumbers])
        let result = try await RedactionScanner.scan(sample.image, settings: settings, includeCustomRules: false)
        #expect(!result.boxes.contains { $0.detector == .phoneNumbers || $0.detector == .cardNumbers })
        #expect(result.boxes.contains { $0.detector == .apiKeys })
    }

    @Test func customRulesRunOnlyWhenIncluded() async throws {
        let sample = SampleScreenshot.render(.webForm)
        var settings = DetectionSettings(enabled: [])
        settings.customRules = [CustomRule(kind: .phrase, value: "Acme Corporation")]
        let without = try await RedactionScanner.scan(sample.image, settings: settings, includeCustomRules: false)
        #expect(without.boxes.isEmpty)
        let with = try await RedactionScanner.scan(sample.image, settings: settings, includeCustomRules: true)
        #expect(with.boxes.count == 1)
        #expect(with.boxes.first?.category == .custom)
    }

    /// Long lines across the seams of a wide 1× image, which is read in tiles.
    @Test func linesAcrossTileSeamsAreFullyCovered() async throws {
        let sample = SampleScreenshot.render(.wide, style: .init(dark: false, font: .sfMono, pointSize: 13, scale: 1, width: 2400))
        #expect(!TileLayout(imageSize: CGSize(width: sample.image.width, height: sample.image.height), tileSize: 1280).isSingleTile)
        let result = try await scan(sample)
        for planted in sample.planted {
            let missed = uncoveredInk(planted, boxes: result.boxes)
            #expect(missed.isEmpty, "\(planted.text): \(missed.count) of \(planted.ink.count) uncovered; boxes: \(result.boxes.map { "\($0.label) \($0.rect)" })")
        }
    }

    /// A tall scrolling capture: wider than nothing, but far taller than a tile.
    @Test func aTallCaptureIsFullyCovered() async throws {
        let sample = SampleScreenshot.render(.chat, style: .init(dark: false, font: .sfPro, pointSize: 13, scale: 2, width: 700), repeating: 30)
        #expect(sample.image.height > 4000)
        let result = try await scan(sample)
        for planted in sample.planted {
            #expect(uncoveredInk(planted, boxes: result.boxes).isEmpty, "\(planted.text) at \(planted.rect.integral)")
        }
    }

    /// A 5K screenshot full of text, scanned within the time the preview
    /// promises (about a second; 1.5 s allows for a busy test machine).
    @Test func a5KScreenshotScansInTime() async throws {
        let sample = SampleScreenshot.render(.log, style: .init(dark: true, font: .sfMono, pointSize: 12, scale: 2, width: 2560), repeating: 18)
        #expect(sample.image.width == 5120)
        _ = try await scan(SampleScreenshot.render(.terminal)) // warm Vision up
        let start = ContinuousClock.now
        let result = try await scan(sample)
        let elapsed = ContinuousClock.now - start
        #expect(result.lineCount >= 60)
        #expect(elapsed < .milliseconds(1500), "Took \(elapsed)")
        for planted in sample.planted {
            #expect(uncoveredInk(planted, boxes: result.boxes).isEmpty, "\(planted.text) at \(planted.rect.integral)")
        }
    }
}
