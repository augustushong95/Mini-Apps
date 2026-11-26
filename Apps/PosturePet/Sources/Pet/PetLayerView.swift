import AppKit
import QuartzCore

/// Mochi drawn with Core Animation layers.
///
/// Idle motion (breathing, blinking, leaf sway) runs as layer animations in
/// the render server, so an always-visible Mochi costs almost no CPU. Pose
/// changes spring from wherever the current animation is, so a stream of
/// posture updates reads as smooth movement.
///
/// On top of that Mochi performs acts (`PetAct`): short scripted moves with a
/// temporary face and effects. Every 12–35 s it picks one that suits its mood
/// by itself; reactions to events come from outside through `perform(_:)`.
/// Everything pauses while the window is hidden and respects Reduce Motion.
final class PetLayerView: NSView {
    /// The pose from the engine (posture mirroring, mood). Acts lay a
    /// temporary face over it without replacing it.
    private(set) var pose = PetPose()

    /// The mood whose idle acts Mochi picks from.
    var mood: PetMood = .happy

    /// The act playing now, if any.
    private(set) var currentAct: PetAct?

    /// Turn off for static renders (icons, snapshots).
    var idleAnimationsEnabled = true {
        didSet { updateIdleAnimations() }
    }

    // Transform stack, outermost first. Each layer owns one kind of motion so
    // animations never fight over the same transform.
    private let canvas = CALayer()
    private let groundShadow = CAGradientLayer()
    private let hopLayer = CALayer()      // jumps, rocking, leaning, shivers
    private let spinLayer = CALayer()     // rolls and turnarounds, around Mochi's middle
    private let squashLayer = CALayer()   // squash and stretch
    private let breathLayer = CALayer()   // idle breathing
    /// Hearts, notes, "!", "?" and friends; above Mochi and not transformed.
    private let effectsLayer = CALayer()

    private let sprout = CALayer()
    private let stem = CAShapeLayer()
    private let leaves = CAShapeLayer()
    private let veins = CAShapeLayer()
    private let bud = CAShapeLayer()
    private let petals = CAShapeLayer()
    private let flowerCenter = CAShapeLayer()

    // No layer masks anywhere: `CALayer.render(in:)` ignores them, and mask-free
    // layers keep debug snapshots and the app icon identical to the screen.
    private let bodyBase = CAShapeLayer()
    private let bodyGlow = CAGradientLayer()
    private let bodyShade = CAGradientLayer()
    private let outline = CAShapeLayer()
    private let highlight = CAShapeLayer()
    private let blushes = [CAGradientLayer(), CAGradientLayer()]
    private let eyes = [EyeLayers(), EyeLayers()]

    private let mouth = CALayer()
    private let mouthStroke = CAShapeLayer()
    private let mouthFill = CAShapeLayer()
    private let tongue = CAShapeLayer()

    private let sweat = CAShapeLayer()
    private let thermometer = CALayer()
    private let thermometerStick = CAShapeLayer()
    private let thermometerBulb = CAShapeLayer()
    private let crownLayer = CALayer()
    private let crownBand = CAShapeLayer()
    private let crownJewels = CAShapeLayer()
    private let sparkles = [CAShapeLayer(), CAShapeLayer(), CAShapeLayer()]
    private let zees = [CAShapeLayer(), CAShapeLayer(), CAShapeLayer()]

    private var side: CGFloat = 0
    /// What's on screen: `pose` with the current act's face laid over it.
    private var renderedPose = PetPose()
    private var faceOverlay: PetFace?
    private var director = BehaviorDirector()
    private var stillEffects = false
    private var idleTimer: Timer?
    private var actWork: [DispatchWorkItem] = []
    private var blinkTimer: Timer?
    private var isVisibleOnScreen = false
    private var reduceMotionObserver: NSObjectProtocol?
    private var occlusionObserver: NSObjectProtocol?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // Layer-hosting: the layer is assigned before `wantsLayer`, so AppKit
        // never replaces it or touches its sublayers.
        let root = CALayer()
        root.masksToBounds = false
        layer = root
        wantsLayer = true
        buildLayers()

        reduceMotionObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateIdleAnimations() }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        // Views are released on the main thread.
        MainActor.assumeIsolated {
            blinkTimer?.invalidate()
            idleTimer?.invalidate()
            actWork.forEach { $0.cancel() }
            if let reduceMotionObserver {
                NSWorkspace.shared.notificationCenter.removeObserver(reduceMotionObserver)
            }
            if let occlusionObserver {
                NotificationCenter.default.removeObserver(occlusionObserver)
            }
        }
    }

    override var isFlipped: Bool { false }
    override var wantsUpdateLayer: Bool { true }

    // MARK: Public API

    /// Moves Mochi to `pose`, springing there when `animated`.
    func apply(_ pose: PetPose, animated: Bool = true) {
        self.pose = pose
        if side == 0 {
            layoutCanvas()
        }
        guard side > 0 else { return }
        refresh(animated: animated && window != nil)
    }

    /// Performs an act now, replacing any act already playing.
    func perform(_ act: PetAct) {
        guard side > 0 else { return }
        cancelAct()
        let script = act.script
        currentAct = act
        for face in script.faces {
            schedule(after: face.at) { [weak self] in self?.setFace(face.value) }
        }
        if !reduceMotion {
            for (index, motion) in script.motions.enumerated() {
                play(motion.value, delay: motion.at, key: "act.\(index)")
            }
        }
        for effect in script.effects {
            schedule(after: effect.at) { [weak self] in self?.emit(effect.value) }
        }
        schedule(after: script.duration) { [weak self] in
            self?.currentAct = nil
            self?.setFace(nil)
        }
    }

    /// A quick hop (a desktop-pet click, for instance).
    func hop(height: CGFloat = 0.14) {
        guard side > 0, !reduceMotion else { return }
        play(.hop(height: Double(height), duration: 0.62), delay: 0, key: "hop")
    }

    /// Holds a face until `nil` (the desktop pet while it's being dragged).
    func hold(_ face: PetFace?) {
        cancelAct()
        setFace(face)
    }

    // MARK: Layout

    override func layout() {
        super.layout()
        layoutCanvas()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsLayout = true
    }

    /// Fits the square canvas into the bounds. Also called directly when a
    /// pose arrives before the first layout pass (views outside a window).
    private func layoutCanvas() {
        let newSide = min(bounds.width, bounds.height)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        canvas.frame = CGRect(
            x: (bounds.width - newSide) / 2,
            y: (bounds.height - newSide) / 2,
            width: newSide,
            height: newSide
        )
        CATransaction.commit()
        if newSide != side {
            side = newSide
            renderedPose = faceOverlay?.applied(to: pose) ?? pose
            render(renderedPose, previous: renderedPose, animated: false)
            updateIdleAnimations()
        }
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let scale = window?.backingScaleFactor ?? 2
        allLayers.forEach { $0.contentsScale = scale }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let occlusionObserver {
            NotificationCenter.default.removeObserver(occlusionObserver)
            self.occlusionObserver = nil
        }
        if let window {
            occlusionObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification,
                object: window, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateIdleAnimations() }
            }
        }
        viewDidChangeBackingProperties()
        updateIdleAnimations()
    }

    // MARK: Building

    private var allLayers: [CALayer] {
        [canvas, groundShadow, hopLayer, spinLayer, squashLayer, breathLayer, effectsLayer, sprout, stem, leaves, veins, bud, petals,
         flowerCenter, bodyBase, bodyGlow, bodyShade, outline, highlight, mouth, mouthStroke, mouthFill,
         tongue, sweat, thermometer, thermometerStick, thermometerBulb, crownLayer, crownBand, crownJewels]
            + blushes + sparkles + zees + eyes.flatMap(\.all)
    }

    private func buildLayers() {
        guard let root = layer else { return }
        root.addSublayer(canvas)

        groundShadow.type = .radial
        groundShadow.colors = [NSColor.black.withAlphaComponent(0.16).cgColor, NSColor.black.withAlphaComponent(0).cgColor]
        groundShadow.startPoint = CGPoint(x: 0.5, y: 0.5)
        groundShadow.endPoint = CGPoint(x: 1, y: 1)
        canvas.addSublayer(groundShadow)

        canvas.addSublayer(hopLayer)
        hopLayer.addSublayer(spinLayer)
        spinLayer.addSublayer(squashLayer)
        squashLayer.addSublayer(breathLayer)

        // The sprout sits behind the body so its stem grows out of the dome.
        breathLayer.addSublayer(sprout)
        for shape in [stem, veins] {
            shape.fillColor = nil
            shape.lineCap = .round
            shape.lineJoin = .round
        }
        stem.strokeColor = Palette.leafDark.cgColor
        veins.strokeColor = Palette.leafVein.withAlphaComponent(0.9).cgColor
        petals.fillColor = Palette.petal.cgColor
        flowerCenter.fillColor = Palette.petalCenter.cgColor
        bud.fillColor = Palette.bud.cgColor
        [stem, leaves, veins, bud, petals, flowerCenter].forEach(sprout.addSublayer)

        breathLayer.addSublayer(bodyBase)
        // Soft light on the dome and shade low on one side give Mochi volume.
        // Both fade to clear before the silhouette's edge.
        for glow in [bodyGlow, bodyShade] {
            glow.type = .radial
            glow.startPoint = CGPoint(x: 0.5, y: 0.5)
            glow.endPoint = CGPoint(x: 1, y: 1)
            glow.locations = [0, 0.55, 1]
            breathLayer.addSublayer(glow)
        }
        bodyShade.colors = [
            Palette.mochiOutline.withAlphaComponent(0.3).cgColor,
            Palette.mochiOutline.withAlphaComponent(0.12).cgColor,
            Palette.mochiOutline.withAlphaComponent(0).cgColor,
        ]

        outline.fillColor = nil
        outline.strokeColor = Palette.mochiOutline.withAlphaComponent(0.72).cgColor
        breathLayer.addSublayer(outline)

        highlight.fillColor = NSColor.white.withAlphaComponent(0.75).cgColor
        breathLayer.addSublayer(highlight)

        for blush in blushes {
            blush.type = .radial
            blush.colors = [Palette.blush.withAlphaComponent(0.75).cgColor, Palette.blush.withAlphaComponent(0).cgColor]
            blush.startPoint = CGPoint(x: 0.5, y: 0.5)
            blush.endPoint = CGPoint(x: 1, y: 1)
            breathLayer.addSublayer(blush)
        }

        for eye in eyes {
            eye.iris.fillColor = Palette.ink.cgColor
            eye.shine.fillColor = NSColor.white.cgColor
            eye.arc.fillColor = nil
            eye.arc.strokeColor = Palette.ink.cgColor
            eye.arc.lineCap = .round
            [eye.iris, eye.shine, eye.arc].forEach(eye.container.addSublayer)
            breathLayer.addSublayer(eye.container)
        }

        mouthStroke.fillColor = nil
        mouthStroke.strokeColor = Palette.ink.cgColor
        mouthStroke.lineCap = .round
        mouthStroke.lineJoin = .round
        mouthFill.fillColor = Palette.ink.cgColor
        tongue.fillColor = NSColor(hex: 0xFF8C96).cgColor
        [mouthFill, tongue, mouthStroke].forEach(mouth.addSublayer)
        breathLayer.addSublayer(mouth)

        sweat.fillColor = Palette.sweat.cgColor
        sweat.strokeColor = NSColor.white.withAlphaComponent(0.8).cgColor
        breathLayer.addSublayer(sweat)

        thermometerStick.fillColor = NSColor.white.cgColor
        thermometerStick.strokeColor = NSColor(hex: 0xD9CFC8).cgColor
        thermometerBulb.fillColor = Palette.thermometerBulb.cgColor
        [thermometerStick, thermometerBulb].forEach(thermometer.addSublayer)
        breathLayer.addSublayer(thermometer)

        crownBand.fillColor = Palette.gold.cgColor
        crownBand.strokeColor = Palette.goldDark.cgColor
        crownBand.lineJoin = .round
        crownJewels.fillColor = NSColor(hex: 0xFF7D6E).cgColor
        [crownBand, crownJewels].forEach(crownLayer.addSublayer)
        breathLayer.addSublayer(crownLayer)

        for sparkle in sparkles {
            sparkle.fillColor = Palette.gold.cgColor
            sparkle.opacity = 0
            breathLayer.addSublayer(sparkle)
        }
        for z in zees {
            z.fillColor = nil
            // Lavender reads on light and dark backgrounds alike.
            z.strokeColor = NSColor(hex: 0x8E86E8).cgColor
            z.lineCap = .round
            z.lineJoin = .round
            canvas.addSublayer(z)
        }
        canvas.addSublayer(effectsLayer)
    }

    // MARK: Rendering

    private func render(_ pose: PetPose, previous: PetPose, animated: Bool) {
        let s = side
        let layout = PetGeometry.layout(for: pose, size: s)
        let pivot = CGPoint(x: layout.pivot.x / s, y: layout.pivot.y / s)

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        for container in [hopLayer, squashLayer, breathLayer] {
            container.bounds = CGRect(x: 0, y: 0, width: s, height: s)
            container.anchorPoint = pivot
            container.position = layout.pivot
        }
        // Rolls and turns happen around Mochi's middle, not its base.
        let middle = CGPoint(x: layout.centerX, y: layout.base + layout.bodyHeight * 0.5)
        spinLayer.bounds = CGRect(x: 0, y: 0, width: s, height: s)
        spinLayer.anchorPoint = CGPoint(x: middle.x / s, y: middle.y / s)
        spinLayer.position = middle
        effectsLayer.frame = CGRect(x: 0, y: 0, width: s, height: s)

        // Shadow follows the body's width; it doesn't tilt.
        set(groundShadow, \.bounds, CGRect(origin: .zero, size: layout.shadowRect.size), animated)
        set(groundShadow, \.position, CGPoint(x: layout.shadowRect.midX, y: layout.shadowRect.midY), animated)

        // Leaning is drawn into the shapes (see PetGeometry); only the sprout
        // rotates, following the dome.
        setValue(sprout, keyPath: "transform.rotation.z", to: Double(layout.sproutRotation), animated: animated)

        // Body.
        setPath(bodyBase, layout.body, animated)
        setPath(outline, layout.body, animated)
        outline.lineWidth = s * 0.013
        setPath(highlight, layout.highlight, animated)
        let w = layout.bodyWidth
        let h = layout.bodyHeight
        set(bodyGlow, \.bounds, CGRect(x: 0, y: 0, width: w * 0.84, height: h * 0.74), animated)
        set(bodyGlow, \.position, CGPoint(x: layout.centerX - w * 0.04, y: layout.base + h * 0.6), animated)
        set(bodyShade, \.bounds, CGRect(x: 0, y: 0, width: w * 0.7, height: h * 0.42), animated)
        set(bodyShade, \.position, CGPoint(x: layout.centerX + w * 0.16, y: layout.base + h * 0.2), animated)

        let pale = CGFloat(clamp(pose.paleness))
        let baseColor = Palette.mochiBottom.mixed(with: Palette.mochiPaleBottom, pale)
        let glowColor = Palette.mochiTop.mixed(with: Palette.mochiPaleTop, pale)
        setValue(bodyBase, keyPath: "fillColor", to: baseColor.cgColor, animated: animated, spring: false)
        let glowColors = [
            glowColor.cgColor,
            glowColor.withAlphaComponent(0.75).cgColor,
            glowColor.withAlphaComponent(0).cgColor,
        ]
        setValue(bodyGlow, keyPath: "colors", to: glowColors, animated: animated, spring: false)

        // Blush.
        for (blush, center) in zip(blushes, layout.blushCenters) {
            set(blush, \.bounds, CGRect(origin: .zero, size: layout.blushSize), animated)
            set(blush, \.position, center, animated)
            setValue(blush, keyPath: "opacity", to: Float(clamp(pose.blush) * (1 - Double(pale) * 0.6)), animated: animated, spring: false)
        }

        renderEyes(pose, previous: previous, layout: layout, animated: animated)
        renderMouth(pose, previous: previous, layout: layout, animated: animated)
        renderSprout(pose, previous: previous, layout: layout, animated: animated)
        renderAccessories(pose, previous: previous, layout: layout, animated: animated)

        CATransaction.commit()
    }

    private func renderEyes(_ pose: PetPose, previous: PetPose, layout: PetLayout, animated: Bool) {
        let size = layout.eyeSize
        let shapes = PetGeometry.eyeShapes(for: pose.eyes)
        let previousShapes = PetGeometry.eyeShapes(for: previous.eyes)
        for (index, (eye, center)) in zip(eyes, layout.eyeCenters).enumerated() {
            let shape = shapes[index]
            let sameShape = shape == previousShapes[index]
            set(eye.container, \.position, center, animated)

            var showsShine = false
            switch shape {
            case .round(let scale):
                let fill = PetGeometry.eyeFill(shape, size: size, openness: max(pose.eyeOpenness, 0.12))
                sameShape ? setPath(eye.iris, fill, animated) : (eye.iris.path = fill)
                let shineSize = CGSize(width: size.width * scale, height: size.height * scale)
                let shine = PetGeometry.eyeHighlights(size: shineSize, openness: pose.eyeOpenness, gaze: pose.gaze)
                sameShape ? setPath(eye.shine, shine, animated) : (eye.shine.path = shine)
                showsShine = pose.eyeOpenness > 0.3
            case .star:
                eye.iris.path = PetGeometry.eyeFill(shape, size: size, openness: 1)
            case .happyArc, .closedArc, .spiral:
                eye.arc.path = PetGeometry.eyeStroke(shape, size: size)
                eye.arc.lineWidth = PetGeometry.eyeStrokeWidth(size: size) * (shape == .spiral ? 0.5 : 1)
            }
            let filled = !shape.isStroked
            setValue(eye.iris, keyPath: "opacity", to: Float(filled ? 1 : 0), animated: animated, spring: false, duration: 0.12)
            setValue(eye.shine, keyPath: "opacity", to: Float(showsShine ? 1 : 0), animated: animated, spring: false, duration: 0.12)
            setValue(eye.arc, keyPath: "opacity", to: Float(filled ? 0 : 1), animated: animated, spring: false, duration: 0.12)
        }
        if animated, pose.eyes != previous.eyes {
            // Changing expression reads best as a tiny blink.
            blink(duration: 0.16)
        }
    }

    private func renderMouth(_ pose: PetPose, previous: PetPose, layout: PetLayout, animated: Bool) {
        set(mouth, \.position, layout.mouthCenter, animated)
        let shapes = PetGeometry.mouth(pose.mouth, width: layout.mouthWidth)
        mouthStroke.lineWidth = PetGeometry.mouthStrokeWidth(width: layout.mouthWidth)
        if pose.mouth == previous.mouth {
            if let stroke = shapes.stroke { setPath(mouthStroke, stroke, animated) }
            if let fill = shapes.fill { setPath(mouthFill, fill, animated) }
        } else {
            mouthStroke.path = shapes.stroke
            mouthFill.path = shapes.fill
            if animated {
                let pop = CASpringAnimation(keyPath: "transform.scale")
                pop.fromValue = 0.6
                pop.toValue = 1
                pop.stiffness = 320
                pop.damping = 16
                pop.duration = pop.settlingDuration
                mouth.add(pop, forKey: "pop")
            }
        }
        tongue.path = shapes.tongue
        // Hidden while the thermometer is in.
        mouth.opacity = pose.accessories.contains(.thermometer) && pose.mouth != .wobble ? 0 : 1
    }

    private func renderSprout(_ pose: PetPose, previous: PetPose, layout: PetLayout, animated: Bool) {
        let s = side
        let shapes = PetGeometry.sprout(stage: pose.stage, droop: pose.leafDroop, size: s)
        let sameStage = pose.stage == previous.stage
        let animatePaths = animated && sameStage

        // The stem base sits just inside the dome.
        set(sprout, \.position, CGPoint(x: layout.crown.x, y: layout.crown.y - s * 0.018), animated)
        setPath(stem, shapes.stem, animatePaths)
        stem.lineWidth = shapes.stemWidth
        setPath(leaves, shapes.leaves, animatePaths)
        setPath(veins, shapes.veins, animatePaths)
        veins.lineWidth = shapes.veinWidth
        bud.path = shapes.bud
        petals.path = shapes.petals
        flowerCenter.path = shapes.flowerCenter
        if let budPath = shapes.bud, animatePaths { setPath(bud, budPath, true) }
        if let petalPath = shapes.petals, animatePaths { setPath(petals, petalPath, true) }
        if let centerPath = shapes.flowerCenter, animatePaths { setPath(flowerCenter, centerPath, true) }

        let wilt = CGFloat(max(clamp(pose.paleness) * 0.8, clamp(pose.leafDroop) * 0.35))
        setValue(leaves, keyPath: "fillColor", to: Palette.leaf.mixed(with: Palette.leafWilted, wilt).cgColor, animated: animated, spring: false)

        if animated, !sameStage, pose.stage > previous.stage {
            // Growing up: the sprout pops in and Mochi sparkles.
            let grow = CASpringAnimation(keyPath: "transform.scale")
            grow.fromValue = 0.3
            grow.toValue = 1
            grow.stiffness = 140
            grow.damping = 9
            grow.duration = grow.settlingDuration
            sprout.add(grow, forKey: "grow")
            flashSparkles()
        }
    }

    private func renderAccessories(_ pose: PetPose, previous: PetPose, layout: PetLayout, animated: Bool) {
        let s = side
        let w = layout.bodyWidth
        let h = layout.bodyHeight
        let top = layout.base + h

        sweat.path = PetGeometry.sweatDrop(radius: s * 0.028)
        sweat.lineWidth = s * 0.006
        set(sweat, \.position, CGPoint(x: layout.centerX + w * 0.37, y: layout.base + h * 0.78), animated)
        fade(sweat, visible: pose.accessories.contains(.sweat), animated: animated)

        let thermo = PetGeometry.thermometer(length: s * 0.15)
        thermometerStick.path = thermo.stick
        thermometerStick.lineWidth = s * 0.006
        thermometerBulb.path = thermo.bulb
        set(thermometer, \.position, CGPoint(x: layout.mouthCenter.x + layout.mouthWidth * 0.1, y: layout.mouthCenter.y), animated)
        thermometer.setAffineTransform(CGAffineTransform(rotationAngle: -0.32))
        fade(thermometer, visible: pose.accessories.contains(.thermometer), animated: animated)

        let crown = PetGeometry.crown(width: s * 0.17)
        crownBand.path = crown.band
        crownBand.lineWidth = s * 0.008
        crownJewels.path = crown.jewels
        set(crownLayer, \.position, CGPoint(x: layout.centerX - w * 0.2, y: top - h * 0.1), animated)
        crownLayer.setAffineTransform(CGAffineTransform(rotationAngle: 0.26))
        fade(crownLayer, visible: pose.accessories.contains(.crown), animated: animated)

        let sparkleSpots = [
            CGPoint(x: layout.centerX - w * 0.6, y: top - h * 0.1),
            CGPoint(x: layout.centerX + w * 0.62, y: top - h * 0.25),
            CGPoint(x: layout.centerX + w * 0.5, y: top + h * 0.22),
        ]
        for (index, sparkle) in sparkles.enumerated() {
            sparkle.path = PetGeometry.sparkle(radius: s * [0.045, 0.035, 0.028][index])
            sparkle.position = sparkleSpots[index]
        }
        if pose.accessories.contains(.sparkles) != previous.accessories.contains(.sparkles) || !animated {
            updateSparkleLoop(pose.accessories.contains(.sparkles))
        }

        let zSpots = [
            CGPoint(x: layout.centerX + w * 0.42, y: top + h * 0.02),
            CGPoint(x: layout.centerX + w * 0.56, y: top + h * 0.26),
            CGPoint(x: layout.centerX + w * 0.68, y: top + h * 0.52),
        ]
        for (index, z) in zees.enumerated() {
            let zSize = s * [0.045, 0.06, 0.075][index]
            z.path = PetGeometry.zGlyph(size: zSize)
            z.lineWidth = zSize * 0.2
            z.position = zSpots[index]
        }
        let sleeping = pose.accessories.contains(.zzz)
        if sleeping != previous.accessories.contains(.zzz) || !animated {
            updateZzzLoop(sleeping)
        }
    }

    // MARK: Idle animations

    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private func updateIdleAnimations() {
        let visible = window.map { $0.occlusionState.contains(.visible) } ?? false
        isVisibleOnScreen = visible
        let run = idleAnimationsEnabled && visible && side > 0

        breathLayer.removeAnimation(forKey: "breathe")
        sprout.removeAnimation(forKey: "sway")
        blinkTimer?.invalidate()
        blinkTimer = nil
        idleTimer?.invalidate()
        idleTimer = nil

        guard run else {
            // Hidden mid-act: finish it now so it reappears in its own face.
            if currentAct != nil {
                cancelAct()
                currentAct = nil
                setFace(nil)
            }
            return
        }
        director.reduceMotion = reduceMotion
        scheduleIdleAct()
        if !reduceMotion {
            let sleeping = pose.accessories.contains(.zzz)
            let breathe = CABasicAnimation(keyPath: "transform.scale.y")
            breathe.fromValue = 1
            breathe.toValue = sleeping ? 1.035 : 1.022
            breathe.duration = sleeping ? 2.4 : 1.7
            breathe.autoreverses = true
            breathe.repeatCount = .infinity
            breathe.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            breathLayer.add(breathe, forKey: "breathe")

            let sway = CABasicAnimation(keyPath: "transform.rotation.z")
            sway.fromValue = -0.05
            sway.toValue = 0.05
            sway.duration = 2.6
            sway.autoreverses = true
            sway.repeatCount = .infinity
            sway.isAdditive = true
            sway.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            sprout.add(sway, forKey: "sway")
        }
        scheduleBlink()
        updateZzzLoop(pose.accessories.contains(.zzz))
        updateSparkleLoop(pose.accessories.contains(.sparkles))
    }

    private func scheduleBlink() {
        blinkTimer?.invalidate()
        let timer = Timer(timeInterval: .random(in: 2.6...6.5), repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isVisibleOnScreen, self.idleAnimationsEnabled else { return }
                let roundEyes = PetGeometry.eyeShapes(for: self.renderedPose.eyes).allSatisfy {
                    if case .round = $0 { return true }
                    return false
                }
                if roundEyes {
                    self.blink(duration: 0.18)
                    if Double.random(in: 0...1) < 0.18 {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) { [weak self] in
                            self?.blink(duration: 0.16)
                        }
                    }
                }
                self.scheduleBlink()
            }
        }
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        blinkTimer = timer
    }

    private func blink(duration: TimeInterval) {
        for eye in eyes {
            let blink = CAKeyframeAnimation(keyPath: "transform.scale.y")
            blink.values = [1, 0.08, 1]
            blink.keyTimes = [0, 0.45, 1]
            blink.duration = duration
            blink.timingFunctions = [CAMediaTimingFunction(name: .easeIn), CAMediaTimingFunction(name: .easeOut)]
            eye.container.add(blink, forKey: "blink")
        }
    }

    private func updateZzzLoop(_ on: Bool) {
        let run = on && isVisibleOnScreen && idleAnimationsEnabled && !reduceMotion
        for (index, z) in zees.enumerated() {
            z.removeAllAnimations()
            z.opacity = on ? (run ? 0 : [0.5, 0.75, 1][index]) : 0
            guard run else { continue }
            let group = CAAnimationGroup()
            let rise = CABasicAnimation(keyPath: "position.y")
            rise.fromValue = z.position.y - side * 0.04
            rise.toValue = z.position.y + side * 0.03
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [0, 1, 1, 0]
            fade.keyTimes = [0, 0.25, 0.7, 1]
            group.animations = [rise, fade]
            group.duration = 2.4
            group.repeatCount = .infinity
            group.beginTime = CACurrentMediaTime() + Double(index) * 0.8
            group.fillMode = .backwards
            z.add(group, forKey: "float")
        }
    }

    private func updateSparkleLoop(_ on: Bool) {
        let run = on && isVisibleOnScreen && idleAnimationsEnabled && !reduceMotion
        for (index, sparkle) in sparkles.enumerated() {
            sparkle.removeAnimation(forKey: "twinkle")
            sparkle.opacity = on && !run ? 1 : 0
            guard run else { continue }
            sparkle.add(twinkle(delay: Double(index) * 0.35, repeating: true), forKey: "twinkle")
        }
    }

    private func flashSparkles() {
        guard !reduceMotion else { return }
        for (index, sparkle) in sparkles.enumerated() {
            sparkle.add(twinkle(delay: Double(index) * 0.12, repeating: false), forKey: "flash")
        }
    }

    private func twinkle(delay: TimeInterval, repeating: Bool) -> CAAnimation {
        let scale = CAKeyframeAnimation(keyPath: "transform.scale")
        scale.values = [0.2, 1.15, 0.9, 0.2]
        let opacity = CAKeyframeAnimation(keyPath: "opacity")
        opacity.values = [0, 1, 1, 0]
        let group = CAAnimationGroup()
        group.animations = [scale, opacity]
        group.duration = 1.1
        group.beginTime = CACurrentMediaTime() + delay
        group.fillMode = .backwards
        group.repeatCount = repeating ? .infinity : 1
        return group
    }

    private func squash(values: [CGFloat], keyTimes: [NSNumber], duration: TimeInterval, delay: TimeInterval = 0, key: String = "squash") {
        let y = CAKeyframeAnimation(keyPath: "transform.scale.y")
        y.values = values
        y.keyTimes = keyTimes
        let x = CAKeyframeAnimation(keyPath: "transform.scale.x")
        // Keep the volume roughly constant: wider when squashed.
        x.values = values.map { 1 + (1 - $0) * 0.7 }
        x.keyTimes = keyTimes
        let group = CAAnimationGroup()
        group.animations = [x, y]
        group.duration = duration
        group.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        group.beginTime = CACurrentMediaTime() + delay
        squashLayer.add(group, forKey: key)
    }

    // MARK: Acts

    private func refresh(animated: Bool) {
        let effective = faceOverlay?.applied(to: pose) ?? pose
        let previous = renderedPose
        renderedPose = effective
        render(effective, previous: previous, animated: animated)
    }

    private func setFace(_ face: PetFace?) {
        guard face != faceOverlay else { return }
        faceOverlay = face
        guard side > 0 else { return }
        refresh(animated: window != nil)
    }

    private func schedule(after delay: TimeInterval, _ work: @escaping @MainActor () -> Void) {
        let item = DispatchWorkItem {
            MainActor.assumeIsolated { work() }
        }
        actWork.append(item)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    /// Stops the playing act's timers and motions (the face is reset by the caller).
    private func cancelAct() {
        actWork.forEach { $0.cancel() }
        actWork = []
        for layer in [hopLayer, spinLayer, squashLayer, sprout] {
            for key in layer.animationKeys() ?? [] where key.hasPrefix("act.") {
                layer.removeAnimation(forKey: key)
            }
        }
        faceOverlay = nil
    }

    private func scheduleIdleAct() {
        idleTimer?.invalidate()
        let timer = Timer(timeInterval: director.nextIdleDelay(), repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isVisibleOnScreen, self.idleAnimationsEnabled else { return }
                if self.currentAct == nil, let act = self.director.pick(.idle(self.mood), now: CACurrentMediaTime()) {
                    self.perform(act)
                }
                self.scheduleIdleAct()
            }
        }
        timer.tolerance = 2
        RunLoop.main.add(timer, forMode: .common)
        idleTimer = timer
    }

    // MARK: Body motions

    private func play(_ motion: BodyMotion, delay: TimeInterval, key: String) {
        let s = side
        func keyframes(_ layer: CALayer, _ path: String, _ values: [Any], times: [NSNumber]? = nil,
                       duration: TimeInterval, additive: Bool = true, name: String = "") {
            let animation = CAKeyframeAnimation(keyPath: path)
            animation.values = values
            animation.keyTimes = times
            animation.duration = duration
            animation.isAdditive = additive
            animation.calculationMode = .linear
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animation.beginTime = CACurrentMediaTime() + delay
            animation.fillMode = .backwards
            layer.add(animation, forKey: key + name)
        }
        func radians(_ degrees: Double) -> Double { -degrees * .pi / 180 }

        switch motion {
        case .hop(let height, let duration):
            keyframes(hopLayer, "position.y", [0, 0, s * height, 0, 0], times: [0, 0.14, 0.5, 0.82, 1], duration: duration)
            squash(values: [1, 0.86, 1.1, 1.0, 0.84, 1.04, 1], keyTimes: [0, 0.14, 0.3, 0.6, 0.82, 0.92, 1],
                   duration: duration, delay: delay, key: key + ".squash")
        case .rock(let angle, let swings, let duration):
            var values: [Double] = [0]
            for swing in 0..<swings {
                let fade = 1 - 0.12 * Double(swing) / Double(max(1, swings))
                values.append(radians(swing.isMultiple(of: 2) ? angle : -angle) * fade)
            }
            values.append(0)
            keyframes(hopLayer, "transform.rotation.z", values, duration: duration)
        case .shiver(let duration):
            let count = max(4, Int(duration * 22))
            let values = (0...count).map { $0 == 0 || $0 == count ? 0 : ($0.isMultiple(of: 2) ? 1 : -1) * s * 0.012 }
            keyframes(hopLayer, "position.x", values, duration: duration)
        case .roll(let duration):
            keyframes(spinLayer, "transform.rotation.z", [0, -Double.pi, -2 * Double.pi], duration: duration)
            keyframes(hopLayer, "position.y", [0, s * 0.07, 0], duration: duration, name: ".lift")
        case .turn(let duration):
            keyframes(spinLayer, "transform.scale.x", [1, 0.04, -1, -0.04, 1], times: [0, 0.25, 0.5, 0.75, 1],
                      duration: duration, additive: false)
        case .sink(let depth, let hold):
            let total = 0.3 + hold + 0.35
            let down = 0.3 / total
            let up = (0.3 + hold) / total
            squash(values: [1, 1 - depth, 1 - depth, 1.03, 1],
                   keyTimes: [0, NSNumber(value: down), NSNumber(value: up), NSNumber(value: up + (1 - up) * 0.6), 1],
                   duration: total, delay: delay, key: key + ".squash")
        case .stretchTall(let amount, let hold):
            let total = 0.3 + hold + 0.4
            let rise = 0.3 / total
            let fall = (0.3 + hold) / total
            squash(values: [1, 1 + amount, 1 + amount, 0.96, 1],
                   keyTimes: [0, NSNumber(value: rise), NSNumber(value: fall), NSNumber(value: fall + (1 - fall) * 0.6), 1],
                   duration: total, delay: delay, key: key + ".squash")
        case .nodOff(let duration):
            squash(values: [1, 0.9, 0.9, 1.05, 1], keyTimes: [0, 0.75, 0.84, 0.9, 1], duration: duration, delay: delay, key: key + ".squash")
            keyframes(hopLayer, "position.y", [0, 0, s * 0.035, 0], times: [0, 0.84, 0.9, 1], duration: duration)
        case .chew:
            squash(values: [1, 0.93, 1, 0.93, 1, 0.93, 1], keyTimes: [0, 0.16, 0.33, 0.5, 0.66, 0.83, 1],
                   duration: 0.9, delay: delay, key: key + ".squash")
        case .leafTwirl(let duration):
            keyframes(sprout, "transform.rotation.z", [0, -Double.pi, -2 * Double.pi], duration: duration)
        case .leafWave(let swings, let duration):
            var values: [Double] = [0]
            for swing in 0..<(swings * 2) {
                values.append(swing.isMultiple(of: 2) ? 0.5 : -0.5)
            }
            values.append(0)
            keyframes(sprout, "transform.rotation.z", values, duration: duration)
        case .float(let height, let duration):
            keyframes(hopLayer, "position.y", [0, s * height, s * height * 0.6, s * height, 0], duration: duration)
        case .lean(let angle, let duration):
            keyframes(hopLayer, "transform.rotation.z", [0, radians(angle), radians(angle), 0], times: [0, 0.3, 0.7, 1], duration: duration)
        case .jolt:
            keyframes(hopLayer, "position.y", [0, s * 0.04, 0], duration: 0.24)
            squash(values: [1, 1.07, 0.95, 1], keyTimes: [0, 0.3, 0.7, 1], duration: 0.24, delay: delay, key: key + ".squash")
        }
    }

    // MARK: Effects

    private func emit(_ effect: PetEffect, still: Bool = false) {
        guard side > 0 else { return }
        stillEffects = still
        let s = side
        let layout = PetGeometry.layout(for: renderedPose, size: s)
        let head = CGPoint(x: layout.crown.x, y: layout.crown.y)
        let right = CGPoint(x: layout.centerX + layout.bodyWidth * 0.42, y: layout.base + layout.bodyHeight * 0.92)
        let mouthSide = CGPoint(x: layout.mouthCenter.x + layout.bodyWidth * 0.3, y: layout.mouthCenter.y)

        switch effect {
        case .hearts:
            for (index, dx) in [-0.16, 0.12, 0.34].enumerated() {
                particle(PetGeometry.heart(size: s * [0.09, 0.07, 0.06][index]),
                         fill: NSColor(hex: 0xFF6F91), at: CGPoint(x: head.x + s * dx, y: head.y - s * 0.02),
                         rise: s * 0.16, drift: s * 0.03 * (index.isMultiple(of: 2) ? -1 : 1), delay: Double(index) * 0.18, lifetime: 1.2)
            }
        case .notes:
            for index in 0..<2 {
                particle(PetGeometry.glyph("♪", size: s * (index == 0 ? 0.11 : 0.09)),
                         fill: NSColor(hex: 0x8E86E8), at: CGPoint(x: right.x + s * 0.04 * Double(index), y: right.y),
                         rise: s * 0.14, drift: s * 0.06, delay: Double(index) * 0.35, lifetime: 1.3)
            }
        case .exclaim:
            particle(PetGeometry.glyph("!", size: s * 0.16), fill: NSColor(hex: 0xFF7D6E),
                     at: CGPoint(x: right.x + s * 0.02, y: right.y + s * 0.06), rise: s * 0.03, drift: 0, delay: 0, lifetime: 1.1, pop: true)
        case .question:
            particle(PetGeometry.glyph("?", size: s * 0.15), fill: NSColor(hex: 0x8E86E8),
                     at: CGPoint(x: right.x + s * 0.02, y: right.y + s * 0.06), rise: s * 0.04, drift: s * 0.02, delay: 0, lifetime: 1.5, pop: true)
        case .puff:
            particle(PetGeometry.puff(size: s * 0.17), fill: NSColor(hex: 0xF4F1EE, alpha: 0.95), stroke: NSColor(hex: 0xE3DDD7),
                     at: CGPoint(x: mouthSide.x + s * 0.03, y: mouthSide.y), rise: s * 0.03, drift: s * 0.12, delay: 0, lifetime: 1.2, grow: true)
        case .sleepBubble:
            let radius = s * 0.06
            let bubble = CGPath(ellipseIn: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2), transform: nil)
            let bubbleCentre = CGPoint(x: mouthSide.x - s * 0.04, y: mouthSide.y)
            particle(bubble, fill: NSColor(hex: 0xB8E4FF, alpha: 0.6), stroke: NSColor(hex: 0x8FCBF2, alpha: 0.9),
                     at: bubbleCentre, rise: 0, drift: s * 0.02, delay: 0, lifetime: 2.4, grow: true)
            let shine = CGPath(ellipseIn: CGRect(x: -radius * 0.28, y: -radius * 0.28, width: radius * 0.56, height: radius * 0.56), transform: nil)
            particle(shine, fill: NSColor(white: 1, alpha: 0.9),
                     at: CGPoint(x: bubbleCentre.x - radius * 0.35, y: bubbleCentre.y + radius * 0.35),
                     rise: 0, drift: s * 0.02, delay: 0, lifetime: 2.4, grow: true)
        case .sparkles:
            if still {
                sparkles.forEach { $0.opacity = 1 }
            } else {
                flashSparkles()
            }
        case .zzz:
            for index in 0..<3 {
                particle(PetGeometry.glyph("z", size: s * [0.07, 0.09, 0.11][index]), fill: NSColor(hex: 0x8E86E8),
                         at: CGPoint(x: right.x + s * 0.03 * Double(index), y: right.y), rise: s * 0.15, drift: s * 0.05,
                         delay: Double(index) * 0.3, lifetime: 1.3)
            }
        case .sweat:
            particle(PetGeometry.sweatDrop(radius: s * 0.026), fill: Palette.sweat, stroke: NSColor(white: 1, alpha: 0.8),
                     at: CGPoint(x: right.x - s * 0.02, y: right.y - s * 0.04), rise: -s * 0.05, drift: 0, delay: 0, lifetime: 1.2)
        }
    }

    /// One short-lived shape that rises (or sinks), drifts and fades.
    private func particle(
        _ path: CGPath, fill: NSColor, stroke: NSColor? = nil, at point: CGPoint,
        rise: CGFloat, drift: CGFloat, delay: TimeInterval, lifetime: TimeInterval,
        pop: Bool = false, grow: Bool = false
    ) {
        let shape = CAShapeLayer()
        shape.path = path
        shape.fillColor = fill.cgColor
        shape.strokeColor = stroke?.cgColor
        shape.lineWidth = side * 0.006
        shape.contentsScale = window?.backingScaleFactor ?? 2
        shape.position = point
        shape.opacity = 0
        effectsLayer.addSublayer(shape)
        if stillEffects {
            // A still frame (debug contact sheet): halfway through, fully visible.
            shape.position = CGPoint(x: point.x + drift * 0.5 + CGFloat(delay) * side * 0.04, y: point.y + rise * 0.5)
            shape.opacity = 1
            return
        }

        let move = CABasicAnimation(keyPath: "position")
        move.fromValue = point
        move.toValue = CGPoint(x: point.x + drift, y: point.y + rise)
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0, 1, 1, 0]
        fade.keyTimes = [0, 0.15, 0.7, 1]
        let scale = CAKeyframeAnimation(keyPath: "transform.scale")
        scale.values = grow ? [0.3, 0.9, 1.15] : (pop ? [0.2, 1.25, 1, 1] : [0.5, 1, 1])
        let group = CAAnimationGroup()
        group.animations = [move, fade, scale]
        group.duration = lifetime
        group.beginTime = CACurrentMediaTime() + delay
        group.fillMode = .backwards
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        shape.add(group, forKey: "fx")
        DispatchQueue.main.asyncAfter(deadline: .now() + delay + lifetime + 0.1) { [weak shape] in
            shape?.removeFromSuperlayer()
        }
    }

    #if DEBUG
    /// Freezes an act at its key moment for the debug contact sheet: its
    /// distinctive face, its effects mid-flight, and its main motion at its peak.
    func debugStill(_ act: PetAct) {
        guard side > 0 else { return }
        let script = act.script
        let face = script.faces.count > 1 && [.nodOff, .chomp].contains(act) ? script.faces[1].value : script.faces.first?.value
        faceOverlay = face
        refresh(animated: false)
        for effect in script.effects {
            emit(effect.value, still: true)
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let s = side
        for motion in script.motions.prefix(1).map(\.value) {
            switch motion {
            case .hop(let height, _), .float(let height, _):
                hopLayer.setAffineTransform(CGAffineTransform(translationX: 0, y: s * height))
            case .rock(let angle, _, _), .lean(let angle, _):
                hopLayer.setAffineTransform(CGAffineTransform(rotationAngle: -angle * .pi / 180))
            case .shiver:
                hopLayer.setAffineTransform(CGAffineTransform(translationX: s * 0.012, y: 0))
            case .roll:
                spinLayer.setAffineTransform(CGAffineTransform(rotationAngle: -.pi / 2))
            case .turn:
                spinLayer.setAffineTransform(CGAffineTransform(scaleX: 0.35, y: 1))
            case .sink(let depth, _):
                squashLayer.setAffineTransform(CGAffineTransform(scaleX: 1 + depth * 0.7, y: 1 - depth))
            case .stretchTall(let amount, _):
                squashLayer.setAffineTransform(CGAffineTransform(scaleX: 1 - amount * 0.5, y: 1 + amount))
            case .nodOff:
                squashLayer.setAffineTransform(CGAffineTransform(scaleX: 1.06, y: 0.9))
            case .chew:
                squashLayer.setAffineTransform(CGAffineTransform(scaleX: 1.05, y: 0.93))
            case .leafTwirl:
                sprout.setAffineTransform(CGAffineTransform(rotationAngle: -.pi * 0.6))
            case .leafWave:
                sprout.setAffineTransform(CGAffineTransform(rotationAngle: 0.5))
            case .jolt:
                hopLayer.setAffineTransform(CGAffineTransform(translationX: 0, y: s * 0.04))
            }
        }
        CATransaction.commit()
    }
    #endif

    // MARK: Animation helpers

    private func setPath(_ layer: CAShapeLayer, _ path: CGPath, _ animated: Bool) {
        let from = layer.presentation()?.path ?? layer.path
        layer.path = path
        guard animated, let from, from != path else { return }
        let spring = springAnimation(keyPath: "path")
        spring.fromValue = from
        spring.toValue = path
        layer.add(spring, forKey: "path")
    }

    private func set(_ layer: CALayer, _ keyPath: ReferenceWritableKeyPath<CALayer, CGPoint>, _ value: CGPoint, _ animated: Bool) {
        let from = layer.presentation()?.position ?? layer.position
        layer.position = value
        guard animated, from != value else { return }
        let spring = springAnimation(keyPath: "position")
        spring.fromValue = from
        spring.toValue = value
        layer.add(spring, forKey: "position")
    }

    private func set(_ layer: CALayer, _ keyPath: ReferenceWritableKeyPath<CALayer, CGRect>, _ value: CGRect, _ animated: Bool) {
        let from = layer.presentation()?.bounds ?? layer.bounds
        layer.bounds = value
        guard animated, from != value else { return }
        let spring = springAnimation(keyPath: "bounds")
        spring.fromValue = from
        spring.toValue = value
        layer.add(spring, forKey: "bounds")
    }

    private func setValue(
        _ layer: CALayer, keyPath: String, to value: Any, animated: Bool,
        spring: Bool = true, duration: TimeInterval = 0.35
    ) {
        let from = layer.presentation()?.value(forKeyPath: keyPath) ?? layer.value(forKeyPath: keyPath)
        layer.setValue(value, forKeyPath: keyPath)
        guard animated, let from else { return }
        let animation: CABasicAnimation
        if spring {
            animation = springAnimation(keyPath: keyPath)
        } else {
            animation = CABasicAnimation(keyPath: keyPath)
            animation.duration = duration
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        }
        animation.fromValue = from
        animation.toValue = value
        layer.add(animation, forKey: keyPath)
    }

    private func springAnimation(keyPath: String) -> CASpringAnimation {
        let spring = CASpringAnimation(keyPath: keyPath)
        spring.mass = 1
        spring.stiffness = 210
        spring.damping = 20
        spring.duration = spring.settlingDuration
        return spring
    }

    private func fade(_ layer: CALayer, visible: Bool, animated: Bool) {
        setValue(layer, keyPath: "opacity", to: Float(visible ? 1 : 0), animated: animated, spring: false, duration: 0.25)
    }
}

/// The layers for one eye, positioned by a zero-size container at the eye's
/// centre so blinking scales around the middle.
private struct EyeLayers {
    let container = CALayer()
    let iris = CAShapeLayer()
    let shine = CAShapeLayer()
    let arc = CAShapeLayer()

    var all: [CALayer] { [container, iris, shine, arc] }
}
