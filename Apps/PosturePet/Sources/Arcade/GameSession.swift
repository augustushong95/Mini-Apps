import AppKit
import Observation

/// One visit to the arcade: the range check (first time only), countdown,
/// play, pause and results, for one game. Rounds can be replayed.
@Observable
final class GameSession {
    enum Phase: Equatable {
        case rangeCheck(RangeStep)
        case countdown(Int)
        case playing
        case paused(PauseReason)
        case finished(GameResult)
    }

    enum PauseReason: Equatable {
        case user, lostFocus, headphonesDisconnected

        var message: String {
            switch self {
            case .user: "Paused"
            case .lostFocus: "Paused while you were away"
            case .headphonesDisconnected: "AirPods disconnected. Keep playing with the keyboard."
            }
        }
    }

    enum RangeStep: Int, CaseIterable, Equatable {
        case left, right, up, down

        var instruction: String {
            switch self {
            case .left: "Gently tilt toward your left shoulder"
            case .right: "Now toward your right shoulder"
            case .up: "Look up, as far as is comfortable"
            case .down: "And down toward your chest"
            }
        }
    }

    let game: ArcadeGame
    private(set) var phase: Phase
    private(set) var sim: any GameSimulation
    /// Seconds since the session began, for ambient animation.
    private(set) var time: Double = 0
    private(set) var usesHead: Bool
    /// 0…1 through the current range-check step.
    private(set) var stepProgress: Double = 0
    private(set) var isNewBest = false
    var best: Int { engine.bestScores[game.rawValue] ?? 0 }

    @ObservationIgnored var onRoundFinished: ((GameResult) -> Void)?
    @ObservationIgnored private let engine: PetEngine
    @ObservationIgnored private var mapper: HeadInputMapper?
    @ObservationIgnored private var headInput = (steer: 0.0, lift: 0.0, hop: false)
    @ObservationIgnored private var keys: Set<Key> = []
    @ObservationIgnored private var keyboardSteer: Double = 0
    @ObservationIgnored private var keyboardLift: Double = 0
    @ObservationIgnored private var pendingHop = false
    @ObservationIgnored private var accumulator: Double = 0
    @ObservationIgnored private var phaseClock: Double = 0
    @ObservationIgnored private var subscriptions: [MotionSubscription] = []
    @ObservationIgnored private var rangeNeutral: (pitch: Double, roll: Double)?
    @ObservationIgnored private var measuredRange = MotionRange(up: 0, down: 0, left: 0, right: 0)
    @ObservationIgnored private var latestAngles: (pitch: Double, roll: Double)?
    @ObservationIgnored private let sounds: GameSounds
    /// Where `resume()` returns to.
    @ObservationIgnored private var resumePhase: Phase = .countdown(2)
    /// Seconds the range check has waited for the first head sample.
    @ObservationIgnored private var waitingForHead: Double = 0

    static let step: TimeInterval = 1.0 / 120
    static let countdownStep: TimeInterval = 0.8
    static let rangeStepDuration: TimeInterval = 3
    /// Rounds played at least this long count as a break.
    static let breakThreshold: TimeInterval = 45

    enum Key: Hashable {
        case left, right, up, space
    }

    init(game: ArcadeGame, engine: PetEngine) {
        self.game = game
        self.engine = engine
        sounds = GameSounds(enabled: engine.settings.soundsEnabled)
        sim = Self.makeSimulation(game, stage: engine.pet.stage)
        // Provisional: the stream may still be starting. Whether the round
        // really uses the head is settled when play begins.
        let motion = engine.motion
        let headExpected = motion.isAuthorized && motion.connection != .disconnected
        usesHead = headExpected
        if headExpected, engine.store.state.calibration.range == nil {
            phase = .rangeCheck(.left)
        } else {
            phase = .countdown(3)
        }

        // Never the first thing to ask for motion access: games use the head
        // only if the user already allowed it.
        if engine.motion.isAuthorized {
            engine.motion.setDemand(.game, active: true)
        }
        subscriptions.append(engine.motion.subscribe { [weak self] sample in
            self?.handle(sample)
        })
        subscriptions.append(engine.motion.observeEvents { [weak self] event in
            guard let self else { return }
            switch event {
            case .disconnected, .stalled:
                // The last tilt must not keep steering.
                headInput = (0, 0, false)
                if event == .disconnected, usesHead {
                    pause(.headphonesDisconnected)
                }
            default:
                break
            }
        })
    }

    func end() {
        engine.motion.setDemand(.game, active: false)
        subscriptions.forEach { $0.cancel() }
        subscriptions = []
    }

