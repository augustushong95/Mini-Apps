import Foundation
import Testing
@testable import PosturePet

/// The whole engine, end to end, with simulated AirPods:
/// motion → posture → mood → Mochi's pose → stats → nudges.
@Suite(.serialized)
struct EngineTests {
    // MARK: Posture with simulated AirPods

    @Test func calibratesFromSimulatedAirPods() {
        let rig = TestRig()
        defer { rig.cleanUp() }
        #expect(!rig.engine.hasAnyBaseline)
        #expect(rig.calibrate())
        #expect(rig.engine.hasAnyBaseline)
        rig.hold(pitch: 0, seconds: 1)
        #expect(rig.engine.posture.state == .upright)
    }

    @Test func calibrationRefusesAMovingHead() {
        let rig = TestRig()
        defer { rig.cleanUp() }
        rig.putOnAirPods()
        for index in 0..<70 {
            rig.hold(pitch: index.isMultiple(of: 2) ? 0 : -15, seconds: 0.04)
        }
        #expect(!rig.engine.captureBaseline())
    }

    @Test func mochiMirrorsSittingTallSlumpingAndTilting() {
        let rig = TestRig()
        defer { rig.cleanUp() }
        rig.calibrate()

        rig.hold(pitch: 0, seconds: 3)
        #expect(rig.engine.pose.uprightness > 0.9)
        #expect(rig.engine.pose.leafDroop < 0.1)

        rig.hold(pitch: -26, seconds: 4)
        #expect(rig.engine.pose.uprightness < 0.25, "Head down: Mochi squashes")
        #expect(rig.engine.pose.leafDroop > 0.7, "and its leaf droops")

        rig.hold(pitch: 0, roll: 14, seconds: 4)
        #expect(rig.engine.pose.tilt > 8, "Tilt right: Mochi leans right")
        rig.hold(pitch: 0, roll: -14, seconds: 4)
        #expect(rig.engine.pose.tilt < -8, "Tilt left: Mochi leans left")
    }

    @Test func aHeldSlumpBecomesTheSlumpingMoodAndIsCounted() {
        let rig = TestRig()
        defer { rig.cleanUp() }
        rig.calibrate()
        rig.hold(pitch: -26, seconds: 130)
        #expect(rig.engine.posture.state == .slouching)
        #expect(rig.engine.mood == .slumped)

        rig.engine.tick()
        #expect(rig.engine.today.slouchSeconds > 5)
        #expect(rig.engine.today.measuredSeconds > 120)
    }

    @Test func sittingBackUpRecovers() {
        let rig = TestRig()
        defer { rig.cleanUp() }
        rig.calibrate()
        rig.hold(pitch: -26, seconds: 130)
        rig.hold(pitch: 0, seconds: 8)
        #expect(rig.engine.posture.state == .upright)
        #expect(rig.engine.mood == .happy)
    }

    @Test func takingAirPodsOutForgetsPosture() {
        let rig = TestRig()
        defer { rig.cleanUp() }
        rig.calibrate()
        rig.hold(pitch: -26, seconds: 130)
        rig.motion.debugStopSimulation()
        #expect(rig.engine.posture.state == .unknown)
        #expect(rig.engine.mood != .slumped, "No false slump without data")
    }

    @Test func gamesSuspendPostureTracking() {
        let rig = TestRig()
        defer { rig.cleanUp() }
        rig.calibrate()
        rig.engine.tick()
        let measured = rig.engine.today.measuredSeconds
        rig.engine.isPostureSuspended = true
        rig.hold(pitch: -26, seconds: 130)
        rig.engine.tick()
        #expect(rig.engine.posture.state == .unknown)
        #expect(rig.engine.today.measuredSeconds == measured, "Game nods aren't posture")
    }

    // MARK: Breaks and moods

