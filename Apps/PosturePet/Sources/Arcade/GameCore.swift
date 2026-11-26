import SwiftUI

/// What the player is doing this frame, from the head or the keyboard.
nonisolated struct GameInput: Sendable, Equatable {
    /// −1 is full left, 1 is full right (Leaf Glide).
    var steer: Double = 0
    /// True for the one step a hop is triggered (Puddle Hop).
    var hop = false
    /// 0 is resting, 1 is looking fully up (Star Float).
    var lift: Double = 0
}

/// The stretching the player did, shown on the results card.
nonisolated struct StretchStats: Sendable, Equatable {
    var moves = 0
    var heldSeconds: Double = 0
}

nonisolated enum GameEvent: Sendable, Equatable {
    case collect, hit, hop
}

nonisolated struct GameResult: Sendable, Equatable {
    var score: Int
    var treats: Int
    var stats: StretchStats
    /// Played (nearly) to the end.
    var completed: Bool
    /// Completed after a long enough sit to add to the day's breaks.
    var countsAsBreak = false
}

/// A Neck Arcade game: a deterministic simulation stepped at a fixed rate
/// in a 640 × 400 world (y down), plus how to draw it.
nonisolated protocol GameSimulation: Sendable {
    static var duration: TimeInterval { get }
    var elapsed: TimeInterval { get }
    var score: Int { get }
    var stats: StretchStats { get }
    /// Events since the last `drainEvents()`, for sounds and haptics.
    var events: [GameEvent] { get set }
    /// Mochi's pose this frame.
    var pose: PetPose { get }
    init(seed: UInt64, stage: GrowthStage)
    mutating func step(dt: TimeInterval, input: GameInput)
    /// Drawing happens on the main actor, inside a SwiftUI `Canvas`.
    @MainActor func draw(in context: GraphicsContext, time: Double)
}

extension GameSimulation {
    nonisolated var isFinished: Bool { elapsed >= Self.duration }
    nonisolated var remaining: TimeInterval { max(0, Self.duration - elapsed) }
}

nonisolated enum World {
    static let width: CGFloat = 640
    static let height: CGFloat = 400
    static let size = CGSize(width: width, height: height)
}

/// SplitMix64: a small, fast, seedable generator so games are reproducible
/// (and testable).
nonisolated struct SeededRandom: RandomNumberGenerator, Sendable {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// A short-lived sparkle.
nonisolated struct Particle: Sendable {
    var position: CGPoint
    var velocity: CGVector
    var life: Double
    var maxLife: Double
    var color: UInt32

    static func burst(at point: CGPoint, color: UInt32, count: Int = 8, rng: inout SeededRandom) -> [Particle] {
        (0..<count).map { index in
            let angle = Double(index) / Double(count) * 2 * .pi + Double.random(in: 0...0.4, using: &rng)
            let speed = Double.random(in: 70...140, using: &rng)
            return Particle(
                position: point,
                velocity: CGVector(dx: cos(angle) * speed, dy: sin(angle) * speed),
                life: 0.5, maxLife: 0.5, color: color
            )
        }
    }
}

extension [Particle] {
    nonisolated mutating func step(dt: TimeInterval) {
        for index in indices {
            self[index].position.x += self[index].velocity.dx * dt
            self[index].position.y += self[index].velocity.dy * dt
            self[index].velocity.dx *= 0.92
            self[index].velocity.dy *= 0.92
            self[index].life -= dt
        }
        removeAll { $0.life <= 0 }
    }

    @MainActor func draw(in context: GraphicsContext) {
        for particle in self {
            let t = particle.life / particle.maxLife
            let r = 2 + 3 * t
            context.fill(
                Path(PetGeometry.sparkle(radius: r)).offsetBy(dx: particle.position.x, dy: particle.position.y),
                with: .color(Color(hex: particle.color).opacity(t))
            )
        }
    }
}

nonisolated func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
    hypot(a.x - b.x, a.y - b.y)
}

/// Shared drawing helpers for game items.
enum GameArt {
    static func dewdrop(at point: CGPoint, radius r: CGFloat, in context: GraphicsContext, time: Double) {
        var ctx = context
        ctx.translateBy(x: point.x, y: point.y + sin(time * 4 + point.x) * 2)
        ctx.scaleBy(x: 1, y: -1)
        let drop = Path(PetGeometry.sweatDrop(radius: r))
        ctx.fill(drop, with: .linearGradient(
            Gradient(colors: [Color(hex: 0xC8ECFF), Color(hex: 0x6EC1F5)]),
            startPoint: CGPoint(x: 0, y: r * 1.7), endPoint: CGPoint(x: 0, y: -r)
        ))
        ctx.stroke(drop, with: .color(.white.opacity(0.8)), lineWidth: 1.2)
        ctx.fill(Path(ellipseIn: CGRect(x: -r * 0.45, y: 0, width: r * 0.4, height: r * 0.55)), with: .color(.white.opacity(0.85)))
    }

    static func star(at point: CGPoint, radius r: CGFloat, rotation: Double, in context: GraphicsContext) {
        var path = Path()
        for index in 0..<10 {
            let angle = Double(index) * .pi / 5 - .pi / 2 + rotation
            let radius = index.isMultiple(of: 2) ? r : r * 0.48
            let p = CGPoint(x: point.x + cos(angle) * radius, y: point.y + sin(angle) * radius)
            index == 0 ? path.move(to: p) : path.addLine(to: p)
        }
        path.closeSubpath()
        context.fill(path, with: .color(Color(hex: 0xFFD866)))
        context.stroke(path, with: .color(Color(hex: 0xF2B43A)), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
    }

    static func cloud(at point: CGPoint, width w: CGFloat, in context: GraphicsContext, opacity: Double = 0.85) {
        let h = w * 0.36
        var path = Path(roundedRect: CGRect(x: point.x - w / 2, y: point.y - h * 0.2, width: w, height: h * 0.62), cornerRadius: h * 0.31)
        path.addEllipse(in: CGRect(x: point.x - w * 0.3, y: point.y - h * 0.62, width: h * 0.85, height: h * 0.85))
        path.addEllipse(in: CGRect(x: point.x - w * 0.02, y: point.y - h * 0.82, width: h, height: h))
        context.fill(path, with: .color(.white.opacity(opacity)))
    }
}
