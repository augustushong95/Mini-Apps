import Foundation

nonisolated enum PostureSensitivity: String, Codable, CaseIterable, Sendable {
    case gentle, normal, strict

    var title: String {
        switch self {
        case .gentle: "Gentle"
        case .normal: "Normal"
        case .strict: "Strict"
        }
    }

    /// Degrees below the baseline that start a slump.
    var enterAngle: Double {
        switch self {
        case .gentle: 24
        case .normal: 18
        case .strict: 13
        }
    }

    /// Degrees below the baseline that end one; lower than `enterAngle` so
    /// hovering near the line doesn't flicker.
    var exitAngle: Double {
        switch self {
        case .gentle: 16
        case .normal: 12
        case .strict: 8
        }
    }

    /// How long the head must stay down before it counts as a slump, so
    /// glancing at the keyboard or a phone doesn't.
    var dwell: TimeInterval {
        switch self {
        case .gentle: 180
        case .normal: 120
        case .strict: 60
        }
    }
}

nonisolated enum PostureState: Equatable, Sendable {
    case unknown, upright, slouching
}

nonisolated struct PostureReading: Equatable, Sendable {
    var state: PostureState
    /// Smoothed degrees from the baseline: negative is head down.
    var pitch: Double
    /// Smoothed degrees from the baseline: positive is toward the right shoulder.
    var roll: Double
    /// How long the current slump has lasted (0 when not slouching).
    var slouchDuration: TimeInterval

    var mirror: PostureMirror? {
        guard state != .unknown else { return nil }
        // Fully upright within 4° of the baseline, fully slumped by 26° down.
        let down = max(0, -pitch)
        return PostureMirror(uprightness: clamp(1 - (down - 4) / 22), tilt: clamp(roll, -18, 18))
    }

    static let unknown = PostureReading(state: .unknown, pitch: 0, roll: 0, slouchDuration: 0)
}

/// Turns head samples into upright / slouching / unknown, relative to the
/// user's calibrated baseline. Pure and deterministic: time comes from the
/// samples' timestamps.
nonisolated struct PostureClassifier: Sendable {
    var baseline: PostureBaseline
    var sensitivity: PostureSensitivity

    /// Smoothing time constant in seconds.
    static let smoothing: TimeInterval = 1.5
    /// A gap longer than this restarts smoothing.
    static let restartGap: TimeInterval = 1
    /// A gap longer than this forgets the posture entirely.
    static let forgetGap: TimeInterval = 10
    /// Beyond these the user isn't sitting at a screen (lying back, looking
    /// far away), so there's no posture to judge.
    static let maxPitch: Double = 55
    static let maxRoll: Double = 40
    /// Seconds above the exit angle before a slump ends.
    static let recoveryTime: TimeInterval = 4

    private(set) var reading = PostureReading.unknown
    private var lastTimestamp: TimeInterval?
    private var lastSensor: HeadSample.Sensor?
    private var smoothedPitch: Double?
    private var smoothedRoll: Double?
    private var downSince: TimeInterval?
    private var slouchStart: TimeInterval?
    private var recoveringSince: TimeInterval?

    init(baseline: PostureBaseline, sensitivity: PostureSensitivity) {
        self.baseline = baseline
        self.sensitivity = sensitivity
    }

    /// Forgets everything, for example after headphones disconnect or a game.
    mutating func reset() {
        reading = .unknown
        lastTimestamp = nil
        lastSensor = nil
        smoothedPitch = nil
        smoothedRoll = nil
        downSince = nil
        slouchStart = nil
        recoveringSince = nil
    }

    /// Feeds one sample. Returns the new reading and how many seconds it
    /// covers, for time accounting (0 for the first sample after a gap).
    @discardableResult
    mutating func update(_ sample: HeadSample) -> (reading: PostureReading, covered: TimeInterval) {
        let pitch = sample.gravityPitch - baseline.pitch
        let roll = sample.gravityRoll - baseline.roll
        let time = sample.timestamp

        var dt: TimeInterval = 0
        if let lastTimestamp {
            dt = time - lastTimestamp
            // A long gap, time running backwards, or the sensor switching buds
            // (which shifts the frame) all mean starting over.
            if dt < 0 || dt > Self.forgetGap || sample.sensor != lastSensor {
                reset()
                dt = 0
            }
        }
        lastTimestamp = time
        lastSensor = sample.sensor

        // After a short gap, smoothing restarts from this sample but a slump
        // in progress is kept.
        if smoothedPitch == nil || dt > Self.restartGap {
            smoothedPitch = pitch
            smoothedRoll = roll
            dt = 0
        } else {
            let alpha = 1 - exp(-dt / Self.smoothing)
            smoothedPitch! += (pitch - smoothedPitch!) * alpha
            smoothedRoll! += (roll - smoothedRoll!) * alpha
        }

        let p = smoothedPitch!
        let r = smoothedRoll!

        guard abs(p) <= Self.maxPitch, abs(r) <= Self.maxRoll else {
            downSince = nil
            slouchStart = nil
            recoveringSince = nil
            reading = PostureReading(state: .unknown, pitch: p, roll: r, slouchDuration: 0)
            return (reading, 0)
        }

        let down = -p
        var state: PostureState

        if slouchStart != nil {
            // Slouching: end it only after a few seconds back above the exit line.
            if down < sensitivity.exitAngle {
                recoveringSince = recoveringSince ?? time
                if time - recoveringSince! >= Self.recoveryTime {
                    slouchStart = nil
                    recoveringSince = nil
                    downSince = nil
                }
            } else {
                recoveringSince = nil
            }
            state = slouchStart == nil ? .upright : .slouching
        } else {
            // Upright: a slump starts once the head has stayed down for the
            // dwell time. Dipping between the two lines doesn't reset the
            // clock; coming back above the exit line does.
            if down >= sensitivity.enterAngle {
                downSince = downSince ?? time
            } else if down < sensitivity.exitAngle {
                downSince = nil
            }
            if let downSince, time - downSince >= sensitivity.dwell {
                slouchStart = downSince
            }
            state = slouchStart == nil ? .upright : .slouching
        }

        let duration = slouchStart.map { time - $0 } ?? 0
        reading = PostureReading(state: state, pitch: p, roll: r, slouchDuration: duration)
        return (reading, min(dt, Self.restartGap))
    }
}