    @Test func breakLifecycleTiredThenSickThenHappy() {
        let rig = TestRig()
        defer { rig.cleanUp() }
        #expect(rig.engine.mood == .happy)

        rig.engine.debugAddSitting(minutes: 51)
        #expect(rig.engine.breaks.phase == .due)
        #expect(rig.engine.mood == .tired)
        #expect(rig.nudges == [.breakInvite])

        rig.engine.debugAddSitting(minutes: 50)
        #expect(rig.engine.mood == .sick, "A whole extra interval without a break")

        rig.engine.recordBreak(.manual)
        #expect(rig.engine.today.breaks == 1)
        #expect(rig.engine.mood == .happy, "One break fixes it")
    }

    @Test func snoozingHoldsTheInvite() {
        let rig = TestRig()
        defer { rig.cleanUp() }
        rig.engine.debugAddSitting(minutes: 51)
        rig.engine.snoozeBreak()
        #expect(rig.engine.breaks.phase == .snoozed)
        rig.engine.evaluateNudges()
        #expect(rig.nudges == [.breakInvite], "No second invite while snoozed")
    }

    // MARK: Nudges

    @Test func callsKeepMochiQuiet() {
        let rig = TestRig()
        defer { rig.cleanUp() }
        rig.system.quiet = .call(app: "us.zoom.xos")
        rig.engine.tick()
        rig.engine.debugAddSitting(minutes: 51)
        #expect(rig.nudges.isEmpty)
        #expect(rig.engine.quiet.reason == .call(app: "us.zoom.xos"))

        rig.system.quiet = nil
        rig.engine.tick()
        #expect(rig.nudges == [.breakInvite], "Shown once the call ends")
    }

    @Test func manualQuietUntilLater() {
        let rig = TestRig()
        defer { rig.cleanUp() }
        rig.engine.setQuiet(until: .now.addingTimeInterval(3600))
        rig.engine.debugAddSitting(minutes: 51)
        #expect(rig.nudges.isEmpty)
        rig.engine.setQuiet(until: nil)
        rig.engine.evaluateNudges()
        #expect(rig.nudges == [.breakInvite])
    }

    @Test func noBubblesWhileThePanelOrAGameIsOpen() {
        let rig = TestRig()
        defer { rig.cleanUp() }
        rig.engine.isBusy = true
        rig.engine.debugAddSitting(minutes: 51)
        #expect(rig.nudges.isEmpty)
        rig.engine.isBusy = false
        #expect(rig.nudges == [.breakInvite], "Shown when the panel closes")
    }

    @Test func noBubblesWhenAwayFromTheMac() {
        let rig = TestRig()
        defer { rig.cleanUp() }
        rig.system.idleSeconds = 600
        rig.engine.tick()
        rig.engine.debugAddSitting(minutes: 51)
        #expect(rig.nudges.isEmpty)
    }

    @Test func postureNudgeAfterAHeldSlump() {
        let rig = TestRig()
        defer { rig.cleanUp() }
        rig.calibrate()
        rig.hold(pitch: -26, seconds: 130)
        rig.engine.evaluateNudges()
        #expect(rig.nudges == [.posture])
    }

    @Test func noPostureNudgesOnTheLearningDay() {
        let rig = TestRig { state in
            state.onboarding.nudgesFrom = PetDay(containing: .now).adding(days: 1)
        }
        defer { rig.cleanUp() }
        rig.calibrate()
        rig.hold(pitch: -26, seconds: 130)
        rig.engine.evaluateNudges()
        #expect(rig.nudges.isEmpty)
        #expect(rig.engine.mood == .slumped, "Mochi still mirrors the slump")
    }

    @Test func lateNightMakesMochiSleepyAndSaysGoodnight() throws {
        let rig = TestRig()
        defer { rig.cleanUp() }
        let parts = Calendar.current.dateComponents([.hour, .minute], from: rig.engine.clock.now)
        let minutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        rig.preferences.windDownMinutes = (minutes + 24 * 60 - 1) % (24 * 60)
        try #require(PetBrain.isLate(rig.engine.clock.now, windDownMinutes: rig.preferences.windDownMinutes))

        rig.engine.tick()
        #expect(rig.engine.isLate)
        #expect(rig.engine.mood == .sleepy)
        #expect(rig.engine.pose.eyes == .closed)
        #expect(rig.engine.pose.accessories.contains(.zzz))
        #expect(rig.nudges == [.windDown])
    }

