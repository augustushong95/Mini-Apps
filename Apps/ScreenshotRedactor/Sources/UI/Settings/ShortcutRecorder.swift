import AppKit
import SwiftUI

/// Click, then press the new shortcut. Esc cancels; Delete clears it.
/// Shortcuts must use ⌘ or ⌃ and can't be one the system already uses.
struct ShortcutRecorder: View {
    @Binding var combo: KeyCombo?
    /// Shown under the field (e.g. "already used by another app").
    var problem: String?

    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var feedback: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Button {
                    isRecording ? stopRecording() : startRecording()
                } label: {
                    Text(isRecording ? "Type a shortcut…" : (combo?.displayString ?? "None"))
                        .frame(minWidth: 110)
                        .foregroundStyle(isRecording ? Color.accentColor : Color.primary)
                }
                .accessibilityLabel(isRecording ? "Recording a shortcut" : "Capture shortcut: \(combo?.spokenDescription ?? "none")")
                .accessibilityHint("Press to record a new shortcut")
                if combo != nil, !isRecording {
                    Button("Clear") { combo = nil }
                        .buttonStyle(.borderless)
                }
                if combo != KeyCombo.defaultCapture, !isRecording {
                    Button("Use Default") { combo = .defaultCapture }
                        .buttonStyle(.borderless)
                }
            }
            if let message = feedback ?? problem {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .onDisappear { stopRecording() }
    }

    private func startRecording() {
        feedback = nil
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            handle(event)
            return nil
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
    }

    private func handle(_ event: NSEvent) {
        let modifiers = event.modifierFlags.intersection(KeyCombo.relevantModifiers)
        if event.keyCode == 53, modifiers.isEmpty { // Esc
            stopRecording()
            return
        }
        if [51, 117].contains(event.keyCode), modifiers.isEmpty { // Delete
            combo = nil
            stopRecording()
            return
        }
        let candidate = KeyCombo(keyCode: event.keyCode, modifiers: modifiers)
        guard candidate.isValid else {
            feedback = "Include ⌘ or ⌃, for example ⌥⇧⌘4."
            NSSound.beep()
            return
        }
        if let conflict = HotKeyCenter.conflict(for: candidate) {
            feedback = conflict
            NSSound.beep()
            return
        }
        feedback = nil
        combo = candidate
        stopRecording()
    }
}
