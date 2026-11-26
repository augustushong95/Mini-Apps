import AppKit
import SwiftUI
import MenuBarKit

/// A nudge Mochi says out loud: one short line, picked from a few so it
/// doesn't say the same thing every time.
struct Nudge: Identifiable, Equatable {
    let kind: NudgeKind
    let title: String
    let id = UUID()

    init(kind: NudgeKind, title: String? = nil) {
        self.kind = kind
        self.title = title ?? PetLines.bubbleTitles(for: kind)[0]
    }

    /// How long it stays before going away by itself.
    var lifetime: TimeInterval {
        kind == .breakInvite ? 20 : 12
    }

    static func == (lhs: Nudge, rhs: Nudge) -> Bool { lhs.id == rhs.id }
}

enum BubbleAction {
    /// `timedOut` is the bubble going away by itself; the rest are clicks.
    case play, snooze, tookBreak, dismiss, timedOut
}

/// Shows speech bubbles pointing at Mochi: below the menu bar icon, or
/// beside the desktop pet. Never takes focus; goes away by itself, but
/// waits while the pointer is over it.
final class BubbleController {
    var onAction: ((Nudge, BubbleAction) -> Void)?
    private let panel: FloatingPanel
    private let model = BubbleModel()
    private var dismissWork: DispatchWorkItem?
    private(set) var current: Nudge?

    static let size = NSSize(width: 300, height: 150)

    init() {
        panel = FloatingPanel(size: Self.size, canBecomeKey: false, level: .statusBar)
        panel.setContent(BubbleHost(model: model) { [weak self] action in
            self?.handle(action)
        })
    }

    var isVisible: Bool { panel.isVisible }

    /// - Parameters:
    ///   - anchor: Mochi's frame in screen coordinates.
    ///   - fromMenuBar: true points the tail up at the menu bar icon,
    ///     false points it sideways at the desktop pet.
    func show(_ nudge: Nudge, pose: PetPose, anchor: NSRect, fromMenuBar: Bool) {
        current = nudge
        model.isHovering = false
        model.nudge = nudge
        model.pose = pose
        panel.contentView?.layoutSubtreeIfNeeded()
        let size = panel.contentView?.fittingSize ?? Self.size
        panel.setContentSize(size)

        let origin: NSPoint
        if fromMenuBar {
            model.tail = .top
            origin = PanelPlacement.below(anchor, size: size, gap: 2)
        } else {
            let placed = PanelPlacement.beside(anchor, size: size, gap: 2)
            model.tail = placed.x >= anchor.midX ? .leading : .trailing
            origin = placed
        }
        panel.present(at: origin, animated: true)
        panel.invalidateShadow()
        scheduleDismiss(after: nudge.lifetime)
    }

    func hide() {
        dismissWork?.cancel()
        current = nil
        // Ordered out under the pointer, the bubble may never get its
        // mouse-exited event; don't let that keep the next one up.
        model.isHovering = false
        panel.dismiss(animated: true)
    }

    private func handle(_ action: BubbleAction) {
        guard let nudge = current else { return }
        hide()
        onAction?(nudge, action)
    }

    private func scheduleDismiss(after seconds: TimeInterval) {
        dismissWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                // The user is reading or reaching for a button: wait.
                if self.model.isHovering {
                    self.scheduleDismiss(after: 4)
                } else {
                    self.handle(.timedOut)
                }
            }
        }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }
}

/// Which way a speech bubble's tail points.
nonisolated enum BubbleTail: Sendable {
    case top, leading, trailing
}

@Observable
final class BubbleModel {
    var nudge: Nudge?
    var pose = PetPose()
    var tail: BubbleTail = .top
    var isHovering = false
}

private struct BubbleHost: View {
    let model: BubbleModel
    let action: (BubbleAction) -> Void

    var body: some View {
        if let nudge = model.nudge {
            BubbleView(nudge: nudge, pose: model.pose, tail: model.tail, action: action)
                .onHover { model.isHovering = $0 }
                .padding(12)
                .id(nudge.id)
        }
    }
}

