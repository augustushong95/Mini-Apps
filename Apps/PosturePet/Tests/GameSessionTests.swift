import Foundation
import Testing
@testable import PosturePet

/// A Neck Arcade visit: countdown, play, pause, results, with the keyboard
/// and with simulated AirPods.
@Suite(.serialized)
struct GameSessionTests {
    /// Advances the session `seconds` at 60 fps, optionally streaming a head
    /// angle (pitch, roll) at each frame.
    private func run(
        _ session: GameSession, _ rig: TestRig, seconds: Double, head: ((Double) -> (Double, Double))? = nil
    ) {
        var t = 0.0
        while t < seconds {
            if let head {
                let (pitch, roll) = head(t)
                rig.hold(pitch: pitch, roll: roll, seconds: 1.0 / 60)
            }
            session.frame(dt: 1.0 / 60)
            t += 1.0 / 60
        }
    }

    /// Runs while `phase` is unchanged (at most `limit` seconds), streaming a head angle.
    private func runThrough(
        _ phase: GameSession.Phase, _ session: GameSession, _ rig: TestRig, limit: Double = 5, head: (Double, Double)
    ) {
        var t = 0.0
        while session.phase == phase, t < limit {
            rig.hold(pitch: head.0, roll: head.1, seconds: 1.0 / 60)
            session.frame(dt: 1.0 / 60)
            t += 1.0 / 60
        }
    }

    private func leaf(_ session: GameSession) -> LeafGlide? {
        session.sim as? LeafGlide
    }

    // MARK: Keyboard

    @Test func keyboardRoundFromCountdownToResults() {
        let rig = TestRig()
        defer { rig.cleanUp() }
        let session = GameSession(game: .leafGlide, engine: rig.engine)
        defer { session.end() }
        var finished: [GameResult] = []
        session.onRoundFinished = { finished.append($0) }

        #expect(session.phase == .countdown(3))
        #expect(!session.usesHead, "No AirPods: keyboard")
        run(session, rig, seconds: 2.6)
        #expect(session.phase == .playing)

        _ = session.key(.right, down: true)
        run(session, rig, seconds: 1.5)
        #expect((leaf(session)?.mochiX ?? 0) > 450, "→ steers right")
        _ = session.key(.right, down: false)

        session.endRound()
        guard case .finished(let result) = session.phase else {
            Issue.record("Expected results, got \(session.phase)")
            return
        }
        #expect(finished == [result], "Reported exactly once")
        #expect(!result.completed, "Ended early: not a break")
    }

    @Test func aFullRoundNeedsASitToCountAsABreak() {
        let rig = TestRig()
        defer { rig.cleanUp() }
        let session = GameSession(game: .puddleHop, engine: rig.engine)
        defer { session.end() }
        run(session, rig, seconds: 2.6 + 61)
        guard case .finished(let result) = session.phase else {
            Issue.record("Expected results, got \(session.phase)")
            return
        }
        #expect(result.completed)
        #expect(!result.countsAsBreak, "Played right after starting: no break")

        rig.engine.debugAddSitting(minutes: 15)
        session.playAgain()
        run(session, rig, seconds: 2.6 + 61)
        guard case .finished(let second) = session.phase else {
            Issue.record("Expected results, got \(session.phase)")
            return
        }
        #expect(second.countsAsBreak, "After 15 minutes of sitting: +1 break")
    }

    @Test func losingFocusDuringTheCountdownPauses() {
        let rig = TestRig()
        defer { rig.cleanUp() }
        let session = GameSession(game: .leafGlide, engine: rig.engine)
        defer { session.end() }
        run(session, rig, seconds: 1)
        session.pause(.lostFocus)
        #expect(session.phase == .paused(.lostFocus))
        run(session, rig, seconds: 5)
        #expect(session.phase == .paused(.lostFocus), "Doesn't play by itself")
        #expect(session.sim.elapsed == 0)

        session.resume()
        #expect(session.phase == .countdown(2))
    }

    @Test func heldKeysAreForgottenWhenPaused() {
        let rig = TestRig()
        defer { rig.cleanUp() }
        let session = GameSession(game: .leafGlide, engine: rig.engine)
        defer { session.end() }
        run(session, rig, seconds: 2.6)
        _ = session.key(.right, down: true)
        run(session, rig, seconds: 0.5)
        session.pause(.lostFocus)
        // The key-up happened in another app and never arrives.
        session.resume()
        run(session, rig, seconds: 1.8 + 3)
        #expect(abs((leaf(session)?.mochiX ?? 0) - World.width / 2) < 20, "Back in the middle, not stuck right")
    }

