import AppKit
import Observation
import OSLog

/// Access to the folder screenshots are saved in.
///
/// The sandbox can't read the system's screenshot settings, so the user
/// picks the folder once (usually ~/Desktop) and the app keeps a
/// security-scoped bookmark. Access is opened once and held for the app's
/// lifetime, then reopened only when the folder changes.
@Observable
final class FolderAccess {
    enum Status: Equatable {
        /// No folder chosen yet.
        case notChosen
        case available(URL)
        /// Chosen before, but it can't be reached now (deleted, on an
        /// unmounted drive, or access was revoked).
        case unavailable(path: String)
    }

    private(set) var status: Status = .notChosen
    @ObservationIgnored private let preferences: Preferences
    @ObservationIgnored private var accessedURL: URL?

    init(preferences: Preferences) {
        self.preferences = preferences
        resolve()
    }

    var url: URL? {
        if case .available(let url) = status { return url }
        return nil
    }

    /// "Desktop", or the folder's name.
    var displayName: String {
        switch status {
        case .available(let url): Self.displayName(for: url)
        case .unavailable(let path): Self.displayName(for: URL(fileURLWithPath: path))
        case .notChosen: "No folder"
        }
    }

    static func displayName(for url: URL) -> String {
        FileManager.default.displayName(atPath: url.path)
    }

    /// The user's real home folder; in the sandbox `homeDirectoryForCurrentUser`
    /// points into the app's container.
    static var realHome: URL {
        if let entry = getpwuid(getuid()), let directory = entry.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: directory), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    /// Where macOS saves screenshots unless the user changed it.
    static var defaultScreenshotFolder: URL {
        realHome.appending(path: "Desktop", directoryHint: .isDirectory)
    }

    /// Opens the bookmark again (at launch, after wake, after a mount).
    func resolve() {
        guard let bookmark = preferences.folderBookmark else {
            stopAccessing()
            status = .notChosen
            return
        }
        var isStale = false
        do {
            let url = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope], bookmarkDataIsStale: &isStale)
            if accessedURL != url {
                stopAccessing()
                guard url.startAccessingSecurityScopedResource() else { throw CocoaError(.fileReadNoPermission) }
                accessedURL = url
            }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                throw CocoaError(.fileNoSuchFile)
            }
            if isStale {
                // Renamed or moved: refresh the bookmark while access is open.
                preferences.folderBookmark = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
            }
            preferences.folderPath = url.path
            status = .available(url)
        } catch {
            Logger.app.error("Screenshot folder unavailable: \(error.localizedDescription, privacy: .public)")
            stopAccessing()
            status = .unavailable(path: preferences.folderPath ?? "")
        }
    }

    /// Asks the user for the screenshot folder. Returns false if they cancel.
    @discardableResult
    func choose() -> Bool {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.prompt = "Allow Access"
        panel.message = "Choose the folder your screenshots are saved in. Screenshot Redactor only reads new screenshots there, and never uploads anything."
        panel.directoryURL = url ?? Self.defaultScreenshotFolder
        NSApp.activate()
        guard panel.runModal() == .OK, let chosen = panel.url else { return false }
        return use(chosen)
    }

    /// Remembers `url` as the screenshot folder (it must come from an open panel).
    @discardableResult
    func use(_ url: URL) -> Bool {
        do {
            let bookmark = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
            preferences.folderBookmark = bookmark
            preferences.folderPath = url.path
            stopAccessing()
            resolve()
            return self.url != nil
        } catch {
            Logger.app.error("Couldn't keep access to the folder: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    func forget() {
        stopAccessing()
        preferences.folderBookmark = nil
        preferences.folderPath = nil
        status = .notChosen
    }

    private func stopAccessing() {
        accessedURL?.stopAccessingSecurityScopedResource()
        accessedURL = nil
    }
}
