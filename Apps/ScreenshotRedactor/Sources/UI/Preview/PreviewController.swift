import AppKit
import MenuBarKit
import SwiftUI

/// The card that appears after each screenshot, at the top-right of the
/// display it came from (clear of the system thumbnail at the bottom-right).
///
/// It never takes keystrokes meant for another app: after a ⌘⇧4 screenshot
/// it appears without keyboard focus, and a click gives it focus (the click
/// also works). From then on ⌘C, ⌘S, ↩ and Esc act on it.
final class PreviewController {
    let model: PreviewModel
    var onEdit: ((RedactionDocument) -> Void)?
    var onUpgrade: (() -> Void)?

    private let panel: FloatingPanel
    private let exporter: Exporter
    private let preferences: Preferences
    private var hideTask: Task<Void, Never>?
    private var flashTask: Task<Void, Never>?
    private var isHovering = false

    /// How long the card stays when left alone.
    static let idleTimeout: Duration = .seconds(20)

    init(exporter: Exporter, allowance: DailyAllowance, preferences: Preferences) {
        self.exporter = exporter
        self.preferences = preferences
        model = PreviewModel(allowance: allowance)
        panel = FloatingPanel(size: PreviewModel.size(for: nil), canBecomeKey: true, level: .floating)
        panel.setContent(PreviewCardView(model: model))
        panel.onCancel = { [weak self] in self?.close() }
        panel.keyEquivalentHandler = { [weak self] event in self?.handleKeyEquivalent(event) ?? false }
        panel.keyDownHandler = { [weak self] event in self?.handleKeyDown(event) ?? false }

        model.onIndexChange = { [weak self] in self?.resizeKeepingTopRight() }
        model.actions = PreviewModel.Actions(
            copy: { [weak self] in self?.copy() },
            edit: { [weak self] in self?.edit() },
            save: { [weak self] in self?.save() },
            close: { [weak self] in self?.close() },
            revealOriginal: { [weak self] in self?.revealOriginal() },
            trashOriginal: { [weak self] in self?.trashOriginal() },
            upgrade: { [weak self] in self?.onUpgrade?() },
            dragFile: { [weak self] in self?.dragFile() },
            dragEnded: { [weak self] dropped in self?.dragEnded(dropped) },
            hover: { [weak self] hovering in self?.hoverChanged(hovering) }
        )
    }

    var isVisible: Bool { panel.isVisible }
    var currentDocument: RedactionDocument? { model.document }

    /// Shows `documents` (one capture, or a ⌘⇧3 burst), replacing what was there.
    func show(_ documents: [RedactionDocument], takesFocus: Bool = false) {
        guard !documents.isEmpty else { return }
        model.documents = documents
        model.index = 0
        model.flash = nil
        place(animated: !panel.isVisible, takesFocus: takesFocus)
        restartIdleTimer()
    }

    /// Adds a screenshot from the same burst to the card already showing.
    func append(_ document: RedactionDocument) {
        guard panel.isVisible, model.documents.first?.burstID != nil, model.documents.first?.burstID == document.burstID else {
            show([document])
            return
        }
        model.documents.append(document)
        restartIdleTimer()
    }

    func close() {
        hideTask?.cancel()
        flashTask?.cancel()
        panel.dismiss(animated: true)
    }

    /// The document was removed or replaced elsewhere.
    func closeIfShowing(_ document: RedactionDocument) {
        if model.documents.contains(where: { $0.id == document.id }) { close() }
    }

    // MARK: Placement

    private func place(animated: Bool, takesFocus: Bool) {
        let size = PreviewModel.size(for: model.document)
        panel.setContentSize(size)
        let screen = Self.screen(for: model.document?.globalRect)
        let origin = PanelPlacement.topTrailing(on: screen, size: size)
        panel.present(at: origin, animated: animated, takesFocus: takesFocus)
    }

    /// A capture of another shape: same top-right corner, new size.
    private func resizeKeepingTopRight() {
        guard panel.isVisible else { return }
        let size = PreviewModel.size(for: model.document)
        let frame = panel.frame
        panel.setFrame(NSRect(x: frame.maxX - size.width, y: frame.maxY - size.height, width: size.width, height: size.height), display: true)
    }

