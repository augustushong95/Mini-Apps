import Foundation

/// What Mochi says, in its own voice. Several lines per situation so it
/// doesn't repeat itself.
nonisolated enum PetLines {
    static func pool(for mood: PetMood, hour: Int) -> [String] {
        switch mood {
        case .happy:
            var lines = [
                "Feeling bouncy!", "This is nice.", "You're sitting so well!", "La la la…",
                "Got any dewdrops?", "My leaf feels perky!", "Hi there!", "Good posture club!",
            ]
            switch hour {
            case 4..<12: lines += ["Good morning!", "Fresh start today!"]
            case 12..<18: lines += ["Afternoon already?", "Keep it up!"]
            default: lines += ["Cozy evening.", "Almost done?"]
            }
            return lines
        case .tired:
            return ["I'm stiff… play with me?", "Break time?", "My back is creaky.", "Can we move a little?",
                    "Ooh, so stiff.", "A quick game?", "Stretchy time!", "Let's wiggle!"]
        case .slumped:
            return ["My leaf is drooping.", "Sit tall with me?", "Chin up, friend!", "I'm getting squished.",
                    "Shoulders back?", "Heads up!", "Let's sit tall.", "Ooh, low leaf."]
        case .sleepy:
            return ["It's late. Rest soon?", "Yawn… bedtime?", "Zzz…", "Let's call it a day.",
                    "So sleepy…", "Five more minutes?", "Night night soon.", "Cozy dreams…"]
        case .sick:
            return ["I don't feel so good.", "A break would help.", "Achoo!", "Feeling wobbly…",
                    "Need a stretch…", "Bit under the weather.", "Some fresh air?", "Help me feel better?"]
        }
    }

    /// A line for a moment, shown briefly after the event.
    static func pool(for situation: PetSituation) -> [String] {
        switch situation {
        case .idle(let mood): pool(for: mood, hour: 12)
        case .tapped: ["Hehe!", "That tickles!", "Boop!", "Hi!", "Hello you!"]
        case .tappedALot: ["Whoa, dizzy!", "The room is spinning!"]
        case .fed: ["Yum!", "Delicious!", "Thank you!", "Mmm, dewdrop!"]
        case .breakTaken: ["Welcome back!", "Ahh, much better.", "Refreshed!"]
        case .celebrate: ["That was fun!", "We did it!", "Again?", "Yay!"]
        case .breakDue: ["Break time?", "Play with me?", "Stretch with me?"]
        case .satUp: ["Ta-da! Nice posture!", "Much better!", "Tall and proud!"]
        case .slumpStarted: ["Oof…", "Sinking…", "Uh-oh, slumping."]
        case .feltSick: ["Achoo!", "Feeling wobbly…"]
        case .dropped: ["Wheee!", "Nice spot!", "Landed!"]
        case .airPodsConnected: ["I can feel you!", "Hello, AirPods!"]
        case .airPodsDisconnected: ["Where'd you go?", "Hmm, no AirPods."]
        case .goodMorning: ["Good morning!", "Rise and shine!"]
        case .grew: ["I grew!", "Look at my leaves!"]
        }
    }

    /// A speech bubble's title for a nudge.
    static func bubbleTitles(for kind: NudgeKind) -> [String] {
        switch kind {
        case .breakInvite: ["I'm stiff… play with me?", "Break time!", "A quick game?", "Let's stretch!"]
        case .posture: ["Sit tall with me?", "Chin up!", "My leaf is drooping.", "Shoulders back?"]
        case .windDown: ["Call it a day?", "Bedtime soon?", "It's getting late."]
        }
    }

    /// Picks lines without repeating the previous one.
    struct Rotator: Sendable {
        private(set) var last: String?
        private var rng: SeededRandom

        init(seed: UInt64 = UInt64.random(in: 1...UInt64.max)) {
            rng = SeededRandom(seed: seed)
        }

        mutating func next(from pool: [String]) -> String {
            let choices = pool.count > 1 ? pool.filter { $0 != last } : pool
            let line = choices.randomElement(using: &rng) ?? ""
            last = line
            return line
        }
    }
}
