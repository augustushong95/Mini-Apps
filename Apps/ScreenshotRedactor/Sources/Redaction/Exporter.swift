import AppKit
import OSLog
import UniformTypeIdentifiers

/// Copies, drags and saves redacted images, then does what follows an
/// export: counts it against the free tier and, if the user asked for it,
/// moves the original screenshot to the Trash.
///
/// Only rendered, redacted pixels ever leave: there is no way to export the
/// original from here.
final class Exporter {
    enum Outcome: Equatable {
        case done
        /// Today's free redactions are used up.
        case limitReached
        case cancelled
        case failed(String)
    }

    private let allowance: DailyAllowance
    private let preferences: Preferences
    private let pasteboard: NSPasteboard
    /// Keeps the TIFF provider alive until the pasteboard is done with it.
    private var tiffProvider: TIFFProvider?

    init(allowance: DailyAllowance, preferences: Preferences, pasteboard: NSPasteboard = .general) {
        self.allowance = allowance
        self.preferences = preferences
        self.pasteboard = pasteboard
    }

    // MARK: Copy

    func copy(_ document: RedactionDocument) async -> Outcome {
        allowance.refresh()
        guard allowance.canExport(document) else { return .limitReached }
        guard let image = await document.exportImage(), let png = await document.pngData() else {
            return .failed("The redacted image isn't ready yet.")
        }
        let item = NSPasteboardItem()
        item.setData(png, forType: .png)
        // Some apps only paste TIFF; make it only if one asks.
        let provider = TIFFProvider(image: image)
        item.setDataProvider(provider, forTypes: [.tiff])
        pasteboard.clearContents()
        guard pasteboard.writeObjects([item]) else { return .failed("Couldn't use the clipboard.") }
        tiffProvider = provider
        finishExport(document)
        return .done
    }

    // MARK: Save

    func save(_ document: RedactionDocument) async -> Outcome {
        allowance.refresh()
        guard allowance.canExport(document) else { return .limitReached }
        guard let png = await document.pngData() else { return .failed("The redacted image isn't ready yet.") }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = Self.redactedFileName(for: document)
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        if let folder = document.originalURL?.deletingLastPathComponent() {
            panel.directoryURL = folder
        }
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return .cancelled }
        do {
            try png.write(to: url, options: .atomic)
        } catch {
            Logger.app.error("Couldn't save: \(error.localizedDescription, privacy: .public)")
            return .failed("Couldn't save the image there.")
        }
        finishExport(document)
        return .done
    }

    // MARK: Drag

    /// A file with the redacted PNG for dragging into other apps, or nil if
    /// the free tier is used up or the image isn't ready.
    ///
    /// Written to the container's temporary folder; such files are removed
    /// at the next launch (not when the drag ends, since the receiving app
    /// may read it later).
    func dragFile(for document: RedactionDocument) -> URL? {
        guard allowance.canExport(document), document.isExportable else { return nil }
        guard let png = document.cachedPNG ?? document.rendered.flatMap({ RedactionRenderer.pngData($0, dpi: document.dpi) }) else { return nil }
        let folder = Self.outgoingFolder.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appending(path: Self.redactedFileName(for: document))
            try png.write(to: url, options: .atomic)
            return url
        } catch {
            Logger.app.error("Couldn't prepare the drag: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// The drag ended with a drop somewhere.
    func dragCompleted(_ document: RedactionDocument) {
        finishExport(document)
    }

    static var outgoingFolder: URL {
        FileManager.default.temporaryDirectory.appending(path: "Outgoing", directoryHint: .isDirectory)
    }

    /// Deletes drag files left from earlier sessions.
    static func removeLeftoverFiles() {
        try? FileManager.default.removeItem(at: outgoingFolder)
    }

    static func redactedFileName(for document: RedactionDocument) -> String {
        let base = document.name.isEmpty ? "Screenshot" : document.name
        return "\(base) (redacted).png"
    }

    // MARK: After an export

    private func finishExport(_ document: RedactionDocument) {
        allowance.recordExport(document)
        if preferences.originalHandling == .moveToTrash {
            moveOriginalToTrash(document)
        }
    }

    /// Moves the original screenshot to the Trash, only if the file there
    /// is still the same one the app read.
    @discardableResult
    func moveOriginalToTrash(_ document: RedactionDocument) -> Bool {
        guard !document.originalTrashed, case .screenshot(let url, let identity) = document.origin else { return false }
        guard let current = FileIdentity.of(url), current == identity else {
            Logger.app.info("Original changed or moved; not trashing it")
            return false
        }
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            document.originalTrashed = true
            return true
        } catch {
            Logger.app.error("Couldn't move the original to the Trash: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}

/// Makes TIFF data for the pasteboard on request.
private nonisolated final class TIFFProvider: NSObject, NSPasteboardItemDataProvider {
    private let image: CGImage

    init(image: CGImage) {
        self.image = image
    }

    func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
        guard type == .tiff,
              let data = NSBitmapImageRep(cgImage: image).tiffRepresentation(using: .lzw, factor: 0)
        else { return }
        item.setData(data, forType: .tiff)
    }
}
