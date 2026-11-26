import CoreGraphics
import Foundation

/// One box on an image: something the app found, or a box the user drew.
///
/// `rect` is in image pixels with the origin at the **top-left**, the
/// convention used everywhere in the app. Only `BoxGeometry` converts to
/// and from Vision's and Core Graphics' bottom-left coordinates.
nonisolated struct RedactionBox: Identifiable, Equatable, Sendable {
    enum Source: Equatable, Hashable, Sendable {
        case detected
        case manual
    }

    var id = UUID()
    var rect: CGRect
    var label: String
    var category: FindingCategory
    var detector: Detector?
    var source: Source
    /// Covered boxes are filled in the export; uncovered ones are only
    /// outlined in the editor.
    var isCovered = true

    static func manual(_ rect: CGRect) -> RedactionBox {
        RedactionBox(rect: rect, label: "Drawn by you", category: .manual, detector: nil, source: .manual)
    }
}
