import AppKit
import Observation

/// Why Mochi is keeping quiet. While quiet, no bubbles appear; the menu bar
/// icon still changes expression.
enum QuietReason: Equatable {
    case manual(until: Date)
    case call(app: String?)
    case fullScreen(app: String?)
    case screensAsleep

    var title: String {
        switch self {
        case .manual: "Quiet on"
        case .call: "On a call"
        case .fullScreen: "Full-screen app"
        case .screensAsleep: "Display asleep"
        }
    }

    var detail: String {
        switch self {
        case .manual(let until):
            "Until \(until.formatted(date: .omitted, time: .shortened))"
        case .call(let app):
            app.map { "\(Self.appName($0)) is using the microphone" } ?? "A microphone is in use"
        case .fullScreen(let app):
            app.map { "\(Self.appName($0)) is full screen" } ?? "An app is full screen"
        case .screensAsleep:
            "Back when you are"
        }
    }

    var symbol: String {
        switch self {
        case .manual: "moon.fill"
        case .call: "phone.fill"
        case .fullScreen: "rectangle.inset.filled"
        case .screensAsleep: "display"
        }
    }

    private static func appName(_ bundleID: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        }
        return bundleID.components(separatedBy: ".").last ?? bundleID
    }
}

/// Watches for moments when a bubble would be unwelcome: calls (any app
/// using a microphone), a full-screen app in front (video, slides), the
/// display being asleep, and the user's own "Quiet for…".
///
/// Display mirroring and camera use are deliberately not signals; see NOTES.md.
@Observable
final class QuietDetector {
    private(set) var reason: QuietReason?
    var isQuiet: Bool { reason != nil }

    @ObservationIgnored private let settings: Preferences
    /// Calls and full-screen apps. Injectable so tests don't depend on what
    /// the Mac happens to be doing.
    @ObservationIgnored private let systemSignals: @MainActor () -> QuietReason?
    @ObservationIgnored private var screensAsleep = false
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    /// Processes that hold the mic without being a call.
    private static let ignoredInputProcesses: Set<String> = [
        "com.apple.SpeechRecognitionCore.speechrecognitiond",
        "com.apple.corespeechd",
        "com.apple.assistantd",
    ]

    init(settings: Preferences, systemSignals: @escaping @MainActor () -> QuietReason? = QuietDetector.liveSignals) {
        self.settings = settings
        self.systemSignals = systemSignals
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.screensAsleep = true
                self?.refresh()
            }
        })
        observers.append(workspace.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.screensAsleep = false
                self?.refresh()
            }
        })
    }

    /// Re-reads every signal. Cheap enough to call every few seconds and
    /// right before showing anything.
    @discardableResult
    func refresh(now: Date = .now) -> QuietReason? {
        let newReason = evaluate(now: now)
        // Observers are notified on every assignment, so only assign changes.
        if newReason != reason {
            reason = newReason
        }
        return newReason
    }

    private func evaluate(now: Date) -> QuietReason? {
        if let until = settings.quietUntil {
            if until > now {
                return .manual(until: until)
            }
            settings.quietUntil = nil
        }
        if screensAsleep {
            return .screensAsleep
        }
        return systemSignals()
    }

    /// The real signals: any app using a microphone, or a full-screen app in front.
    static func liveSignals() -> QuietReason? {
        let audio = AudioInputProbe.snapshot()
        let callers = audio.inputProcesses.filter { !Self.ignoredInputProcesses.contains($0) }
        if !callers.isEmpty {
            return .call(app: callers.first)
        }
        if !audio.runningInputDevices.isEmpty {
            return .call(app: nil)
        }
        let display = DisplayProbe.snapshot()
        if display.frontmostCoversScreen {
            return .fullScreen(app: display.frontmostApp)
        }
        return nil
    }
}

/// Whether the user is at the Mac.
///
/// Present means recent keyboard or mouse input, or, without input, a head
/// in a normal sitting position (watching a video with AirPods in is still
/// sitting). Away for 5 minutes counts as a break.
enum Presence {
    /// Input within this many seconds always means present.
    static let inputWindow: TimeInterval = 90
    /// Beyond this, no amount of head motion keeps the user "present".
    static let headOnlyLimit: TimeInterval = 15 * 60

    static func isPresent(idleSeconds: TimeInterval, motionLive: Bool, postureKnown: Bool) -> Bool {
        if idleSeconds < inputWindow {
            return true
        }
        return motionLive && postureKnown && idleSeconds < headOnlyLimit
    }
}
