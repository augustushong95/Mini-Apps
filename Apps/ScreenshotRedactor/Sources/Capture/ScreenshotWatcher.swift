import CoreServices
import Foundation
import ImageIO
import OSLog
import UniformTypeIdentifiers

/// Watches one folder for new screenshots.
///
/// File events are only hints: each one triggers a fresh listing of the
/// folder, compared with the files already seen (by file ID, so renames
/// don't count as new). A file is reported once, when it
/// - is visible (`screencapture` writes a hidden file, then renames it),
/// - is an image created after watching started and within the last minute,
/// - carries the screen-capture attribute (retried for a few seconds,
///   since it can arrive just after the rename),
/// - keeps the same size across two looks and decodes completely.
final class ScreenshotWatcher {
    struct Arrival: Equatable {
        let url: URL
        let identity: FileIdentity
        let created: Date
        let globalRect: CGRect?
        let captureType: String?
    }

    var onScreenshot: ((Arrival) -> Void)?
    /// The folder itself was moved, renamed or deleted.
    var onFolderChanged: (() -> Void)?

    let folder: URL
    private let now: () -> Date
    private let retryInterval: Duration
    private let attributeTimeout: TimeInterval

    private var stream: StreamHandle?
    private var startedAt = Date.distantPast
    private var seen: Set<UInt64> = []
    private var pending: [UInt64: Pending] = [:]
    private var rescanTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var activity: NSObjectProtocol?

    private struct Pending {
        let url: URL
        let firstSeen: Date
        var lastSize: Int?
    }

    /// Newly created files only: ignore anything older than this.
    static let maximumAge: TimeInterval = 60

    init(folder: URL, now: @escaping () -> Date = Date.init, retryInterval: Duration = .milliseconds(150), attributeTimeout: TimeInterval = 3) {
        self.folder = folder
        self.now = now
        self.retryInterval = retryInterval
        self.attributeTimeout = attributeTimeout
    }

    var isRunning: Bool { stream != nil }

