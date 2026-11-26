import CoreAudio
import Foundation

/// Reads whether another app is using a microphone, without opening any audio
/// device (so no microphone permission or entitlement is involved).
///
/// Two signals, because neither is reliable alone:
/// - per-process (macOS 14+): which processes are running audio input. This
///   is the one that should see AirPods, since the device-level flag is
///   reported to stay off for Bluetooth microphones.
/// - per-device: `kAudioDevicePropertyDeviceIsRunningSomewhere` on every
///   device that has input streams.
nonisolated enum AudioInputProbe {
    struct Snapshot: Sendable, Equatable {
        /// Bundle IDs (or "pid N" when a process has none) running audio input.
        var inputProcesses: [String]
        /// Names of input devices that report running somewhere.
        var runningInputDevices: [String]
        /// False when the per-process API returned nothing at all, which
        /// suggests the sandbox hides it.
        var processListAvailable: Bool

        var isMicInUse: Bool {
            !inputProcesses.isEmpty || !runningInputDevices.isEmpty
        }
    }

    static func snapshot(excluding ownPID: pid_t = ProcessInfo.processInfo.processIdentifier) -> Snapshot {
        let processes = objectIDs(of: kAudioHardwarePropertyProcessObjectList)
        let inputProcesses = processes.compactMap { process -> String? in
            guard uint32(process, kAudioProcessPropertyIsRunningInput) == 1 else { return nil }
            let pid = pid(of: process)
            guard pid != ownPID else { return nil }
            return string(process, kAudioProcessPropertyBundleID) ?? "pid \(pid ?? -1)"
        }

        let devices = objectIDs(of: kAudioHardwarePropertyDevices)
        let runningInputDevices = devices.compactMap { device -> String? in
            guard hasInputStreams(device),
                  uint32(device, kAudioDevicePropertyDeviceIsRunningSomewhere) == 1
            else { return nil }
            return string(device, kAudioObjectPropertyName) ?? "device \(device)"
        }

        return Snapshot(
            inputProcesses: inputProcesses.sorted(),
            runningInputDevices: runningInputDevices.sorted(),
            processListAvailable: !processes.isEmpty
        )
    }

    // MARK: Core Audio helpers

    private static func address(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func objectIDs(of selector: AudioObjectPropertySelector) -> [AudioObjectID] {
        var address = address(selector)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else {
            return []
        }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.stride)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else {
            return []
        }
        return Array(ids.prefix(Int(size) / MemoryLayout<AudioObjectID>.stride))
    }

    private static func uint32(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32? {
        var address = address(selector)
        guard AudioObjectHasProperty(object, &address) else { return nil }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    private static func pid(of process: AudioObjectID) -> pid_t? {
        var address = address(kAudioProcessPropertyPID)
        var value: pid_t = 0
        var size = UInt32(MemoryLayout<pid_t>.size)
        guard AudioObjectGetPropertyData(process, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    private static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = address(selector)
        guard AudioObjectHasProperty(object, &address) else { return nil }
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(object, &address, 0, nil, &size, pointer)
        }
        guard status == noErr, let value else { return nil }
        // Core Audio hands back a +1 reference for CFString properties.
        let string = value.takeRetainedValue() as String
        return string.isEmpty ? nil : string
    }

    private static func hasInputStreams(_ device: AudioObjectID) -> Bool {
        var address = address(kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeInput)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr else { return false }
        return size > 0
    }
}
