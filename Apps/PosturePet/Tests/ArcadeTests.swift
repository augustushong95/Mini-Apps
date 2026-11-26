import Foundation
import Testing
@testable import PosturePet

struct ArcadeTests {
    private let step = 1.0 / 120

    private func run<G: GameSimulation>(_ game: inout G, seconds: Double, input: (Double) -> GameInput) {
        var t = 0.0
        while t < seconds {
            game.step(dt: step, input: input(t))
            t += step
        }
    }

    // MARK: Simulations

    @Test func gamesAreDeterministicForASeed() {
        var a = LeafGlide(seed: 42, stage: .sprout)
        var b = LeafGlide(seed: 42, stage: .sprout)
        let wiggle: (Double) -> GameInput = { GameInput(steer: sin($0 * 1.3)) }
        run(&a, seconds: 30, input: wiggle)
        run(&b, seconds: 30, input: wiggle)
        #expect(a.score == b.score)
        #expect(a.mochiX == b.mochiX)
        #expect(a.items.count == b.items.count)
    }

    @Test func gamesEndAfterSixtySeconds() {
        var leaf = LeafGlide(seed: 1, stage: .seedling)
        var puddle = PuddleHop(seed: 1, stage: .seedling)
        var star = StarFloat(seed: 1, stage: .seedling)
        run(&leaf, seconds: 61, input: { _ in GameInput() })
        run(&puddle, seconds: 61, input: { _ in GameInput() })
        run(&star, seconds: 61, input: { _ in GameInput() })
        #expect(leaf.isFinished && puddle.isFinished && star.isFinished)
        #expect(leaf.elapsed <= 60 + step, "No steps after the end")
    }

    @Test func steeringMovesMochiAndCountsTilts() {
        var game = LeafGlide(seed: 7, stage: .sprout)
        run(&game, seconds: 2, input: { _ in GameInput(steer: 1) })
        #expect(game.mochiX > 500)
        run(&game, seconds: 2, input: { _ in GameInput(steer: -1) })
        #expect(game.mochiX < 140)
        #expect(game.stats.moves == 2)
        #expect(game.stats.heldSeconds > 3)
    }

    @Test func leafGlideCollectsDew() {
        // Sweeping side to side through 60 s catches at least some dew.
        var game = LeafGlide(seed: 3, stage: .sprout)
        run(&game, seconds: 60, input: { GameInput(steer: sin($0 * 0.9)) })
        #expect(game.score > 0)
    }

    @Test func puddleHopOnlyHopsFromTheGround() {
        var game = PuddleHop(seed: 9, stage: .sprout)
        game.step(dt: step, input: GameInput(hop: true))
        #expect(game.height > 0)
        #expect(game.stats.moves == 1)
        // A second hop mid-air does nothing.
        game.step(dt: step, input: GameInput(hop: true))
        #expect(game.stats.moves == 1)
        run(&game, seconds: 1, input: { _ in GameInput() })
        #expect(game.isOnGround)
    }

    @Test func puddlesNeverComeTooFast() {
        var game = PuddleHop(seed: 11, stage: .sprout)
        var spawnTimes: [Double] = []
        var seen = 0
        var t = 0.0
        while t < 58 {
            game.step(dt: step, input: GameInput())
            t += step
            if game.puddles.count > seen, let last = game.puddles.last, last.x > World.width {
                spawnTimes.append(t)
            }
            seen = game.puddles.count
        }
        let gaps = zip(spawnTimes.dropFirst(), spawnTimes).map { $0 - $1 }
        #expect(!gaps.isEmpty)
        #expect(gaps.allSatisfy { $0 >= 1.6 }, "Nodding is never asked for faster than every ~1.7 s")
    }

    @Test func starFloatRisesWithLift() {
        var game = StarFloat(seed: 5, stage: .sprout)
        run(&game, seconds: 3, input: { _ in GameInput(lift: 1) })
        #expect(game.altitude > StarFloat.maxAltitude * 0.9)
        run(&game, seconds: 3, input: { _ in GameInput(lift: 0) })
        #expect(game.altitude < 10)
        #expect(game.stats.moves == 1)
    }

    // MARK: Head input

    private func mapper() -> HeadInputMapper {
        HeadInputMapper(neutralPitch: 5, neutralRoll: -2, range: MotionRange(up: 20, down: 20, left: 20, right: 20))
    }

    @Test func steeringIsRelativeToNeutralAndClamped() {
        var m = mapper()
        #expect(abs(m.map(pitch: 5, roll: -2).steer) < 0.001)
        // 60% of a 20° range is 12°: 6° is half steer.
        #expect(abs(m.map(pitch: 5, roll: 4).steer - 0.5) < 0.001)
        #expect(m.map(pitch: 5, roll: 40).steer == 1)
        #expect(m.map(pitch: 5, roll: -40).steer == -1)
    }

    @Test func liftOnlyCountsLookingUp() {
        var m = mapper()
        #expect(m.map(pitch: -10, roll: -2).lift == 0)
        #expect(abs(m.map(pitch: 11, roll: -2).lift - 0.5) < 0.001)
    }

    @Test func aNodHopsOnceUntilTheHeadComesBack() {
        var m = mapper()
        // The nod line is 0.8 × 12° = 9.6° below neutral.
        #expect(!m.map(pitch: 0, roll: -2).hop, "5° down is not a nod")
        #expect(m.map(pitch: -6, roll: -2).hop)
        #expect(!m.map(pitch: -8, roll: -2).hop, "Holding the head down doesn't repeat")
        #expect(!m.map(pitch: -2, roll: -2).hop, "Not back near neutral yet")
        #expect(!m.map(pitch: 3, roll: -2).hop)
        #expect(m.map(pitch: -6, roll: -2).hop, "Re-armed after coming back")
    }

    @Test func tinyRangesStillNeedAComfortableMinimum() {
        var m = HeadInputMapper(neutralPitch: 0, neutralRoll: 0, range: MotionRange(up: 2, down: 2, left: 2, right: 2))
        // Thresholds never drop below 6°, so jitter can't steer or hop.
        #expect(abs(m.map(pitch: 0, roll: 3).steer - 0.5) < 0.001)
        #expect(!m.map(pitch: -3, roll: 0).hop)
    }
}
