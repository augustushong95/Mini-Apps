import Foundation
import Observation

/// The editor's state around one document.
@Observable
final class EditorModel {
    enum Zoom: String, CaseIterable {
        case fit
        case actual
    }

    let document: RedactionDocument
    var selectedID: RedactionBox.ID?
    var hoveredID: RedactionBox.ID?
    /// ⌥ held: every box shows as an outline so you can see what's under it.
    var isPeeking = false
    var zoom: Zoom = .fit
    var flash: String?

    @ObservationIgnored let allowance: DailyAllowance
    @ObservationIgnored var actions = Actions()

    struct Actions {
        var copy: () -> Void = {}
        var save: () -> Void = {}
        var upgrade: () -> Void = {}
        var close: () -> Void = {}
        var dragFile: () -> URL? = { nil }
        var dragEnded: (Bool) -> Void = { _ in }
    }

    init(document: RedactionDocument, allowance: DailyAllowance) {
        self.document = document
        self.allowance = allowance
    }

    var isLocked: Bool { !allowance.canExport(document) }

    var selectedBox: RedactionBox? {
        selectedID.flatMap { id in document.boxes.first { $0.id == id } }
    }

    /// Boxes grouped for the sidebar, most sensitive group first.
    var groups: [(category: FindingCategory, boxes: [RedactionBox])] {
        FindingCategory.allCases.sorted { $0.priority < $1.priority }.compactMap { category in
            let boxes = document.boxes.filter { $0.category == category }
            return boxes.isEmpty ? nil : (category, boxes)
        }
    }

    func deleteSelected() {
        guard let box = selectedBox, box.source == .manual else { return }
        document.deleteManualBox(box.id)
        selectedID = nil
    }

    /// Moves the selected box you drew by a few pixels (arrow keys).
    func nudgeSelected(dx: CGFloat, dy: CGFloat) {
        guard let box = selectedBox, box.source == .manual else { return }
        document.moveBox(box.id, to: CanvasGeometry.move(box.rect, by: CGSize(width: dx, height: dy), imageSize: document.pixelSize))
    }
}
