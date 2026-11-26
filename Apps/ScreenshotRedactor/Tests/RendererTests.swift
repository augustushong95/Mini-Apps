import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import ScreenshotRedactor

/// The exported image: exact boxes, untouched pixels elsewhere, same format,
/// and no metadata.
@Suite nonisolated struct RendererTests {
    /// A test image with a different colour in every pixel.
    private func gradient(width: Int = 200, height: Int = 100, space: CGColorSpace = CGColorSpace(name: CGColorSpace.sRGB)!,
                          bits: Int = 8, alpha: Bool = true) -> CGImage {
        let info: UInt32 = (alpha ? CGImageAlphaInfo.premultipliedLast : .noneSkipLast).rawValue
            | (bits == 16 ? CGBitmapInfo.byteOrder16Little.rawValue : 0)
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: bits, bytesPerRow: 0, space: space, bitmapInfo: info)!
        for y in 0..<height {
            for x in 0..<width {
                context.setFillColor(CGColor(colorSpace: space, components: [CGFloat(x) / CGFloat(width), CGFloat(y) / CGFloat(height), 0.5, 1])!)
                context.fill(CGRect(x: x, y: y, width: 1, height: 1))
            }
        }
        return context.makeImage()!
    }

    /// RGBA8 sRGB bytes, top row first.
    private func bytes(_ image: CGImage) -> [UInt8] {
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        data.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                                    bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return data
    }

    private func pixel(_ data: [UInt8], width: Int, x: Int, y: Int) -> [UInt8] {
        let offset = (y * width + x) * 4
        return Array(data[offset..<offset + 4])
    }

    @Test func coveredBoxesAreSolidAndEverythingElseIsUntouched() throws {
        let source = gradient()
        let covered = RedactionBox(rect: CGRect(x: 10, y: 10, width: 50, height: 20), label: "Email", category: .personal, detector: .emails, source: .detected)
        var uncovered = RedactionBox(rect: CGRect(x: 100, y: 50, width: 30, height: 30), label: "IP", category: .internalInfo, detector: .ipAddresses, source: .detected)
        uncovered.isCovered = false
        let output = try #require(RedactionRenderer.render(source, boxes: [covered, uncovered], style: RenderStyle()))
        #expect(output.width == source.width && output.height == source.height)

        let before = bytes(source), after = bytes(output)
        for y in 0..<source.height {
            for x in 0..<source.width {
                let inBox = covered.rect.contains(CGPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5))
                let expected = inBox ? [0, 0, 0, 255] : pixel(before, width: source.width, x: x, y: y)
                #expect(pixel(after, width: source.width, x: x, y: y) == expected, "pixel \(x),\(y)")
                if pixel(after, width: source.width, x: x, y: y) != expected { return }
            }
        }
    }

    @Test(arguments: BoxColor.allCases)
    func everyBoxColourIsOpaque(_ color: BoxColor) throws {
        let box = RedactionBox(rect: CGRect(x: 0, y: 0, width: 20, height: 20), label: "x", category: .secret, detector: .apiKeys, source: .detected)
        let output = try #require(RedactionRenderer.render(gradient(), boxes: [box], style: RenderStyle(color: color)))
        #expect(pixel(bytes(output), width: output.width, x: 5, y: 5)[3] == 255)
    }

    @Test func formatIsPreserved() throws {
        let p3 = CGColorSpace(name: CGColorSpace.displayP3)!
        let deep = gradient(width: 40, height: 30, space: p3, bits: 16, alpha: true)
        let output = try #require(RedactionRenderer.render(deep, boxes: [], style: RenderStyle()))
        #expect(output.bitsPerComponent == 16)
        #expect(output.colorSpace?.name == CGColorSpace.displayP3)

        let opaque = gradient(width: 40, height: 30, alpha: false)
        let opaqueOutput = try #require(RedactionRenderer.render(opaque, boxes: [], style: RenderStyle()))
        #expect([.none, .noneSkipLast, .noneSkipFirst].contains(opaqueOutput.alphaInfo))
        #expect(opaqueOutput.colorSpace?.name == CGColorSpace.sRGB)
    }

    @Test func unnamedDisplayProfilesBecomeDisplayP3() throws {
        var white: [CGFloat] = [0.9505, 1.0, 1.089]
        var black: [CGFloat] = [0, 0, 0]
        var gamma: [CGFloat] = [2.2, 2.2, 2.2]
        var matrix: [CGFloat] = [0.4124, 0.2126, 0.0193, 0.3576, 0.7152, 0.1192, 0.1805, 0.0722, 0.9505]
        let custom = try #require(CGColorSpace(calibratedRGBWhitePoint: &white, blackPoint: &black, gamma: &gamma, matrix: &matrix))
        #expect(custom.name == nil)
        let output = try #require(RedactionRenderer.render(gradient(width: 20, height: 20, space: custom), boxes: [], style: RenderStyle()))
        #expect(output.colorSpace?.name == CGColorSpace.displayP3)
    }

    @Test func pngHasNoMetadataBeyondResolution() throws {
        let png = try #require(RedactionRenderer.pngData(gradient(), dpi: 144))
        let source = try #require(CGImageSourceCreateWithData(png as CFData, nil))
        #expect(CGImageSourceGetCount(source) == 1)
        #expect(CGImageSourceGetType(source) as String? == UTType.png.identifier)
        let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        #expect(properties[kCGImagePropertyExifDictionary] == nil)
        let chunks = try #require(PNGChunks.types(in: png))
        #expect(Set(chunks).isSubset(of: PNGChunks.essential), "\(chunks)")
        #expect(chunks.contains("pHYs"))
        #expect(properties[kCGImagePropertyGPSDictionary] == nil)
        #expect(properties[kCGImagePropertyIPTCDictionary] == nil)
        #expect(properties[kCGImagePropertyMakerAppleDictionary] == nil)
        if let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            for key in [kCGImagePropertyTIFFMake, kCGImagePropertyTIFFModel, kCGImagePropertyTIFFSoftware, kCGImagePropertyTIFFDateTime] {
                #expect(tiff[key] == nil)
            }
        }
        #expect((properties[kCGImagePropertyDPIWidth] as? Double).map { abs($0 - 144) < 1 } == true)
        #expect(properties[kCGImagePropertyPixelWidth] as? Int == 200)
    }

    @Test func labelsStayInsideTheirBoxes() throws {
        let source = gradient()
        let box = RedactionBox(rect: CGRect(x: 20, y: 20, width: 140, height: 40), label: "Email", category: .personal, detector: .emails, source: .detected)
        let output = try #require(RedactionRenderer.render(source, boxes: [box], style: RenderStyle(color: .black, showsLabels: true)))
        let before = bytes(source), after = bytes(output)
        var labelPixels = 0
        for y in 0..<source.height {
            for x in 0..<source.width {
                let inBox = box.rect.contains(CGPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5))
                let now = pixel(after, width: source.width, x: x, y: y)
                if !inBox {
                    #expect(now == pixel(before, width: source.width, x: x, y: y))
                } else if now != [0, 0, 0, 255] {
                    labelPixels += 1
                }
            }
        }
        #expect(labelPixels > 0, "The label should be drawn")
    }

    @Test func chunkFilterRejectsAnythingThatIsntAPNG() {
        #expect(PNGChunks.keepingEssentials(Data("GIF89a".utf8)) == nil)
        #expect(PNGChunks.keepingEssentials(Data(PNGChunks.signature)) == nil)
    }

    @Test func loaderReadsWhatTheRendererWrites() throws {
        let png = try #require(RedactionRenderer.pngData(gradient(), dpi: 144))
        let loaded = try ImageLoader.load(data: png)
        #expect(loaded.image.width == 200 && loaded.image.height == 100)
        #expect(abs(loaded.dpi - 144) < 1)
        #expect(throws: ImageLoadError.self) { try ImageLoader.load(data: Data("not an image".utf8)) }
    }
}
