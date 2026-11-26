import SwiftUI

/// What the preview card shows and what its buttons do.
@Observable
final class PreviewModel {
    /// The capture shown; several for ⌘⇧3 on more than one display.
    var documents: [RedactionDocument] = []
    var index = 0 {
        didSet { if index != oldValue { onIndexChange?() } }
    }
    /// The card resizes to the new capture's shape.
    @ObservationIgnored var onIndexChange: (() -> Void)?
    /// A short confirmation or problem shown under the title.
    var flash: Flash?

    enum Flash: Equatable {
        case copied
        case saved
        case copiedAutomatically
        case trashed
        case problem(String)

        var text: String {
            switch self {
            case .copied: "Copied. Paste it anywhere."
            case .saved: "Saved."
            case .copiedAutomatically: "Copied to the clipboard."
            case .trashed: "Original moved to the Trash."
            case .problem(let message): message
            }
        }

        var isProblem: Bool {
            if case .problem = self { return true }
            return false
        }
    }

    @ObservationIgnored let allowance: DailyAllowance
    @ObservationIgnored var actions = Actions()

    struct Actions {
        var copy: () -> Void = {}
        var edit: () -> Void = {}
        var save: () -> Void = {}
        var close: () -> Void = {}
        var revealOriginal: () -> Void = {}
        var trashOriginal: () -> Void = {}
        var upgrade: () -> Void = {}
        var dragFile: () -> URL? = { nil }
        var dragEnded: (Bool) -> Void = { _ in }
        var hover: (Bool) -> Void = { _ in }
    }

    init(allowance: DailyAllowance) {
        self.allowance = allowance
    }

    var document: RedactionDocument? {
        documents.indices.contains(index) ? documents[index] : documents.first
    }

    var isLocked: Bool {
        guard let document else { return false }
        return !allowance.canExport(document)
    }

    static let width: CGFloat = 340

    /// The card's size for `document`: the thumbnail keeps the image's
    /// shape, between a short strip and a tall preview.
    static func size(for document: RedactionDocument?) -> CGSize {
        let inner = width - Theme.cardPadding * 2
        var thumbnail: CGFloat = 150
        if let document, document.pixelSize.width > 0 {
            thumbnail = inner * document.pixelSize.height / document.pixelSize.width
        }
        thumbnail = min(max(thumbnail, 84), 210)
        // Header, thumbnail, status row and buttons, with spacing.
        return CGSize(width: width, height: (Theme.cardPadding * 2 + 22 + thumbnail + 22 + 28 + 10 * 3).rounded(.up))
    }
}

struct PreviewCardView: View {
    @Bindable var model: PreviewModel

