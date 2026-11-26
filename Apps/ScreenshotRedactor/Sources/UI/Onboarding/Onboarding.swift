import AppKit
import MenuBarKit
import SwiftUI

/// The first-launch window: four short steps.
final class OnboardingController: NSObject, NSWindowDelegate {
    var onFinish: (() -> Void)?
    private let model: AppModel
    private var window: NSWindow?
    private var finished = false

    init(model: AppModel) {
        self.model = model
    }

    func show() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 520), styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: OnboardingView(model: model, finish: { [weak self] in self?.finish() }))
        window.center()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        window?.close()
        onFinish?()
    }

    func windowWillClose(_ notification: Notification) {
        // Closing the window counts as done; everything is in Settings later.
        if !finished {
            finished = true
            onFinish?()
        }
    }
}

struct OnboardingView: View {
    let model: AppModel
    let finish: () -> Void
    @State private var step = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let stepCount = 4

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case 0: WelcomeStep()
                case 1: FolderStep(model: model, folder: model.folder)
                case 2: SharingStep(preferences: model.preferences)
                default: TryStep(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 44)
            .padding(.top, 44)
            .transition(reduceMotion ? .opacity : .asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .opacity))
            .id(step)

            ZStack {
                HStack(spacing: 6) {
                    ForEach(0..<stepCount, id: \.self) { index in
                        Circle()
                            .fill(index == step ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: 6, height: 6)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Step \(step + 1) of \(stepCount)")
                HStack {
                    if step > 0 {
                        Button("Back") { withAnimation { step -= 1 } }
                    }
                    Spacer()
                    if step < stepCount - 1 {
                        Button("Continue") { withAnimation { step += 1 } }
                            .buttonStyle(.borderedProminent)
                            .keyboardShortcut(.defaultAction)
                    } else {
                        Button("Done") { finish() }
                            .buttonStyle(.borderedProminent)
                            .keyboardShortcut(.defaultAction)
                    }
                }
            }
            .controlSize(.large)
            .padding(20)
        }
        .frame(width: 560, height: 520)
        .background(.background)
    }
}

private struct StepHeader: View {
    let symbol: String
    let title: String
    let text: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 72, height: 72)
                .background(
                    LinearGradient(colors: [Color.accentColor, Color.accentColor.opacity(0.7)], startPoint: .top, endPoint: .bottom),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
                .accessibilityHidden(true)
            Text(title)
                .font(.title.weight(.semibold))
                .multilineTextAlignment(.center)
            Text(text)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct WelcomeStep: View {
    var body: some View {
        VStack(spacing: 22) {
            StepHeader(
                symbol: "eye.slash.fill",
                title: "Cover secrets before you share",
                text: "Take screenshots as usual. Within a second, keys, passwords, personal details and internal addresses are covered with solid boxes, ready to paste into Slack, Jira or email."
            )
            HStack(spacing: 10) {
                Image(systemName: "lock.shield.fill").foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Works 100% offline").font(.headline)
                    Text("The app has no network access at all, so your screenshots can't leave this Mac.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .background(.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            Spacer()
        }
    }
}

private struct FolderStep: View {
    let model: AppModel
    let folder: FolderAccess

    var body: some View {
        VStack(spacing: 20) {
            StepHeader(
                symbol: "folder.fill",
                title: "Where do your screenshots go?",
                text: "macOS saves them to your Desktop unless you changed it. Allow access so new screenshots are redacted as they arrive. Only new screenshots are read."
            )
            if let url = folder.url {
                Label("Watching \(FolderAccess.displayName(for: url))", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.headline)
                Button("Choose Another Folder…") { model.chooseFolder() }
                    .buttonStyle(.borderless)
            } else {
                VStack(spacing: 10) {
                    Button { model.chooseFolder() } label: {
                        Label("Allow Access to Desktop…", systemImage: "folder.badge.plus").frame(minWidth: 240)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    Text("In the next window, check that Desktop is selected, then click Allow Access. If you save screenshots elsewhere, pick that folder instead.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "bolt.fill").foregroundStyle(.yellow)
                Text("Tip: for instant previews, press ⇧⌘5, click Options and uncheck Show Floating Thumbnail. Otherwise macOS waits about 5 seconds before saving each screenshot.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            Spacer()
        }
    }
}

private struct SharingStep: View {
    @Bindable var preferences: Preferences

    var body: some View {
        VStack(spacing: 20) {
            StepHeader(
                symbol: "doc.on.doc.fill",
                title: "How do you want to share?",
                text: "After each screenshot, a small preview shows what was covered. You can fix any box before you copy."
            )
            Picker("When a screenshot is ready", selection: $preferences.readyAction) {
                Text("Show a preview, and copy from it (recommended)").tag(ReadyAction.showPreview)
                Text("Copy the redacted image right away, so you can just paste").tag(ReadyAction.copyAutomatically)
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)

            if let combo = preferences.hotKey {
                HStack(alignment: .top, spacing: 10) {
                    Text(combo.displayString)
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                    Text("captures an area directly, with no file and no waiting. macOS asks for Screen Recording permission the first time.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Spacer()
        }
    }
}

private struct TryStep: View {
    let model: AppModel

    var body: some View {
        VStack(spacing: 22) {
            StepHeader(
                symbol: "sparkles",
                title: "You're set",
                text: "Take a screenshot with ⇧⌘4 to see it work, or try it on a made-up example now. The menu bar icon opens recent captures and settings."
            )
            Button { model.openSample() } label: {
                Label("Try It with a Sample", systemImage: "play.rectangle.fill").frame(minWidth: 220)
            }
            .controlSize(.large)
            LaunchAtLoginToggle()
                .toggleStyle(.checkbox)
            Text("You get \(DailyAllowance.freePerDay) free redactions a day. Pro removes the limit and adds your own rules.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
    }
}