struct BubbleView: View {
    let nudge: Nudge
    let pose: PetPose
    let tail: BubbleTail
    let action: (BubbleAction) -> Void

    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                PetView(pose: pose, animatesIdle: false)
                    .frame(width: 40, height: 40)
                    .accessibilityHidden(true)
                Text(nudge.title)
                    .font(.rounded(14, .bold))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button {
                    action(.dismiss)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 18)
                        .background(.quaternary, in: Circle())
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("Dismiss")
            }
            buttons
        }
        .padding(12)
        .frame(width: 262)
        .background {
            SpeechBubbleShape(tail: tail)
                .fill(.background)
                .shadow(color: .black.opacity(0.16), radius: 10, y: 4)
            SpeechBubbleShape(tail: tail)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .scaleEffect(appeared ? 1 : 0.85, anchor: anchor)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            withAnimation(Theme.Motion.bouncy) { appeared = true }
        }
        .fontDesign(.rounded)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(nudge.title)
    }

    private var anchor: UnitPoint {
        switch tail {
        case .top: .top
        case .leading: .leading
        case .trailing: .trailing
        }
    }

    @ViewBuilder
    private var buttons: some View {
        HStack(spacing: 6) {
            switch nudge.kind {
            case .breakInvite:
                Button { action(.play) } label: { Label("Play", systemImage: "play.fill") }
                    .buttonStyle(.pill(.prominent, tint: Color(Palette.coral)))
                Button("Later") { action(.snooze) }
                    .buttonStyle(.pill(.plain))
                    .help("Ask again in 10 minutes")
                Menu {
                    Button("I took a break") { action(.tookBreak) }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 22, height: 22)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel("More")
            case .posture:
                Button("OK") { action(.dismiss) }
                    .buttonStyle(.pill(.soft, tint: Color(Palette.sky)))
            case .windDown:
                Button("Good night") { action(.dismiss) }
                    .buttonStyle(.pill(.soft, tint: Color(Palette.lavender)))
            }
        }
        .controlSize(.small)
    }
}

/// A rounded rectangle with a small tail pointing at Mochi.
nonisolated struct SpeechBubbleShape: Shape {
    var tail: BubbleTail
    private let radius: CGFloat = 16
    private let tailSize: CGFloat = 8

    func path(in rect: CGRect) -> Path {
        var path = Path(roundedRect: rect, cornerRadius: radius, style: .continuous)
        switch tail {
        case .top:
            let x = rect.midX
            path.move(to: CGPoint(x: x - tailSize, y: rect.minY + 1))
            path.addQuadCurve(to: CGPoint(x: x, y: rect.minY - tailSize), control: CGPoint(x: x - 2, y: rect.minY - 1))
            path.addQuadCurve(to: CGPoint(x: x + tailSize, y: rect.minY + 1), control: CGPoint(x: x + 2, y: rect.minY - 1))
        case .leading:
            let y = rect.midY
            path.move(to: CGPoint(x: rect.minX + 1, y: y - tailSize))
            path.addQuadCurve(to: CGPoint(x: rect.minX - tailSize, y: y), control: CGPoint(x: rect.minX - 1, y: y - 2))
            path.addQuadCurve(to: CGPoint(x: rect.minX + 1, y: y + tailSize), control: CGPoint(x: rect.minX - 1, y: y + 2))
        case .trailing:
            let y = rect.midY
            path.move(to: CGPoint(x: rect.maxX - 1, y: y - tailSize))
            path.addQuadCurve(to: CGPoint(x: rect.maxX + tailSize, y: y), control: CGPoint(x: rect.maxX + 1, y: y - 2))
            path.addQuadCurve(to: CGPoint(x: rect.maxX - 1, y: y + tailSize), control: CGPoint(x: rect.maxX + 1, y: y + 2))
        }
        return path
    }
}
