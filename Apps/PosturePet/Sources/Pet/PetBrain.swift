import Foundation

/// Mochi's rules: mood, happiness, growth and streaks. Pure functions of the
/// app's state, so every rule is unit-tested.
nonisolated enum PetBrain {
    // MARK: Mood

    struct MoodInputs: Sendable {
        var isLate: Bool
        var posture: PostureState
        var breakPhase: BreakScheduler.Phase
        var sittingSeconds: TimeInterval
        var interval: TimeInterval
    }

    /// Most urgent first: sleepy, sick, slumped, tired, happy.
    static func mood(_ inputs: MoodInputs) -> PetMood {
        if inputs.isLate {
            return .sleepy
        }
        // Sitting through a whole extra interval makes Mochi feel poorly;
        // one break fixes it.
        if inputs.interval > 0, inputs.sittingSeconds >= inputs.interval * 2 {
            return .sick
        }
        if inputs.posture == .slouching {
            return .slumped
        }
        if inputs.breakPhase != .sitting {
            return .tired
        }
        return .happy
    }

    /// Whether `date` falls after the wind-down time and before the pet day
    /// rolls over at 04:00.
    static func isLate(_ date: Date, windDownMinutes: Int, calendar: Calendar = .current) -> Bool {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let minutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        let dayStart = PetDay.startHour * 60
        if minutes < dayStart {
            // After midnight it's late, unless wind-down is set after midnight
            // and hasn't been reached yet.
            return windDownMinutes < dayStart ? minutes >= windDownMinutes : true
        }
        return windDownMinutes >= dayStart && minutes >= windDownMinutes
    }

    // MARK: Happiness

    /// 0–100 for a day: good posture 50%, breaks 40%, stopping on time 10%.
    /// Without enough posture data the other two share the weight.
    static func happiness(for record: DayRecord, interval: TimeInterval) -> Int {
        let expectedBreaks = interval > 0 ? floor(record.activeSeconds / interval) : 0
        let breakScore = expectedBreaks < 1 ? 1 : min(1, Double(record.breaks) / expectedBreaks)
        let lateScore = max(0, 1 - record.lateSeconds / 3600)

        var weighted = breakScore * 0.4 + lateScore * 0.1
        var weights = 0.5
        if record.measuredSeconds >= 10 * 60, let posture = record.goodPostureFraction {
            weighted += posture * 0.5
            weights += 0.5
        }
        let feedBonus = Double(min(record.treatsFed, 3)) * 0.02
        return Int((min(1, weighted / weights + feedBonus) * 100).rounded())
    }

    // MARK: Growth

    /// A day Mochi felt looked after: two breaks, or half the measured time
    /// (at least 30 minutes of it) sitting well.
    static func isCaredDay(_ record: DayRecord) -> Bool {
        if record.breaks >= 2 {
            return true
        }
        return record.measuredSeconds >= 30 * 60 && (record.goodPostureFraction ?? 0) >= 0.5
    }

    static let caredDaysToGrow = 3

    /// Evaluates every whole week since adoption that hasn't been evaluated,
    /// growing one stage for each week with enough cared days. Never shrinks.
    static func evaluateGrowth(pet: inout PetProfile, days: [DayRecord], today: PetDay) -> Bool {
        guard let adopted = pet.adoptedOn else { return false }
        let completedWeeks = max(0, adopted.days(until: today)) / 7
        var grew = false
        while pet.lastEvaluatedWeek < completedWeeks {
            let week = pet.lastEvaluatedWeek
            let start = adopted.adding(days: week * 7)
            let end = adopted.adding(days: week * 7 + 7)
            let cared = days.filter { $0.day >= start && $0.day < end && isCaredDay($0) }.count
            if cared >= caredDaysToGrow, let next = pet.stage.next {
                pet.stage = next
                grew = true
            }
            pet.lastEvaluatedWeek += 1
        }
        return grew
    }

    // MARK: Streaks

    static let breakGoal = 3
    /// Less use than this and a day doesn't count either way.
    static let activeDayThreshold: TimeInterval = 30 * 60

    /// Consecutive days meeting the break goal, counting back from today.
    /// Days the Mac was barely used are skipped, not counted as misses.
    /// Today only adds once it's met; it can't break the streak while it's
    /// still in progress.
    static func streak(days: [DayRecord], today: PetDay) -> Int {
        let byDay = Dictionary(days.map { ($0.day, $0) }, uniquingKeysWith: { _, last in last })
        var count = 0
        if let record = byDay[today], record.breaks >= breakGoal {
            count += 1
        }
        guard let earliest = days.map(\.day).min() else { return count }
        var day = today.adding(days: -1)
        while day >= earliest {
            if let record = byDay[day], record.activeSeconds >= activeDayThreshold {
                if record.breaks >= breakGoal {
                    count += 1
                } else {
                    break
                }
            }
            day = day.adding(days: -1)
        }
        return count
    }
}
