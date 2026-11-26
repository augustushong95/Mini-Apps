import Foundation
import Observation

/// What happens when a screenshot has been scanned.
enum ReadyAction: String, CaseIterable, Codable {
    /// Show the preview card; the user copies from it.
    case showPreview
    /// Also put the redacted image on the clipboard straight away.
    case copyAutomatically

    var title: String {
        switch self {
        case .showPreview: "Show a preview"
        case .copyAutomatically: "Copy it automatically"
        }
    }
}

/// What happens to the original screenshot file after a redacted version
/// is copied, dragged or saved.
enum OriginalHandling: String, CaseIterable, Codable {
    case keep
    case moveToTrash

    var title: String {
        switch self {
        case .keep: "Keep the original"
        case .moveToTrash: "Move the original to the Trash"
        }
    }
}

/// The user's settings, saved in UserDefaults. Tests pass their own defaults.
@Observable
final class Preferences {
    @ObservationIgnored private let defaults: UserDefaults

    var watchesFolder: Bool { didSet { defaults.set(watchesFolder, forKey: Keys.watchesFolder) } }
    var readyAction: ReadyAction { didSet { defaults.set(readyAction.rawValue, forKey: Keys.readyAction) } }
    var originalHandling: OriginalHandling { didSet { defaults.set(originalHandling.rawValue, forKey: Keys.originalHandling) } }
    var closesPreviewAfterCopy: Bool { didSet { defaults.set(closesPreviewAfterCopy, forKey: Keys.closesPreviewAfterCopy) } }
    var boxColor: BoxColor { didSet { defaults.set(boxColor.rawValue, forKey: Keys.boxColor) } }
    var showsLabels: Bool { didSet { defaults.set(showsLabels, forKey: Keys.showsLabels) } }
    var detection: DetectionSettings { didSet { save(detection, forKey: Keys.detection) } }
    var hotKey: KeyCombo? { didSet { save(hotKey, forKey: Keys.hotKey) } }
    var onboardingCompleted: Bool { didSet { defaults.set(onboardingCompleted, forKey: Keys.onboardingCompleted) } }

    /// The screenshot folder's security-scoped bookmark, and where it pointed.
    var folderBookmark: Data? { didSet { defaults.set(folderBookmark, forKey: Keys.folderBookmark) } }
    var folderPath: String? { didSet { defaults.set(folderPath, forKey: Keys.folderPath) } }

    var renderStyle: RenderStyle { RenderStyle(color: boxColor, showsLabels: showsLabels) }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Keys.watchesFolder: true,
            Keys.closesPreviewAfterCopy: true,
        ])
        watchesFolder = defaults.bool(forKey: Keys.watchesFolder)
        readyAction = defaults.string(forKey: Keys.readyAction).flatMap(ReadyAction.init) ?? .showPreview
        originalHandling = defaults.string(forKey: Keys.originalHandling).flatMap(OriginalHandling.init) ?? .keep
        closesPreviewAfterCopy = defaults.bool(forKey: Keys.closesPreviewAfterCopy)
        boxColor = defaults.string(forKey: Keys.boxColor).flatMap(BoxColor.init) ?? .black
        showsLabels = defaults.bool(forKey: Keys.showsLabels)
        detection = Self.load(DetectionSettings.self, from: defaults, key: Keys.detection) ?? DetectionSettings()
        hotKey = defaults.object(forKey: Keys.hotKey) == nil
            ? KeyCombo.defaultCapture
            : Self.load(KeyCombo.self, from: defaults, key: Keys.hotKey)
        onboardingCompleted = defaults.bool(forKey: Keys.onboardingCompleted)
        folderBookmark = defaults.data(forKey: Keys.folderBookmark)
        folderPath = defaults.string(forKey: Keys.folderPath)
    }

    private enum Keys {
        static let watchesFolder = "WatchesFolder"
        static let readyAction = "ReadyAction"
        static let originalHandling = "OriginalHandling"
        static let closesPreviewAfterCopy = "ClosesPreviewAfterCopy"
        static let boxColor = "BoxColor"
        static let showsLabels = "ShowsLabels"
        static let detection = "Detection"
        static let hotKey = "CaptureHotKey"
        static let onboardingCompleted = "OnboardingCompleted"
        static let folderBookmark = "FolderBookmark"
        static let folderPath = "FolderPath"
    }

    /// Optional values are stored as JSON; `nil` is stored as JSON null so
    /// "no shortcut" is remembered rather than falling back to the default.
    private func save<Value: Encodable>(_ value: Value, forKey key: String) {
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        }
    }

    private static func load<Value: Decodable>(_ type: Value.Type, from defaults: UserDefaults, key: String) -> Value? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Value.self, from: data)
    }
}