    // MARK: Treats, names, scores

    @Test func feedingUsesTreats() {
        let rig = TestRig()
        defer { rig.cleanUp() }
        #expect(!rig.engine.feed(), "Nothing to feed yet")
        rig.engine.addTreats(2)
        #expect(rig.engine.pet.treats == 2)
        #expect(rig.engine.today.treatsEarned == 2)
        #expect(rig.engine.feed())
        #expect(rig.engine.pet.treats == 1)
        #expect(rig.engine.today.treatsFed == 1)
        #expect(rig.engine.reaction?.kind == .chew)
    }

    @Test func namesAreTidied() {
        let rig = TestRig()
        defer { rig.cleanUp() }
        rig.engine.rename(to: "  Bean  ")
        #expect(rig.engine.pet.name == "Bean")
        rig.engine.rename(to: "   ")
        #expect(rig.engine.pet.name == "Mochi")
        rig.engine.rename(to: String(repeating: "x", count: 40))
        #expect(rig.engine.pet.name.count == 20)
    }

    @Test func bestScoresOnlyGoUp() {
        let rig = TestRig()
        defer { rig.cleanUp() }
        rig.engine.recordScore(12, for: "leafGlide")
        rig.engine.recordScore(7, for: "leafGlide")
        #expect(rig.engine.bestScores["leafGlide"] == 12)
    }

    // MARK: Onboarding, reset, relaunch, days

    @Test func onboardingStartsALearningDay() {
        let rig = TestRig(onboarded: false)
        defer { rig.cleanUp() }
        #expect(!rig.engine.isOnboarded)
        rig.engine.debugAddSitting(minutes: 51)
        #expect(rig.nudges.isEmpty, "No bubbles before onboarding")

        rig.engine.completeOnboarding(name: "Bean")
        let today = PetDay(containing: .now)
        #expect(rig.engine.isOnboarded)
        #expect(rig.engine.pet.name == "Bean")
        #expect(rig.engine.pet.adoptedOn == today)
        #expect(rig.engine.store.state.onboarding.nudgesFrom == today.adding(days: 1))
    }

    @Test func resetClearsEverythingButOnboarding() {
        let rig = TestRig()
        defer { rig.cleanUp() }
        rig.calibrate()
        rig.engine.addTreats(5)
        rig.engine.recordScore(9, for: "leafGlide")
        rig.engine.resetAllData()
        #expect(rig.engine.pet.treats == 0)
        #expect(rig.engine.bestScores.isEmpty)
        #expect(!rig.engine.hasAnyBaseline)
        #expect(rig.engine.isOnboarded)
    }

    @Test func everythingSurvivesARelaunch() {
        let rig = TestRig()
        defer { rig.cleanUp() }
        rig.engine.addTreats(4)
        rig.engine.debugAddSitting(minutes: 15)
        rig.engine.recordBreak(.manual)
        rig.engine.rename(to: "Bean")
        rig.engine.flush()

        rig.makeEngine()
        #expect(rig.engine.pet.treats == 4)
        #expect(rig.engine.pet.name == "Bean")
        #expect(rig.engine.today.breaks == 1)
    }

    @Test func aNewDayStartsFreshAndMochiGrows() {
        let adopted = PetDay(containing: .now).adding(days: -6)
        let rig = TestRig { state in
            state.pet.adoptedOn = adopted
            for offset in 0..<3 {
                state.withRecord(for: adopted.adding(days: offset)) { record in
                    record.breaks = 3
                    record.activeSeconds = 3600
                }
            }
        }
        defer { rig.cleanUp() }
        #expect(rig.engine.pet.stage == .seedling)

        rig.engine.clock.advance(by: 24 * 3600)
        rig.engine.tick()
        #expect(rig.engine.today.day == PetDay(containing: .now).adding(days: 1))
        #expect(rig.engine.today.breaks == 0)
        #expect(rig.engine.pet.stage == .sprout, "A week with three cared days")
        #expect(rig.engine.reaction?.kind == .celebrate)
    }
}
