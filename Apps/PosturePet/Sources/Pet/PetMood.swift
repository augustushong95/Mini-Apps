import CoreGraphics

/// Mochi's mood, from most to least urgent. `PetBrain` decides which applies.
nonisolated enum PetMood: String, Codable, CaseIterable, Sendable {
    case sleepy, sick, slumped, tired, happy

    var title: String {
        switch self {
        case .happy: "Happy"
        case .tired: "Stiff"
        case .slumped: "Slumping"
        case .sleepy: "Sleepy"
        case .sick: "Under the weather"
        }
    }

    /// A short status line in Mochi's voice.
    var line: String {
        switch self {
        case .happy: "Feeling bouncy!"
        case .tired: "I'm stiff… play with me?"
        case .slumped: "My leaf is drooping."
        case .sleepy: "It's late. Time to rest?"
        case .sick: "I don't feel so good. A break would help."
        }
    }

    var symbol: String {
        switch self {
        case .happy: "sun.max.fill"
        case .tired: "figure.cooldown"
        case .slumped: "arrow.down.forward"
        case .sleepy: "moon.zzz.fill"
        case .sick: "thermometer.medium"
        }
    }
}

/// The user's current posture as Mochi should mirror it.
nonisolated struct PostureMirror: Equatable, Sendable {
    /// 1 tall, 0 slumped.
    var uprightness: Double
    /// Degrees; positive is toward the user's right shoulder.
    var tilt: Double

    static let neutral = PostureMirror(uprightness: 1, tilt: 0)
}

extension PetMood {
    /// Mochi's pose for this mood. A live posture reading, when there is one,
    /// drives how tall Mochi sits, its lean and its leaf, except while asleep.
    nonisolated func pose(stage: GrowthStage, posture: PostureMirror?) -> PetPose {
        var pose = PetPose()
        pose.stage = stage
        switch self {
        case .happy:
            pose.eyes = .open
            pose.mouth = .smile
            pose.blush = 0.8
        case .tired:
            pose.eyeOpenness = 0.62
            pose.mouth = .wobble
            pose.blush = 0.45
            pose.uprightness = 0.82
            pose.accessories = [.sweat]
        case .slumped:
            pose.eyeOpenness = 0.8
            pose.gaze = CGVector(dx: 0, dy: -0.8)
            pose.mouth = .flat
            pose.blush = 0.4
            pose.uprightness = 0.2
        case .sleepy:
            pose.eyes = .closed
            pose.mouth = .oh
            pose.blush = 0.55
            pose.uprightness = 0.9
            pose.leafDroop = 0.45
            pose.accessories = [.zzz]
        case .sick:
            pose.eyeOpenness = 0.55
            pose.mouth = .wobble
            pose.blush = 0.25
            pose.paleness = 1
            pose.uprightness = 0.7
            pose.leafDroop = 0.6
            pose.accessories = [.thermometer]
        }

        if let posture, self != .sleepy {
            pose.uprightness = min(pose.uprightness, posture.uprightness)
            pose.tilt = posture.tilt
            pose.leafDroop = max(pose.leafDroop, 1 - posture.uprightness)
            if posture.uprightness < 0.5 {
                pose.gaze.dy = min(pose.gaze.dy, -0.6)
            }
        } else if self != .sleepy {
            pose.leafDroop = max(pose.leafDroop, 1 - pose.uprightness)
        }
        return pose
    }
}
