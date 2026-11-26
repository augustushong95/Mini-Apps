import Foundation

/// A situation Mochi reacts to. Each has a pool of acts to choose from.
nonisolated enum PetSituation: Hashable, Sendable {
    /// Nothing happening: Mochi does something on its own.
    case idle(PetMood)
    case tapped
    /// Five quick taps in a row.
    case tappedALot
    case fed
    case breakTaken
    /// Won a game, bought Pro, finished setup.
    case celebrate
    case breakDue
    case satUp
    case slumpStarted
    case feltSick
    /// The desktop pet was dropped after a drag.
    case dropped
    case airPodsConnected
    case airPodsDisconnected
    case goodMorning
    case grew

    /// Situations that come up every day need real variety; rare ones less.
    var isEveryday: Bool {
        switch self {
        case .idle, .tapped, .fed, .breakTaken, .celebrate, .breakDue, .satUp, .slumpStarted: true
        default: false
        }
    }

    static var all: [PetSituation] {
        PetMood.allCases.map { .idle($0) } + [
            .tapped, .tappedALot, .fed, .breakTaken, .celebrate, .breakDue, .satUp, .slumpStarted,
            .feltSick, .dropped, .airPodsConnected, .airPodsDisconnected, .goodMorning, .grew,
        ]
    }
}

/// Chooses what Mochi does next, so it doesn't do the same thing twice in a
/// row: a weighted pick from the situation's pool that skips the last few
/// acts, respects each act's cooldown, and keeps to face-only acts when
/// Reduce Motion is on. Pure and seedable, so it's unit-tested.
nonisolated struct BehaviorDirector: Sendable {
    /// Acts not to repeat.
    static let memory = 3
    /// Seconds between idle acts.
    static let idleDelay: ClosedRange<Double> = 12...35

    var reduceMotion = false
    private(set) var recent: [PetAct] = []
    private var lastPlayed: [PetAct: TimeInterval] = [:]
    private var rng: SeededRandom

    init(seed: UInt64 = UInt64.random(in: 1...UInt64.max)) {
        rng = SeededRandom(seed: seed)
    }

    /// The acts a situation can produce, with relative weights.
    static func pool(for situation: PetSituation) -> [(act: PetAct, weight: Double)] {
        switch situation {
        case .idle(.happy):
            [(.lookAround, 3), (.doubleBounce, 2), (.wiggle, 2), (.hum, 2), (.leafTwirl, 2), (.wink, 1.5),
             (.heartPop, 1.5), (.roll, 0.7), (.daydream, 1.5), (.stretch, 1.5), (.dance, 0.8)]
        case .idle(.tired):
            [(.sigh, 2), (.stretchFlop, 2), (.slowRock, 1.5), (.yawn, 2), (.fidget, 2), (.lookAtYou, 1.5)]
        case .idle(.slumped):
            [(.melt, 2), (.leafFlutter, 2), (.deepSigh, 2), (.trySitUp, 2)]
        case .idle(.sleepy):
            [(.yawn, 2), (.nodOff, 2), (.sleepBubble, 2), (.snore, 2), (.sleepSmile, 1.5)]
        case .idle(.sick), .feltSick:
            [(.shiver, 2), (.sneeze, 2), (.cough, 2), (.sniffle, 2)]
        case .tapped:
            [(.giggle, 2), (.boing, 2), (.surprised, 1.5), (.heart, 1.5), (.spin, 1.5), (.shy, 1.5)]
        case .tappedALot:
            [(.dizzy, 3), (.surprised, 1)]
        case .fed:
            [(.chomp, 2), (.gulp, 2), (.savour, 1.5), (.yumDance, 1.5)]
        case .breakTaken:
            [(.welcomeBounce, 2), (.stretchCheer, 2), (.happySpin, 2), (.heartPop, 0.7)]
        case .celebrate:
            [(.victoryHop, 2), (.sparkleSpin, 2), (.cheer, 2), (.heart, 0.6)]
        case .breakDue:
            [(.fidget, 2), (.stretch, 2), (.lookAtYou, 2), (.pointLeaf, 2)]
        case .satUp:
            [(.taDa, 2), (.wiggle, 2), (.heartPop, 1.5)]
        case .slumpStarted:
            [(.oof, 2), (.sadLook, 2), (.leafFlop, 2)]
        case .dropped:
            [(.squashLand, 2), (.dizzyLand, 1), (.happyLand, 2)]
        case .airPodsConnected:
            [(.perkUp, 2), (.wiggle, 1)]
        case .airPodsDisconnected:
            [(.puzzled, 2), (.lookAround, 1)]
        case .goodMorning:
            [(.goodMorning, 3), (.yawn, 1), (.stretch, 1)]
        case .grew:
            [(.grow, 2), (.sparkleSpin, 1)]
        }
    }

    /// The next act for `situation` at time `now` (seconds, any clock), or
    /// nil when nothing fits (Reduce Motion with no face-only act).
    mutating func pick(_ situation: PetSituation, now: TimeInterval) -> PetAct? {
        let pool = Self.pool(for: situation).filter { !reduceMotion || $0.act.script.isFaceOnly }
        guard !pool.isEmpty else { return nil }

        let ready = pool.filter { candidate in
            guard let last = lastPlayed[candidate.act] else { return true }
            return now - last >= candidate.act.script.cooldown
        }
        // Prefer acts not seen lately; with a small pool, at least never the
        // very last one; with a single option, allow it.
        let fresh = ready.filter { !recent.contains($0.act) }
        let notLast = ready.filter { $0.act != recent.last }
        let candidates = !fresh.isEmpty ? fresh : (!notLast.isEmpty ? notLast : ready)
        guard let act = weightedPick(candidates) else { return nil }

        recent.append(act)
        if recent.count > Self.memory {
            recent.removeFirst(recent.count - Self.memory)
        }
        lastPlayed[act] = now
        return act
    }

    /// How long to wait before the next idle act.
    mutating func nextIdleDelay() -> TimeInterval {
        Double.random(in: Self.idleDelay, using: &rng)
    }

    private mutating func weightedPick(_ candidates: [(act: PetAct, weight: Double)]) -> PetAct? {
        let total = candidates.reduce(0) { $0 + $1.weight }
        guard total > 0 else { return candidates.first?.act }
        var roll = Double.random(in: 0..<total, using: &rng)
        for candidate in candidates {
            roll -= candidate.weight
            if roll < 0 { return candidate.act }
        }
        return candidates.last?.act
    }
}
