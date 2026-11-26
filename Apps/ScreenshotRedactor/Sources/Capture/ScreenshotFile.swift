import CoreGraphics
import Darwin
import Foundation

/// Which file a screenshot is, so a later action (Move to Trash) touches
/// exactly that file and not one that replaced it.
nonisolated struct FileIdentity: Equatable, Hashable, Sendable {
    let fileID: UInt64
    let modified: Date?

    static func of(_ url: URL) -> FileIdentity? {
        guard let values = url.freshResourceValues([.fileIdentifierKey, .contentModificationDateKey]),
              let id = values.fileIdentifier
        else { return nil }
        return FileIdentity(fileID: id, modified: values.contentModificationDate)
    }
}

extension URL {
    /// Resource values read from disk now. `URL` caches them, so a second
    /// read on the same value would otherwise describe the file as it was
    /// (a replaced file would look unchanged, a growing one finished).
    nonisolated func freshResourceValues(_ keys: Set<URLResourceKey>) -> URLResourceValues? {
        var url = self
        url.removeAllCachedResourceValues()
        return try? url.resourceValues(forKeys: keys)
    }
}

/// The extended attributes macOS writes on every screenshot. They're the
/// same in every system language, unlike file names.
nonisolated enum ScreenshotFile {
    static let isScreenCaptureAttribute = "com.apple.metadata:kMDItemIsScreenCapture"
    static let globalRectAttribute = "com.apple.metadata:kMDItemScreenCaptureGlobalRect"
    static let captureTypeAttribute = "com.apple.metadata:kMDItemScreenCaptureType"

    /// True or false if the attribute is there; nil if it isn't (yet).
    static func isScreenCapture(_ url: URL) -> Bool? {
        guard let value = propertyList(url, attribute: isScreenCaptureAttribute) else { return nil }
        if let flag = value as? Bool { return flag }
        if let number = value as? NSNumber { return number.boolValue }
        return false
    }

    /// The captured area in global screen points (origin top-left of the
    /// main display), which tells which display the screenshot came from.
    static func globalRect(_ url: URL) -> CGRect? {
        guard let values = propertyList(url, attribute: globalRectAttribute) as? [NSNumber], values.count == 4 else { return nil }
        return CGRect(x: values[0].doubleValue, y: values[1].doubleValue, width: values[2].doubleValue, height: values[3].doubleValue)
    }

    /// "selection", "window" or "display".
    static func captureType(_ url: URL) -> String? {
        propertyList(url, attribute: captureTypeAttribute) as? String
    }

    static func readAttribute(_ url: URL, name: String) -> Data? {
        url.withUnsafeFileSystemRepresentation { path -> Data? in
            guard let path else { return nil }
            let size = getxattr(path, name, nil, 0, 0, 0)
            guard size > 0 else { return nil }
            var buffer = [UInt8](repeating: 0, count: size)
            let read = getxattr(path, name, &buffer, size, 0, 0)
            guard read == size else { return nil }
            return Data(buffer)
        }
    }

    /// Writes an attribute (tests, and the debug inbox).
    @discardableResult
    static func writeAttribute(_ url: URL, name: String, propertyList value: Any) -> Bool {
        guard let data = try? PropertyListSerialization.data(fromPropertyList: value, format: .binary, options: 0) else { return false }
        return url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return false }
            return data.withUnsafeBytes { setxattr(path, name, $0.baseAddress, data.count, 0, 0) == 0 }
        }
    }

    private static func propertyList(_ url: URL, attribute: String) -> Any? {
        guard let data = readAttribute(url, name: attribute) else { return nil }
        return try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)
    }
}
