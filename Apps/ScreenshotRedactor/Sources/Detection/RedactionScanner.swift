import CoreGraphics
import Foundation
import OSLog
import Vision

/// What a scan found.
nonisolated struct ScanResult: Sendable {
    var boxes: [RedactionBox]
    /// Custom patterns that ran out of time and were skipped.
    var timedOutRules: Set<UUID>
    var lineCount: Int
    var duration: Duration
}

nonisolated enum ScanError: Error, LocalizedError {
    case visionFailed(String)

    var errorDescription: String? {
        switch self {
        case .visionFailed: "The image couldn't be scanned."
        }
    }
}

/// Reads an image's text with Vision (on this Mac, offline), finds faces,
/// and turns everything sensitive into boxes.
nonisolated enum RedactionScanner {
    /// Recognition languages: English first (keys and addresses are Latin
    /// text), then the user's other Latin-script languages that Vision knows.
    static func recognitionLanguages(preferred: [String] = Locale.preferredLanguages) -> [String] {
        let supported = (try? VNRecognizeTextRequest().supportedRecognitionLanguages()) ?? ["en-US"]
        var languages = ["en-US"]
        let latinPrefixes = ["en", "fr", "de", "es", "it", "pt", "nl", "sv", "da", "nb", "no", "fi", "pl", "cs", "tr", "id", "ms", "vi", "ro", "hu"]
        for language in preferred {
            let code = language.split(separator: "-").first.map(String.init) ?? language
            guard latinPrefixes.contains(code) else { continue }
            if let match = supported.first(where: { $0 == language || $0.hasPrefix(code + "-") }), !languages.contains(match) {
                languages.append(match)
            }
            if languages.count >= 3 { break }
        }
        return languages
    }

    /// Runs off the main actor; Vision's work is synchronous and heavy.
    ///
    /// - Parameter dpi: the image's resolution; 144 means Retina, so text is
    ///   drawn twice as large and tiles can be bigger.
    @concurrent
    static func scan(
        _ image: CGImage,
        dpi: CGFloat = 144,
        settings: DetectionSettings,
        includeCustomRules: Bool,
        languages: [String] = ["en-US"]
    ) async throws -> ScanResult {
        let start = ContinuousClock.now
        let imageSize = CGSize(width: image.width, height: image.height)
        let reading = try readLines(image, dpi: dpi, languages: languages, faces: settings.enabled.contains(.faces))
        let lines = reading.lines
        let faces = reading.faces
        let layoutTiles = reading.tiles
        try Task.checkCancellation()

        let rules = TextRules(settings: settings, includeCustomRules: includeCustomRules)
        let clock = CustomRuleClock()
        let planner = RedactionPlanner(
            rules: rules, imageSize: imageSize,
            refiner: lines.isEmpty ? nil : PixelBuffer(image: image).map(InkRefiner.init),
            clock: clock
        )
        let boxes = planner.boxes(for: lines, faces: faces)
        let duration = ContinuousClock.now - start
        Logger.app.info("Scanned \(image.width)×\(image.height) in \(layoutTiles) tile(s): \(lines.count) lines, \(boxes.count) boxes, \(duration.formatted(.units(allowed: [.milliseconds])), privacy: .public)")
        return ScanResult(boxes: boxes, timedOutRules: clock.timedOut, lineCount: lines.count, duration: duration)
    }

    /// Every line of text and every face in `image`: the whole image first
    /// (large text, and everything when the image fits in one tile), then
    /// tiles for images too large for Vision to read small text in.
    static func readLines(_ image: CGImage, dpi: CGFloat, languages: [String], faces wantsFaces: Bool) throws -> (lines: [ScannedLine], faces: [CGRect], tiles: Int) {
        let imageSize = CGSize(width: image.width, height: image.height)
        let whole = try recognize(image, origin: .zero, languages: languages, faces: wantsFaces)
        let layout = TileLayout(imageSize: imageSize, tileSize: TileLayout.tileSize(scale: dpi / 72))
        guard !layout.isSingleTile else { return (whole.lines.map(\.scanned), whole.faces, 1) }
        var faces = whole.faces
        var tileLines: [[OCRLine]] = []
        for tile in layout.tiles {
            try Task.checkCancellation()
            guard let crop = image.cropping(to: tile) else { tileLines.append([]); continue }
            let result = try recognize(crop, origin: tile.origin, languages: languages, faces: wantsFaces)
            tileLines.append(result.lines)
            faces += result.faces
        }
        return (LineStitcher.combine(full: whole.lines, tiles: tileLines), faces, layout.tiles.count)
    }

    /// Text and faces in `image`, in the coordinates of the full image it
    /// was cut from (`origin` is where it sits there).
    static func recognize(_ image: CGImage, origin: CGPoint, languages: [String], faces wantsFaces: Bool) throws -> (lines: [OCRLine], faces: [CGRect]) {
        let size = CGSize(width: image.width, height: image.height)
        let textRequest = VNRecognizeTextRequest()
        textRequest.revision = VNRecognizeTextRequestRevision3
        textRequest.recognitionLevel = .accurate
        // Language correction "fixes" keys into words. Keep what's on screen.
        textRequest.usesLanguageCorrection = false
        // Any non-zero minimum makes Vision downsample and miss small text.
        textRequest.minimumTextHeight = 0
        textRequest.recognitionLanguages = languages
        let faceRequest = VNDetectFaceRectanglesRequest()

        let handler = VNImageRequestHandler(cgImage: image, orientation: .up, options: [:])
        do {
            try handler.perform(wantsFaces ? [textRequest, faceRequest] : [textRequest])
        } catch {
            Logger.app.error("Vision failed: \(error.localizedDescription, privacy: .public)")
            throw ScanError.visionFailed(error.localizedDescription)
        }

        func place(_ rect: CGRect) -> CGRect { rect.offsetBy(dx: origin.x, dy: origin.y) }

        let lines: [OCRLine] = (textRequest.results ?? []).compactMap { observation in
            let candidates = observation.topCandidates(3)
            guard !candidates.isEmpty else { return nil }
            let lineRect = place(BoxGeometry.pixelRect(
                fromNormalizedCorners: [observation.topLeft, observation.topRight, observation.bottomLeft, observation.bottomRight],
                imageSize: size
            ))
            return OCRLine(candidates: candidates.map(\.string), rect: lineRect) { index, range in
                guard index < candidates.count,
                      let quad = try? candidates[index].boundingBox(for: range)
                else { return nil }
                return place(BoxGeometry.pixelRect(fromNormalizedCorners: [quad.topLeft, quad.topRight, quad.bottomLeft, quad.bottomRight], imageSize: size))
            }
        }
        let faces = (faceRequest.results ?? []).map { place(BoxGeometry.pixelRect(fromNormalized: $0.boundingBox, imageSize: size)) }
        return (lines, faces)
    }
}