    var body: some View {
        let size = PreviewModel.size(for: model.document)
        VStack(alignment: .leading, spacing: 10) {
            header
            thumbnail
            statusRow
            buttons
        }
        .padding(Theme.cardPadding)
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .cardBackground()
        .onHover { model.actions.hover($0) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Screenshot Redactor preview")
    }

    // MARK: Parts

    private var header: some View {
        HStack(spacing: 6) {
            statusIcon
            Text(title)
                .font(.headline)
                .lineLimit(1)
            Spacer(minLength: 4)
            if model.documents.count > 1 { pager }
            CloseButton { model.actions.close() }
        }
        .frame(height: 22)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch model.document?.state {
        case .ready?:
            Image(systemName: (model.document?.coveredCount ?? 0) > 0 ? "eye.slash.fill" : "checkmark.shield.fill")
                .foregroundStyle(Color.accentColor)
        case .failed?:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        default:
            ProgressView().controlSize(.small)
        }
    }

    private var title: String {
        guard let document = model.document else { return "" }
        switch document.state {
        case .scanning: return "Checking for sensitive info…"
        case .failed: return "Couldn't scan this image"
        case .ready:
            let count = document.coveredCount
            return count == 0 ? "Nothing sensitive found" : count == 1 ? "1 item hidden" : "\(count) items hidden"
        }
    }

    private var pager: some View {
        HStack(spacing: 2) {
            Button { model.index = max(0, model.index - 1) } label: { Image(systemName: "chevron.left") }
                .disabled(model.index == 0)
                .accessibilityLabel("Previous display")
            Text("\(model.index + 1) of \(model.documents.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Button { model.index = min(model.documents.count - 1, model.index + 1) } label: { Image(systemName: "chevron.right") }
                .disabled(model.index >= model.documents.count - 1)
                .accessibilityLabel("Next display")
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
    }

    private var thumbnail: some View {
        let document = model.document
        let ready = document?.state == .ready && document?.rendered != nil
        return ZStack {
            RoundedRectangle(cornerRadius: Theme.thumbnailRadius, style: .continuous)
                .fill(.quaternary.opacity(0.6))
            if ready {
                DraggableImage(
                    image: document?.rendered,
                    dragFile: model.actions.dragFile,
                    dragEnded: model.actions.dragEnded,
                    onClick: model.actions.edit,
                    accessibilityLabel: "Redacted screenshot. Click to edit, or drag into another app."
                )
                .help(model.isLocked ? "Click to review and edit" : "Click to edit · Drag into Slack, Mail or a browser")
            } else if case .failed? = document?.state {
                Image(systemName: "photo.badge.exclamationmark")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
            } else {
                // Never the original: a placeholder until the boxes are on.
                Shimmer()
                Image(systemName: "eye.slash")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(.tertiary)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.thumbnailRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.thumbnailRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Category chips, or a message when there's something to say (copied,
    /// limit reached, a problem): one row, so the card never jumps.
    private var statusRow: some View {
        HStack(spacing: 5) {
            if let flash = model.flash {
                Label(flash.text, systemImage: flash.isProblem ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(flash.isProblem ? Color.orange : Color.green)
                    .lineLimit(1)
            } else if model.isLocked {
                Text("You've used today's \(DailyAllowance.freePerDay) free redactions. More at midnight.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else if let document = model.document, document.state == .ready {
                let groups = document.coveredByCategory
                if groups.isEmpty {
                    Text("The copy is a fresh image with no metadata.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(groups.prefix(4), id: \.category) { group in
                        CategoryChip(category: group.category, count: group.count)
                    }
                }
                if document.originalTrashed {
                    Spacer(minLength: 4)
                    Image(systemName: "trash")
                        .foregroundStyle(.secondary)
                        .help("The original was moved to the Trash")
                        .accessibilityLabel("Original moved to the Trash")
                }
            } else if case .failed(let reason)? = model.document?.state {
                Text(reason).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            } else {
                Label("On this Mac only. Nothing is uploaded.", systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(height: 22)
        .animation(.easeOut(duration: 0.15), value: model.flash)
    }

    private var buttons: some View {
        let document = model.document
        let exportable = document?.isExportable == true
        return HStack(spacing: 8) {
            if model.isLocked {
                Button { model.actions.upgrade() } label: {
                    Label("Unlock Unlimited", systemImage: "lock.open.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
            } else {
                Button { model.actions.copy() } label: {
                    Label(model.flash == .copied ? "Copied" : "Copy", systemImage: model.flash == .copied ? "checkmark" : "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!exportable)
                .help("Copy the redacted image (⌘C)")
                .accessibilityHint("Copies the redacted image to the clipboard")
            }
            Button { model.actions.edit() } label: {
                Text("Edit").frame(minWidth: 40)
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(document?.state != .ready)
            .help("Review and change the boxes (↩)")

            Menu {
                Button("Save…") { model.actions.save() }
                    .disabled(!exportable || model.isLocked)
                if document?.originalURL != nil, document?.originalTrashed == false {
                    Divider()
                    Button("Show Original in Finder") { model.actions.revealOriginal() }
                    if case .screenshot? = document?.origin {
                        Button("Move Original to Trash") { model.actions.trashOriginal() }
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("More")
        }
        .frame(height: 28)
    }
}
