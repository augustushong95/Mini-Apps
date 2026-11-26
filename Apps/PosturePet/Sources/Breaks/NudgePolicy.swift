import Foundation

nonisolated enum NudgeKind: String, Sendable, Equatable {
    /// "I'm stiff, play with me?"
    case breakInvite
    /// "My leaf is drooping — sit up with me?"
    case posture
    /// "It's getting late — call it a day?"
    case windDown
}

/// What the app knows right now that bears on nudging.
nonisolated struct NudgeContext: Sendable {
    var now: Date
    var day: PetDay
    /// Some quiet signal is active (a call, a full-screen app, manual quiet).
    var isQuiet: Bool
    /// The panel, a game or onboarding is on screen.
    var isBusy: Bool
    var userPresent: Bool
    var breakPhase: BreakScheduler.Phase
    var slouchDuration: TimeInterval
    var isLate: Bool
    /// Posture nudges are off until this day (Mochi's learning day).
    var postureNudgesFrom: PetDay?
}

/// Decides which nudge, if any, may be shown now. Pure: it only reads the
/// context and the history of what was shown.
///
/// There's no queue. Conditions are re-checked on every evaluation, so when a
/// call ends, whatever still applies is shown once and anything that stopped
/// applying (the user sat up) is simply never shown.
nonisolated enum NudgePolicy {
    /// Minimum time between any two bubbles.
    static let minimumGap: TimeInterval = 2 * 60
    static let postureGap: TimeInterval = 20 * 60
    static let inviteGap: TimeInterval = 10 * 60
    static let postureAfterInvite: TimeInterval = 10 * 60
    static let windDownGap: TimeInterval = 45 * 60
    static let windDownPerNight = 2
    static let invitesPerCycle = 3

    static func next(_ context: NudgeContext, history: NudgeHistory, invitesThisCycle: Int) -> NudgeKind? {
        guard !context.isQuiet, !context.isBusy, context.userPresent else { return nil }
        let now = context.now
        if let lastAny = history.lastAny, now.timeIntervalSince(lastAny) < minimumGap, now >= lastAny {
            return nil
        }

        if context.isLate {
            let count = history.windDownNight == context.day ? history.windDownCount : 0
            if count < windDownPerNight, elapsed(since: history.lastWindDown, now: now) >= windDownGap {
                return .windDown
            }
            // Late at night Mochi is asleep: no other nudges.
            return nil
        }

        if context.breakPhase == .due,
           invitesThisCycle < invitesPerCycle,
           elapsed(since: history.lastBreakInvite, now: now) >= inviteGap {
            return .breakInvite
        }

        let learning = context.postureNudgesFrom.map { context.day < $0 } ?? false
        if !learning,
           context.slouchDuration > 0,
           elapsed(since: history.lastPosture, now: now) >= postureGap,
           elapsed(since: history.lastBreakInvite, now: now) >= postureAfterInvite {
            return .posture
        }
        return nil
    }

    /// Records that `kind` was shown.
    static func record(_ kind: NudgeKind, in history: inout NudgeHistory, context: NudgeContext) {
        history.lastAny = context.now
        switch kind {
        case .posture:
            history.lastPosture = context.now
        case .breakInvite:
            history.lastBreakInvite = context.now
        case .windDown:
            if history.windDownNight != context.day {
                history.windDownNight = context.day
                history.windDownCount = 0
            }
            history.windDownCount += 1
            history.lastWindDown = context.now
        }
    }

    /// Time since `date`; "forever" when it never happened or the clock
    /// went backwards past it.
    private static func elapsed(since date: Date?, now: Date) -> TimeInterval {
        guard let date, now >= date else { return .infinity }
        return now.timeIntervalSince(date)
    }
}
