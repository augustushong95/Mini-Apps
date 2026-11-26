import SwiftUI

/// A night sky: looking up floats Mochi up on a balloon to catch falling
/// stars, and letting go drifts it down past the night birds. Stars come
/// in high clusters, so the reward is for holding a gentle upward look,
/// the opposite of a screen-bound "tech neck".
nonisolated struct StarFloat: GameSimulation {
    static let duration: TimeInterval = 60

    struct Item: Sendable {
        enum Kind: Sendable { case star, bird }
        var kind: Kind
        var position: CGPoint
        var spin: Double
    }

    private(set) var elapsed: TimeInterval = 0
    private(set) var score = 0
    private(set) var stats = StretchStats()
    var events: [GameEvent] = []

    /// Mochi's foot height above the ground line.
    private(set) var altitude: CGFloat = 0
    private var climb: CGFloat = 0
    private(set) var items: [Item] = []
    private var particles: [Particle] = []
    private var rng: SeededRandom
    private var spawnIn: TimeInterval = 1
    private var bumpFor: TimeInterval = 0
    private var happyFor: TimeInterval = 0
    private var lifting = false
    private let stage: GrowthStage

    static let mochiX: CGFloat = 180
    static let ground: CGFloat = 352
    static let maxAltitude: CGFloat = 230

    init(seed: UInt64, stage: GrowthStage) {
        rng = SeededRandom(seed: seed)
        self.stage = stage
    }

    private var speed: CGFloat {
        170 + CGFloat(elapsed) * 0.7
    }

    mutating func step(dt: TimeInterval, input: GameInput) {
        guard !isFinished else { return }
        elapsed += dt

        let target = CGFloat(clamp(input.lift)) * Self.maxAltitude
        let stiffness: CGFloat = 26
        let damping = 2 * sqrt(stiffness)
        climb += (stiffness * (target - altitude) - damping * climb) * dt
        altitude = min(max(altitude + climb * dt, 0), Self.maxAltitude)

        if input.lift > 0.6 {
            stats.heldSeconds += dt
            if !lifting {
                lifting = true
                stats.moves += 1
            }
        } else if input.lift < 0.3 {
            lifting = false
        }

        spawnIn -= dt
        if spawnIn <= 0, elapsed < Self.duration - 2.5 {
            spawn()
            spawnIn = Double.random(in: 1.0...1.5, using: &rng)
        }

        for index in items.indices {
            items[index].position.x -= speed * dt
            items[index].spin += dt * (items[index].kind == .star ? 2 : 9)
        }
        items.removeAll { $0.position.x < -40 }

        let mochi = mochiCenter
        var kept: [Item] = []
        for item in items {
            let hitRadius: CGFloat = item.kind == .star ? 40 : 34
            guard distance(item.position, mochi) < hitRadius else {
                kept.append(item)
                continue
            }
            switch item.kind {
            case .star:
                score += 1
                happyFor = 0.4
                events.append(.collect)
                particles += Particle.burst(at: item.position, color: 0xFFD866, rng: &rng)
            case .bird:
                if bumpFor <= 0 {
                    bumpFor = 0.9
                    events.append(.hit)
                }
            }
        }
        items = kept
        bumpFor = max(0, bumpFor - dt)
        happyFor = max(0, happyFor - dt)
        particles.step(dt: dt)
    }

    var mochiCenter: CGPoint {
        CGPoint(x: Self.mochiX, y: Self.ground - altitude - 30)
    }

    private mutating func spawn() {
        let x = World.width + 30
        let high = Self.ground - Self.maxAltitude - 30
        if Double.random(in: 0...1, using: &rng) < 0.65 {
            // A little arc of stars, mostly up high.
            let base = Double.random(in: 0...1, using: &rng) < 0.75
                ? CGFloat.random(in: high...(high + 60), using: &rng)
                : CGFloat.random(in: (Self.ground - 120)...(Self.ground - 50), using: &rng)
            for index in 0..<3 {
                let y = base + CGFloat(abs(index - 1)) * 14
                items.append(Item(kind: .star, position: CGPoint(x: x + CGFloat(index) * 42, y: y), spin: 0))
            }
        } else {
            // A bird low or in the middle, always leaving room above or below.
            let y = Bool.random(using: &rng)
                ? CGFloat.random(in: (Self.ground - 90)...(Self.ground - 40), using: &rng)
                : CGFloat.random(in: (Self.ground - 190)...(Self.ground - 140), using: &rng)
            items.append(Item(kind: .bird, position: CGPoint(x: x, y: y), spin: 0))
        }
    }

    var pose: PetPose {
        var pose = PetMood.happy.pose(stage: stage, posture: nil)
        pose.gaze = CGVector(dx: 0.3, dy: Double(altitude / Self.maxAltitude) * 0.9)
        if bumpFor > 0 {
            pose.eyes = .closed
            pose.mouth = .oh
        } else if happyFor > 0 {
            pose.eyes = .happy
            pose.mouth = .grin
        }
        return pose
    }

    // MARK: Drawing

    @MainActor func draw(in context: GraphicsContext, time: Double) {
        context.fill(Path(CGRect(origin: .zero, size: World.size)), with: .linearGradient(
            Gradient(colors: [Color(hex: 0x1F2350), Color(hex: 0x4A4C8C)]),
            startPoint: .zero, endPoint: CGPoint(x: 0, y: World.height)
        ))
        // Twinkling backdrop.
        for index in 0..<44 {
            let x = (CGFloat(index * 137 % 640) - CGFloat(elapsed) * 8).truncatingRemainder(dividingBy: World.width)
            let y = CGFloat(index * 71 % 300)
            let twinkle = 0.4 + 0.6 * abs(sin(time * 1.3 + Double(index)))
            let r: CGFloat = index.isMultiple(of: 5) ? 1.8 : 1.1
            context.fill(Path(ellipseIn: CGRect(x: (x < 0 ? x + World.width : x) - r, y: y - r, width: r * 2, height: r * 2)),
                         with: .color(.white.opacity(twinkle)))
        }
        // A crescent moon, cut out rather than painted over so the sky shows through.
        context.drawLayer { layer in
            layer.fill(Path(ellipseIn: CGRect(x: 540, y: 34, width: 54, height: 54)), with: .color(Color(hex: 0xFFEBAE)))
            layer.blendMode = .destinationOut
            layer.fill(Path(ellipseIn: CGRect(x: 556, y: 26, width: 50, height: 50)), with: .color(.black))
        }

        // Hills.
        var hills = Path()
        hills.move(to: CGPoint(x: 0, y: Self.ground))
        hills.addCurve(to: CGPoint(x: World.width, y: Self.ground - 10),
                       control1: CGPoint(x: 200, y: Self.ground - 50), control2: CGPoint(x: 420, y: Self.ground + 30))
        hills.addLine(to: CGPoint(x: World.width, y: World.height))
        hills.addLine(to: CGPoint(x: 0, y: World.height))
        hills.closeSubpath()
        context.fill(hills, with: .color(Color(hex: 0x2E3E62)))

        for item in items {
            switch item.kind {
            case .star:
                GameArt.star(at: item.position, radius: 12, rotation: item.spin, in: context)
            case .bird:
                drawBird(at: item.position, flap: sin(item.spin), in: context)
            }
        }

        // Balloon on a string.
        let center = mochiCenter
        let balloon = CGPoint(x: center.x + 12, y: center.y - 78)
        var string = Path()
        string.move(to: CGPoint(x: center.x + 4, y: center.y - 22))
        string.addQuadCurve(to: CGPoint(x: balloon.x, y: balloon.y + 26), control: CGPoint(x: center.x + 20, y: center.y - 44))
        context.stroke(string, with: .color(.white.opacity(0.7)), lineWidth: 1.2)
        let balloonRect = CGRect(x: balloon.x - 22, y: balloon.y - 26, width: 44, height: 52)
        context.fill(Path(ellipseIn: balloonRect), with: .linearGradient(
            Gradient(colors: [Color(hex: 0xFFB2C8), Color(hex: 0xFF7FA3)]),
            startPoint: CGPoint(x: balloonRect.minX, y: balloonRect.minY), endPoint: CGPoint(x: balloonRect.maxX, y: balloonRect.maxY)
        ))
        context.fill(Path(ellipseIn: CGRect(x: balloon.x - 12, y: balloon.y - 18, width: 9, height: 14)), with: .color(.white.opacity(0.6)))

        let blink = bumpFor > 0 && Int(bumpFor * 12).isMultiple(of: 2)
        if !blink {
            PetCanvasRenderer.draw(pose, in: context, foot: CGPoint(x: center.x, y: center.y + 30), size: 80)
        }
        particles.draw(in: context)
    }

    @MainActor private func drawBird(at point: CGPoint, flap: Double, in context: GraphicsContext) {
        var body = Path(ellipseIn: CGRect(x: point.x - 14, y: point.y - 8, width: 28, height: 16))
        body.addEllipse(in: CGRect(x: point.x - 20, y: point.y - 10, width: 14, height: 13))
        context.fill(body, with: .color(Color(hex: 0x15173A)))
        var wing = Path()
        wing.move(to: CGPoint(x: point.x - 4, y: point.y - 2))
        wing.addQuadCurve(to: CGPoint(x: point.x + 14, y: point.y - 2 - CGFloat(flap) * 16),
                          control: CGPoint(x: point.x + 2, y: point.y - 16 * CGFloat(flap)))
        wing.addLine(to: CGPoint(x: point.x + 8, y: point.y + 2))
        wing.closeSubpath()
        context.fill(wing, with: .color(Color(hex: 0x23264F)))
        context.fill(Path(ellipseIn: CGRect(x: point.x - 15, y: point.y - 6, width: 4, height: 4)), with: .color(Color(hex: 0xFFD866)))
        var beak = Path()
        beak.move(to: CGPoint(x: point.x - 20, y: point.y - 4))
        beak.addLine(to: CGPoint(x: point.x - 27, y: point.y - 1))
        beak.addLine(to: CGPoint(x: point.x - 20, y: point.y + 1))
        context.fill(beak, with: .color(Color(hex: 0xF2B43A)))
    }
}
