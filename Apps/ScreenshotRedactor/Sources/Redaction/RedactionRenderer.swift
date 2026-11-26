import AppKit
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers

/// The colour of the boxes. Always solid: blurred or pixelated text can be
/// reconstructed, a filled box can't.
nonisolated enum BoxColor: String, CaseIterable, Codable, Sendable {
    case black
    case graphite
    case white

    var title: String {
        switch self {
        case .black: "Black"
        case .graphite: "Graphite"
        case .white: "White"
        }
    }

    var fill: CGColor {
        switch self {
        case .black: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
        case .graphite: CGColor(srgbRed: 0.29, green: 0.30, blue: 0.33, alpha: 1)
        case .white: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
        }
    }

    /// Label text on top of the fill.
    var labelColor: CGColor {
        switch self {
        case .black, .graphite: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.85)
        case .white: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.6)
        }
    }
}

nonisolated struct RenderStyle: Equatable, Sendable {
    var color: BoxColor = .black
    /// Writes what each box hides ("email") inside it, when it fits.
    var showsLabels = false
}

/// Draws the redacted image: a new bitmap with the original's pixels and
/// solid boxes on top, then encodes it as a fresh PNG with no metadata.
nonisolated enum RedactionRenderer {
    static func render(_ image: CGImage, boxes: [RedactionBox], style: RenderStyle) -> CGImage? {
        let width = image.width, height = image.height
        guard width > 0, height > 0 else { return nil }

        let space = outputColorSpace(for: image)
        let hasAlpha = ![.none, .noneSkipFirst, .noneSkipLast].contains(image.alphaInfo)
        let sixteenBit = image.bitsPerComponent > 8
        let alphaInfo: CGImageAlphaInfo = hasAlpha ? .premultipliedLast : .noneSkipLast
        let bitmapInfo = sixteenBit
            ? alphaInfo.rawValue | CGBitmapInfo.byteOrder16Little.rawValue
            : alphaInfo.rawValue
        guard let context = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: sixteenBit ? 16 : 8, bytesPerRow: 0,
            space: space, bitmapInfo: bitmapInfo
        ) else { return nil }

        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        context.interpolationQuality = .none
        context.draw(image, in: bounds)

        let covered = boxes.filter(\.isCovered)
        // Exact, hard-edged boxes: no antialiasing, full replacement.
        context.setShouldAntialias(false)
        context.setBlendMode(.copy)
        context.setFillColor(style.color.fill)
        for box in covered {
            let rect = BoxGeometry.outwardIntegral(box.rect).intersection(bounds)
            guard !rect.isNull, !rect.isEmpty else { continue }
            context.fill(BoxGeometry.cgRect(fromTopLeft: rect, imageHeight: CGFloat(height)))
        }

        if style.showsLabels {
            context.setShouldAntialias(true)
            context.setBlendMode(.normal)
            for box in covered {
                drawLabel(box.label.lowercased(), in: box.rect, imageHeight: CGFloat(height), color: style.color.labelColor, context: context)
            }
        }
        return context.makeImage()
    }

    /// Keeps standard colour spaces (sRGB, Display P3…). A display's own
    /// profile can carry its model name, so anything unnamed becomes P3.
    static func outputColorSpace(for image: CGImage) -> CGColorSpace {
        if let space = image.colorSpace, space.model == .rgb, space.name != nil, space.supportsOutput {
            return space
        }
        return CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpaceCreateDeviceRGB()
    }

    private static func drawLabel(_ text: String, in rect: CGRect, imageHeight: CGFloat, color: CGColor, context: CGContext) {
        let fontSize = min(rect.height * 0.5, 26)
        guard fontSize >= 8, rect.width > fontSize * 2 else { return }
        let font = CTFontCreateUIFontForLanguage(.system, fontSize, nil) ?? CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        let width = CTLineGetTypographicBounds(line, nil, nil, nil)
        let cgRect = BoxGeometry.cgRect(fromTopLeft: rect, imageHeight: imageHeight)
        let inset = fontSize * 0.5
        guard width + inset * 2 <= Double(rect.width) else { return }
        context.saveGState()
        context.clip(to: cgRect)
        context.textPosition = CGPoint(x: cgRect.minX + inset, y: cgRect.midY - fontSize * 0.35)
        CTLineDraw(line, context)
        context.restoreGState()
    }

    /// A new PNG with only pixels, colour and resolution: no EXIF, TIFF,
    /// GPS, IPTC or text chunks, no thumbnail, no gain map.
    static func pngData(_ image: CGImage, dpi: CGFloat = 72) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        let properties: [CFString: Any] = [
            kCGImagePropertyDPIWidth: dpi,
            kCGImagePropertyDPIHeight: dpi,
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        // ImageIO always adds an eXIf chunk (colour space and pixel size).
        // Harmless, but "no metadata" should mean none: keep only the
        // chunks that describe the pixels.
        return PNGChunks.keepingEssentials(data as Data)
    }
}

/// Filters a PNG down to the chunks needed to show it correctly.
nonisolated enum PNGChunks {
    /// Image data, palette, transparency, colour (profile, gamma, primaries)
    /// and physical resolution. Everything else (eXIf, tEXt, iTXt, zTXt,
    /// tIME, private chunks) is dropped.
    static let essential: Set<String> = ["IHDR", "PLTE", "tRNS", "cHRM", "gAMA", "iCCP", "sBIT", "sRGB", "cICP", "pHYs", "IDAT", "IEND"]
    static let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

    /// The chunk types in a PNG, in order; nil if it isn't a well-formed PNG.
    static func types(in data: Data) -> [String]? {
        chunks(in: data)?.map(\.type)
    }

    /// `data` without non-essential chunks, or nil if it isn't a well-formed PNG.
    static func keepingEssentials(_ data: Data) -> Data? {
        guard let chunks = chunks(in: data) else { return nil }
        var result = Data(signature)
        for chunk in chunks where essential.contains(chunk.type) {
            result.append(data[chunk.range])
        }
        return result
    }

    private struct Chunk {
        let type: String
        /// Length, type, data and CRC: the whole chunk as stored.
        let range: Range<Data.Index>
    }

    private static func chunks(in data: Data) -> [Chunk]? {
        let bytes = [UInt8](data)
        guard bytes.count >= 8, Array(bytes[0..<8]) == signature else { return nil }
        var chunks: [Chunk] = []
        var offset = 8
        while offset + 12 <= bytes.count {
            let length = Int(bytes[offset]) << 24 | Int(bytes[offset + 1]) << 16 | Int(bytes[offset + 2]) << 8 | Int(bytes[offset + 3])
            let end = offset + 12 + length
            guard length >= 0, end <= bytes.count,
                  let type = String(bytes: bytes[(offset + 4)..<(offset + 8)], encoding: .ascii)
            else { return nil }
            chunks.append(Chunk(type: type, range: (data.startIndex + offset)..<(data.startIndex + end)))
            offset = end
            if type == "IEND" { break }
        }
        guard chunks.first?.type == "IHDR", chunks.last?.type == "IEND" else { return nil }
        return chunks
    }
}
