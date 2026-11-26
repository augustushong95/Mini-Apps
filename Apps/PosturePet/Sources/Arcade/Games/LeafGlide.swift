import SwiftUI

/// Mochi rides a falling leaf. Tilting the head left and right steers;
/// dewdrops are treats, thorny twigs are to be avoided, and "breeze lanes"
/// down either edge reward holding a tilt for a couple of seconds.
nonisolated struct LeafGlide: GameSimulation {
    static let duration: TimeInterval = 60

    struct Item: Sendable {
        enum Kind: Sendable { case dew, thorn }
        var kind: Kind
        var position: CGPoint
        var radius: CGFloat { kind == .dew ? 11 : 17 }
    }

    struct Breeze: Sendable {
        var x: CGFloat
        var top: CGFloat
        var height: CGFloat
    }

    private(set) var elapsed: TimeInterval = 0
    private(set) var score = 0
    private(set) var stats = StretchStats()
    var events: [GameEvent] = []

    private(set) var mochiX: CGFloat = World.width / 2
    private var mochiVelocity: CGFloat = 0
    private(set) var items: [Item] = []
    private(set) var breezes: [Breeze] = []
    private var particles: [Particle] = []
    private var rng: SeededRandom
    private var spawnIn: TimeInterval = 0.9
    private var breezeIn: TimeInterval = 7
    private var breezeSide: CGFloat = -1
    private var hurtFor: TimeInterval = 0
    private var happyFor: TimeInterval = 0
    /// −1, 0 or 1: which side the head is tilted to, for counting tilts.
    private var tiltSide = 0
    private var steer: Double = 0
    private let stage: GrowthStage

    static let mochiY: CGFloat = 132
    static let mochiRadius: CGFloat = 26

    init(seed: UInt64, stage: GrowthStage) {
        rng = SeededRandom(seed: seed)
        self.stage = stage
    }

    private var speed: CGFloat {
        140 + CGFloat(elapsed) * 0.9
    }

    mutating func step(dt: TimeInterval, input: GameInput) {
        guard !isFinished else { return }
        elapsed += dt
        steer = input.steer

        // A critically damped spring toward the steered position: responsive,
        // never jerky.
        let target = World.width / 2 + CGFloat(input.steer) * 250
        let stiffness: CGFloat = 70
        let damping = 2 * sqrt(stiffness)
        mochiVelocity += (stiffness * (target - mochiX) - damping * mochiVelocity) * dt
        mochiX = min(max(mochiX + mochiVelocity * dt, 60), World.width - 60)

        // A tilt counts when the head reaches a side it wasn't on, so going
        // straight from right to left is two tilts.
        let side: Int
        if input.steer > 0.65 {
            side = 1
        } else if input.steer < -0.65 {
            side = -1
        } else {
            side = abs(input.steer) < 0.35 ? 0 : tiltSide
        }
        if side != 0, side != tiltSide {
            stats.moves += 1
        }
        tiltSide = side
        if side != 0 {
            stats.heldSeconds += dt
        }

        spawnIn -= dt
        if spawnIn <= 0, elapsed < Self.duration - 2.5 {
            spawnWave()
            spawnIn = Double.random(in: 1.1...1.6, using: &rng)
        }
        breezeIn -= dt
        if breezeIn <= 0, elapsed < Self.duration - 5 {
            spawnBreeze()
            breezeIn = 11
        }

        let rise = speed * dt
        for index in items.indices { items[index].position.y -= rise }
        for index in breezes.indices { breezes[index].top -= rise }
        items.removeAll { $0.position.y < -40 }
        breezes.removeAll { $0.top + $0.height < -20 }

        let mochi = CGPoint(x: mochiX, y: Self.mochiY)
        var kept: [Item] = []
        for item in items {
            guard distance(item.position, mochi) < item.radius + Self.mochiRadius else {
                kept.append(item)
                continue
            }
            switch item.kind {
            case .dew:
                score += 1
                happyFor = 0.4
                events.append(.collect)
                particles += Particle.burst(at: item.position, color: 0x8FD3FF, rng: &rng)
            case .thorn:
                if hurtFor <= 0 {
                    hurtFor = 0.9
                    events.append(.hit)
                }
            }
        }
        items = kept
        hurtFor = max(0, hurtFor - dt)
        happyFor = max(0, happyFor - dt)
        particles.step(dt: dt)
    }

    private mutating func spawnWave() {
        let y = World.height + 30
        let lanes: [CGFloat] = [110, 215, 320, 425, 530]
        if Double.random(in: 0...1, using: &rng) < 0.45 {
            // A thorn in one lane, dew a safe distance away.
            let thornLane = Int.random(in: 0..<lanes.count, using: &rng)
            items.append(Item(kind: .thorn, position: CGPoint(x: lanes[thornLane], y: y)))
            let dewLane = (thornLane + 2 + Int.random(in: 0...1, using: &rng)) % lanes.count
            items.append(Item(kind: .dew, position: CGPoint(x: lanes[dewLane], y: y + 10)))
        } else {
            // A short diagonal of dew to follow.
            let start = Int.random(in: 0...2, using: &rng)
            let direction = Bool.random(using: &rng) ? 1 : -1
            for step in 0..<3 {
                let lane = min(max(start + step * direction + (direction < 0 ? 2 : 0), 0), lanes.count - 1)
                items.append(Item(kind: .dew, position: CGPoint(x: lanes[lane], y: y + CGFloat(step) * 46)))
            }
        }
    }

    private mutating func spawnBreeze() {
        let x = World.width / 2 + breezeSide * 250
        let height: CGFloat = 400
        breezes.append(Breeze(x: x, top: World.height + 20, height: height))
        for index in 0..<8 {
            items.append(Item(kind: .dew, position: CGPoint(x: x, y: World.height + 60 + CGFloat(index) * 44)))
        }
        breezeSide = -breezeSide
    }

    var pose: PetPose {
        var pose = PetMood.happy.pose(stage: stage, posture: nil)
        pose.tilt = steer * 12
        pose.gaze = CGVector(dx: steer * 0.8, dy: -0.3)
        if hurtFor > 0 {
            pose.eyes = .closed
            pose.mouth = .wobble
        } else if happyFor > 0 {
            pose.eyes = .happy
            pose.mouth = .grin
        }
        return pose
    }

    // MARK: Drawing

    @MainActor func draw(in context: GraphicsContext, time: Double) {
        context.fill(Path(CGRect(origin: .zero, size: World.size)), with: .linearGradient(
            Gradient(colors: [Color(hex: 0xDFF4E4), Color(hex: 0xFFF3DF)]),
            startPoint: .zero, endPoint: CGPoint(x: 0, y: World.height)
        ))

        // Clouds drift up, slower than the items, for depth.
        let drift = CGFloat(elapsed) * 30
        for (index, x) in [90.0, 300, 520, 200, 450].enumerated() {
            let y = (CGFloat(index) * 130 - drift).truncatingRemainder(dividingBy: 560)
            GameArt.cloud(at: CGPoint(x: x, y: y < -60 ? y + 560 : y), width: 70 + CGFloat(index % 3) * 18, in: context, opacity: 0.7)
        }

        for breeze in breezes {
            let rect = CGRect(x: breeze.x - 34, y: breeze.top, width: 68, height: breeze.height)
            context.fill(Path(roundedRect: rect, cornerRadius: 34), with: .linearGradient(
                Gradient(colors: [.white.opacity(0), .white.opacity(0.55), .white.opacity(0)]),
                startPoint: CGPoint(x: rect.minX, y: 0), endPoint: CGPoint(x: rect.maxX, y: 0)
            ))
            for line in 0..<5 {
                let ly = breeze.top + CGFloat(line) * 80 + CGFloat((time * 120).truncatingRemainder(dividingBy: 80))
                var streak = Path()
                streak.move(to: CGPoint(x: breeze.x - 12, y: ly))
                streak.addLine(to: CGPoint(x: breeze.x - 12, y: ly + 30))
                context.stroke(streak, with: .color(.white.opacity(0.8)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            }
        }

        for item in items {
            switch item.kind {
            case .dew:
                GameArt.dewdrop(at: item.position, radius: 8, in: context, time: time)
            case .thorn:
                drawThorn(at: item.position, in: context)
            }
        }

        // The leaf under Mochi tips with its motion.
        var leafContext = context
        leafContext.translateBy(x: mochiX, y: Self.mochiY + 20)
        leafContext.rotate(by: .radians(Double(mochiVelocity) * 0.0012 + steer * 0.12))
        let leaf = Path(PetGeometry.leafShape(length: 120, width: 70))
        leafContext.translateBy(x: -60, y: 0)
        leafContext.fill(leaf, with: .linearGradient(
            Gradient(colors: [Color(Palette.leaf), Color(Palette.leafDark)]),
            startPoint: CGPoint(x: 0, y: -30), endPoint: CGPoint(x: 0, y: 30)
        ))
        var vein = Path()
        vein.move(to: CGPoint(x: 12, y: 0))
        vein.addLine(to: CGPoint(x: 105, y: 2))
        leafContext.stroke(vein, with: .color(Color(Palette.leafVein)), style: StrokeStyle(lineWidth: 2, lineCap: .round))

        let blink = hurtFor > 0 && Int(hurtFor * 12).isMultiple(of: 2)
        if !blink {
            PetCanvasRenderer.draw(pose, in: context, foot: CGPoint(x: mochiX, y: Self.mochiY + 28), size: 84)
        }
        particles.draw(in: context)
    }

    @MainActor private func drawThorn(at point: CGPoint, in context: GraphicsContext) {
        var twig = Path()
        twig.move(to: CGPoint(x: point.x - 22, y: point.y + 6))
        twig.addQuadCurve(to: CGPoint(x: point.x + 22, y: point.y - 6), control: CGPoint(x: point.x, y: point.y + 8))
        context.stroke(twig, with: .color(Color(hex: 0x8A5A3B)), style: StrokeStyle(lineWidth: 6, lineCap: .round))
        for offset in [-14.0, -2, 10] {
            var spike = Path()
            let base = CGPoint(x: point.x + offset, y: point.y + 2 - offset * 0.25)
            spike.move(to: CGPoint(x: base.x - 4, y: base.y))
            spike.addLine(to: CGPoint(x: base.x + 2, y: base.y - 12))
            spike.addLine(to: CGPoint(x: base.x + 5, y: base.y))
            spike.closeSubpath()
            context.fill(spike, with: .color(Color(hex: 0x6E4329)))
        }
    }
}
