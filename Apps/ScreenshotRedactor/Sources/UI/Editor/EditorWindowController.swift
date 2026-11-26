import AppKit
import SwiftUI

/// The editor window: one at a time, showing the capture being reviewed.
/// A regular window that activates the app while it's open, so the keyboard
/// shortcuts work as in any Mac app.
final class EditorWindowController: NSObject, NSWindowDelegate {
    private var window: EditorWindow?
    private(set) var model: EditorModel?
    private let exporter: Exporter
    private let allowance: DailyAllowance
    private var flashTask: Task<Void, Never>?

    var onUpgrade: (() -> Void)?
    /// ⌘V in the editor: an image from the clipboard to redact.
    var onPaste: (() -> Void)?

    init(exporter: Exporter, allowance: DailyAllowance) {
        self.exporter = exporter
        self.allowance = allowance
    }

    var isOpen: Bool { window?.isVisible == true }
    var document: RedactionDocument? { model?.document }

    func open(_ document: RedactionDocument) {
        let model = EditorModel(document: document, allowance: allowance)
        model.actions = EditorModel.Actions(
            copy: { [weak self] in self?.copyImage() },
            save: { [weak self] in self?.saveImage() },
            upgrade: { [weak self] in self?.onUpgrade?() },
            close: { [weak self] in self?.window?.performClose(nil) },
            dragFile: { [weak self] in self?.dragFile() },
            dragEnded: { [weak self] dropped in self?.dragEnded(dropped) }
        )
        self.model = model

        let window = self.window ?? makeWindow()
        window.title = document.name
        window.contentView = NSHostingView(rootView: EditorView(model: model))
        if !window.isVisible {
            window.setContentSize(Self.initialSize(for: document, on: window.screen ?? NSScreen.main))
            window.center()
        }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }

    func close() {
        window?.performClose(nil)
    }

    private func makeWindow() -> EditorWindow {
        let window = EditorWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.titlebarAppearsTransparent = false
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 760, height: 480)
        window.tabbingMode = .disallowed
        window.collectionBehavior = [.fullScreenPrimary]
        window.delegate = self
        window.keyEquivalentHandler = { [weak self] event in self?.handleKeyEquivalent(event) ?? false }
        window.onOptionChanged = { [weak self] held in self?.model?.isPeeking = held }
        return window
    }

    /// Big enough to show the image at its point size, within most of the screen.
    static func initialSize(for document: RedactionDocument, on screen: NSScreen?) -> NSSize {
        let visible = screen?.visibleFrame.size ?? NSSize(width: 1440, height: 900)
        let imagePoints = NSSize(width: document.pixelSize.width * 72 / document.dpi, height: document.pixelSize.height * 72 / document.dpi)
        let width = min(max(imagePoints.width + 270 + 48, 760), visible.width * 0.85)
        let height = min(max(imagePoints.height + 44 + 48, 480), visible.height * 0.85)
        return NSSize(width: width.rounded(), height: height.rounded())
    }

    func windowWillClose(_ notification: Notification) {
        model = nil
        // Back to the app the user was in.
        DispatchQueue.main.async {
            if !NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeMain }) { NSApp.deactivate() }
        }
    }

    // MARK: Actions

    private func copyImage() {
        guard let model else { return }
        Task {
            switch await exporter.copy(model.document) {
            case .done: flash("Copied")
            case .limitReached: onUpgrade?()
            case .failed(let message): flash(message)
            case .cancelled: break
            }
        }
    }

    private func saveImage() {
        guard let model else { return }
        Task {
            switch await exporter.save(model.document) {
            case .done: flash("Saved")
            case .limitReached: onUpgrade?()
            case .failed(let message): flash(message)
            case .cancelled: break
            }
        }
    }

    private func dragFile() -> URL? {
        guard let model else { return nil }
        return exporter.dragFile(for: model.document)
    }

    private func dragEnded(_ dropped: Bool) {
        guard dropped, let model else { return }
        exporter.dragCompleted(model.document)
        flash("Dropped")
    }

    private func flash(_ text: String) {
        model?.flash = text
        flashTask?.cancel()
        flashTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, self?.model?.flash == text else { return }
            self?.model?.flash = nil
        }
    }

    private func handleKeyEquivalent(_ event: NSEvent) -> Bool {
        guard let model else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        switch (flags, key) {
        case (.command, "c"):
            if model.isLocked { onUpgrade?() } else { copyImage() }
        case (.command, "s"):
            saveImage()
        case (.command, "z"):
            model.document.undo()
        case ([.command, .shift], "z"):
            model.document.redo()
        case (.command, "0"):
            model.zoom = .fit
        case (.command, "1"):
            model.zoom = .actual
        case (.command, "v"):
            onPaste?()
        case (.command, "w"):
            window?.performClose(nil)
        case (.command, "a"):
            model.document.setCovered(true, ids: Set(model.document.boxes.map(\.id)))
        default:
            return false
        }
        return true
    }
}

/// Gives the editor first look at key equivalents and tells it when ⌥ is held.
final class EditorWindow: NSWindow {
    var keyEquivalentHandler: ((NSEvent) -> Bool)?
    var onOptionChanged: ((Bool) -> Void)?
    private var optionHeld = false

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if keyEquivalentHandler?(event) == true { return true }
        return super.performKeyEquivalent(with: event)
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .flagsChanged {
            let held = event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .option
            if held != optionHeld {
                optionHeld = held
                onOptionChanged?(held)
            }
        }
        super.sendEvent(event)
    }

    override func resignKey() {
        super.resignKey()
        if optionHeld {
            optionHeld = false
            onOptionChanged?(false)
        }
    }
}
