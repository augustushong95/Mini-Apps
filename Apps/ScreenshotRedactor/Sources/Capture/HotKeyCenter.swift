import AppKit
import Carbon.HIToolbox
import Observation
import OSLog

/// The app's one global shortcut, through Carbon's `RegisterEventHotKey`:
/// it works in the sandbox and needs no Accessibility permission.
@Observable
final class HotKeyCenter {
    @ObservationIgnored private var hotKey: EventHotKeyRef?
    @ObservationIgnored private var eventHandler: EventHandlerRef?
    @ObservationIgnored private var action: (() -> Void)?
    /// Why the last registration failed, for Settings to show.
    private(set) var problem: String?

    private static let signature: OSType = 0x53_52_64_63 // "SRdc"

    /// Registers `combo` (replacing any earlier one). Nil clears it.
    @discardableResult
    func register(_ combo: KeyCombo?, action: @escaping () -> Void) -> Bool {
        unregister()
        problem = nil
        guard let combo else { return true }
        guard combo.isValid else {
            problem = "Shortcuts need ⌘ or ⌃."
            return false
        }
        self.action = action
        installHandlerIfNeeded()
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(combo.keyCode), combo.carbonModifiers,
            EventHotKeyID(signature: Self.signature, id: 1),
            GetApplicationEventTarget(), 0, &reference
        )
        guard status == noErr, let reference else {
            problem = status == eventHotKeyExistsErr
                ? "\(combo.displayString) is already used by another app. Choose another shortcut."
                : "\(combo.displayString) couldn't be used. Choose another shortcut."
            Logger.app.error("RegisterEventHotKey failed: \(status)")
            return false
        }
        hotKey = reference
        return true
    }

    func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
    }

    private func installHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            guard status == noErr, identifier.signature == HotKeyCenter.signature else { return OSStatus(eventNotHandledErr) }
            let center = Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
            // Carbon delivers application events on the main thread.
            MainActor.assumeIsolated { center.action?() }
            return noErr
        }
        InstallEventHandler(GetApplicationEventTarget(), callback, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
    }

    /// Shortcuts the system or every app already uses.
    static func conflict(for combo: KeyCombo) -> String? {
        let reserved: [(KeyCombo, String)] = [
            (KeyCombo(keyCode: UInt16(kVK_ANSI_3), modifiers: [.command, .shift]), "the system's screenshot"),
            (KeyCombo(keyCode: UInt16(kVK_ANSI_4), modifiers: [.command, .shift]), "the system's screenshot"),
            (KeyCombo(keyCode: UInt16(kVK_ANSI_5), modifiers: [.command, .shift]), "the system's screenshot"),
            (KeyCombo(keyCode: UInt16(kVK_ANSI_3), modifiers: [.command, .shift, .control]), "the system's screenshot"),
            (KeyCombo(keyCode: UInt16(kVK_ANSI_4), modifiers: [.command, .shift, .control]), "the system's screenshot"),
            (KeyCombo(keyCode: UInt16(kVK_Space), modifiers: [.command]), "Spotlight"),
            (KeyCombo(keyCode: UInt16(kVK_Tab), modifiers: [.command]), "the app switcher"),
        ]
        if let match = reserved.first(where: { $0.0 == combo }) { return "\(combo.displayString) is used by \(match.1)." }
        let everyApp: Set<Int> = [kVK_ANSI_Q, kVK_ANSI_W, kVK_ANSI_C, kVK_ANSI_V, kVK_ANSI_X, kVK_ANSI_Z, kVK_ANSI_A, kVK_ANSI_S, kVK_ANSI_N, kVK_ANSI_O, kVK_ANSI_P, kVK_ANSI_H, kVK_ANSI_M, kVK_ANSI_F, kVK_ANSI_T]
        if combo.modifiers == .command, everyApp.contains(Int(combo.keyCode)) {
            return "\(combo.displayString) is used by every app."
        }
        return nil
    }
}
