import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Foundation
import Testing
@testable import ScreenshotRedactor

/// Shared test helpers: throwaway defaults and small documents.
enum Fixtures {
    nonisolated static func defaults() -> UserDefaults {
        let suite = "ScreenshotRedactorTests-\(UUID().uuidString)"
        return UserDefaults(suiteName: suite)!
    }

    nonisolated static func image(width: Int = 120, height: Int = 60) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    static func document(origin: RedactionDocument.Origin = .capture, burst: UUID? = nil, boxes: [RedactionBox] = []) -> RedactionDocument {
        let document = RedactionDocument(image: image(), dpi: 144, origin: origin, name: "Test", style: RenderStyle(), burstID: burst)
        document.finishScan(ScanResult(boxes: boxes, timedOutRules: [], lineCount: 0, duration: .zero))
        return document
    }

    nonisolated static func box(_ rect: CGRect, category: FindingCategory = .secret) -> RedactionBox {
        RedactionBox(rect: rect, label: "Secret", category: category, detector: .apiKeys, source: .detected)
    }
}

@Suite struct AllowanceTests {
    final class Clock {
        var now: Date
        init(_ now: Date) { self.now = now }
    }

    private func makeAllowance(_ defaults: UserDefaults, clock: Clock) -> DailyAllowance {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return DailyAllowance(defaults: defaults, now: { clock.now }, calendar: calendar)
    }

    /// 2026-11-26 10:00 in Shanghai.
    let morning = Date(timeIntervalSince1970: 1_795_658_400)

    @Test func fivePerDayAndEachCaptureCountsOnce() {
        let defaults = Fixtures.defaults()
        let allowance = makeAllowance(defaults, clock: Clock(morning))
        let documents = (0..<6).map { _ in Fixtures.document() }
        for document in documents.prefix(5) {
            #expect(allowance.canExport(document))
            allowance.recordExport(document)
            allowance.recordExport(document) // a second copy is free
        }
        #expect(allowance.usedToday == 5)
        #expect(allowance.remaining == 0)
        #expect(!allowance.canExport(documents[5]))
        #expect(allowance.canExport(documents[0]), "Exporting an already counted capture again stays free")
    }

    @Test func aBurstCountsOnceAndTheSampleIsFree() {
        let allowance = makeAllowance(Fixtures.defaults(), clock: Clock(morning))
        let burst = UUID()
        let first = Fixtures.document(burst: burst), second = Fixtures.document(burst: burst)
        allowance.recordExport(first)
        allowance.recordExport(second)
        #expect(allowance.usedToday == 1)
        allowance.recordExport(Fixtures.document(origin: .sample))
        #expect(allowance.usedToday == 1)
    }

    @Test func theCountStartsOverAtMidnightButNotWhenTheClockGoesBack() {
        let defaults = Fixtures.defaults()
        let clock = Clock(morning)
        let allowance = makeAllowance(defaults, clock: clock)
        for _ in 0..<5 { allowance.recordExport(Fixtures.document()) }
        #expect(allowance.remaining == 0)

        clock.now = morning.addingTimeInterval(-3 * 3600)  // 07:00, earlier the same day
        allowance.refresh()
        #expect(allowance.remaining == 0)
        clock.now = morning.addingTimeInterval(-24 * 3600) // yesterday
        allowance.refresh()
        #expect(allowance.remaining == 0, "Turning the clock back doesn't hand out a new day")

        clock.now = morning.addingTimeInterval(15 * 3600)  // 01:00 the next day
        allowance.refresh()
        #expect(allowance.remaining == DailyAllowance.freePerDay)

        // A relaunch reads the same count.
        let relaunched = makeAllowance(defaults, clock: clock)
        #expect(relaunched.usedToday == 0)
    }

    @Test func proIsUnlimited() {
        let allowance = makeAllowance(Fixtures.defaults(), clock: Clock(morning))
        allowance.isUnlimited = true
        for _ in 0..<20 {
            let document = Fixtures.document()
            #expect(allowance.canExport(document))
            allowance.recordExport(document)
        }
        #expect(allowance.usedToday == 0)
    }
}

