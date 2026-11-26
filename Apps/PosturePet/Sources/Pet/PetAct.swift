import CoreGraphics

/// A temporary face Mochi makes during an act, laid over its normal pose.
/// Nil fields keep the pose's own value.
nonisolated struct PetFace: Equatable, Sendable {
    var eyes: PetPose.EyeStyle?
    var openness: Double?
    var gaze: CGVector?
    var mouth: PetPose.MouthStyle?
    var blush: Double?

    init(
        eyes: PetPose.EyeStyle? = nil, openness: Double? = nil, gaze: CGVector? = nil,
        mouth: PetPose.MouthStyle? = nil, blush: Double? = nil
    ) {
        self.eyes = eyes
        self.openness = openness
        self.gaze = gaze
        self.mouth = mouth
        self.blush = blush
    }

    func applied(to pose: PetPose) -> PetPose {
        var pose = pose
        if let eyes { pose.eyes = eyes }
        if let openness { pose.eyeOpenness = openness }
        if let gaze { pose.gaze = gaze }
        if let mouth { pose.mouth = mouth }
        if let blush { pose.blush = blush }
        return pose
    }
}

/// A body movement, played by `PetLayerView` with Core Animation.
/// Heights and depths are fractions of Mochi's size; angles are degrees.
nonisolated enum BodyMotion: Equatable, Sendable {
    /// A jump with a squash on take-off and landing.
    case hop(height: Double, duration: Double)
    /// Rocking side to side around the base.
    case rock(angle: Double, swings: Int, duration: Double)
    /// A fast little tremble.
    case shiver(duration: Double)
    /// A full turn around its middle, with a small lift.
    case roll(duration: Double)
    /// Turning around on the spot (it squeezes thin and comes back mirrored).
    case turn(duration: Double)
    /// Squashing down low, holding, and recovering.
    case sink(depth: Double, hold: Double)
    /// Stretching up tall, holding, and settling.
    case stretchTall(amount: Double, hold: Double)
    /// Slowly drooping forward, then a jolt awake.
    case nodOff(duration: Double)
    /// Three quick chews.
    case chew
    /// The leaf spins all the way round.
    case leafTwirl(duration: Double)
    /// The leaf waves back and forth.
    case leafWave(swings: Int, duration: Double)
    /// Drifting up and down, like floating.
    case float(height: Double, duration: Double)
    /// Leaning to one side and back.
    case lean(angle: Double, duration: Double)
    /// A tiny startled jump.
    case jolt
}

/// A short-lived effect drawn around Mochi's head.
nonisolated enum PetEffect: String, CaseIterable, Sendable {
    case hearts, notes, exclaim, question, puff, sleepBubble, sparkles, zzz, sweat
}

nonisolated struct Timed<Value: Sendable & Equatable>: Sendable, Equatable {
    let at: Double
    let value: Value

    init(_ at: Double, _ value: Value) {
        self.at = at
        self.value = value
    }
}

/// What an act does over time.
nonisolated struct ActScript: Sendable, Equatable {
    var duration: Double
    var faces: [Timed<PetFace>] = []
    var motions: [Timed<BodyMotion>] = []
    var effects: [Timed<PetEffect>] = []
    /// Seconds before the same act may play again.
    var cooldown: Double = 0

    /// Only the face and effects change: allowed with Reduce Motion.
    var isFaceOnly: Bool { motions.isEmpty }
}

