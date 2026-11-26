#if DEBUG
import AppKit
import OSLog

/// Writes debug output into the sandbox container's Application Support
/// folder (`~/Library/Containers/<bundle id>/Data/Library/Application Support/Debug`).
enum DebugFiles {
    static var folder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appending(path: "Debug", directoryHint: .isDirectory)
    }

    static func write(_ text: String, to name: String) {
        write(Data(text.utf8), to: name)
    }

    static func write(_ data: Data, to name: String) {
        do {
            let url = folder.appending(path: name)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        } catch {
            Logger.app.error("Couldn't write debug file \(name, privacy: .public): \(error)")
        }
    }

    /// Renders a layer tree (model values, no masks) to a PNG.
    static func writePNG(of layer: CALayer, to name: String, scale: CGFloat = 2) {
        let size = layer.bounds.size
        guard size.width > 0, size.height > 0,
              let context = CGContext(
                  data: nil,
                  width: Int(size.width * scale),
                  height: Int(size.height * scale),
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return }
        context.scaleBy(x: scale, y: scale)
        layer.render(in: context)
        guard let image = context.makeImage() else { return }
        let rep = NSBitmapImageRep(cgImage: image)
        if let png = rep.representation(using: .png, properties: [:]) {
            write(png, to: name)
        }
    }

    /// Renders an `NSView` (including Core Animation layers) to a PNG.
    static func writePNG(of view: NSView, to name: String, scale: CGFloat = 2) {
        view.layoutSubtreeIfNeeded()
        let size = view.bounds.size
        guard size.width > 0, size.height > 0,
              let rep = NSBitmapImageRep(
                  bitmapDataPlanes: nil,
                  pixelsWide: Int(size.width * scale),
                  pixelsHigh: Int(size.height * scale),
                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                  colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
              )
        else { return }
        rep.size = size
        guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        if let layer = view.layer {
            context.cgContext.scaleBy(x: scale, y: scale)
            layer.render(in: context.cgContext)
        } else {
            view.displayIgnoringOpacity(view.bounds, in: context)
        }
        NSGraphicsContext.restoreGraphicsState()
        if let png = rep.representation(using: .png, properties: [:]) {
            write(png, to: name)
        }
    }
}
#endif