@Suite struct LibraryTests {
    @Test func recentIsCappedByCountAndMemory() {
        let library = Library(preferences: Preferences(defaults: Fixtures.defaults()), includesCustomRules: { false })
        for _ in 0..<8 { library.add(ImageLoader.load(Fixtures.image(), dpi: 144), origin: .capture, name: "small") }
        #expect(library.recent.count == Library.maximumRecent)
        // Full 5K screenshots: only as many as fit in the budget, newest kept.
        let big = Fixtures.image(width: 5120, height: 2880)
        for index in 0..<4 { library.add(ImageLoader.load(big, dpi: 144), origin: .capture, name: "big \(index)") }
        let pixels = library.recent.reduce(0) { $0 + $1.image.width * $1.image.height }
        #expect(pixels <= Library.pixelBudget)
        #expect(library.recent.first?.name == "big 3")
        #expect(library.recent.count >= 2)
    }
}

@Suite struct DocumentTests {
    @Test func toggleUndoRedo() {
        let box = Fixtures.box(CGRect(x: 10, y: 10, width: 30, height: 10))
        let document = Fixtures.document(boxes: [box])
        #expect(!document.canUndo)
        document.toggle(box.id)
        #expect(document.boxes[0].isCovered == false)
        #expect(document.canUndo)
        document.undo()
        #expect(document.boxes[0].isCovered == true)
        #expect(document.canRedo)
        document.redo()
        #expect(document.boxes[0].isCovered == false)
    }

    @Test func manualBoxesAreClampedAndOnlyTheyCanBeDeleted() {
        let found = Fixtures.box(CGRect(x: 10, y: 10, width: 30, height: 10))
        let document = Fixtures.document(boxes: [found])
        #expect(document.addManualBox(CGRect(x: 5, y: 5, width: 1, height: 1)) == nil, "A stray click adds nothing")
        let id = document.addManualBox(CGRect(x: 100, y: 40, width: 80, height: 80))
        let manual = document.boxes.first { $0.id == id }
        #expect(manual?.rect == CGRect(x: 100, y: 40, width: 20, height: 20))
        document.deleteManualBox(found.id)
        #expect(document.boxes.contains { $0.id == found.id })
        if let id { document.deleteManualBox(id) }
        #expect(!document.boxes.contains { $0.id == id })
    }

    /// Copy right after an edit must export the edit, never an older render.
    @Test func exportWaitsForTheLatestRender() async throws {
        let box = Fixtures.box(CGRect(x: 0, y: 0, width: 60, height: 60))
        let document = Fixtures.document(boxes: [box])
        document.toggle(box.id)          // uncovered
        document.toggle(box.id)          // covered again
        document.addManualBox(CGRect(x: 80, y: 10, width: 20, height: 20))
        let image = try #require(await document.exportImage())
        let pixels = try #require(PixelBuffer(image: image))
        #expect(pixels.rgb(30, 30) == (0, 0, 0))
        #expect(pixels.rgb(90, 20) == (0, 0, 0))
        #expect(pixels.rgb(110, 50) == (255, 255, 255))
        #expect(document.isExportable)
        let png = try #require(await document.pngData())
        #expect(document.cachedPNG == png)
    }

    @Test func styleChangesRerender() async throws {
        let document = Fixtures.document(boxes: [Fixtures.box(CGRect(x: 0, y: 0, width: 20, height: 20))])
        document.setStyle(RenderStyle(color: .white, showsLabels: false))
        let image = try #require(await document.exportImage())
        let pixels = try #require(PixelBuffer(image: image))
        #expect(pixels.rgb(10, 10) == (255, 255, 255))
        #expect(document.coveredByCategory.first?.count == 1)
    }

