import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A decoded image ready to scan and render.
nonisolated struct LoadedImage: @unchecked Sendable {
    let image: CGImage
    /// Pixels per inch, for the exported PNG (144 on Retina screenshots).
    let dpi: CGFloat

    var pixelSize: CGSize { CGSize(width: image.width, height: image.height) }
}

nonisolated enum ImageLoadError: Error, Equatable, LocalizedError {
    case unreadable
    case incomplete
    case unsupported(String)

    var errorDescription: String? {
        switch self {
        case .unreadable: "This file isn't an image the app can read."
        case .incomplete: "The image is still being written."
        case .unsupported(let kind): "\(kind) files aren't scanned. Take a screenshot or open a PNG, JPEG or HEIC image."
        }
    }
}

/// Decodes an image once, upright, the same way for Vision and the renderer.
nonisolated enum ImageLoader {
    /// Decodes off the main thread (large screenshots take a moment).
    @concurrent
    static func loadInBackground(contentsOf url: URL) async throws -> LoadedImage {
        try load(contentsOf: url)
    }

    @concurrent
    static func loadInBackground(data: Data) async throws -> LoadedImage {
        try load(data: data)
    }

    static func load(contentsOf url: URL) throws -> LoadedImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            throw ImageLoadError.unreadable
        }
        return try load(source)
    }

    static func load(data: Data) throws -> LoadedImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            throw ImageLoadError.unreadable
        }
        return try load(source)
    }

    static func load(_ image: CGImage, dpi: CGFloat = 144) -> LoadedImage {
        LoadedImage(image: image, dpi: dpi)
    }

    private static func load(_ source: CGImageSource) throws -> LoadedImage {
        switch CGImageSourceGetStatus(source) {
        case .statusComplete: break
        case .statusIncomplete, .statusReadingHeader: throw ImageLoadError.incomplete
        default: throw ImageLoadError.unreadable
        }
        if let typeIdentifier = CGImageSourceGetType(source) as String?, let type = UTType(typeIdentifier) {
            if type.conforms(to: .pdf) { throw ImageLoadError.unsupported("PDF") }
            if type.conforms(to: .gif) || CGImageSourceGetCount(source) > 1 { throw ImageLoadError.unsupported("Animated") }
            guard type.conforms(to: .image) else { throw ImageLoadError.unreadable }
        }
        guard CGImageSourceGetCount(source) >= 1 else { throw ImageLoadError.unreadable }

        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        let orientation = (properties[kCGImagePropertyOrientation] as? UInt32) ?? 1
        let dpi = (properties[kCGImagePropertyDPIWidth] as? Double).map { CGFloat($0) } ?? 72

        let image: CGImage?
        if orientation == 1 {
            image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
        } else {
            // Apply the EXIF rotation so boxes land where the pixels are.
            let width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
            let height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
            image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: max(width, height, 1),
                kCGImageSourceShouldCacheImmediately: true,
            ] as CFDictionary)
        }
        guard let image, image.width > 0, image.height > 0 else { throw ImageLoadError.unreadable }
        return LoadedImage(image: image, dpi: dpi)
    }
}
