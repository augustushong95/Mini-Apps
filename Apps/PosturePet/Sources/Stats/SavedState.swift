import Foundation

/// Everything the app remembers between launches. Versioned so later
/// releases can migrate it. Holds daily totals only: no motion samples.
nonisolated struct SavedState: Codable, Sendable, Equatable {
    static let currentVersion = 1

    var version = SavedState.currentVersion
    var pet = PetProfile()
    var days: [DayRecord] = []
    var scheduler = BreakScheduler()
    var nudges = NudgeHistory()
    var calibration = CalibrationStore()
    var bestScores: [String: Int] = [:]
    var onboarding = OnboardingProgress()
    /// When the state was last written, so a relaunch can tell how long the
    /// app was closed.
    var savedAt: Date?

    /// Keeps a year of history.
    static let maxDays = 400

    func record(for day: PetDay) -> DayRecord? {
        days.last(where: { $0.day == day })
    }

    /// Returns the record for `day`, creating it if needed, and trims old ones.
    mutating func withRecord<T>(for day: PetDay, _ update: (inout DayRecord) -> T) -> T {
        if let index = days.lastIndex(where: { $0.day == day }) {
            return update(&days[index])
        }
        var record = DayRecord(day: day)
        let result = update(&record)
        days.append(record)
        days.sort { $0.day < $1.day }
        if days.count > Self.maxDays {
            days.removeFirst(days.count - Self.maxDays)
        }
        return result
    }
}

nonisolated struct PetProfile: Codable, Sendable, Equatable {
    var name = "Mochi"
    var adoptedOn: PetDay?
    var stage: GrowthStage = .seedling
    var treats = 0
    /// The last whole week since adoption that growth was evaluated for.
    var lastEvaluatedWeek = 0
}

/// One pet day's totals.
nonisolated struct DayRecord: Codable, Sendable, Equatable, Identifiable {
    var day: PetDay
    /// Time at the Mac (input or a headphone wearer at the desk).
    var activeSeconds: Double = 0
    /// Time posture was actually measured.
    var measuredSeconds: Double = 0
    var goodPostureSeconds: Double = 0
    var slouchSeconds: Double = 0
    var breaks = 0
    var gamesPlayed = 0
    var treatsEarned = 0
    var treatsFed = 0
    /// Active time after the wind-down hour.
    var lateSeconds: Double = 0
    /// Happiness when the day was last updated, for history charts.
    var happiness: Int?

    var id: PetDay { day }

    var goodPostureFraction: Double? {
        measuredSeconds >= 60 ? goodPostureSeconds / measuredSeconds : nil
    }
}

nonisolated struct NudgeHistory: Codable, Sendable, Equatable {
    var lastAny: Date?
    var lastPosture: Date?
    var lastBreakInvite: Date?
    var lastWindDown: Date?
    var windDownNight: PetDay?
    var windDownCount = 0
    /// Break invites shown since the last break.
    var invitesThisCycle = 0
}

/// Calibrated "sitting well" head angles, one per display arrangement:
/// people hold their head differently for a laptop screen and a monitor.
nonisolated struct CalibrationStore: Codable, Sendable, Equatable {
    var baselines: [String: PostureBaseline] = [:]
    /// The comfortable range found in the arcade's range check.
    var range: MotionRange?

    func baseline(for arrangement: String) -> PostureBaseline? {
        baselines[arrangement] ?? baselines.values.max(by: { $0.capturedAt < $1.capturedAt })
    }
}

nonisolated struct PostureBaseline: Codable, Sendable, Equatable {
    /// Gravity-derived head pitch and roll, in degrees, when sitting well.
    var pitch: Double
    var roll: Double
    var capturedAt: Date
}

/// How far the user comfortably tilts, in degrees from neutral.
nonisolated struct MotionRange: Codable, Sendable, Equatable {
    var up: Double
    var down: Double
    var left: Double
    var right: Double

    static let `default` = MotionRange(up: 20, down: 22, left: 22, right: 22)
}

nonisolated struct OnboardingProgress: Codable, Sendable, Equatable {
    var completed = false
    var safetyNoteShown = false
    /// Posture nudges stay off until this day, while Mochi learns.
    var nudgesFrom: PetDay?
}
