import CoreGraphics
import Foundation
import Observation

/// The session's captures: newest first, at most six, kept only in memory.
/// Scans run one at a time, in the order captures arrive.
@Observable
final class Library {
    static let maximumRecent = 6
    /// Originals are kept in memory (never on disk), plus their renders.
    /// Past this many pixels the oldest captures are let go: about three
    /// full 5K screenshots, or all six typical area selections.
    static let pixelBudget = 45_000_000

    private(set) var recent: [RedactionDocument] = []

    /// Custom rules that ran out of time in a scan (to switch them off).
    @ObservationIgnored var onRulesTimedOut: ((Set<UUID>) -> Void)?

    @ObservationIgnored private let preferences: Preferences
    @ObservationIgnored private let includesCustomRules: () -> Bool
    @ObservationIgnored private var scanQueue: Task<Void, Never>?
    @ObservationIgnored private let languages = RedactionScanner.recognitionLanguages()

    init(preferences: Preferences, includesCustomRules: @escaping () -> Bool) {
        self.preferences = preferences
        self.includesCustomRules = includesCustomRules
    }

    /// Adds a capture and queues its scan.
    @discardableResult
    func add(_ loaded: LoadedImage, origin: RedactionDocument.Origin, name: String,
             burstID: UUID? = nil, globalRect: CGRect? = nil) -> RedactionDocument {
        let document = RedactionDocument(
            image: loaded.image, dpi: loaded.dpi, origin: origin, name: name,
            style: preferences.renderStyle, burstID: burstID, globalRect: globalRect
        )
        recent.insert(document, at: 0)
        if recent.count > Self.maximumRecent {
            recent.removeLast(recent.count - Self.maximumRecent)
        }
        while recent.count > 1, recent.reduce(0, { $0 + $1.image.width * $1.image.height }) > Self.pixelBudget {
            recent.removeLast()
        }
        enqueueScan(document)
        return document
    }

    func remove(_ document: RedactionDocument) {
        recent.removeAll { $0.id == document.id }
    }

    func clear() {
        recent.removeAll()
    }

    /// Box colour and labels apply to every open capture straight away.
    func applyStyle() {
        for document in recent { document.setStyle(preferences.renderStyle) }
    }

    private func enqueueScan(_ document: RedactionDocument) {
        let previous = scanQueue
        let settings = preferences.detection
        let custom = includesCustomRules()
        let languages = languages
        scanQueue = Task { [weak self] in
            await previous?.value
            do {
                let result = try await RedactionScanner.scan(
                    document.image, dpi: document.dpi, settings: settings,
                    includeCustomRules: custom, languages: languages
                )
                document.finishScan(result)
                if !result.timedOutRules.isEmpty { self?.onRulesTimedOut?(result.timedOutRules) }
            } catch {
                document.failScan((error as? LocalizedError)?.errorDescription ?? "The image couldn't be scanned.")
            }
        }
    }

    /// Waits for every queued scan (tests, smoke test).
    func waitForScans() async {
        await scanQueue?.value
    }
}
