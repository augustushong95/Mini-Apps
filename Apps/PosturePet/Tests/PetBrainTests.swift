import Foundation
import Testing
@testable import PosturePet

struct PetBrainTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    // MARK: Mood

    private func inputs(
        late: Bool = false, posture: PostureState = .upright, phase: BreakScheduler.Phase = .sitting, sitting: TimeInterval = 0
    ) -> PetBrain.MoodInputs {
        PetBrain.MoodInputs(isLate: late, posture: posture, breakPhase: phase, sittingSeconds: sitting, interval: 3000)
    }

    @Test func moodPriority() {
        #expect(PetBrain.mood(inputs()) == .happy)
        #expect(PetBrain.mood(inputs(phase: .due, sitting: 3100)) == .tired)
        #expect(PetBrain.mood(inputs(phase: .snoozed, sitting: 3100)) == .tired)
        #expect(PetBrain.mood(inputs(posture: .slouching, phase: .due, sitting: 3100)) == .slumped)
        #expect(PetBrain.mood(inputs(posture: .slouching, phase: .due, sitting: 6000)) == .sick)
        #expect(PetBrain.mood(inputs(late: true, posture: .slouching, phase: .due, sitting: 6000)) == .sleepy)
    }

    @Test func lateHours() {
        let windDown = 22 * 60
        #expect(!PetBrain.isLate(date(2026, 11, 26, 21, 59), windDownMinutes: windDown, calendar: calendar))
        #expect(PetBrain.isLate(date(2026, 11, 26, 22, 0), windDownMinutes: windDown, calendar: calendar))
        #expect(PetBrain.isLate(date(2026, 11, 27, 1, 30), windDownMinutes: windDown, calendar: calendar))
        #expect(!PetBrain.isLate(date(2026, 11, 27, 4, 0), windDownMinutes: windDown, calendar: calendar))
        // Wind-down after midnight.
        #expect(!PetBrain.isLate(date(2026, 11, 26, 23, 30), windDownMinutes: 30, calendar: calendar))
        #expect(!PetBrain.isLate(date(2026, 11, 27, 0, 15), windDownMinutes: 30, calendar: calendar))
        #expect(PetBrain.isLate(date(2026, 11, 27, 0, 45), windDownMinutes: 30, calendar: calendar))
    }

    // MARK: Happiness

    @Test func aGreatDayIsHappy() {
        var record = DayRecord(day: PetDay(year: 2026, month: 11, day: 26))
        record.activeSeconds = 6 * 3600
        record.breaks = 7
        record.measuredSeconds = 5 * 3600
        record.goodPostureSeconds = 5 * 3600
        #expect(PetBrain.happiness(for: record, interval: 3000) == 100)
    }

    @Test func happinessWithoutPostureDataUsesBreaksAndBedtime() {
        var record = DayRecord(day: PetDay(year: 2026, month: 11, day: 26))
        record.activeSeconds = 5 * 3000
        record.breaks = 5
        #expect(PetBrain.happiness(for: record, interval: 3000) == 100)
        record.breaks = 0
        // Breaks 0/5 (0.4 weight) and on time (0.1 weight): 0.1 / 0.5.
        #expect(PetBrain.happiness(for: record, interval: 3000) == 20)
    }

    @Test func noBreaksDueYetIsNotPenalised() {
        let record = DayRecord(day: PetDay(year: 2026, month: 11, day: 26))
        #expect(PetBrain.happiness(for: record, interval: 3000) == 100)
    }

    // MARK: Growth

    private func caredDay(_ day: PetDay) -> DayRecord {
        var record = DayRecord(day: day)
        record.breaks = 2
        record.activeSeconds = 3600
        return record
    }

    @Test func growsAfterAWeekWithThreeCaredDays() {
        let adopted = PetDay(year: 2026, month: 11, day: 1)
        var pet = PetProfile(adoptedOn: adopted)
        let days = [0, 2, 4].map { caredDay(adopted.adding(days: $0)) }

        #expect(!PetBrain.evaluateGrowth(pet: &pet, days: days, today: adopted.adding(days: 6)))
        #expect(pet.stage == .seedling)
        #expect(PetBrain.evaluateGrowth(pet: &pet, days: days, today: adopted.adding(days: 7)))
        #expect(pet.stage == .sprout)
        // Evaluated once per week only.
        #expect(!PetBrain.evaluateGrowth(pet: &pet, days: days, today: adopted.adding(days: 8)))
    }

    @Test func aQuietWeekNeverShrinks() {
        let adopted = PetDay(year: 2026, month: 11, day: 1)
        var pet = PetProfile(adoptedOn: adopted, stage: .bud)
        #expect(!PetBrain.evaluateGrowth(pet: &pet, days: [], today: adopted.adding(days: 21)))
        #expect(pet.stage == .bud)
        #expect(pet.lastEvaluatedWeek == 3)
    }

    @Test func stopsAtBloom() {
        let adopted = PetDay(year: 2026, month: 1, day: 1)
        var pet = PetProfile(adoptedOn: adopted)
        let days = (0..<70).map { caredDay(adopted.adding(days: $0)) }
        _ = PetBrain.evaluateGrowth(pet: &pet, days: days, today: adopted.adding(days: 70))
        #expect(pet.stage == .bloom)
    }

    // MARK: Streaks

    private func day(_ offset: Int, breaks: Int, active: TimeInterval = 3600) -> DayRecord {
        var record = DayRecord(day: PetDay(year: 2026, month: 11, day: 26).adding(days: offset))
        record.breaks = breaks
        record.activeSeconds = active
        return record
    }

    @Test func streakCountsBackAndSkipsDaysOff() {
        let today = PetDay(year: 2026, month: 11, day: 26)
        let days = [
            day(-5, breaks: 1),            // the miss that ends the streak
            day(-4, breaks: 3),
            day(-3, breaks: 0, active: 0), // a day off: skipped
            day(-2, breaks: 4),
            day(-1, breaks: 3),
            day(0, breaks: 1),             // today, still in progress
        ]
        #expect(PetBrain.streak(days: days, today: today) == 3)
    }

    @Test func todayCountsOnceMet() {
        let today = PetDay(year: 2026, month: 11, day: 26)
        let days = [day(-1, breaks: 3), day(0, breaks: 3)]
        #expect(PetBrain.streak(days: days, today: today) == 2)
    }

    // MARK: Pet day

    @Test func earlyHoursBelongToTheEveningBefore() {
        #expect(PetDay(containing: date(2026, 11, 27, 2, 30), calendar: calendar) == PetDay(year: 2026, month: 11, day: 26))
        #expect(PetDay(containing: date(2026, 11, 27, 4, 0), calendar: calendar) == PetDay(year: 2026, month: 11, day: 27))
    }

    @Test func dayArithmeticAcrossDaylightSaving() {
        // US clocks spring forward on 8 March 2026.
        let before = PetDay(year: 2026, month: 3, day: 7)
        #expect(before.adding(days: 1, calendar: calendar) == PetDay(year: 2026, month: 3, day: 8))
        #expect(before.adding(days: 2, calendar: calendar) == PetDay(year: 2026, month: 3, day: 9))
        #expect(before.days(until: PetDay(year: 2026, month: 3, day: 14), calendar: calendar) == 7)
    }

    @Test func savedStateRoundTrips() throws {
        var state = SavedState()
        state.pet.adoptedOn = PetDay(year: 2026, month: 11, day: 20)
        state.withRecord(for: PetDay(year: 2026, month: 11, day: 26)) { $0.breaks = 4 }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(SavedState.self, from: encoder.encode(state))
        #expect(decoded == state)
    }
}
