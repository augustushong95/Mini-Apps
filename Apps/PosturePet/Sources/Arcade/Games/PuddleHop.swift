import SwiftUI

/// A rainy path: a gentle nod makes Mochi hop over puddles and grab the
/// dewdrops floating above them. Puddles never come faster than one every
/// ~1.7 s, so nodding stays slow and comfortable.
nonisolated struct PuddleHop: GameSimulation {
    static let duration: TimeInterval = 60

    struct Puddle: Sendable {
        var x: CGFloat
        var width: CGFloat
        var hasDew: Bool
        var cleared = false
    }

    private(set) var elapsed: TimeInterval = 0
    private(set) var score = 0
    private(set) var stats = StretchStats()
    var events: [GameEvent] = []

    private(set) var height: CGFloat = 0
    private var velocity: CGFloat = 0
    private(set) var puddles: [Puddle] = []
    private var particles: [Particle] = []
    private var rng: SeededRandom
    private var nextPuddleIn: TimeInterval = 1.6
    private var splashFor: TimeInterval = 0
    private var happyFor: TimeInterval = 0
    private var scroll: CGFloat = 0
    private let stage: GrowthStage

    static let mochiX: CGFloat = 160
    static let ground: CGFloat = 318
    static let hopSpeed: CGFloat = 560
    static let gravity: CGFloat = 1500
    static let dewHeight: CGFloat = 78

    init(seed: UInt64, stage: GrowthStage) {
        rng = SeededRandom(seed: seed)
        self.stage = stage
    }

    private var speed: CGFloat {
        190 + CGFloat(elapsed) * 0.8
    }

    var isOnGround: Bool { height <= 0 && velocity <= 0 }

    mutating func step(dt: TimeInterval, input: GameInput) {
        guard !isFinished else { return }
        elapsed += dt

        if input.hop, isOnGround {
            velocity = Self.hopSpeed
            stats.moves += 1
            events.append(.hop)
        }
        velocity -= Self.gravity * dt
        height = max(0, height + velocity * dt)
        if height == 0, velocity < 0 {
            velocity = 0
        }

        let travel = speed * dt
        scroll += travel
        for index in puddles.indices { puddles[index].x -= travel }
        puddles.removeAll { $0.x + $0.width < -20 }

        nextPuddleIn -= dt
        if nextPuddleIn <= 0, elapsed < Self.duration - 2 {
            let width = CGFloat.random(in: 64...96, using: &rng)
            puddles.append(Puddle(x: World.width + 40, width: width, hasDew: Double.random(in: 0...1, using: &rng) < 0.75))
            nextPuddleIn = Double.random(in: 1.7...2.4, using: &rng)
        }

        for index in puddles.indices {
            let puddle = puddles[index]
            let over = abs(puddle.x - Self.mochiX) < puddle.width / 2 - 8
            if over, height < 6, splashFor <= 0, !puddle.cleared {
                splashFor = 0.8
                puddles[index].cleared = true
                puddles[index].hasDew = false
                events.append(.hit)
                particles += Particle.burst(at: CGPoint(x: Self.mochiX, y: Self.ground), color: 0x7CC4F2, rng: &rng)
            }
            let dew = CGPoint(x: puddle.x, y: Self.ground - Self.dewHeight - 24)
            let mochi = CGPoint(x: Self.mochiX, y: Self.ground - height - 28)
            if puddle.hasDew, distance(dew, mochi) < 34 {
                puddles[index].hasDew = false
                score += 1
                happyFor = 0.4
                events.append(.collect)
                particles += Particle.burst(at: dew, color: 0x8FD3FF, rng: &rng)
            }
            if puddle.x + puddle.width / 2 < Self.mochiX - 10, !puddle.cleared {
                puddles[index].cleared = true
            }
        }

        splashFor = max(0, splashFor - dt)
        happyFor = max(0, happyFor - dt)
        particles.step(dt: dt)
    }

    var pose: PetPose {
        var pose = PetMood.happy.pose(stage: stage, posture: nil)
        if splashFor > 0 {
            pose.eyes = .closed
            pose.mouth = .wobble
            pose.accessories = [.sweat]
        } else if happyFor > 0 || height > 20 {
            pose.eyes = .happy
            pose.mouth = .grin
        }
        pose.leafDroop = height > 0 ? 0 : 0.1
        return pose
    }

    // MARK: Drawing

    @MainActor func draw(in context: GraphicsContext, time: Double) {
        context.fill(Path(CGRect(origin: .zero, size: World.size)), with: .linearGradient(
            Gradient(colors: [Color(hex: 0xCFE6F7), Color(hex: 0xEAF3F8)]),
            startPoint: .zero, endPoint: CGPoint(x: 0, y: Self.ground)
        ))
        for (index, x) in [80.0, 330, 560].enumerated() {
            let cx = (CGFloat(x) - scroll * 0.15).truncatingRemainder(dividingBy: 760)
            GameArt.cloud(at: CGPoint(x: cx < -80 ? cx + 760 : cx, y: 60 + CGFloat(index % 2) * 30), width: 110, in: context, opacity: 0.9)
        }
        // Soft rain.
        for index in 0..<36 {
            let x = (CGFloat(index) * 53 + CGFloat(time * 40)).truncatingRemainder(dividingBy: World.width)
            let y = (CGFloat(index * 97) + CGFloat(time * 260)).truncatingRemainder(dividingBy: Self.ground)
            var drop = Path()
            drop.move(to: CGPoint(x: x, y: y))
            drop.addLine(to: CGPoint(x: x - 3, y: y + 12))
            context.stroke(drop, with: .color(Color(hex: 0x8DB9DA).opacity(0.5)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        }

        // Ground.
        let groundRect = CGRect(x: 0, y: Self.ground, width: World.width, height: World.height - Self.ground)
        context.fill(Path(groundRect), with: .linearGradient(
            Gradient(colors: [Color(hex: 0xA8D99A), Color(hex: 0x86C47A)]),
            startPoint: CGPoint(x: 0, y: Self.ground), endPoint: CGPoint(x: 0, y: World.height)
        ))
        for index in 0..<14 {
            let x = (CGFloat(index) * 50 - scroll).truncatingRemainder(dividingBy: 700)
            let tuft = CGPoint(x: x < -20 ? x + 700 : x, y: Self.ground + 4)
            var grass = Path()
            grass.move(to: CGPoint(x: tuft.x - 4, y: tuft.y + 6))
            grass.addLine(to: CGPoint(x: tuft.x, y: tuft.y - 4))
            grass.addLine(to: CGPoint(x: tuft.x + 4, y: tuft.y + 6))
            context.stroke(grass, with: .color(Color(hex: 0x6DAE62)), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }

        for puddle in puddles {
            let rect = CGRect(x: puddle.x - puddle.width / 2, y: Self.ground - 2, width: puddle.width, height: 16)
            context.fill(Path(ellipseIn: rect), with: .linearGradient(
                Gradient(colors: [Color(hex: 0x8CC8F0), Color(hex: 0x5BA6DC)]),
                startPoint: CGPoint(x: 0, y: rect.minY), endPoint: CGPoint(x: 0, y: rect.maxY)
            ))
            let ripple = CGFloat((time * 1.5 + Double(puddle.x) * 0.01).truncatingRemainder(dividingBy: 1))
            context.stroke(
                Path(ellipseIn: rect.insetBy(dx: puddle.width * 0.3 * (1 - ripple), dy: 5 * (1 - ripple))),
                with: .color(.white.opacity(0.6 * (1 - ripple))), lineWidth: 1.2
            )
            if puddle.hasDew {
                GameArt.dewdrop(at: CGPoint(x: puddle.x, y: Self.ground - Self.dewHeight - 24), radius: 8, in: context, time: time)
            }
        }

        // Squash on landing, stretch going up.
        let squash: CGFloat = height > 0 ? (velocity > 0 ? 1.08 : 1.0) : (splashFor > 0.6 ? 0.88 : 1)
        PetCanvasRenderer.draw(pose, in: context, foot: CGPoint(x: Self.mochiX, y: Self.ground + 8 - height), size: 84, squash: squash)
        particles.draw(in: context)
    }
}
