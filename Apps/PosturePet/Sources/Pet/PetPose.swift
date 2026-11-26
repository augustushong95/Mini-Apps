import CoreGraphics

/// Everything that decides how Mochi looks at one moment. Renderers turn a
/// pose into shapes; nothing in here knows how it's drawn.
nonisolated struct PetPose: Equatable, Sendable {
    /// 1 is sitting tall, 0 is fully slumped. Mirrors the user's head pitch.
    var uprightness: Double = 1
    /// Sideways lean in degrees; positive leans toward the viewer's right,
    /// like a mirror image of the user tilting toward their right shoulder.
    var tilt: Double = 0
    var eyes: EyeStyle = .open
    /// How open `.open` eyes are, 0…1.
    var eyeOpenness: Double = 1
    /// Where Mochi looks, each axis −1…1 (positive is right / up).
    var gaze: CGVector = .zero
    var mouth: MouthStyle = .smile
    var blush: Double = 0.7
    /// 0 is a perky leaf, 1 is fully wilted.
    var leafDroop: Double = 0
    /// 0 is healthy, 1 is the pale "under the weather" tint.
    var paleness: Double = 0
    var accessories: Set<Accessory> = []
    var stage: GrowthStage = .seedling

    enum EyeStyle: Sendable {
        /// Round eyes; `eyeOpenness` controls how open.
        case open
        /// Upturned "^ ^" arcs.
        case happy
        /// Downturned arcs, asleep.
        case closed
        /// One "^" and one round eye.
        case wink
        /// Sparkly star eyes, for big wins.
        case star
        /// Swirls, after spinning around.
        case dizzy
        /// Big round eyes, surprised or attentive.
        case wide
    }

    enum MouthStyle: Sendable {
        case smile, grin, flat, frown, wobble, oh
        /// A cat-like "ω".
        case cat
        /// A smile with the tongue poking out.
        case tongue
        /// A big tall "O".
        case yawn
        /// A small round kiss-shaped mouth.
        case pout
    }

    enum Accessory: Sendable, Hashable {
        case zzz, sweat, thermometer, crown, sparkles
    }
}

nonisolated enum GrowthStage: Int, Codable, CaseIterable, Sendable, Comparable {
    case seedling, sprout, bud, bloom

    nonisolated static func < (lhs: GrowthStage, rhs: GrowthStage) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var name: String {
        switch self {
        case .seedling: "Seedling"
        case .sprout: "Sprout"
        case .bud: "Bud"
        case .bloom: "Bloom"
        }
    }

    var next: GrowthStage? {
        GrowthStage(rawValue: rawValue + 1)
    }
}

extension PetPose {
    /// The same pose with values rounded to steps a viewer can't tell apart,
    /// so tiny sensor jitter doesn't trigger redraws.
    nonisolated var quantized: PetPose {
        var pose = self
        pose.uprightness = (uprightness * 50).rounded() / 50
        pose.tilt = tilt.rounded()
        pose.eyeOpenness = (eyeOpenness * 20).rounded() / 20
        pose.gaze = CGVector(dx: (gaze.dx * 10).rounded() / 10, dy: (gaze.dy * 10).rounded() / 10)
        pose.blush = (blush * 10).rounded() / 10
        pose.leafDroop = (leafDroop * 20).rounded() / 20
        pose.paleness = (paleness * 10).rounded() / 10
        return pose
    }
}