/// Everything Mochi can do: short scripted performances, picked by
/// `BehaviorDirector` for the situation at hand.
nonisolated enum PetAct: String, CaseIterable, Sendable {
    // Idle, happy
    case lookAround, doubleBounce, wiggle, hum, leafTwirl, wink, heartPop, roll, daydream, stretch, dance
    // Idle, stiff
    case sigh, stretchFlop, slowRock, yawn, fidget, lookAtYou
    // Idle, slumping
    case melt, leafFlutter, deepSigh, trySitUp
    // Idle, sleepy
    case nodOff, sleepBubble, snore, sleepSmile
    // Idle, under the weather
    case shiver, sneeze, cough, sniffle
    // Tapped
    case giggle, boing, surprised, heart, spin, shy, dizzy
    // Fed
    case chomp, gulp, savour, yumDance
    // Back from a break
    case welcomeBounce, stretchCheer, happySpin
    // Won a game, bought Pro, finished setup
    case victoryHop, sparkleSpin, cheer
    // A break is due
    case pointLeaf
    // Sat back up / started slumping
    case taDa, oof, sadLook, leafFlop
    // Desktop pet dropped
    case squashLand, dizzyLand, happyLand
    // AirPods
    case perkUp, puzzled
    // Morning, growth
    case goodMorning, grow

    var script: ActScript {
        let up = CGVector(dx: 0, dy: 1)
        let down = CGVector(dx: 0, dy: -1)
        let ahead = CGVector.zero
        switch self {
        // MARK: Idle, happy
        case .lookAround:
            return ActScript(duration: 2.4, faces: [
                Timed(0, PetFace(gaze: CGVector(dx: -1, dy: 0.15))),
                Timed(0.8, PetFace(gaze: CGVector(dx: 1, dy: 0.15))),
                Timed(1.6, PetFace(gaze: ahead)),
            ])
        case .doubleBounce:
            return ActScript(duration: 1.3,
                             faces: [Timed(0, PetFace(eyes: .happy, mouth: .grin))],
                             motions: [Timed(0, .hop(height: 0.1, duration: 0.55)), Timed(0.6, .hop(height: 0.07, duration: 0.5))])
        case .wiggle:
            return ActScript(duration: 1.2,
                             faces: [Timed(0, PetFace(eyes: .happy, mouth: .cat))],
                             motions: [Timed(0, .rock(angle: 7, swings: 4, duration: 1.1))])
        case .hum:
            return ActScript(duration: 3.0,
                             faces: [Timed(0, PetFace(eyes: .happy, mouth: .cat))],
                             motions: [Timed(0, .rock(angle: 4, swings: 4, duration: 2.8))],
                             effects: [Timed(0.2, .notes), Timed(1.4, .notes)])
        case .leafTwirl:
            return ActScript(duration: 1.5,
                             faces: [Timed(0, PetFace(gaze: up, mouth: .oh)), Timed(1.2, PetFace(eyes: .happy, mouth: .smile))],
                             motions: [Timed(0, .leafTwirl(duration: 1.2))])
        case .wink:
            return ActScript(duration: 1.1, faces: [Timed(0.05, PetFace(eyes: .wink, mouth: .tongue))])
        case .heartPop:
            return ActScript(duration: 1.6,
                             faces: [Timed(0, PetFace(eyes: .happy, mouth: .cat, blush: 1))],
                             effects: [Timed(0.15, .hearts)])
        case .roll:
            return ActScript(duration: 1.5,
                             faces: [Timed(0, PetFace(eyes: .closed, mouth: .grin)), Timed(1.2, PetFace(eyes: .happy, mouth: .grin))],
                             motions: [Timed(0, .roll(duration: 1.2))],
                             effects: [Timed(1.15, .sparkles)],
                             cooldown: 90)
        case .daydream:
            return ActScript(duration: 3.0,
                             faces: [Timed(0, PetFace(gaze: CGVector(dx: 0.5, dy: 1), mouth: .oh))],
                             motions: [Timed(0, .float(height: 0.05, duration: 2.8))],
                             effects: [Timed(0.5, .question)],
                             cooldown: 30)
        case .stretch:
            return ActScript(duration: 2.0,
                             faces: [Timed(0.1, PetFace(eyes: .closed, mouth: .yawn)), Timed(1.4, PetFace(eyes: .happy, mouth: .smile))],
                             motions: [Timed(0, .stretchTall(amount: 0.16, hold: 0.7))])
        case .dance:
            return ActScript(duration: 2.6,
                             faces: [Timed(0, PetFace(eyes: .happy, mouth: .grin))],
                             motions: [Timed(0, .rock(angle: 10, swings: 6, duration: 2.4)),
                                       Timed(0.6, .hop(height: 0.06, duration: 0.45)),
                                       Timed(1.6, .hop(height: 0.06, duration: 0.45))],
                             effects: [Timed(0.2, .notes), Timed(1.3, .notes)],
                             cooldown: 60)

        // MARK: Idle, stiff
        case .sigh:
            return ActScript(duration: 2.0,
                             faces: [Timed(0, PetFace(openness: 0.4, mouth: .oh)), Timed(1.2, PetFace(openness: 0.55, mouth: .wobble))],
                             effects: [Timed(0.35, .puff)])
        case .stretchFlop:
            return ActScript(duration: 2.4,
                             faces: [Timed(0, PetFace(eyes: .closed, mouth: .yawn)), Timed(1.2, PetFace(openness: 0.6, mouth: .wobble))],
                             motions: [Timed(0, .stretchTall(amount: 0.14, hold: 0.35)), Timed(1.2, .sink(depth: 0.12, hold: 0.4))])
        case .slowRock:
            return ActScript(duration: 2.6,
                             faces: [Timed(0, PetFace(openness: 0.55, mouth: .flat))],
                             motions: [Timed(0, .rock(angle: 5, swings: 3, duration: 2.5))])
        case .yawn:
            return ActScript(duration: 2.2,
                             faces: [Timed(0.15, PetFace(eyes: .closed, mouth: .yawn))],
                             motions: [Timed(0.1, .stretchTall(amount: 0.06, hold: 0.8))])
        case .fidget:
            return ActScript(duration: 1.6,
                             faces: [Timed(0, PetFace(gaze: CGVector(dx: -1, dy: 0))), Timed(0.65, PetFace(gaze: CGVector(dx: 1, dy: 0)))],
                             motions: [Timed(0, .lean(angle: 6, duration: 0.55)), Timed(0.65, .lean(angle: -6, duration: 0.55))])
        case .lookAtYou:
            return ActScript(duration: 2.0,
                             faces: [Timed(0, PetFace(eyes: .wide, gaze: ahead, mouth: .pout))],
                             effects: [Timed(0.3, .question)])

        // MARK: Idle, slumping
        case .melt:
            return ActScript(duration: 2.4,
                             faces: [Timed(0, PetFace(openness: 0.5, mouth: .wobble))],
                             motions: [Timed(0, .sink(depth: 0.14, hold: 1.2))])
        case .leafFlutter:
            return ActScript(duration: 1.8,
                             faces: [Timed(0, PetFace(gaze: down))],
                             motions: [Timed(0, .leafWave(swings: 3, duration: 1.6))])
        case .deepSigh:
            return ActScript(duration: 2.2,
                             faces: [Timed(0, PetFace(eyes: .closed, mouth: .oh))],
                             effects: [Timed(0.5, .puff)])
        case .trySitUp:
            return ActScript(duration: 2.4,
                             faces: [Timed(0, PetFace(eyes: .wide)), Timed(1.1, PetFace(openness: 0.6, mouth: .flat))],
                             motions: [Timed(0, .stretchTall(amount: 0.12, hold: 0.3)), Timed(1.0, .sink(depth: 0.1, hold: 0.4))])

        // MARK: Idle, sleepy
        case .nodOff:
            return ActScript(duration: 2.7,
                             faces: [Timed(0, PetFace(eyes: .closed)),
                                     Timed(2.0, PetFace(eyes: .wide, mouth: .oh)),
                                     Timed(2.5, PetFace(eyes: .closed))],
                             motions: [Timed(0, .nodOff(duration: 2.3))])
        case .sleepBubble:
            return ActScript(duration: 3.0, faces: [Timed(0, PetFace(mouth: .oh))], effects: [Timed(0.2, .sleepBubble)])
        case .snore:
            return ActScript(duration: 2.0, faces: [Timed(0.2, PetFace(mouth: .yawn))], effects: [Timed(0.1, .zzz)])
        case .sleepSmile:
            return ActScript(duration: 2.0, faces: [Timed(0, PetFace(mouth: .smile, blush: 1))])

        // MARK: Idle, under the weather
        case .shiver:
            return ActScript(duration: 1.4,
                             faces: [Timed(0, PetFace(openness: 0.5, mouth: .wobble))],
                             motions: [Timed(0, .shiver(duration: 1.2))])
        case .sneeze:
            return ActScript(duration: 1.8,
                             faces: [Timed(0, PetFace(eyes: .closed, mouth: .oh)), Timed(0.8, PetFace(eyes: .closed, mouth: .yawn))],
                             motions: [Timed(0, .stretchTall(amount: 0.07, hold: 0.3)), Timed(0.8, .jolt)],
                             effects: [Timed(0.85, .puff)])
        case .cough:
            return ActScript(duration: 1.4,
                             faces: [Timed(0, PetFace(eyes: .closed, mouth: .oh))],
                             motions: [Timed(0.1, .jolt), Timed(0.5, .jolt), Timed(0.9, .jolt)])
        case .sniffle:
            return ActScript(duration: 1.6, faces: [Timed(0, PetFace(openness: 0.4, mouth: .pout))], effects: [Timed(0.2, .sweat)])

        // MARK: Tapped
        case .giggle:
            return ActScript(duration: 1.2,
                             faces: [Timed(0, PetFace(eyes: .happy, mouth: .grin, blush: 1))],
                             motions: [Timed(0, .rock(angle: 6, swings: 4, duration: 1.0))])
        case .boing:
            return ActScript(duration: 0.9,
                             faces: [Timed(0, PetFace(eyes: .wide, mouth: .oh)), Timed(0.4, PetFace(eyes: .happy, mouth: .grin))],
                             motions: [Timed(0, .hop(height: 0.18, duration: 0.8))])
        case .surprised:
            return ActScript(duration: 1.3,
                             faces: [Timed(0, PetFace(eyes: .wide, mouth: .oh))],
                             motions: [Timed(0, .jolt)],
                             effects: [Timed(0, .exclaim)])
        case .heart:
            return ActScript(duration: 1.4,
                             faces: [Timed(0, PetFace(eyes: .happy, mouth: .cat, blush: 1))],
                             effects: [Timed(0.1, .hearts)])
        case .spin:
            return ActScript(duration: 1.0,
                             faces: [Timed(0, PetFace(eyes: .happy, mouth: .grin))],
                             motions: [Timed(0, .turn(duration: 0.9))])
        case .shy:
            return ActScript(duration: 1.6, faces: [Timed(0, PetFace(eyes: .happy, gaze: CGVector(dx: 1, dy: -0.5), mouth: .pout, blush: 1))])
        case .dizzy:
            return ActScript(duration: 2.4,
                             faces: [Timed(0, PetFace(eyes: .dizzy, mouth: .wobble))],
                             motions: [Timed(0, .rock(angle: 10, swings: 6, duration: 2.2))],
                             cooldown: 15)

        // MARK: Fed
        case .chomp:
            return ActScript(duration: 1.2,
                             faces: [Timed(0, PetFace(eyes: .happy, mouth: .oh)), Timed(0.3, PetFace(eyes: .happy, mouth: .cat)),
                                     Timed(0.6, PetFace(eyes: .happy, mouth: .oh)), Timed(0.9, PetFace(eyes: .happy, mouth: .cat))],
                             motions: [Timed(0, .chew)])
        case .gulp:
            return ActScript(duration: 1.4,
                             faces: [Timed(0, PetFace(eyes: .wide, mouth: .oh)), Timed(0.5, PetFace(eyes: .happy, mouth: .smile))],
                             motions: [Timed(0, .stretchTall(amount: 0.06, hold: 0.15)), Timed(0.45, .sink(depth: 0.06, hold: 0.1))],
                             effects: [Timed(0.6, .hearts)])
        case .savour:
            return ActScript(duration: 1.8, faces: [Timed(0, PetFace(eyes: .closed, mouth: .cat, blush: 1))], effects: [Timed(0.3, .sparkles)])
        case .yumDance:
            return ActScript(duration: 2.0,
                             faces: [Timed(0, PetFace(eyes: .happy, mouth: .tongue))],
                             motions: [Timed(0, .rock(angle: 8, swings: 4, duration: 1.8)), Timed(0.9, .hop(height: 0.06, duration: 0.45))],
                             effects: [Timed(0.3, .notes)])

        // MARK: Back from a break
        case .welcomeBounce:
            return ActScript(duration: 1.4,
                             faces: [Timed(0, PetFace(eyes: .happy, mouth: .grin))],
                             motions: [Timed(0, .hop(height: 0.14, duration: 0.6)), Timed(0.7, .hop(height: 0.08, duration: 0.5))],
                             effects: [Timed(0.6, .sparkles)])
        case .stretchCheer:
            return ActScript(duration: 2.0,
                             faces: [Timed(0, PetFace(eyes: .closed, mouth: .yawn)), Timed(1.0, PetFace(eyes: .happy, mouth: .grin))],
                             motions: [Timed(0, .stretchTall(amount: 0.18, hold: 0.5))],
                             effects: [Timed(1.1, .notes)])
        case .happySpin:
            return ActScript(duration: 1.3,
                             faces: [Timed(0, PetFace(eyes: .happy, mouth: .grin))],
                             motions: [Timed(0, .turn(duration: 1.0)), Timed(0.1, .hop(height: 0.06, duration: 0.5))])

        // MARK: Celebrations
        case .victoryHop:
            return ActScript(duration: 1.4,
                             faces: [Timed(0, PetFace(eyes: .star, mouth: .grin))],
                             motions: [Timed(0, .hop(height: 0.16, duration: 0.62)), Timed(0.66, .hop(height: 0.1, duration: 0.55))],
                             effects: [Timed(0.2, .sparkles)])
        case .sparkleSpin:
            return ActScript(duration: 1.5,
                             faces: [Timed(0, PetFace(eyes: .star, mouth: .grin))],
                             motions: [Timed(0, .roll(duration: 1.1))],
                             effects: [Timed(1.0, .sparkles)])
        case .cheer:
            return ActScript(duration: 1.8,
                             faces: [Timed(0, PetFace(eyes: .star, mouth: .grin, blush: 1))],
                             motions: [Timed(0, .rock(angle: 6, swings: 4, duration: 1.6))],
                             effects: [Timed(0.1, .notes), Timed(0.8, .hearts)])

        // MARK: Nudging, posture
        case .pointLeaf:
            return ActScript(duration: 1.6,
                             faces: [Timed(0, PetFace(gaze: CGVector(dx: 0.8, dy: 0.6), mouth: .oh))],
                             motions: [Timed(0, .leafWave(swings: 2, duration: 1.4)), Timed(0, .lean(angle: 5, duration: 1.4))])
        case .taDa:
            return ActScript(duration: 1.6,
                             faces: [Timed(0, PetFace(eyes: .happy, mouth: .grin))],
                             motions: [Timed(0, .stretchTall(amount: 0.14, hold: 0.45))],
                             effects: [Timed(0.55, .sparkles)])
        case .oof:
            return ActScript(duration: 1.4,
                             faces: [Timed(0, PetFace(openness: 0.6, mouth: .wobble))],
                             motions: [Timed(0, .sink(depth: 0.1, hold: 0.4))],
                             effects: [Timed(0.2, .sweat)])
        case .sadLook:
            return ActScript(duration: 1.6, faces: [Timed(0, PetFace(gaze: down, mouth: .frown))])
        case .leafFlop:
            return ActScript(duration: 1.4,
                             faces: [Timed(0, PetFace(gaze: up, mouth: .pout))],
                             motions: [Timed(0, .leafWave(swings: 2, duration: 1.2))])

        // MARK: Desktop pet landing
        case .squashLand:
            return ActScript(duration: 0.9,
                             faces: [Timed(0, PetFace(eyes: .closed, mouth: .oh)), Timed(0.45, PetFace(eyes: .happy, mouth: .smile))],
                             motions: [Timed(0, .sink(depth: 0.16, hold: 0.05))])
        case .dizzyLand:
            return ActScript(duration: 1.8,
                             faces: [Timed(0, PetFace(eyes: .dizzy, mouth: .wobble))],
                             motions: [Timed(0, .rock(angle: 8, swings: 4, duration: 1.6))])
        case .happyLand:
            return ActScript(duration: 1.0,
                             faces: [Timed(0, PetFace(eyes: .happy, mouth: .grin))],
                             motions: [Timed(0, .hop(height: 0.08, duration: 0.5))])

        // MARK: AirPods
        case .perkUp:
            return ActScript(duration: 1.3,
                             faces: [Timed(0, PetFace(eyes: .wide, mouth: .oh))],
                             motions: [Timed(0, .stretchTall(amount: 0.08, hold: 0.3))],
                             effects: [Timed(0, .exclaim)])
        case .puzzled:
            return ActScript(duration: 1.6,
                             faces: [Timed(0, PetFace(gaze: CGVector(dx: -0.6, dy: 0.4), mouth: .pout))],
                             effects: [Timed(0.2, .question)])

        // MARK: Morning, growth
        case .goodMorning:
            return ActScript(duration: 2.6,
                             faces: [Timed(0, PetFace(eyes: .closed, mouth: .yawn)), Timed(1.4, PetFace(eyes: .happy, mouth: .grin))],
                             motions: [Timed(0, .stretchTall(amount: 0.16, hold: 0.6)), Timed(1.6, .hop(height: 0.08, duration: 0.5))],
                             effects: [Timed(1.6, .sparkles)])
        case .grow:
            return ActScript(duration: 2.0,
                             faces: [Timed(0, PetFace(eyes: .star, mouth: .grin))],
                             motions: [Timed(0.2, .hop(height: 0.12, duration: 0.6))],
                             effects: [Timed(0, .sparkles), Timed(0.8, .hearts)])
        }
    }
}
