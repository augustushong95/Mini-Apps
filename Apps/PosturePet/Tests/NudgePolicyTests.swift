import Foundation
import Testing
@testable import PosturePet

struct NudgePolicyTests {
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let today = PetDay(year: 2026, month: 11, day: 26)

    private func context(
        at offset: TimeInterval = 0,
        quiet: Bool = false,
        busy: Bool = false,
        phase: BreakScheduler.Phase = .sitting,
        slouch: TimeInterval = 0,
        late: Bool = false,
        learningUntil: PetDay? = nil
    ) -> NudgeContext {
        NudgeContext(
            now: start + offset, day: today, isQuiet: quiet, isBusy: busy, userPresent: true,
            breakPhase: phase, slouchDuration: slouch, isLate: late, postureNudgesFrom: learningUntil
        )
    }

    @Test func nothingDuringQuietOrWhileBusy() {
        let history = NudgeHistory()
        #expect(NudgePolicy.next(context(quiet: true, phase: .due), history: history, invitesThisCycle: 0) == nil)
        #expect(NudgePolicy.next(context(busy: true, phase: .due), history: history, invitesThisCycle: 0) == nil)
    }

    @Test func breakInvitesAreSpacedAndCapped() {
        var history = NudgeHistory()
        var invites = 0
        var shown: [TimeInterval] = []
        for minute in stride(from: 0.0, through: 60, by: 1) {
            let ctx = context(at: minute * 60, phase: .due)
            if let kind = NudgePolicy.next(ctx, history: history, invitesThisCycle: invites) {
                #expect(kind == .breakInvite)
                NudgePolicy.record(kind, in: &history, context: ctx)
                invites += 1
                shown.append(minute)
            }
        }
        #expect(shown == [0, 10, 20])
    }

    @Test func postureNudgeWaitsOutTheLearningDay() {
        let history = NudgeHistory()
        let learning = context(slouch: 30, learningUntil: today.adding(days: 1))
        #expect(NudgePolicy.next(learning, history: history, invitesThisCycle: 0) == nil)
        let learned = context(slouch: 30, learningUntil: today)
        #expect(NudgePolicy.next(learned, history: history, invitesThisCycle: 0) == .posture)
    }

    @Test func postureNudgeStaysClearOfABreakInvite() {
        var history = NudgeHistory()
        let invite = context(phase: .due)
        NudgePolicy.record(.breakInvite, in: &history, context: invite)
        #expect(NudgePolicy.next(context(at: 5 * 60, slouch: 60), history: history, invitesThisCycle: 3) == nil)
        #expect(NudgePolicy.next(context(at: 11 * 60, slouch: 60), history: history, invitesThisCycle: 3) == .posture)
    }

    @Test func anyTwoBubblesAreAtLeastTwoMinutesApart() {
        var history = NudgeHistory()
        NudgePolicy.record(.posture, in: &history, context: context())
        #expect(NudgePolicy.next(context(at: 60, phase: .due), history: history, invitesThisCycle: 0) == nil)
        #expect(NudgePolicy.next(context(at: 121, phase: .due), history: history, invitesThisCycle: 0) == .breakInvite)
    }

    @Test func windDownTwicePerNightAndNothingElse() {
        var history = NudgeHistory()
        var shown: [TimeInterval] = []
        for minute in stride(from: 0.0, through: 180, by: 5) {
            let ctx = context(at: minute * 60, phase: .due, slouch: 60, late: true)
            if let kind = NudgePolicy.next(ctx, history: history, invitesThisCycle: 0) {
                #expect(kind == .windDown)
                NudgePolicy.record(kind, in: &history, context: ctx)
                shown.append(minute)
            }
        }
        #expect(shown == [0, 45])
    }

    @Test func aClockJumpBackDoesNotBlockForever() {
        var history = NudgeHistory()
        NudgePolicy.record(.breakInvite, in: &history, context: context(at: 3600))
        // The clock is set back an hour: treat the last invite as long ago.
        #expect(NudgePolicy.next(context(at: 0, phase: .due), history: history, invitesThisCycle: 1) == .breakInvite)
    }
}