    @Test func nothingExportsBeforeTheScanFinishes() async {
        let document = RedactionDocument(image: Fixtures.image(), dpi: 144, origin: .capture, name: "x", style: RenderStyle())
        #expect(!document.isExportable)
        #expect(await document.exportImage() == nil)
        #expect(await document.pngData() == nil)
    }
}

@Suite struct ExporterTests {
    private func pasteboard() -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name("ScreenshotRedactorTests-\(UUID().uuidString)"))
    }

    @Test func copyPutsOnePNGWithoutMetadataAndATIFFOnTheClipboard() async throws {
        let defaults = Fixtures.defaults()
        let allowance = DailyAllowance(defaults: defaults)
        let board = pasteboard()
        let exporter = Exporter(allowance: allowance, preferences: Preferences(defaults: defaults), pasteboard: board)
        let document = Fixtures.document(boxes: [Fixtures.box(CGRect(x: 0, y: 0, width: 20, height: 20))])
        #expect(await exporter.copy(document) == .done)
        #expect(board.pasteboardItems?.count == 1)
        let png = try #require(board.data(forType: .png))
        let chunks = try #require(PNGChunks.types(in: png))
        #expect(Set(chunks).isSubset(of: PNGChunks.essential))
        #expect(board.types?.contains(.tiff) == true)
        #expect(board.data(forType: .tiff) != nil)
        #expect(board.types?.contains(.fileURL) != true)
        #expect(document.exportCounted)
        #expect(allowance.usedToday == 1)
    }

    @Test func nothingIsCopiedOnceTheLimitIsReached() async {
        let defaults = Fixtures.defaults()
        let allowance = DailyAllowance(defaults: defaults)
        for _ in 0..<DailyAllowance.freePerDay { allowance.recordExport(Fixtures.document()) }
        let board = pasteboard()
        board.clearContents()
        board.setString("untouched", forType: .string)
        let exporter = Exporter(allowance: allowance, preferences: Preferences(defaults: defaults), pasteboard: board)
        #expect(await exporter.copy(Fixtures.document()) == .limitReached)
        #expect(board.string(forType: .string) == "untouched")
        #expect(exporter.dragFile(for: Fixtures.document()) == nil)
    }

    @Test func dragFilesAreRedactedPNGsNamedAfterTheCapture() async throws {
        let defaults = Fixtures.defaults()
        let exporter = Exporter(allowance: DailyAllowance(defaults: defaults), preferences: Preferences(defaults: defaults), pasteboard: pasteboard())
        let document = Fixtures.document(boxes: [Fixtures.box(CGRect(x: 0, y: 0, width: 20, height: 20))])
        _ = await document.pngData()
        let url = try #require(exporter.dragFile(for: document))
        #expect(url.lastPathComponent == "Test (redacted).png")
        #expect(url.path.hasPrefix(Exporter.outgoingFolder.path))
        let loaded = try ImageLoader.load(contentsOf: url)
        let pixels = try #require(PixelBuffer(image: loaded.image))
        #expect(pixels.rgb(5, 5) == (0, 0, 0))
        #expect(!document.exportCounted, "Only a completed drop counts")
        exporter.dragCompleted(document)
        #expect(document.exportCounted)
    }

    @Test func theOriginalIsTrashedOnlyIfItIsStillTheSameFile() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "TrashTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let defaults = Fixtures.defaults()
        let exporter = Exporter(allowance: DailyAllowance(defaults: defaults), preferences: Preferences(defaults: defaults), pasteboard: pasteboard())

        let original = folder.appending(path: "Shot.png")
        try Data("one".utf8).write(to: original)
        let identity = try #require(FileIdentity.of(original))
        // Replaced by a different file with the same name: left alone.
        try FileManager.default.removeItem(at: original)
        try Data("two".utf8).write(to: original)
        let replaced = Fixtures.document(origin: .screenshot(original, identity))
        #expect(!exporter.moveOriginalToTrash(replaced))
        #expect(FileManager.default.fileExists(atPath: original.path))

        let current = try #require(FileIdentity.of(original))
        let same = Fixtures.document(origin: .screenshot(original, current))
        #expect(exporter.moveOriginalToTrash(same))
        #expect(!FileManager.default.fileExists(atPath: original.path))
        #expect(same.originalTrashed)
        #expect(!exporter.moveOriginalToTrash(same), "Only once")
        // Files that weren't screenshots are never trashed.
        #expect(!exporter.moveOriginalToTrash(Fixtures.document(origin: .file(original))))
    }
}

