import CoreGraphics
import Foundation
import Observation

/// One image being redacted: the original pixels (kept only in memory), its
/// boxes, and the redacted render that every export uses.
@Observable
final class RedactionDocument: Identifiable {
    enum Origin: Equatable {
        /// A new file in the watched screenshot folder.
        case screenshot(URL, FileIdentity)
        /// Opened with Open Image… or dropped on the app.
        case file(URL)
        case clipboard
        /// The app's own capture shortcut.
        case capture
        /// The built-in sample; exporting it is always free.
        case sample
    }

    enum State: Equatable {
        case scanning
        case ready
        case failed(String)
    }

    let id = UUID()
    let origin: Origin
    /// Base name for exported files, e.g. "Screenshot 2026-11-26 at 10.00.00".
    let name: String
    let created: Date
    let image: CGImage
    let dpi: CGFloat
    /// Screenshots taken together (⌘⇧3 on several displays) share one.
    let burstID: UUID?
    /// Where on screen it was captured (global points, top-left origin).
    let globalRect: CGRect?

    private(set) var state: State = .scanning
    private(set) var boxes: [RedactionBox] = []
    /// The latest redacted pixels. Nil until the first render after the scan.
    private(set) var rendered: CGImage?
    private(set) var style: RenderStyle
    /// Custom rules that ran out of time during the scan.
    private(set) var timedOutRules: Set<UUID> = []
    /// Set once this capture has used one of the day's free redactions.
    var exportCounted = false
    /// Set when its original file was moved to the Trash.
    var originalTrashed = false

    @ObservationIgnored private var undoStack: [[RedactionBox]] = []
    @ObservationIgnored private var redoStack: [[RedactionBox]] = []
    private(set) var canUndo = false
    private(set) var canRedo = false

    @ObservationIgnored private var renderVersion = 0
    @ObservationIgnored private var renderTask: Task<CGImage?, Never>?
    @ObservationIgnored private var pngCache: (version: Int, data: Data)?
    private(set) var isRendering = false

    init(image: CGImage, dpi: CGFloat, origin: Origin, name: String, style: RenderStyle,
         burstID: UUID? = nil, globalRect: CGRect? = nil, created: Date = Date()) {
        self.image = image
        self.dpi = dpi
        self.origin = origin
        self.name = name
        self.style = style
        self.burstID = burstID
        self.globalRect = globalRect
        self.created = created
    }

    var pixelSize: CGSize { CGSize(width: image.width, height: image.height) }

    var isSample: Bool { origin == .sample }

    /// Ready to copy, drag or save: scanned, and the shown render matches the boxes.
    var isExportable: Bool { state == .ready && rendered != nil && !isRendering }

    var coveredCount: Int { boxes.filter(\.isCovered).count }

    /// Covered boxes per category, most sensitive first, for the card's chips.
    var coveredByCategory: [(category: FindingCategory, count: Int)] {
        FindingCategory.allCases.compactMap { category in
            let count = boxes.filter { $0.isCovered && $0.category == category }.count
            return count > 0 ? (category, count) : nil
        }
    }

    var originalURL: URL? {
        switch origin {
        case .screenshot(let url, _), .file(let url): url
        default: nil
        }
    }

    // MARK: Scan results

    func finishScan(_ result: ScanResult) {
        boxes = result.boxes
        timedOutRules = result.timedOutRules
        state = .ready
        render()
    }

    func failScan(_ message: String) {
        state = .failed(message)
    }

    // MARK: Editing

    /// Applies an edit as one undoable step and re-renders.
    func edit(_ change: (inout [RedactionBox]) -> Void) {
        var updated = boxes
        change(&updated)
        guard updated != boxes else { return }
        undoStack.append(boxes)
        if undoStack.count > 200 { undoStack.removeFirst() }
        redoStack.removeAll()
        boxes = updated
        updateUndoState()
        render()
    }

    func toggle(_ id: RedactionBox.ID) {
        edit { boxes in
            guard let index = boxes.firstIndex(where: { $0.id == id }) else { return }
            boxes[index].isCovered.toggle()
        }
    }

    func setCovered(_ covered: Bool, ids: Set<RedactionBox.ID>) {
        edit { boxes in
            for index in boxes.indices where ids.contains(boxes[index].id) {
                boxes[index].isCovered = covered
            }
        }
    }

    /// Adds a box the user drew. Tiny drags (a stray click) are ignored.
    @discardableResult
    func addManualBox(_ rect: CGRect) -> RedactionBox.ID? {
        let clamped = BoxGeometry.clampToImage(BoxGeometry.outwardIntegral(rect), imageSize: pixelSize)
        guard clamped.width >= 3, clamped.height >= 3 else { return nil }
        let box = RedactionBox.manual(clamped)
        edit { $0.append(box) }
        return box.id
    }

    func moveBox(_ id: RedactionBox.ID, to rect: CGRect) {
        let clamped = BoxGeometry.clampToImage(BoxGeometry.outwardIntegral(rect), imageSize: pixelSize)
        guard clamped.width >= 1, clamped.height >= 1 else { return }
        edit { boxes in
            guard let index = boxes.firstIndex(where: { $0.id == id }) else { return }
            boxes[index].rect = clamped
        }
    }

    /// Removes a box the user drew. Found boxes are uncovered, never removed,
    /// so they can always be covered again.
    func deleteManualBox(_ id: RedactionBox.ID) {
        edit { boxes in
            boxes.removeAll { $0.id == id && $0.source == .manual }
        }
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(boxes)
        boxes = previous
        updateUndoState()
        render()
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(boxes)
        boxes = next
        updateUndoState()
        render()
    }

    private func updateUndoState() {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
    }

    func setStyle(_ newStyle: RenderStyle) {
        guard newStyle != style else { return }
        style = newStyle
        if state == .ready { render() }
    }

    // MARK: Rendering

    /// Renders the current boxes off the main thread. A newer render
    /// supersedes an older one still running.
    private func render() {
        renderVersion += 1
        let version = renderVersion
        let image = image, boxes = boxes, style = style
        isRendering = true
        renderTask = Task { [weak self] in
            let output = await Self.renderOffMain(image, boxes: boxes, style: style)
            guard let self, self.renderVersion == version else { return output }
            self.rendered = output
            self.isRendering = false
            self.renderTask = nil
            return output
        }
    }

    @concurrent
    private nonisolated static func renderOffMain(_ image: CGImage, boxes: [RedactionBox], style: RenderStyle) async -> CGImage? {
        RedactionRenderer.render(image, boxes: boxes, style: style)
    }

    @concurrent
    private nonisolated static func encodeOffMain(_ image: CGImage, dpi: CGFloat) async -> Data? {
        RedactionRenderer.pngData(image, dpi: dpi)
    }

    /// The redacted image for the current boxes, waiting for a render in progress.
    func exportImage() async -> CGImage? {
        guard state == .ready else { return nil }
        while let task = renderTask {
            let version = renderVersion
            let output = await task.value
            if version == renderVersion { return output }
        }
        return rendered
    }

    /// The redacted image as PNG, encoded once per render.
    func pngData() async -> Data? {
        guard let image = await exportImage() else { return nil }
        let version = renderVersion
        if let cache = pngCache, cache.version == version { return cache.data }
        guard let data = await Self.encodeOffMain(image, dpi: dpi) else { return nil }
        if version == renderVersion { pngCache = (version, data) }
        return data
    }

    /// The PNG if it's already encoded for the current boxes (no waiting).
    var cachedPNG: Data? {
        guard let cache = pngCache, cache.version == renderVersion, !isRendering else { return nil }
        return cache.data
    }
}
