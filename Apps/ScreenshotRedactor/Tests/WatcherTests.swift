import CoreGraphics
import Foundation
import Testing
@testable import ScreenshotRedactor

/// The folder watcher against real files and real FSEvents, in a temporary
/// folder inside the app's container.
@Suite(.serialized) struct WatcherTests {
    let folder: URL
    let png: Data

    init() throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "WatcherTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let context = CGContext(data: nil, width: 40, height: 20, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(srgbRed: 0.2, green: 0.4, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 40, height: 20))
        png = try #require(RedactionRenderer.pngData(context.makeImage()!, dpi: 144))
    }

    private func cleanUp() {
        try? FileManager.default.removeItem(at: folder)
    }

    /// Writes a file the way `screencapture` does: hidden first, then renamed,
    /// with the screen-capture attribute (optionally a little later).
    @discardableResult
    private func writeScreenshot(_ name: String, attribute: Bool = true, attributeDelay: Duration = .zero, data: Data? = nil) async throws -> URL {
        let hidden = folder.appending(path: ".\(name)")
        try (data ?? png).write(to: hidden)
        if attribute, attributeDelay == .zero {
            ScreenshotFile.writeAttribute(hidden, name: ScreenshotFile.isScreenCaptureAttribute, propertyList: true)
        }
        let visible = folder.appending(path: name)
        try FileManager.default.moveItem(at: hidden, to: visible)
        if attribute, attributeDelay > .zero {
            try await Task.sleep(for: attributeDelay)
            ScreenshotFile.writeAttribute(visible, name: ScreenshotFile.isScreenCaptureAttribute, propertyList: true)
        }
        return visible
    }

    private func eventually(timeout: Duration = .seconds(4), _ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return condition()
    }

    private func makeWatcher(_ arrivals: Box<[ScreenshotWatcher.Arrival]>) -> ScreenshotWatcher {
        let watcher = ScreenshotWatcher(folder: folder, retryInterval: .milliseconds(60), attributeTimeout: 0.8)
        watcher.onScreenshot = { arrivals.value.append($0) }
        return watcher
    }

    @Test func aNewScreenshotIsReportedOnceAndOldOnesAreNot() async throws {
        defer { cleanUp() }
        try await writeScreenshot("Old.png")
        let arrivals = Box<[ScreenshotWatcher.Arrival]>([])
        let watcher = makeWatcher(arrivals)
        watcher.start()
        defer { watcher.stop() }

        let url = try await writeScreenshot("Screenshot 2026-11-26 at 10.00.00\u{202F}AM.png")
        #expect(await eventually { arrivals.value.count == 1 })
        #expect(arrivals.value.first?.url.lastPathComponent == url.lastPathComponent)
        #expect(arrivals.value.first?.identity == FileIdentity.of(url))

        // Renaming it isn't a new screenshot; neither is touching it.
        try FileManager.default.moveItem(at: url, to: folder.appending(path: "Renamed.png"))
        try png.write(to: folder.appending(path: "Renamed.png"), options: [])
        try await Task.sleep(for: .seconds(1))
        #expect(arrivals.value.count == 1)
    }

    @Test func theAttributeCanArriveAfterTheRename() async throws {
        defer { cleanUp() }
        let arrivals = Box<[ScreenshotWatcher.Arrival]>([])
        let watcher = makeWatcher(arrivals)
        watcher.start()
        defer { watcher.stop() }
        try await writeScreenshot("Late.png", attributeDelay: .milliseconds(400))
        #expect(await eventually { arrivals.value.count == 1 })
    }

    @Test func filesThatArentScreenshotsAreIgnored() async throws {
        defer { cleanUp() }
        let arrivals = Box<[ScreenshotWatcher.Arrival]>([])
        let watcher = makeWatcher(arrivals)
        watcher.start()
        defer { watcher.stop() }
        try await writeScreenshot("Downloaded.png", attribute: false)
        try await writeScreenshot("Notes.txt", data: Data("hello".utf8))
        try FileManager.default.createDirectory(at: folder.appending(path: "Sub"), withIntermediateDirectories: true)
        try await Task.sleep(for: .seconds(2))
        #expect(arrivals.value.isEmpty)
    }

    @Test func aBurstOfScreenshotsIsReportedInFull() async throws {
        defer { cleanUp() }
        let arrivals = Box<[ScreenshotWatcher.Arrival]>([])
        let watcher = makeWatcher(arrivals)
        watcher.start()
        defer { watcher.stop() }
        for index in 1...3 {
            try await writeScreenshot("Screenshot (\(index)).png")
        }
        #expect(await eventually { arrivals.value.count == 3 })
        #expect(Set(arrivals.value.map(\.url.lastPathComponent)).count == 3)
    }

    @Test func screenshotAttributesAreRead() async throws {
        defer { cleanUp() }
        let url = folder.appending(path: "Attributes.png")
        try png.write(to: url)
        #expect(ScreenshotFile.isScreenCapture(url) == nil)
        ScreenshotFile.writeAttribute(url, name: ScreenshotFile.isScreenCaptureAttribute, propertyList: true)
        ScreenshotFile.writeAttribute(url, name: ScreenshotFile.globalRectAttribute, propertyList: [259.0, 187.0, 1031.0, 402.0])
        ScreenshotFile.writeAttribute(url, name: ScreenshotFile.captureTypeAttribute, propertyList: "selection")
        #expect(ScreenshotFile.isScreenCapture(url) == true)
        #expect(ScreenshotFile.globalRect(url) == CGRect(x: 259, y: 187, width: 1031, height: 402))
        #expect(ScreenshotFile.captureType(url) == "selection")
    }

    @Test func removingTheFolderIsReported() async throws {
        let changed = Box(false)
        let watcher = ScreenshotWatcher(folder: folder)
        watcher.onFolderChanged = { changed.value = true }
        watcher.start()
        defer { watcher.stop() }
        try await Task.sleep(for: .milliseconds(200))
        try FileManager.default.removeItem(at: folder)
        #expect(await eventually { changed.value })
    }
}

/// A mutable value shared with a closure.
final class Box<Value> {
    var value: Value
    init(_ value: Value) { self.value = value }
}
