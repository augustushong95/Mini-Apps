import SwiftUI
import UniformTypeIdentifiers

/// What the menu bar panel shows and does.
@Observable
final class MenuPanelModel {
    enum WatchStatus: Equatable {
        case watching(String)
        case paused(String)
        case unavailable(String)
        case notChosen
    }

    var watchStatus: WatchStatus = .notChosen
    var shortcut: KeyCombo?
    var isPro = false

    @ObservationIgnored let library: Library
    @ObservationIgnored let allowance: DailyAllowance
    @ObservationIgnored var actions = Actions()

    struct Actions {
        var setWatching: (Bool) -> Void = { _ in }
        var chooseFolder: () -> Void = {}
        var capture: () -> Void = {}
        var openImage: () -> Void = {}
        var pasteImage: () -> Void = {}
        var open: (RedactionDocument) -> Void = { _ in }
        var dragFile: (RedactionDocument) -> URL? = { _ in nil }
        var dragEnded: (RedactionDocument, Bool) -> Void = { _, _ in }
        var openFiles: ([URL]) -> Void = { _ in }
        var clearRecent: () -> Void = {}
        var settings: () -> Void = {}
        var upgrade: () -> Void = {}
        var quit: () -> Void = {}
    }

    init(library: Library, allowance: DailyAllowance) {
        self.library = library
        self.allowance = allowance
    }
}

struct MenuPanelView: View {
    @Bindable var model: MenuPanelModel
    @State private var isDropTargeted = false

    static let width: CGFloat = 320

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            status
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
            Divider()
            actions
                .padding(6)
            Divider()
            recent
                .padding(12)
            Divider()
            footer
                .padding(.horizontal, 12)
                .frame(height: 36)
        }
        .frame(width: Self.width)
        .cardBackground()
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
                    .background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                    .overlay(Label("Drop an image to redact it", systemImage: "arrow.down.doc").font(.headline))
                    .allowsHitTesting(false)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            loadFileURLs(providers)
            return true
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(nsImage: StatusIcon.image(.watching))
                .renderingMode(.template)
                .foregroundStyle(Color.accentColor)
            Text("Screenshot Redactor")
                .font(.headline)
            Spacer()
            Button { model.actions.settings() } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .help("Settings (⌘,)")
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var status: some View {
        switch model.watchStatus {
        case .watching(let folder), .paused(let folder):
            let watching: Bool = { if case .watching = model.watchStatus { return true } else { return false } }()
            HStack(spacing: 8) {
                Circle()
                    .fill(watching ? Color.green : Color.secondary.opacity(0.5))
                    .frame(width: 7, height: 7)
                VStack(alignment: .leading, spacing: 1) {
                    Text(watching ? "Watching \(folder)" : "Paused")
                        .font(.callout.weight(.medium))
                    Text(watching ? "New screenshots are redacted automatically." : "New screenshots in \(folder) are left alone.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Toggle("Watch", isOn: Binding(get: { watching }, set: { model.actions.setWatching($0) }))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
                    .accessibilityLabel("Watch for new screenshots")
            }
        case .unavailable(let folder):
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Can't reach \(folder)").font(.callout.weight(.medium))
                    Text("It was moved, renamed or is on a drive that isn't connected.")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer()
                Button("Reconnect…") { model.actions.chooseFolder() }.controlSize(.small)
            }
        case .notChosen:
            HStack(spacing: 8) {
                Image(systemName: "folder.badge.questionmark").foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Not watching a folder").font(.callout.weight(.medium))
                    Text("Choose where your screenshots are saved.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Choose…") { model.actions.chooseFolder() }.controlSize(.small)
            }
        }
    }

    private var actions: some View {
        VStack(spacing: 0) {
            PanelActionRow(title: "Capture Area", symbol: "rectangle.dashed", shortcut: model.shortcut?.displayString) {
                model.actions.capture()
            }
            PanelActionRow(title: "Open Image…", symbol: "photo", shortcut: nil) {
                model.actions.openImage()
            }
            PanelActionRow(title: "Redact Clipboard Image", symbol: "doc.on.clipboard", shortcut: nil) {
                model.actions.pasteImage()
            }
        }
    }

    private var recent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Recent").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                if !model.library.recent.isEmpty {
                    Button("Clear") { model.actions.clearRecent() }
                        .buttonStyle(.borderless)
                        .font(.caption)
                        .help("Forget these captures now (they're never saved to disk)")
                }
            }
            if model.library.recent.isEmpty {
                Text("Screenshots you take appear here, already redacted. They're kept only until you quit.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 6)
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                    ForEach(model.library.recent) { document in
                        RecentThumbnail(document: document, model: model)
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            if model.isPro {
                Label("Pro", systemImage: "checkmark.seal.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            } else {
                Text("\(model.allowance.remaining) of \(DailyAllowance.freePerDay) free today")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Button("Upgrade") { model.actions.upgrade() }
                    .buttonStyle(.borderless)
                    .font(.caption.weight(.semibold))
            }
            Spacer()
            Button("Quit") { model.actions.quit() }
                .buttonStyle(.borderless)
                .font(.caption)
        }
    }

    private func loadFileURLs(_ providers: [NSItemProvider]) {
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in model.actions.openFiles([url]) }
            }
        }
    }
}

/// A full-width row that highlights on hover, like a menu item.
private struct PanelActionRow: View {
    let title: String
    let symbol: String
    let shortcut: String?
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .frame(width: 18)
                    .foregroundStyle(isHovering ? Color.white : Color.accentColor)
                Text(title)
                Spacer()
                if let shortcut {
                    Text(shortcut)
                        .font(.callout)
                        .foregroundStyle(isHovering ? Color.white.opacity(0.8) : Color.secondary)
                }
            }
            .foregroundStyle(isHovering ? Color.white : Color.primary)
            .padding(.horizontal, 8)
            .frame(height: 30)
            .background(isHovering ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

private struct RecentThumbnail: View {
    let document: RedactionDocument
    @Bindable var model: MenuPanelModel

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.quaternary.opacity(0.7))
            if document.isExportable {
                DraggableImage(
                    image: document.rendered,
                    cornerRadius: 6,
                    dragFile: { model.actions.dragFile(document) },
                    dragEnded: { model.actions.dragEnded(document, $0) },
                    onClick: { model.actions.open(document) },
                    accessibilityLabel: "\(document.name), \(document.coveredCount) items hidden. Click to open, or drag into another app."
                )
            } else if case .failed = document.state {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(.secondary)
            } else {
                Shimmer()
                ProgressView().controlSize(.small)
            }
        }
        .frame(height: 58)
        .overlay(alignment: .bottomTrailing) {
            if document.state == .ready, document.coveredCount > 0 {
                Text("\(document.coveredCount)")
                    .font(.system(size: 10, weight: .bold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.accentColor, in: Capsule())
                    .padding(4)
                    .accessibilityHidden(true)
            }
        }
        .help("\(document.name) · \(document.created.formatted(date: .omitted, time: .shortened))")
    }
}