    private static func makeSimulation(_ game: ArcadeGame, stage: GrowthStage) -> any GameSimulation {
        let seed = UInt64.random(in: 1...UInt64.max)
        return switch game {
        case .leafGlide: LeafGlide(seed: seed, stage: stage)
        case .puddleHop: PuddleHop(seed: seed, stage: stage)
        case .starFloat: StarFloat(seed: seed, stage: stage)
        }
    }

    // MARK: Frame loop

    /// Advances by `dt` real seconds (from the display link).
    func frame(dt rawDT: Double) {
        // A long frame (the Mac slept, the window was hidden) never
        // fast-forwards the game.
        let dt = min(rawDT, 0.1)
        time += dt
        phaseClock += dt

        switch phase {
        case .rangeCheck(let step):
            guard latestAngles != nil else {
                // No head samples yet: hold the clock, and give up after a
                // few seconds rather than saving a range from no movement.
                phaseClock = 0
                waitingForHead += dt
                if waitingForHead > 3 {
                    usesHead = false
                    phase = .countdown(3)
                }
                return
            }
            advanceRangeCheck(step)
        case .countdown(let count):
            if phaseClock >= Self.countdownStep {
                phaseClock = 0
                if count > 1 {
                    phase = .countdown(count - 1)
                    sounds.play(.tick)
                } else {
                    beginPlaying()
                }
            }
        case .playing:
            updateKeyboard(dt: dt)
            accumulator += dt
            var hop = pendingHop || headInput.hop
            pendingHop = false
            headInput.hop = false
            while accumulator >= Self.step {
                let input = GameInput(
                    steer: keyboardSteer != 0 ? keyboardSteer : (usesHead ? headInput.steer : 0),
                    hop: hop,
                    lift: max(keyboardLift, usesHead ? headInput.lift : 0)
                )
                sim.step(dt: Self.step, input: input)
                hop = false
                accumulator -= Self.step
            }
            for event in sim.events {
                switch event {
                case .collect: sounds.play(.collect)
                case .hit: sounds.play(.hit)
                case .hop: sounds.play(.hop)
                }
            }
            sim.events.removeAll()
            if sim.isFinished {
                finish()
            }
        case .paused, .finished:
            break
        }
    }

    private func beginPlaying() {
        phaseClock = 0
        accumulator = 0
        clearInput()
        // Decided now, not when the window opened: a stream started for this
        // game is live by the end of the countdown.
        usesHead = engine.motion.isLive
        if usesHead, let angles = engine.steadyAngles(over: 0.8) ?? latestAngles {
            mapper = HeadInputMapper(
                neutralPitch: angles.pitch,
                neutralRoll: angles.roll,
                range: engine.store.state.calibration.range ?? .default
            )
        } else {
            usesHead = false
            mapper = nil
        }
        phase = .playing
        sounds.play(.go)
    }

    /// Forgets held keys and the last head input, so nothing steers by itself
    /// after a pause.
    private func clearInput() {
        keys.removeAll()
        keyboardSteer = 0
        keyboardLift = 0
        pendingHop = false
        headInput = (0, 0, false)
    }

    private func finish() {
        let completed = sim.elapsed >= Self.breakThreshold
        let result = GameResult(
            score: sim.score,
            treats: sim.score,
            stats: sim.stats,
            completed: completed,
            // Same rule as BreakScheduler: a break needs a sit before it.
            countsAsBreak: completed && engine.breaks.sittingSeconds >= BreakScheduler.minimumSitToCount
        )
        isNewBest = result.score > best && result.score > 0
        phase = .finished(result)
        sounds.play(.finish)
        onRoundFinished?(result)
    }

    // MARK: Controls

    /// Pauses play, a countdown or the range check (which restarts on resume).
    func pause(_ reason: PauseReason = .user) {
        switch phase {
        case .playing, .countdown:
            resumePhase = .countdown(2)
        case .rangeCheck:
            resumePhase = .rangeCheck(.left)
        case .paused, .finished:
            return
        }
        phase = .paused(reason)
        clearInput()
        if reason == .headphonesDisconnected {
            usesHead = false
        }
    }

    /// Resumes with a short countdown, re-reading the neutral head position.
    func resume() {
        guard case .paused = phase else { return }
        phaseClock = 0
        if case .rangeCheck = resumePhase, engine.motion.isLive {
            rangeNeutral = nil
            measuredRange = MotionRange(up: 0, down: 0, left: 0, right: 0)
            stepProgress = 0
            phase = .rangeCheck(.left)
        } else {
            phase = .countdown(2)
        }
    }

    /// Whether play had started before the current pause or countdown.
    var hasStarted: Bool { sim.elapsed > 0 }

    /// Ends the round early; it still shows results and pays out.
    func endRound() {
        switch phase {
        case .playing, .paused:
            finish()
        default:
            break
        }
    }

