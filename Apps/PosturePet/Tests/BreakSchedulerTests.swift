import Foundation
import Testing
@testable import PosturePet

struct BreakSchedulerTests {
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    /// Ticks every 5 s for `duration`, returning all events.
    @discardableResult
    private func run(
        _ s: inout BreakScheduler, from offset: TimeInterval, for duration: TimeInterval, present: Bool = true
    ) -> [BreakEvent] {
        var events: [BreakEvent] = []
        var t = offset
        while t <= offset + duration {
            events += s.tick(now: start + t, present: present)
            t += 5
        }
        return events
    }

    @Test func sittingAccumulatesAndBecomesDueOnce() {
        var s = BreakScheduler()
        s.setInterval(10 * 60, now: start)
        let events = run(&s, from: 0, for: 15 * 60)
        #expect(events.filter { $0 == .becameDue }.count == 1)
        #expect(s.phase == .due)
        #expect(abs(s.sittingSeconds - 15 * 60) < 6)
    }

    @Test func sleepIsNeverSitting() {
        var s = BreakScheduler()
        run(&s, from: 0, for: 20 * 60)
        let before = s.sittingSeconds
        // The Mac sleeps for an hour: one huge delta.
        let events = s.tick(now: start + 20 * 60 + 3600, present: true)
        #expect(events.contains(.completed(.away, counted: true)))
        #expect(s.sittingSeconds == 0)
        #expect(before > 19 * 60)
    }

    @Test func aShortStallIsNotABreak() {
        var s = BreakScheduler()
        run(&s, from: 0, for: 20 * 60)
        // A 2-minute gap: not sitting, but not a break either.
        let events = s.tick(now: start + 22 * 60, present: true)
        #expect(events.isEmpty)
        #expect(s.sittingSeconds > 19 * 60 && s.sittingSeconds < 20 * 60 + 6)
    }

    @Test func aDelayedTimerWithInputStillCountsAsSitting() {
        var s = BreakScheduler()
        run(&s, from: 0, for: 10 * 60)
        let before = s.sittingSeconds
        // App Nap held the timer for 50 s, but the user was typing.
        _ = s.tick(now: start + 10 * 60 + 50, present: true, gapWasPresent: true)
        #expect(abs(s.sittingSeconds - (before + 50)) < 6)
        // A long gap is never credited, even with input.
        _ = s.tick(now: start + 10 * 60 + 50 + 600, present: true, gapWasPresent: true)
        #expect(s.sittingSeconds == 0, "Ten minutes without ticks is a break")
    }

    @Test func walkingAwayForFiveMinutesIsABreak() {
        var s = BreakScheduler()
        run(&s, from: 0, for: 30 * 60)
        let events = run(&s, from: 30 * 60 + 5, for: 6 * 60, present: false)
        #expect(events.contains(.completed(.away, counted: true)))
        #expect(s.sittingSeconds == 0)
    }

    @Test func aBreakAfterAShortSitDoesNotCount() {
        var s = BreakScheduler()
        run(&s, from: 0, for: 4 * 60)
        let events = run(&s, from: 4 * 60 + 5, for: 6 * 60, present: false)
        #expect(events.contains(.completed(.away, counted: false)))
    }

    @Test func clockGoingBackwardsChangesNothing() {
        var s = BreakScheduler()
        run(&s, from: 0, for: 10 * 60)
        let before = s.sittingSeconds
        let events = s.tick(now: start - 3600, present: true)
        #expect(events.isEmpty)
        #expect(s.sittingSeconds == before)
    }

    @Test func snoozeHoldsThenReturnsToDue() {
        var s = BreakScheduler()
        s.setInterval(10 * 60, now: start)
        run(&s, from: 0, for: 11 * 60)
        #expect(s.phase == .due)
        s.snooze(until: start + 21 * 60, now: start + 11 * 60)
        #expect(s.phase == .snoozed)
        run(&s, from: 11 * 60 + 5, for: 5 * 60)
        #expect(s.phase == .snoozed)
        run(&s, from: 16 * 60 + 5, for: 6 * 60)
        #expect(s.phase == .due)
    }

    @Test func aGameBreakResetsAndCountsAfterASit() {
        var s = BreakScheduler()
        run(&s, from: 0, for: 12 * 60)
        let event = s.completeBreak(.game, at: start + 12 * 60)
        #expect(event == .completed(.game, counted: true))
        #expect(s.sittingSeconds == 0)
        #expect(s.phase == .sitting)
    }

    @Test func backToBackGamesCountOnce() {
        var s = BreakScheduler()
        run(&s, from: 0, for: 12 * 60)
        #expect(s.completeBreak(.game, at: start + 12 * 60) == .completed(.game, counted: true))
        // Play Again a minute later: resets the timer, but no extra break.
        run(&s, from: 12 * 60 + 5, for: 60)
        #expect(s.completeBreak(.game, at: start + 13 * 60 + 5) == .completed(.game, counted: false))
        #expect(s.completeBreak(.manual, at: start + 13 * 60 + 10) == .completed(.manual, counted: false))
    }

    @Test func changingTheIntervalUpdatesThePhase() {
        var s = BreakScheduler()
        run(&s, from: 0, for: 40 * 60)
        #expect(s.phase == .sitting)
        s.setInterval(30 * 60, now: start + 40 * 60)
        #expect(s.phase == .due)
    }

    @Test func survivesEncodingRoundTrip() throws {
        var s = BreakScheduler()
        run(&s, from: 0, for: 12 * 60)
        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(BreakScheduler.self, from: data)
        #expect(decoded == s)
    }
}
