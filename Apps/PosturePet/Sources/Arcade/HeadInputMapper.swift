import Foundation

/// Turns head angles into game input, relative to where the head was when
/// the round started.
///
/// Everything triggers on angle, never on speed, and the angles needed are
/// a fraction of the player's comfortable range, so no game asks for a
/// fast or deep movement.
nonisolated struct HeadInputMapper: Sendable {
    var neutralPitch: Double
    var neutralRoll: Double
    var range: MotionRange

    /// Full input needs this share of the comfortable range.
    static let comfortableShare = 0.6

    private var hopArmed = true

    init(neutralPitch: Double, neutralRoll: Double, range: MotionRange) {
        self.neutralPitch = neutralPitch
        self.neutralRoll = neutralRoll
        self.range = range
    }

    /// - Returns: steer (−1…1), lift (0…1), and whether a hop was triggered.
    mutating func map(pitch: Double, roll: Double) -> (steer: Double, lift: Double, hop: Bool) {
        let dPitch = pitch - neutralPitch
        let dRoll = roll - neutralRoll

        let side = dRoll >= 0 ? range.right : range.left
        let steer = clamp(dRoll / max(6, side * Self.comfortableShare), -1, 1)
        let lift = clamp(dPitch / max(6, range.up * Self.comfortableShare))

        // A nod is the head going down past the line; it re-arms only once
        // the head is back near neutral, so holding the head down doesn't
        // repeat, and nods can't come faster than the player moves.
        let nodLine = max(6, range.down * Self.comfortableShare * 0.8)
        var hop = false
        if hopArmed, dPitch <= -nodLine {
            hop = true
            hopArmed = false
        } else if !hopArmed, dPitch > -nodLine * 0.35 {
            hopArmed = true
        }
        return (steer, lift, hop)
    }
}