    func start() {
        guard stream == nil else { return }
        startedAt = now()
        // Everything already there is old.
        for file in listing() { seen.insert(file.id) }

        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, _, flags, _ in
            guard let info else { return }
            let watcher = Unmanaged<ScreenshotWatcher>.fromOpaque(info).takeUnretainedValue()
            let flagList = Array(UnsafeBufferPointer(start: flags, count: count))
            MainActor.assumeIsolated { watcher.handle(flagList) }
        }
        let flags = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot | kFSEventStreamCreateFlagNoDefer)
        guard let created = FSEventStreamCreate(nil, callback, &context, [folder.path] as CFArray,
                                                FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 0.05, flags)
        else {
            Logger.app.error("Couldn't watch the screenshot folder")
            return
        }
        FSEventStreamSetDispatchQueue(created, DispatchQueue.main)
        let handle = StreamHandle(created)
        guard FSEventStreamStart(created) else {
            Logger.app.error("Couldn't start watching the screenshot folder")
            return
        }
        stream = handle
    }

    func stop() {
        stream = nil
        rescanTask?.cancel()
        retryTask?.cancel()
        pending.removeAll()
        endActivity()
    }

    /// Owns an FSEvents stream and tears it down when released (FSEvents
    /// allows that from any thread), so the watcher needs no deinit.
    private nonisolated final class StreamHandle: @unchecked Sendable {
        let stream: FSEventStreamRef

        init(_ stream: FSEventStreamRef) {
            self.stream = stream
        }

        deinit {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }

    // MARK: Events

    private func handle(_ flags: [FSEventStreamEventFlags]) {
        if flags.contains(where: { $0 & FSEventStreamEventFlags(kFSEventStreamEventFlagRootChanged) != 0 }) {
            onFolderChanged?()
            return
        }
        scheduleRescan()
    }

    /// Several events arrive per screenshot; look once they've settled.
    private func scheduleRescan() {
        rescanTask?.cancel()
        rescanTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled else { return }
            self?.rescan()
        }
    }

    /// Looks for new files now (also after wake or a missed event).
    func rescan() {
        let current = now()
        for file in listing() where !seen.contains(file.id) && pending[file.id] == nil {
            let isNew = file.created >= startedAt.addingTimeInterval(-2) && current.timeIntervalSince(file.created) <= Self.maximumAge
            guard isNew, file.isImage else {
                seen.insert(file.id)
                continue
            }
            pending[file.id] = Pending(url: file.url, firstSeen: current)
        }
        checkPending()
    }

    private func checkPending() {
        for (id, entry) in pending {
            switch readiness(of: entry) {
            case .ready(let arrival):
                pending[id] = nil
                seen.insert(id)
                onScreenshot?(arrival)
            case .notAScreenshot, .gone:
                pending[id] = nil
                seen.insert(id)
            case .waiting(let size):
                if now().timeIntervalSince(entry.firstSeen) > attributeTimeout + 2 {
                    pending[id] = nil
                    seen.insert(id)
                } else {
                    pending[id]?.lastSize = size
                }
            }
        }
        if pending.isEmpty {
            retryTask?.cancel()
            retryTask = nil
            endActivity()
        } else {
            beginActivity()
            scheduleRetry()
        }
    }

    private func scheduleRetry() {
        guard retryTask == nil else { return }
        retryTask = Task { [weak self, retryInterval] in
            try? await Task.sleep(for: retryInterval)
            guard !Task.isCancelled, let self else { return }
            self.retryTask = nil
            self.checkPending()
        }
    }

    private enum Readiness {
        case ready(Arrival)
        case waiting(size: Int?)
        case notAScreenshot
        case gone
    }

    private func readiness(of entry: Pending) -> Readiness {
        let url = entry.url
        guard let values = url.freshResourceValues([.fileSizeKey, .creationDateKey]), let size = values.fileSize else { return .gone }
        guard let flag = ScreenshotFile.isScreenCapture(url) else {
            return now().timeIntervalSince(entry.firstSeen) > attributeTimeout ? .notAScreenshot : .waiting(size: size)
        }
        guard flag else { return .notAScreenshot }
        // Same size twice in a row, and the image decodes completely.
        guard size > 0, entry.lastSize == size, Self.isCompleteImage(url) else { return .waiting(size: size) }
        guard let identity = FileIdentity.of(url) else { return .gone }
        return .ready(Arrival(
            url: url, identity: identity, created: values.creationDate ?? now(),
            globalRect: ScreenshotFile.globalRect(url), captureType: ScreenshotFile.captureType(url)
        ))
    }

    static func isCompleteImage(_ url: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return false }
        return CGImageSourceGetStatus(source) == .statusComplete && CGImageSourceGetCount(source) > 0
    }

    // MARK: Listing

    private struct Entry {
        let url: URL
        let id: UInt64
        let created: Date
        let isImage: Bool
    }

    /// The folder's visible regular files (not subfolders).
    private func listing() -> [Entry] {
        let keys: [URLResourceKey] = [.fileIdentifierKey, .creationDateKey, .isRegularFileKey, .contentTypeKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]) else {
            return []
        }
        return urls.compactMap { url in
            guard !url.lastPathComponent.hasPrefix("."),
                  let values = url.freshResourceValues(Set(keys)),
                  values.isRegularFile == true, let id = values.fileIdentifier
            else { return nil }
            let type = values.contentType ?? UTType(filenameExtension: url.pathExtension)
            let isImage = type.map { $0.conforms(to: .image) || $0.conforms(to: .pdf) } ?? false
            return Entry(url: url, id: id, created: values.creationDate ?? .distantPast, isImage: isImage)
        }
    }

    private func beginActivity() {
        guard activity == nil else { return }
        // App Nap could stretch the short retries into seconds.
        activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated], reason: "Reading a new screenshot")
    }

    private func endActivity() {
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        activity = nil
    }
}
