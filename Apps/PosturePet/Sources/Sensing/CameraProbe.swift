import CoreMediaIO
import Foundation

/// Reads whether any camera is running in another app, through CoreMediaIO's
/// device properties. It never opens a camera. Whether the sandbox exposes the
/// device list without the camera entitlement is checked in the Sensor Lab.
nonisolated enum CameraProbe {
    struct Snapshot: Sendable, Equatable {
        var deviceCount: Int
        var runningDevices: [String]

        var isCameraInUse: Bool { !runningDevices.isEmpty }
    }

    static func snapshot() -> Snapshot {
        let devices = deviceIDs()
        let running = devices.compactMap { device -> String? in
            guard uint32(device, CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere)) == 1 else {
                return nil
            }
            return name(device) ?? "camera \(device)"
        }
        return Snapshot(deviceCount: devices.count, runningDevices: running.sorted())
    }

    private static func address(_ selector: CMIOObjectPropertySelector) -> CMIOObjectPropertyAddress {
        CMIOObjectPropertyAddress(
            mSelector: selector,
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
    }

    private static func deviceIDs() -> [CMIOObjectID] {
        var address = address(CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices))
        let system = CMIOObjectID(kCMIOObjectSystemObject)
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else {
            return []
        }
        let count = Int(size) / MemoryLayout<CMIOObjectID>.stride
        var ids = [CMIOObjectID](repeating: 0, count: count)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(system, &address, 0, nil, size, &used, &ids) == noErr else {
            return []
        }
        return Array(ids.prefix(Int(used) / MemoryLayout<CMIOObjectID>.stride))
    }

    private static func uint32(_ object: CMIOObjectID, _ selector: CMIOObjectPropertySelector) -> UInt32? {
        var address = address(selector)
        guard CMIOObjectHasProperty(object, &address) else { return nil }
        var value: UInt32 = 0
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(object, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &used, &value) == noErr
        else { return nil }
        return value
    }

    private static func name(_ object: CMIOObjectID) -> String? {
        var address = address(CMIOObjectPropertySelector(kCMIOObjectPropertyName))
        guard CMIOObjectHasProperty(object, &address) else { return nil }
        var value: Unmanaged<CFString>?
        var used: UInt32 = 0
        let size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            CMIOObjectGetPropertyData(object, &address, 0, nil, size, &used, pointer)
        }
        guard status == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }
}