    /// The display a capture came from: its rect is in global points with
    /// the origin at the top-left of the main display; screens use bottom-left.
    static func screen(for globalRect: CGRect?) -> NSScreen? {
        let main = NSScreen.screens.first
        if let globalRect, let main {
            let center = NSPoint(x: globalRect.midX, y: main.frame.maxY - globalRect.midY)
            if let screen = NSScreen.screens.first(where: { $0.frame.contains(center) }) { return screen }
        }
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
    }

    // MARK: Actions

    func copy() {
        guard let document = model.document else { return }
        restartIdleTimer()
        Task {
            let outcome = await exporter.copy(document)
            handle(outcome, success: .copied, closeAfter: preferences.closesPreviewAfterCopy)
        }
    }

    /// The scan finished and the user chose "Copy automatically".
    func copyAutomatically(_ document: RedactionDocument) {
        Task {
            let outcome = await exporter.copy(document)
            guard model.documents.contains(where: { $0.id == document.id }) else { return }
            if outcome == .done { flash(.copiedAutomatically) } else { handle(outcome, success: .copiedAutomatically, closeAfter: false) }
        }
    }

    func save() {
        guard let document = model.document else { return }
        hideTask?.cancel()
        Task {
            let outcome = await exporter.save(document)
            handle(outcome, success: .saved, closeAfter: false)
            restartIdleTimer()
        }
    }

    func edit() {
        guard let document = model.document, document.state == .ready else { return }
        close()
        onEdit?(document)
    }

    private func revealOriginal() {
        guard let url = model.document?.originalURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func trashOriginal() {
        guard let document = model.document else { return }
        if exporter.moveOriginalToTrash(document) {
            flash(.trashed)
        } else {
            flash(.problem("The original couldn't be moved to the Trash."))
        }
    }

    private func dragFile() -> URL? {
        guard let document = model.document else { return nil }
        guard let url = exporter.dragFile(for: document) else {
            if !model.allowance.canExport(document) { NSSound.beep() }
            return nil
        }
        hideTask?.cancel()
        return url
    }

    private func dragEnded(_ dropped: Bool) {
        if dropped, let document = model.document {
            exporter.dragCompleted(document)
            flash(.copied)
        }
        restartIdleTimer()
    }

    private func handle(_ outcome: Exporter.Outcome, success: PreviewModel.Flash, closeAfter: Bool) {
        switch outcome {
        case .done:
            flash(success)
            if closeAfter {
                hideTask?.cancel()
                hideTask = Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(900))
                    guard !Task.isCancelled else { return }
                    self?.close()
                }
            }
        case .limitReached:
            flash(.problem("Today's free redactions are used up."))
        case .cancelled:
            break
        case .failed(let message):
            flash(.problem(message))
        }
    }

    private func flash(_ value: PreviewModel.Flash) {
        model.flash = value
        flashTask?.cancel()
        flashTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, self?.model.flash == value else { return }
            self?.model.flash = nil
        }
    }

    // MARK: Keyboard

    private func handleKeyEquivalent(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags == .command, let key = event.charactersIgnoringModifiers?.lowercased() else { return false }
        switch key {
        case "c":
            if model.isLocked { onUpgrade?() } else { copy() }
            return true
        case "s":
            save()
            return true
        case "w":
            close()
            return true
        default:
            return false
        }
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        switch Int(event.keyCode) {
        case 36, 76: // Return, Enter
            edit()
            return true
        case 123: // ←
            model.index = max(0, model.index - 1)
            return true
        case 124: // →
            model.index = min(model.documents.count - 1, model.index + 1)
            return true
        default:
            return false
        }
    }

    // MARK: Auto-hide

    private func hoverChanged(_ hovering: Bool) {
        isHovering = hovering
        if hovering { hideTask?.cancel() } else { restartIdleTimer() }
    }

    private func restartIdleTimer() {
        hideTask?.cancel()
        guard !isHovering else { return }
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: Self.idleTimeout)
            guard !Task.isCancelled else { return }
            self?.close()
        }
    }
}
