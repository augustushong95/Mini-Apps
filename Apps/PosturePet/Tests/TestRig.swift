import Foundation
@testable import PosturePet

/// Values the engine reads from the system, set by tests instead.
final class FakeSystem {
    var quiet: QuietReason?
    var idleSeconds: TimeInterval = 0
}

/// A complete, isolated Posture Pet engine for tests: its own data folder,
/// its own settings, simulated AirPods, and fake call/idle signals. Nothing
/// here touches the real app's data, and real motion is never started.
final class TestRig {
    let folder: URL
    let suiteName: String
    let preferences: Preferences
    let motion: MotionHub
    let system = FakeSystem()
    private(set) var engine: PetEngine!
    private(set) var nudges: [NudgeKind] = []
    /// The simulated AirPods' clock (Core Motion timestamps).
    private(set) var sampleTime: TimeInterval = 10_000

    init(onboarded: Bool = true, configure: (inout SavedState) -> Void = { _ in }) {
        folder = FileManager.default.temporaryDirectory.appending(path: "PosturePetTests-\(UUID().uuidString)")
        suiteName = "PosturePetTests-\(UUID().uuidString)"
        preferences = Preferences(defaults: UserDefaults(suiteName: suiteName)!)
        // Never "late" during a test unless the test says so (late only 03:59–04:00).
        preferences.windDownMinutes = 3 * 60 + 59
        motion = MotionHub(streamingEnabled: false)

        let store = StateStore(folder: folder)
        store.update { state in
            if onboarded {
                state.onboarding.completed = true
                state.onboarding.safetyNoteShown = true
                state.pet.adoptedOn = PetDay(containing: .now)
                // Learning day over, so posture nudges are allowed.
                state.onboarding.nudgesFrom = PetDay(containing: .now)
            }
            configure(&state)
        }
        store.flush()
        makeEngine(store: store)
    }

    /// Builds (or rebuilds, as on relaunch) the engine over the same data.
    func makeEngine(store: StateStore? = nil) {
        let system = system
        engine = PetEngine(
            settings: preferences,
            motion: motion,
            store: store ?? StateStore(folder: folder),
            quietSignals: { system.quiet },
            idleSeconds: { system.idleSeconds }
        )
        engine.onNudge = { [weak self] kind in self?.nudges.append(kind) }
    }

    func cleanUp() {
        motion.debugStopSimulation()
        try? FileManager.default.removeItem(at: folder)
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }

    // MARK: Simulated AirPods

    func putOnAirPods() {
        motion.debugStartSimulation()
    }

    /// Streams 25 samples a second holding a head angle, as AirPods would.
    /// `speed` > 1 compresses time: 120 s of head time in 120/speed samples' worth.
    func hold(pitch: Double, roll: Double = 0, seconds: Double, speed: Double = 1) {
        let step = 0.04
        var elapsed = 0.0
        while elapsed < seconds {
            sampleTime += step * speed
            motion.debugInject(.synthetic(pitch: pitch, roll: roll, timestamp: sampleTime))
            elapsed += step
        }
    }

    /// Sits well for a moment and saves it as the baseline, like onboarding.
    @discardableResult
    func calibrate() -> Bool {
        putOnAirPods()
        hold(pitch: 0, seconds: 2.5)
        return engine.captureBaseline()
    }
}
