import OSLog

extension Logger {
    /// The app's log. Never log recognised text, matches or file contents:
    /// counts and states only.
    nonisolated static let app = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ScreenshotRedactor", category: "App")
}