@Suite nonisolated struct CanvasGeometryTests {
    let geometry = CanvasGeometry(imageSize: CGSize(width: 1000, height: 500), canvasSize: CGSize(width: 700, height: 400), scale: 0.5)

    @Test func theImageIsCentredAndPointsMapBack() {
        #expect(geometry.origin == CGPoint(x: 100, y: 75))
        #expect(geometry.toCanvas(CGRect(x: 100, y: 100, width: 200, height: 50)) == CGRect(x: 150, y: 125, width: 100, height: 25))
        #expect(geometry.toImage(CGPoint(x: 150, y: 125)) == CGPoint(x: 100, y: 100))
        #expect(CanvasGeometry.fitScale(imageSize: CGSize(width: 1000, height: 500), available: CGSize(width: 500, height: 500), maximum: 2) == 0.5)
        #expect(CanvasGeometry.fitScale(imageSize: CGSize(width: 100, height: 50), available: CGSize(width: 1000, height: 1000), maximum: 1) == 1)
    }

    @Test func hitTestingPrefersDrawnBoxesThenTheSmallest() {
        let big = Fixtures.box(CGRect(x: 0, y: 0, width: 400, height: 200))
        let small = Fixtures.box(CGRect(x: 100, y: 50, width: 40, height: 20))
        let manual = RedactionBox.manual(CGRect(x: 0, y: 0, width: 400, height: 200))
        let point = geometry.toCanvas(CGRect(x: 110, y: 55, width: 0, height: 0)).origin
        #expect(geometry.box(at: point, in: [big, small])?.id == small.id)
        #expect(geometry.box(at: point, in: [big, small, manual])?.id == manual.id)
        #expect(geometry.box(at: CGPoint(x: 690, y: 390), in: [big, small]) == nil)
    }

    @Test func resizingKeepsTheOppositeCornerAndAMinimumSize() {
        let rect = CGRect(x: 100, y: 100, width: 50, height: 50)
        #expect(CanvasGeometry.resize(rect, handle: .bottomRight, to: CGPoint(x: 300, y: 260), imageSize: CGSize(width: 1000, height: 500)) == CGRect(x: 100, y: 100, width: 200, height: 160))
        #expect(CanvasGeometry.resize(rect, handle: .topLeft, to: CGPoint(x: 500, y: 500), imageSize: CGSize(width: 1000, height: 500)) == CGRect(x: 147, y: 147, width: 3, height: 3))
        #expect(CanvasGeometry.resize(rect, handle: .topLeft, to: CGPoint(x: -50, y: -50), imageSize: CGSize(width: 1000, height: 500)) == CGRect(x: 0, y: 0, width: 150, height: 150))
        #expect(CanvasGeometry.move(rect, by: CGSize(width: 2000, height: -500), imageSize: CGSize(width: 1000, height: 500)) == CGRect(x: 950, y: 0, width: 50, height: 50))
        #expect(geometry.handle(at: geometry.toCanvas(rect).origin, of: rect) == .topLeft)
    }
}

