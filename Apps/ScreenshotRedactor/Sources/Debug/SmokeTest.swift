#if DEBUG
import AppKit
import MenuBarKit

/// `-SmokeTest YES`: drives the live app end to end, logs each step to
/// `Debug/SmokeTest.txt`, and quits. Uses a private pasteboard so the
/// developer's clipboard is left alone.
enum SmokeTest {
    static func run(model: AppModel) async {
        var log: [String] = []
        func check(_ condition: Bool, _ step: String) {
            log.append("\(condition ? "PASS" : "FAIL") \(step)")
        }

        // 1. The sample, scanned.
        let sample = SampleScreenshot.demo()
        let document = model.library.add(ImageLoader.load(sample.image, dpi: 144), origin: .sample, name: "Smoke Sample")
        model.preview.show([document])
        check(model.preview.isVisible, "preview card appears")
        await model.library.waitForScans()
        check(document.state == .ready, "scan finishes")
        check(document.coveredCount >= sample.planted.count, "covers at least \(sample.planted.count) items (found \(document.coveredCount))")
        _ = await document.exportImage()
        check(document.isExportable, "redacted image is ready")

        // 2. Copy to a private pasteboard.
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("ScreenshotRedactorSmokeTest"))
        let exporter = Exporter(allowance: model.allowance, preferences: model.preferences, pasteboard: pasteboard)
        let outcome = await exporter.copy(document)
        check(outcome == .done, "copy succeeds")
        let png = pasteboard.data(forType: .png)
        check(png != nil, "pasteboard holds a PNG")
        if let png, let types = PNGChunks.types(in: png) {
            check(Set(types).isSubset(of: PNGChunks.essential), "PNG has no metadata chunks (\(types.joined(separator: ",")))")
        }
        check(pasteboard.types?.contains(.tiff) == true, "pasteboard offers TIFF")
        check(pasteboard.types?.contains(.fileURL) != true, "pasteboard has no file URL")

        // 3. Edit: uncover one, undo, draw one.
        model.openEditor(document)
        check(model.editor.isOpen, "editor opens")
        if let first = document.boxes.first {
            document.toggle(first.id)
            check(document.boxes.first?.isCovered == false, "click uncovers a box")
            document.undo()
            check(document.boxes.first?.isCovered == true, "undo covers it again")
        }
        let before = document.boxes.count
        document.addManualBox(CGRect(x: 10, y: 10, width: 120, height: 40))
        check(document.boxes.count == before + 1, "a drawn box is added")
        let exported = await document.exportImage()
        check(exported != nil, "export after edits renders")

        // 4. Drag file.
        let dragFile = exporter.dragFile(for: document)
        check(dragFile.map { FileManager.default.fileExists(atPath: $0.path) } == true, "drag file is written")
        model.editor.close()
        model.preview.close()

        DebugFiles.write(log.joined(separator: "\n"), to: "SmokeTest.txt")
    }
}
#endif
