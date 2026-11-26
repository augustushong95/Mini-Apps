import AppKit
import CoreGraphics

/// Display-level quiet signals: mirroring (presenting on a projector or TV)
/// and a frontmost app covering a whole screen (full-screen video, a slide
/// show). Uses window bounds and owner PIDs only, which don't need the
/// Screen Recording permission.
enum DisplayProbe {
    struct Snapshot: Sendable, Equatable {
        var isMirroring: Bool
        var frontmostCoversScreen: Bool
        var frontmostApp: String?
    }

    static func snapshot() -> Snapshot {
        let front = NSWorkspace.shared.frontmostApplication
        return Snapshot(
            isMirroring: isMirroring(),
            frontmostCoversScreen: front.map(coversAScreen) ?? false,
            frontmostApp: front?.bundleIdentifier
        )
    }

    static func isMirroring() -> Bool {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return false }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displays, &count) == .success else { return false }
        return displays.prefix(Int(count)).contains { CGDisplayIsInMirrorSet($0) != 0 }
    }

    /// Whether the given app has a normal-level window exactly the size of a
    /// screen. A maximized window never qualifies because the menu bar takes
    /// space; a full-screen window or a borderless presentation does.
    static func coversAScreen(_ app: NSRunningApplication) -> Bool {
        guard app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[CFString: Any]]
        else { return false }

        let screenSizes = NSScreen.screens.map(\.frame.size)
        return windows.contains { window in
            guard (window[kCGWindowOwnerPID] as? pid_t) == app.processIdentifier,
                  (window[kCGWindowLayer] as? Int) == 0,
                  let boundsDictionary = window[kCGWindowBounds] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary)
            else { return false }
            return screenSizes.contains { $0 == bounds.size }
        }
    }
}

/// Seconds since the last keyboard, mouse or trackpad input from the user.
/// A plain read of the session's event state: no Input Monitoring permission.
nonisolated enum IdleProbe {
    static func secondsSinceLastInput() -> TimeInterval {
        // ~0 is kCGAnyInputEventType, which Swift doesn't import.
        guard let anyInput = CGEventType(rawValue: ~0) else { return 0 }
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
    }
}