    func playAgain() {
        sim = Self.makeSimulation(game, stage: engine.pet.stage)
        isNewBest = false
        usesHead = engine.motion.isLive
        clearInput()
        phaseClock = 0
        phase = .countdown(3)
    }

    func skipRangeCheck() {
        engine.store.update { $0.calibration.range = .default }
        phaseClock = 0
        phase = .countdown(3)
    }

    // MARK: Keyboard

    /// Returns true when the key was used.
    func key(_ key: Key, down: Bool) -> Bool {
        if down {
            keys.insert(key)
            if key == .space {
                switch phase {
                case .playing: pendingHop = true
                case .paused: resume()
                default: break
                }
            }
        } else {
            keys.remove(key)
        }
        return true
    }

    private func updateKeyboard(dt: Double) {
        // Ease keyboard input in and out so it feels like tilting.
        let targetSteer: Double = (keys.contains(.right) ? 1 : 0) - (keys.contains(.left) ? 1 : 0)
        keyboardSteer += (targetSteer - keyboardSteer) * min(1, dt * 10)
        if abs(keyboardSteer) < 0.01, targetSteer == 0 { keyboardSteer = 0 }
        let targetLift: Double = keys.contains(.up) ? 1 : 0
        keyboardLift += (targetLift - keyboardLift) * min(1, dt * 6)
    }

    // MARK: Head

    private func handle(_ sample: HeadSample) {
        latestAngles = (sample.gravityPitch, sample.gravityRoll)
        if case .rangeCheck(let step) = phase {
            recordRange(step, pitch: sample.gravityPitch, roll: sample.gravityRoll)
        }
        guard phase == .playing, usesHead, var mapper else { return }
        let mapped = mapper.map(pitch: sample.gravityPitch, roll: sample.gravityRoll)
        self.mapper = mapper
        headInput.steer = mapped.steer
        headInput.lift = mapped.lift
        if mapped.hop { headInput.hop = true }
    }

    // MARK: Range check

    private func advanceRangeCheck(_ step: RangeStep) {
        if rangeNeutral == nil {
            rangeNeutral = latestAngles
        }
        stepProgress = min(1, phaseClock / Self.rangeStepDuration)
        guard phaseClock >= Self.rangeStepDuration else { return }
        phaseClock = 0
        if let next = RangeStep(rawValue: step.rawValue + 1) {
            phase = .rangeCheck(next)
            sounds.play(.tick)
        } else {
            // Keep each direction within sensible bounds: too small would make
            // games twitchy, too large would ask for strain.
            let range = MotionRange(
                up: clamp(measuredRange.up, 12, 35),
                down: clamp(measuredRange.down, 12, 35),
                left: clamp(measuredRange.left, 12, 35),
                right: clamp(measuredRange.right, 12, 35)
            )
            engine.store.update { $0.calibration.range = range }
            phase = .countdown(3)
        }
    }

    private func recordRange(_ step: RangeStep, pitch: Double, roll: Double) {
        guard let neutral = rangeNeutral else { return }
        let dPitch = pitch - neutral.pitch
        let dRoll = roll - neutral.roll
        switch step {
        case .left: measuredRange.left = max(measuredRange.left, -dRoll)
        case .right: measuredRange.right = max(measuredRange.right, dRoll)
        case .up: measuredRange.up = max(measuredRange.up, dPitch)
        case .down: measuredRange.down = max(measuredRange.down, -dPitch)
        }
    }

    /// The live pose for Mochi while checking range or counting down.
    var mirrorPose: PetPose {
        var pose = PetMood.happy.pose(stage: engine.pet.stage, posture: nil)
        if let latest = latestAngles, let neutral = rangeNeutral ?? latestAngles {
            pose.tilt = clamp(latest.roll - neutral.roll, -18, 18)
            pose.gaze = CGVector(dx: 0, dy: clamp((latest.pitch - neutral.pitch) / 20, -1, 1))
        }
        return pose
    }
}

/// Soft system sounds for game events, preloaded so they play instantly.
final class GameSounds {
    enum Effect {
        case collect, hit, hop, tick, go, finish
    }

    private let enabled: Bool
    private var cache: [Effect: NSSound] = [:]

    init(enabled: Bool) {
        self.enabled = enabled
        guard enabled else { return }
        let names: [Effect: String] = [.collect: "Pop", .hit: "Bottle", .hop: "Tink", .tick: "Tink", .go: "Purr", .finish: "Glass"]
        for (effect, name) in names {
            if let sound = NSSound(named: NSSound.Name(name))?.copy() as? NSSound {
                sound.volume = effect == .collect ? 0.18 : 0.25
                cache[effect] = sound
            }
        }
    }

    func play(_ effect: Effect) {
        guard enabled, let sound = cache[effect] else { return }
        sound.stop()
        sound.play()
    }
}