    // MARK: Simulated AirPods

    @Test func simulatedHeadTiltsSteerLeafGlide() {
        let rig = TestRig { $0.calibration.range = .default }
        defer { rig.cleanUp() }
        rig.putOnAirPods()
        rig.hold(pitch: 0, seconds: 1)
        let session = GameSession(game: .leafGlide, engine: rig.engine)
        defer { session.end() }

        run(session, rig, seconds: 2.6) { _ in (0, 0) }
        #expect(session.phase == .playing)
        #expect(session.usesHead)

        // 13° is 60% of a 22° range: full steer to the right.
        run(session, rig, seconds: 2) { _ in (0, 13) }
        #expect((leaf(session)?.mochiX ?? 0) > 500)
        run(session, rig, seconds: 2) { _ in (0, -13) }
        #expect((leaf(session)?.mochiX ?? 999) < 140)
        #expect((leaf(session)?.stats.moves ?? 0) >= 2)
    }

    @Test func simulatedNodHopsInPuddleHop() {
        let rig = TestRig { $0.calibration.range = .default }
        defer { rig.cleanUp() }
        rig.putOnAirPods()
        rig.hold(pitch: 0, seconds: 1)
        let session = GameSession(game: .puddleHop, engine: rig.engine)
        defer { session.end() }
        run(session, rig, seconds: 2.6) { _ in (0, 0) }

        run(session, rig, seconds: 0.2) { _ in (-16, 0) }
        #expect(((session.sim as? PuddleHop)?.height ?? 0) > 0, "A nod hops")
        #expect(session.sim.stats.moves == 1)
    }

    @Test func rangeCheckMeasuresTheSimulatedHead() {
        let rig = TestRig()
        defer { rig.cleanUp() }
        rig.putOnAirPods()
        rig.hold(pitch: 0, seconds: 1)
        let session = GameSession(game: .leafGlide, engine: rig.engine)
        defer { session.end() }
        #expect(session.phase == .rangeCheck(.left))

        // The check starts from wherever the head rests, then each direction.
        run(session, rig, seconds: 0.2) { _ in (0, 0) }
        runThrough(.rangeCheck(.left), session, rig, head: (0, -20))
        runThrough(.rangeCheck(.right), session, rig, head: (0, 25))
        runThrough(.rangeCheck(.up), session, rig, head: (18, 0))
        runThrough(.rangeCheck(.down), session, rig, head: (-50, 0))
        #expect(session.phase == .countdown(3))

        let range = try? #require(rig.engine.store.state.calibration.range)
        #expect(abs((range?.left ?? 0) - 20) < 2)
        #expect(abs((range?.right ?? 0) - 25) < 2)
        #expect(abs((range?.up ?? 0) - 18) < 2)
        #expect(range?.down == 35, "Capped: games never ask for more than 35°")
    }

    @Test func rangeCheckGivesUpWithoutHeadData() {
        let rig = TestRig()
        defer { rig.cleanUp() }
        rig.putOnAirPods()
        let session = GameSession(game: .leafGlide, engine: rig.engine)
        defer { session.end() }
        #expect(session.phase == .rangeCheck(.left))
        run(session, rig, seconds: 3.5)
        #expect(session.phase == .countdown(3))
        #expect(!session.usesHead)
        #expect(rig.engine.store.state.calibration.range == nil, "Nothing saved from no movement")
    }

    @Test func airPodsDisconnectingPausesAndSwitchesToKeys() {
        let rig = TestRig { $0.calibration.range = .default }
        defer { rig.cleanUp() }
        rig.putOnAirPods()
        rig.hold(pitch: 0, seconds: 1)
        let session = GameSession(game: .leafGlide, engine: rig.engine)
        defer { session.end() }
        run(session, rig, seconds: 2.6) { _ in (0, 0) }
        #expect(session.phase == .playing)

        rig.motion.debugStopSimulation()
        #expect(session.phase == .paused(.headphonesDisconnected))
        #expect(!session.usesHead)
    }
}
