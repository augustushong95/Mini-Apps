import AppKit
import SwiftUI

/// Shows one SwiftUI surface in a `FloatingPanel` and closes it when the
/// user clicks elsewhere or presses Esc.
final class PanelController {
    let panel: FloatingPanel
    var onClose: (() -> Void)?
    private var outsideClickMonitor: Any?
    private var closeObserver: NSObjectProtocol?
    /// Closes when the user clicks outside or presses Esc.
    private let dismissesOnOutsideClick: Bool

    init<Content: View>(size: NSSize, canBecomeKey: Bool = true, level: NSWindow.Level = .statusBar,
                        dismissesOnOutsideClick: Bool = true, content: Content) {
        panel = FloatingPanel(size: size, canBecomeKey: canBecomeKey, level: level)
        self.dismissesOnOutsideClick = dismissesOnOutsideClick
        panel.setContent(content)
        panel.onCancel = { [weak self] in self?.close() }
        // If anything closes the window directly (not through `close`),
        // still remove the monitor and report the close.
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: panel, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.removeMonitor()
                self.onClose?()
            }
        }
    }

    var isVisible: Bool { panel.isVisible }

    func show(at origin: NSPoint, animated: Bool = true) {
        let wasVisible = panel.isVisible
        panel.present(at: origin, animated: animated && !wasVisible)
        // Reopening during a fade-out leaves the panel visible but without
        // a monitor, so check the monitor rather than visibility.
        guard outsideClickMonitor == nil, dismissesOnOutsideClick else { return }
        // Clicks in other apps close the panel. Clicks in our own windows
        // (the status item included) don't reach a global monitor, so the
        // status item can toggle it without a close-then-reopen flicker.
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
    }

    func close(animated: Bool = true) {
        removeMonitor()
        guard panel.isVisible else { return }
        panel.dismiss(animated: animated) { [weak self] in
            self?.onClose?()
        }
    }

    private func removeMonitor() {
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
    }

    /// The panel's size once SwiftUI has laid out its content.
    var fittingSize: NSSize {
        panel.contentView?.fittingSize ?? panel.frame.size
    }
}
