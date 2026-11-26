import Foundation

nonisolated enum BreakKind: String, Codable, Sendable {
    /// Away from the Mac long enough (or it slept).
    case away
    /// Played a Neck Arcade game.
    case game
    /// Tapped "I took a break".
    case manual
}

nonisolated enum BreakEvent: Equatable, Sendable {
    case becameDue
    /// `counted` is false when the break came after a short sit (under
    /// `minimumSitToCount`), whatever kind it was: it resets the timer but
    /// doesn't add to the day's breaks, so back-to-back games can't pad them.
    case completed(BreakKind, counted: Bool)
}

/// Tracks how long the user has been sitting since their last break.
///
/// Pure and clock-agnostic: `tick` is called every few seconds with the
/// current time, and sitting time is the sum of small deltas between ticks.
/// A delta that's too big (the Mac slept, the app was closed, the clock
/// jumped) is never credited as sitting.
nonisolated struct BreakScheduler: Codable, Equatable, Sendable {
    enum Phase: String, Codable, Sendable {
        case sitting, due, snoozed
    }

    /// Sitting time before a break is due.
    var interval: TimeInterval = 50 * 60
    private(set) var sittingSeconds: TimeInterval = 0
    private(set) var awaySeconds: TimeInterval = 0
    private(set) var lastTick: Date?
    private(set) var snoozedUntil: Date?
    private(set) var lastBreakAt: Date?
    private(set) var phase: Phase = .sitting

    /// Continuous time away that counts as a break.
    static let breakAfterAway: TimeInterval = 5 * 60
    /// Sitting needed before a break adds to the day's count.
    static let minimumSitToCount: TimeInterval = 10 * 60
    /// Ticks further apart than this are a gap, not sitting.
    static let maxTickGap: TimeInterval = 30

    /// Sitting time past the interval, or 0.
    var overdueSeconds: TimeInterval {
        max(0, sittingSeconds - interval)
    }

    var progress: Double {
        interval > 0 ? min(1, sittingSeconds / interval) : 0
    }

    func remaining() -> TimeInterval {
        max(0, interval - sittingSeconds)
    }

    /// Advances the timer to `now`. `present` is whether the user is at the
    /// Mac right now. `gapWasPresent` says a late tick (beyond `maxTickGap`)
    /// was only a delayed timer, not time away: the Mac didn't sleep and the
    /// user was using it during the gap.
    mutating func tick(now: Date, present: Bool, gapWasPresent: Bool = false) -> [BreakEvent] {
        var events: [BreakEvent] = []
        defer { lastTick = now }
        guard let lastTick else { return events }

        let delta = now.timeIntervalSince(lastTick)
        if delta < 0 {
            // The clock went backwards; ignore this interval.
            return events
        }
        if delta > Self.maxTickGap, !(gapWasPresent && present && delta < Self.breakAfterAway) {
            // Slept, closed, or a stalled timer: count the gap as time away.
            awaySeconds += delta
        } else if present {
            sittingSeconds += delta
            awaySeconds = 0
        } else {
            awaySeconds += delta
        }

        if awaySeconds >= Self.breakAfterAway, sittingSeconds > 0 {
            events.append(complete(.away, at: now))
        }

        events += updatePhase(now: now)
        return events
    }

    /// Records a break taken in the app (a game, or the user saying so).
    mutating func completeBreak(_ kind: BreakKind, at now: Date) -> BreakEvent {
        let event = complete(kind, at: now)
        _ = updatePhase(now: now)
        return event
    }

    mutating func snooze(until date: Date, now: Date) {
        snoozedUntil = date
        _ = updatePhase(now: now)
    }

    /// Applies a new interval from Settings.
    mutating func setInterval(_ interval: TimeInterval, now: Date) {
        self.interval = interval
        _ = updatePhase(now: now)
    }

    #if DEBUG
    /// Adds sitting time, for walking through states in debug builds.
    mutating func debugAddSitting(_ seconds: TimeInterval, now: Date) -> [BreakEvent] {
        sittingSeconds += seconds
        return updatePhase(now: now)
    }
    #endif

    private mutating func complete(_ kind: BreakKind, at now: Date) -> BreakEvent {
        let counted = sittingSeconds >= Self.minimumSitToCount
        sittingSeconds = 0
        awaySeconds = 0
        snoozedUntil = nil
        lastBreakAt = now
        return .completed(kind, counted: counted)
    }

    private mutating func updatePhase(now: Date) -> [BreakEvent] {
        let previous = phase
        if sittingSeconds < interval {
            phase = .sitting
            snoozedUntil = nil
        } else if let snoozedUntil, snoozedUntil > now {
            phase = .snoozed
        } else {
            phase = .due
            snoozedUntil = nil
        }
        return previous == .sitting && phase == .due ? [.becameDue] : []
    }
}
