import Foundation
import OSLog

/// Reads and writes `SavedState` as JSON in the sandbox container's
/// Application Support folder. Writes are throttled (at most one every
/// `saveDelay`) and atomic; a file that can't be read is kept aside as a
/// backup and the app starts fresh.
final class StateStore {
    private(set) var state: SavedState
    private let url: URL
    private var saveWork: DispatchWorkItem?
    static let saveDelay: TimeInterval = 20

    init(folder: URL? = nil) {
        let base = folder ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        url = base.appending(path: "PosturePet.json")
        state = Self.load(from: url)
    }

    /// Changes the state and schedules a save.
    func update(_ change: (inout SavedState) -> Void) {
        change(&state)
        scheduleSave()
    }

    /// Writes now (on sleep and quit).
    func flush() {
        saveWork?.cancel()
        saveWork = nil
        write()
    }

    private func scheduleSave() {
        // Already scheduled: that save will include this change.
        guard saveWork == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.saveWork = nil
                self?.write()
            }
        }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.saveDelay, execute: work)
    }

    private func write() {
        state.savedAt = .now
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(state)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        } catch {
            Logger.app.error("Couldn't save state: \(error)")
        }
    }

    private static func load(from url: URL) -> SavedState {
        guard let data = try? Data(contentsOf: url) else { return SavedState() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            var state = try decoder.decode(SavedState.self, from: data)
            if state.version > SavedState.currentVersion {
                Logger.app.warning("State is from a newer version (\(state.version)); reading what we can.")
            }
            state.version = SavedState.currentVersion
            return state
        } catch {
            // Keep the unreadable file for support instead of overwriting it.
            let backup = url.deletingPathExtension().appendingPathExtension("corrupt-\(Int(Date.now.timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: url, to: backup)
            Logger.app.error("State was unreadable and was moved aside: \(error)")
            return SavedState()
        }
    }
}
