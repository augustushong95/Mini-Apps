import SwiftUI

struct EditorView: View {
    @Bindable var model: EditorModel

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                EditorToolbar(model: model)
                Divider()
                ZStack(alignment: .bottom) {
                    RedactionCanvas(model: model, revision: revision)
                        .background(Color(nsColor: .underPageBackgroundColor))
                    hint
                }
            }
            .frame(minWidth: 460)
            Divider()
            FindingsSidebar(model: model)
                .frame(width: 270)
        }
        .frame(minHeight: 420)
    }

    /// Anything drawn on the canvas, so it redraws when one changes.
    private var revision: Int {
        var hasher = Hasher()
        for box in model.document.boxes {
            hasher.combine(box.id)
            hasher.combine(box.isCovered)
            hasher.combine(box.rect.minX)
            hasher.combine(box.rect.minY)
            hasher.combine(box.rect.width)
            hasher.combine(box.rect.height)
        }
        hasher.combine(model.selectedID)
        hasher.combine(model.hoveredID)
        hasher.combine(model.isPeeking)
        hasher.combine(model.zoom)
        hasher.combine(model.document.style.color)
        hasher.combine(model.document.style.showsLabels)
        return hasher.finalize()
    }

    private var hint: some View {
        Text(model.isPeeking
             ? "Showing what's under the boxes. Release ⌥ to hide it again."
             : "Click a box to uncover it · Drag to cover more · Hold ⌥ to peek")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.regularMaterial, in: Capsule())
            .padding(.bottom, 10)
            .allowsHitTesting(false)
    }
}

private struct EditorToolbar: View {
    @Bindable var model: EditorModel

    var body: some View {
        let document = model.document
        HStack(spacing: 10) {
            ControlGroup {
                Button { document.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                    .disabled(!document.canUndo)
                    .help("Undo (⌘Z)")
                    .accessibilityLabel("Undo")
                Button { document.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                    .disabled(!document.canRedo)
                    .help("Redo (⇧⌘Z)")
                    .accessibilityLabel("Redo")
            }
            .fixedSize()

            Picker("Zoom", selection: $model.zoom) {
                Text("Fit").tag(EditorModel.Zoom.fit)
                Text("Actual Size").tag(EditorModel.Zoom.actual)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .help("Fit (⌘0) · Actual Size (⌘1)")

            Spacer(minLength: 8)

            if let flash = model.flash {
                Label(flash, systemImage: "checkmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.green)
                    .transition(.opacity)
            } else if model.isLocked {
                Text("Today's \(DailyAllowance.freePerDay) free redactions are used up.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                DraggableImage(
                    image: document.isExportable && !model.isLocked ? document.rendered : nil,
                    cornerRadius: 3,
                    dragFile: model.actions.dragFile,
                    dragEnded: model.actions.dragEnded,
                    onClick: {},
                    accessibilityLabel: "Drag the redacted image into another app"
                )
                .frame(width: 30, height: 22)
                .background(RoundedRectangle(cornerRadius: 3).fill(.quaternary))
                Text("Drag")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .allowsHitTesting(false)
            }
            .help("Drag the thumbnail into Slack, Mail or a browser")

            Button("Save…") { model.actions.save() }
                .disabled(!document.isExportable || model.isLocked)
                .help("Save the redacted image (⌘S)")

            if model.isLocked {
                Button { model.actions.upgrade() } label: { Label("Unlock Unlimited", systemImage: "lock.open.fill") }
                    .buttonStyle(.borderedProminent)
            } else {
                Button { model.actions.copy() } label: { Label("Copy", systemImage: "doc.on.doc") }
                    .buttonStyle(.borderedProminent)
                    .disabled(!document.isExportable)
                    .help("Copy the redacted image (⌘C)")
            }
        }
        .controlSize(.regular)
        .padding(.horizontal, 12)
        .frame(height: 44)
        .animation(.easeOut(duration: 0.2), value: model.flash)
    }
}

private struct FindingsSidebar: View {
    @Bindable var model: EditorModel

    var body: some View {
        let document = model.document
        VStack(spacing: 0) {
            if model.groups.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(model.groups, id: \.category) { group in
                        Section {
                            ForEach(group.boxes) { box in
                                FindingRow(model: model, box: box)
                            }
                        } header: {
                            GroupHeader(document: document, category: group.category, boxes: group.boxes)
                        }
                    }
                }
                .listStyle(.sidebar)
            }
            Divider()
            footer
        }
        .background(.background)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "checkmark.shield")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.secondary)
            Text("Nothing sensitive found")
                .font(.headline)
            Text("Drag on the image to cover anything you'd rather not share.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity)
    }

    private var footer: some View {
        let document = model.document
        let total = document.boxes.count
        let covered = document.coveredCount
        return HStack {
            Text(total == 0 ? "No boxes" : "\(covered) of \(total) covered")
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Spacer()
            Button("Cover All") {
                document.setCovered(true, ids: Set(document.boxes.map(\.id)))
            }
            .disabled(covered == total)
            .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
    }
}

private struct GroupHeader: View {
    let document: RedactionDocument
    let category: FindingCategory
    let boxes: [RedactionBox]

    var body: some View {
        let covered = boxes.filter(\.isCovered).count
        HStack(spacing: 6) {
            Image(systemName: category.symbolName)
                .foregroundStyle(Theme.color(for: category))
                .font(.system(size: 10, weight: .semibold))
            Text(category.title)
            Text("\(boxes.count)")
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Spacer()
            Button(covered == boxes.count ? "Uncover" : "Cover") {
                document.setCovered(covered != boxes.count, ids: Set(boxes.map(\.id)))
            }
            .buttonStyle(.borderless)
            .font(.caption)
            .padding(.trailing, 8)
            .accessibilityLabel(covered == boxes.count ? "Uncover all \(category.title.lowercased())" : "Cover all \(category.title.lowercased())")
        }
    }
}

private struct FindingRow: View {
    @Bindable var model: EditorModel
    let box: RedactionBox
    @State private var isHovering = false

    var body: some View {
        let document = model.document
        HStack(spacing: 8) {
            Toggle(isOn: Binding(
                get: { box.isCovered },
                set: { _ in document.toggle(box.id) }
            )) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(box.label)
                        .lineLimit(1)
                    Text(box.isCovered ? "Covered" : "Visible in the copy")
                        .font(.caption)
                        .foregroundStyle(box.isCovered ? Color.secondary : Color.orange)
                }
            }
            .toggleStyle(.checkbox)
            Spacer(minLength: 0)
            if box.source == .manual, isHovering || model.selectedID == box.id {
                Button {
                    document.deleteManualBox(box.id)
                    if model.selectedID == box.id { model.selectedID = nil }
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Remove this box")
                .accessibilityLabel("Remove box")
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
            model.hoveredID = hovering ? box.id : (model.hoveredID == box.id ? nil : model.hoveredID)
        }
        .onTapGesture { model.selectedID = box.id }
        .listRowBackground(model.selectedID == box.id ? Color.accentColor.opacity(0.12) : Color.clear)
    }
}