@Suite nonisolated struct CaptureGeometryTests {
    /// A 2× main display (1512×982 pt) and a 1× display to its left, lower.
    let main = CGRect(x: 0, y: 0, width: 1512, height: 982)
    let left = CGRect(x: -1920, y: -200, width: 1920, height: 1080)

    @Test func cocoaAndGlobalRectsConvertBothWays() {
        let cocoa = CGRect(x: 100, y: 700, width: 200, height: 100)
        let global = CaptureGeometry.cgGlobal(fromCocoa: cocoa, mainHeight: main.height)
        #expect(global == CGRect(x: 100, y: 182, width: 200, height: 100))
        #expect(CaptureGeometry.cocoa(fromCGGlobal: global, mainHeight: main.height) == cocoa)
    }

    @Test func selectionsBecomeImagePixelsOnEachDisplay() {
        // Top-left of the main display at 2×.
        #expect(CaptureGeometry.pixelRect(selection: CGRect(x: 0, y: 882, width: 100, height: 100), screenFrame: main, scale: 2)
                == CGRect(x: 0, y: 0, width: 200, height: 200))
        // A display with a negative origin, at 1×.
        #expect(CaptureGeometry.pixelRect(selection: CGRect(x: -1900, y: 780, width: 300, height: 80), screenFrame: left, scale: 1)
                == CGRect(x: 20, y: 20, width: 300, height: 80))
        // Spilling past the edge is clipped to the display.
        #expect(CaptureGeometry.pixelRect(selection: CGRect(x: 1400, y: -50, width: 300, height: 100), screenFrame: main, scale: 2)
                == CGRect(x: 2800, y: 1864, width: 224, height: 100))
    }

    @Test func aDragStaysOnItsDisplay() {
        let selection = CaptureGeometry.selection(from: CGPoint(x: 1400, y: 500), to: CGPoint(x: 2000, y: 1200), on: main)
        #expect(selection == CGRect(x: 1400, y: 500, width: 112, height: 482))
    }
}

@Suite struct ShortcutAndPreferencesTests {
    @Test func theDefaultShortcut() {
        let combo = KeyCombo.defaultCapture
        #expect(combo.isValid)
        #expect(combo.displayString.hasPrefix("⌥⇧⌘"))
        #expect(combo.carbonModifiers == UInt32(cmdKey | optionKey | shiftKey))
        #expect(HotKeyCenter.conflict(for: combo) == nil)
    }

    @Test func badShortcutsAreRejected() {
        #expect(!KeyCombo(keyCode: UInt16(kVK_ANSI_4), modifiers: [.option, .shift]).isValid)
        #expect(HotKeyCenter.conflict(for: KeyCombo(keyCode: UInt16(kVK_ANSI_4), modifiers: [.command, .shift])) != nil)
        #expect(HotKeyCenter.conflict(for: KeyCombo(keyCode: UInt16(kVK_ANSI_C), modifiers: [.command])) != nil)
        #expect(HotKeyCenter.conflict(for: KeyCombo(keyCode: UInt16(kVK_ANSI_R), modifiers: [.command, .control])) == nil)
    }

    @Test func settingsPersistIncludingNoShortcut() {
        let defaults = Fixtures.defaults()
        let preferences = Preferences(defaults: defaults)
        #expect(preferences.hotKey == .defaultCapture)
        #expect(preferences.watchesFolder)
        #expect(preferences.readyAction == .showPreview)
        #expect(preferences.originalHandling == .keep)
        preferences.hotKey = nil
        preferences.boxColor = .graphite
        preferences.originalHandling = .moveToTrash
        var detection = preferences.detection
        detection.enabled.remove(.faces)
        detection.customRules = [CustomRule(kind: .phrase, value: "Falcon")]
        preferences.detection = detection

        let reloaded = Preferences(defaults: defaults)
        #expect(reloaded.hotKey == nil)
        #expect(reloaded.boxColor == .graphite)
        #expect(reloaded.originalHandling == .moveToTrash)
        #expect(!reloaded.detection.enabled.contains(.faces))
        #expect(reloaded.detection.customRules.map(\.value) == ["Falcon"])
    }

    @Test func outgoingFilesAreRemovedAtLaunch() throws {
        let folder = Exporter.outgoingFolder.appending(path: "leftover", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: folder.appending(path: "a.png"))
        Exporter.removeLeftoverFiles()
        #expect(!FileManager.default.fileExists(atPath: Exporter.outgoingFolder.path))
    }
}
