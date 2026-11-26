import AppKit
import OSLog
import ScreenCaptureKit

/// The app's own capture: freezes every display (ScreenCaptureKit), lets the
/// user drag an area or click a window, and hands back the pixels. Faster
/// than ⌘⇧4 + folder watching, since there's no file and no thumbnail delay.
///
/// Screen Recording permission is asked the first time it's used, never at
/// launch; watching the screenshot folder never needs it.
final class CaptureController {
    enum Result {
        case captured(LoadedImage, globalRect: CGRect)
        case cancelled
        case needsPermission
        case failed(String)
    }

    private var overlays: [CaptureOverlayWindow] = []
    private var completion: ((Result) -> Void)?
    private var previousApp: NSRunningApplication?
    private var screenObserver: NSObjectProtocol?
    private var isStarting = false

    private static let askedKey = "AskedForScreenRecording"

    var isActive: Bool { !overlays.isEmpty || isStarting }

    func start(completion: @escaping (Result) -> Void) {
        guard !isActive else { return }
        isStarting = true
        previousApp = NSWorkspace.shared.frontmostApplication
        Task {
            defer { isStarting = false }
            guard await ensurePermission() else {
                completion(.cancelled)
                return
            }
            do {
                let frozen = try await freezeDisplays()
                guard !frozen.isEmpty else {
                    completion(.failed("No display could be captured."))
                    return
                }
                self.completion = completion
                showOverlays(frozen, windows: Self.onScreenWindows())
            } catch let error as SCStreamError where error.code == .userDeclined {
                showPermissionHelp()
                completion(.cancelled)
            } catch {
                Logger.app.error("Capture failed: \(error.localizedDescription, privacy: .public)")
                if !CGPreflightScreenCaptureAccess() {
                    showPermissionHelp()
                    completion(.cancelled)
                } else {
                    completion(.failed(error.localizedDescription))
                }
            }
        }
    }

    // MARK: Permission

    /// The first time, explains why before macOS asks. After that, the
    /// capture itself is the real test (the preflight check can be stale
    /// until the app is reopened).
    private func ensurePermission() async -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: Self.askedKey) {
            let alert = NSAlert()
            alert.messageText = "Allow Screen Recording for the capture shortcut"
            alert.informativeText = "Screenshot Redactor captures your screen only when you press its shortcut, and the image never leaves this Mac. macOS will ask you to allow this once.\n\nWatching your screenshot folder doesn't need this permission."
            alert.addButton(withTitle: "Continue")
            alert.addButton(withTitle: "Cancel")
            NSApp.activate()
            guard alert.runModal() == .alertFirstButtonReturn else { return false }
            defaults.set(true, forKey: Self.askedKey)
            if CGRequestScreenCaptureAccess() { return true }
            // Not granted yet: macOS showed its prompt or System Settings.
            return false
        }
        // Asked before: try anyway; a refusal comes back as an error.
        return true
    }

    private func showPermissionHelp() {
        let alert = NSAlert()
        alert.messageText = "Screen Recording is turned off"
        alert.informativeText = "To use the capture shortcut, turn on Screenshot Redactor in System Settings › Privacy & Security › Screen & System Audio Recording. If you just turned it on, quit and reopen the app.\n\nYour screenshot folder keeps working without it."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Quit & Reopen")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
            }
        case .alertSecondButtonReturn:
            Self.relaunch()
        default:
            break
        }
    }

    static func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    // MARK: Freezing the displays

    struct Frozen {
        let screen: NSScreen
        let image: CGImage
        /// Pixels per point of `image`.
        let scale: CGFloat
    }

    /// Every display, captured first (without this app's own windows or the
    /// cursor), so the overlays show a still picture to select from.
    private func freezeDisplays() async throws -> [Frozen] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let ownApp = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        var frozen: [Frozen] = []
        for display in content.displays {
            guard let screen = NSScreen.screens.first(where: { $0.displayID == display.displayID }) else { continue }
            let filter = SCContentFilter(display: display, excludingApplications: ownApp, exceptingWindows: [])
            let info = SCShareableContent.info(for: filter)
            let configuration = SCStreamConfiguration()
            // The default is 1920×1080: always ask for the display's real pixels.
            configuration.width = Int((info.contentRect.width * CGFloat(info.pointPixelScale)).rounded())
            configuration.height = Int((info.contentRect.height * CGFloat(info.pointPixelScale)).rounded())
            configuration.captureResolution = .best
            configuration.showsCursor = false
            configuration.scalesToFit = false
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            frozen.append(Frozen(screen: screen, image: image, scale: CGFloat(image.width) / screen.frame.width))
        }
        return frozen
    }

    /// On-screen app windows, front to back, in Cocoa coordinates, for
    /// "click a window". Bounds only (no titles), which needs no extra permission.
    static func onScreenWindows() -> [CGRect] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]],
              let mainHeight = NSScreen.screens.first?.frame.height
        else { return [] }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        return list.compactMap { info in
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  (info[kCGWindowOwnerPID as String] as? Int32) != ownPID,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0.05,
                  let boundsInfo = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsInfo),
                  bounds.width >= 40, bounds.height >= 40
            else { return nil }
            return CaptureGeometry.cocoa(fromCGGlobal: bounds, mainHeight: mainHeight)
        }
    }

    // MARK: Overlays

    private func showOverlays(_ frozen: [Frozen], windows: [CGRect]) {
        NSApp.activate()
        overlays = frozen.map { item in
            let overlay = CaptureOverlayWindow(screen: item.screen, image: item.image, windows: windows)
            overlay.onFinish = { [weak self] selection in self?.finish(selection, frozen: frozen) }
            overlay.onCancel = { [weak self] in self?.finish(nil, frozen: frozen) }
            return overlay
        }
        for overlay in overlays { overlay.orderFrontRegardless() }
        let underMouse = overlays.first { $0.frame.contains(NSEvent.mouseLocation) } ?? overlays.first
        underMouse?.makeKey()
        NSCursor.crosshair.set()
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.finish(nil, frozen: frozen) }
        }
    }

    /// Closes the overlays and returns the selected pixels (nil: cancelled).
    private func finish(_ selection: CGRect?, frozen: [Frozen]) {
        guard let completion else { return }
        self.completion = nil
        for overlay in overlays { overlay.orderOut(nil) }
        overlays.removeAll()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        NSCursor.arrow.set()
        previousApp?.activate()

        guard let selection, selection.width >= 2, selection.height >= 2,
              let source = frozen.first(where: { $0.screen.frame.intersects(selection) && $0.screen.frame.contains(CGPoint(x: selection.midX, y: selection.midY)) })
                ?? frozen.first(where: { $0.screen.frame.intersects(selection) })
        else {
            completion(.cancelled)
            return
        }
        let pixels = CaptureGeometry.pixelRect(selection: selection, screenFrame: source.screen.frame, scale: source.scale)
        guard let cropped = source.image.cropping(to: pixels) else {
            completion(.failed("The selected area couldn't be read."))
            return
        }
        let mainHeight = NSScreen.screens.first?.frame.height ?? source.screen.frame.height
        let global = CaptureGeometry.cgGlobal(fromCocoa: selection.intersection(source.screen.frame), mainHeight: mainHeight)
        completion(.captured(LoadedImage(image: cropped, dpi: 72 * source.scale), globalRect: global))
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber).map { CGDirectDisplayID($0.uint32Value) }
    }
}
