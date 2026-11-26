import CoreMotion
import Foundation

/// One headphone motion reading, copied out of `CMDeviceMotion` the moment it
/// arrives so it can cross isolation boundaries (`CMDeviceMotion` isn't Sendable).
///
/// Posture uses gravity only: it's absolute, so it survives the yaw re-centre
/// that happens when Spatial Audio playback starts. Raw samples are never
/// stored or logged.
nonisolated struct HeadSample: Sendable, Equatable {
    enum Sensor: Sendable, Equatable {
        case unknown, left, right
    }

    /// Seconds since boot, from Core Motion.
    var timestamp: TimeInterval
    /// Gravity in the headphone's frame, in g.
    var gravity: SIMD3<Double>
    /// Rotation rate in radians per second.
    var rotationRate: SIMD3<Double>
    /// Attitude from Core Motion, in radians. Yaw drifts and re-centres, so
    /// it's for diagnostics and game steering only.
    var attitude: SIMD3<Double>
    var sensor: Sensor

    /// Head pitch from gravity, in degrees. Sign convention is fixed by
    /// `MotionAxes.pitchSign`.
    var gravityPitch: Double {
        MotionAxes.pitchSign * degrees(atan2(gravity.y, -gravity.z))
    }

    /// Head roll (sideways tilt) from gravity, in degrees.
    var gravityRoll: Double {
        MotionAxes.rollSign * degrees(atan2(gravity.x, -gravity.z))
    }
}

extension HeadSample {
    nonisolated init(_ motion: CMDeviceMotion) {
        timestamp = motion.timestamp
        gravity = SIMD3(motion.gravity.x, motion.gravity.y, motion.gravity.z)
        rotationRate = SIMD3(motion.rotationRate.x, motion.rotationRate.y, motion.rotationRate.z)
        attitude = SIMD3(motion.attitude.pitch, motion.attitude.roll, motion.attitude.yaw)
        sensor = switch motion.sensorLocation {
        case .headphoneLeft: .left
        case .headphoneRight: .right
        default: .unknown
        }
    }
}

extension HeadSample {
    /// A sample whose gravity-derived pitch and roll are the given degrees,
    /// for tests, previews and the debug posture simulator.
    nonisolated static func synthetic(pitch: Double, roll: Double, timestamp: TimeInterval, sensor: Sensor = .left) -> HeadSample {
        let p = pitch * .pi / 180 * MotionAxes.pitchSign
        let r = roll * .pi / 180 * MotionAxes.rollSign
        let z = -cos(p)
        return HeadSample(
            timestamp: timestamp,
            gravity: SIMD3(tan(r) * -z, sin(p), z),
            rotationRate: .zero,
            attitude: .zero,
            sensor: sensor
        )
    }
}

/// Sign conventions for turning gravity into "head down is negative pitch" and
/// "tilt right is positive roll". Confirmed on a real device in the Sensor Lab
/// sign check (see NOTES.md).
nonisolated enum MotionAxes {
    static let pitchSign: Double = 1
    static let rollSign: Double = 1
}

nonisolated func degrees(_ radians: Double) -> Double {
    radians * 180 / .pi
}
