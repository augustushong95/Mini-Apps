import CoreGraphics
import Foundation

/// Where every part of Mochi goes for a pose, in a square canvas of side
/// `size` with the origin at the bottom left (y up).
nonisolated struct PetLayout {
    let size: CGFloat
    /// The ground line Mochi sits on.
    let base: CGFloat
    let centerX: CGFloat
    let bodyWidth: CGFloat
    let bodyHeight: CGFloat
    let body: CGPath
    /// Top of the dome, where the stem grows from.
    let crown: CGPoint
    let eyeCenters: [CGPoint]
    /// Size of a fully open eye.
    let eyeSize: CGSize
    let mouthCenter: CGPoint
    let mouthWidth: CGFloat
    let blushCenters: [CGPoint]
    let blushSize: CGSize
    let highlight: CGPath
    let shadowRect: CGRect
    /// How far the dome shifts sideways per point of height when leaning.
    let shear: CGFloat
    /// The sprout's lean in radians (clockwise is negative).
    var sproutRotation: CGFloat { -atan(shear) * 0.8 }
    /// The point Mochi squashes around: bottom centre.
    var pivot: CGPoint { CGPoint(x: centerX, y: base) }
}

/// Mochi's shapes as pure functions of a pose. Part shapes (eyes, mouth,
/// leaves, accessories) are in local coordinates centred on their anchor, so
/// renderers can position, blink and sway them independently.
nonisolated enum PetGeometry {
    // MARK: Layout

    static func layout(for pose: PetPose, size s: CGFloat) -> PetLayout {
        let u = clamp(pose.uprightness)
        let width = s * 0.70 * lerp(1.10, 1.0, u)
        let height = s * 0.52 * lerp(0.82, 1.0, u)
        let base = s * 0.13
        let centerX = s / 2
        let waist = lerp(0.33, 0.40, u)

        // Leaning is a shear, not a rotation: a soft mochi keeps its base on
        // the ground and its dome slides sideways. The face also rolls a
        // little, the way a head does, so the eye on the leaning side drops.
        let shear = CGFloat(tan(clamp(pose.tilt, -18, 18) * .pi / 180))
        var shearTransform = CGAffineTransform(a: 1, b: 0, c: shear, d: 1, tx: -shear * base, ty: 0)
        func lean(_ point: CGPoint) -> CGPoint {
            CGPoint(
                x: point.x + (point.y - base) * shear,
                y: point.y - (point.x - centerX) * shear * 0.35
            )
        }

        let body = bodyPath(centerX: centerX, base: base, width: width, height: height, waist: waist)
            .copy(using: &shearTransform) ?? bodyPath(centerX: centerX, base: base, width: width, height: height, waist: waist)

        let gaze = CGVector(dx: clamp(pose.gaze.dx, -1, 1), dy: clamp(pose.gaze.dy, -1, 1))
        let eyeY = base + height * lerp(0.40, 0.50, u) + gaze.dy * height * 0.05
        let eyeShift = gaze.dx * width * 0.035
        let eyeSpacing = width * 0.19
        let eyeCenters = [
            lean(CGPoint(x: centerX - eyeSpacing + eyeShift, y: eyeY)),
            lean(CGPoint(x: centerX + eyeSpacing + eyeShift, y: eyeY)),
        ]
        let blushY = eyeY - height * 0.12
        let highlightCenter = CGPoint(x: centerX - width * 0.21, y: base + height * 0.80)
        let highlight = ellipse(
            center: CGPoint(x: highlightCenter.x + (highlightCenter.y - base) * shear, y: highlightCenter.y),
            size: CGSize(width: width * 0.21, height: height * 0.11),
            rotation: 28
        )

        return PetLayout(
            size: s,
            base: base,
            centerX: centerX,
            bodyWidth: width,
            bodyHeight: height,
            body: body,
            crown: CGPoint(x: centerX + height * shear, y: base + height),
            eyeCenters: eyeCenters,
            eyeSize: CGSize(width: width * 0.095, height: width * 0.13),
            mouthCenter: lean(CGPoint(x: centerX + eyeShift * 0.6, y: eyeY - height * 0.165)),
            mouthWidth: width * 0.11,
            blushCenters: [
                lean(CGPoint(x: centerX - width * 0.31 + eyeShift * 0.4, y: blushY)),
                lean(CGPoint(x: centerX + width * 0.31 + eyeShift * 0.4, y: blushY)),
            ],
            blushSize: CGSize(width: width * 0.17, height: width * 0.09),
            highlight: highlight,
            shadowRect: CGRect(x: centerX - width * 0.44, y: base - s * 0.04, width: width * 0.88, height: s * 0.08),
            shear: shear
        )
    }

    /// A daifuku silhouette: flat, wide bottom and a round dome. `waist` is
    /// the height of the widest point as a fraction of the height; slumping
    /// lowers it so Mochi spreads out.
    static func bodyPath(centerX cx: CGFloat, base: CGFloat, width w: CGFloat, height h: CGFloat, waist: CGFloat) -> CGPath {
        let waistY = h * waist
        let bottom = CGPoint(x: cx, y: base)
        let right = CGPoint(x: cx + w / 2, y: base + waistY)
        let top = CGPoint(x: cx, y: base + h)
        let left = CGPoint(x: cx - w / 2, y: base + waistY)

        let path = CGMutablePath()
        path.move(to: bottom)
        path.addCurve(
            to: right,
            control1: CGPoint(x: bottom.x + w * 0.40, y: bottom.y),
            control2: CGPoint(x: right.x, y: right.y - waistY * 0.64)
        )
        path.addCurve(
            to: top,
            control1: CGPoint(x: right.x, y: right.y + (h - waistY) * 0.56),
            control2: CGPoint(x: top.x + w * 0.31, y: top.y)
        )
        path.addCurve(
            to: left,
            control1: CGPoint(x: top.x - w * 0.31, y: top.y),
            control2: CGPoint(x: left.x, y: left.y + (h - waistY) * 0.56)
        )
        path.addCurve(
            to: bottom,
            control1: CGPoint(x: left.x, y: left.y - waistY * 0.64),
            control2: CGPoint(x: bottom.x - w * 0.40, y: bottom.y)
        )
        path.closeSubpath()
        return path
    }

    // MARK: Eyes (local, centred on the eye)

    static func openEye(size: CGSize, openness: Double) -> CGPath {
        let height = size.height * max(0.12, clamp(openness))
        return CGPath(
            ellipseIn: CGRect(x: -size.width / 2, y: -height / 2, width: size.width, height: height),
            transform: nil
        )
    }

    /// The two catch-lights that make the eyes look glossy. They follow the
    /// gaze slightly and shrink as the eye closes. Always two ellipses, so the
    /// path can animate; renderers fade them out below about 0.3 openness.
    static func eyeHighlights(size: CGSize, openness: Double, gaze: CGVector) -> CGPath {
        let o = clamp(openness)
        let path = CGMutablePath()
        let big = size.width * 0.30 * min(1, o * 1.2)
        let small = size.width * 0.13 * min(1, o * 1.2)
        let bigCenter = CGPoint(
            x: -size.width * 0.14 + gaze.dx * size.width * 0.08,
            y: size.height * 0.18 * o + gaze.dy * size.height * 0.05
        )
        let smallCenter = CGPoint(x: size.width * 0.17, y: -size.height * 0.2 * o)
        path.addEllipse(in: CGRect(x: bigCenter.x - big, y: bigCenter.y - big, width: big * 2, height: big * 2))
        path.addEllipse(in: CGRect(x: smallCenter.x - small, y: smallCenter.y - small, width: small * 2, height: small * 2))
        return path
    }

    /// A stroked arc for `.happy` (^) or `.closed` (◡) eyes.
    static func eyeArc(_ style: PetPose.EyeStyle, size: CGSize) -> CGPath {
        let path = CGMutablePath()
        let w = size.width
        let h = size.height
        switch style {
        case .happy:
            path.move(to: CGPoint(x: -w * 0.72, y: -h * 0.14))
            path.addQuadCurve(to: CGPoint(x: w * 0.72, y: -h * 0.14), control: CGPoint(x: 0, y: h * 0.52))
        case .closed, .open:
            path.move(to: CGPoint(x: -w * 0.78, y: h * 0.06))
            path.addQuadCurve(to: CGPoint(x: w * 0.78, y: h * 0.06), control: CGPoint(x: 0, y: -h * 0.46))
        }
        return path
    }

    static func eyeStrokeWidth(size: CGSize) -> CGFloat {
        size.width * 0.42
    }

    // MARK: Mouth (local, centred)

    struct MouthShapes {
        var stroke: CGPath?
        var fill: CGPath?
        var tongue: CGPath?
    }

    static func mouth(_ style: PetPose.MouthStyle, width w: CGFloat) -> MouthShapes {
        switch style {
        case .smile:
            let path = CGMutablePath()
            path.move(to: CGPoint(x: -w / 2, y: w * 0.08))
            path.addQuadCurve(to: CGPoint(x: w / 2, y: w * 0.08), control: CGPoint(x: 0, y: -w * 0.5))
            return MouthShapes(stroke: path)
        case .grin:
            let path = CGMutablePath()
            path.move(to: CGPoint(x: -w * 0.6, y: w * 0.12))
            path.addLine(to: CGPoint(x: w * 0.6, y: w * 0.12))
            path.addCurve(
                to: CGPoint(x: -w * 0.6, y: w * 0.12),
                control1: CGPoint(x: w * 0.6, y: -w * 0.78),
                control2: CGPoint(x: -w * 0.6, y: -w * 0.78)
            )
            path.closeSubpath()
            // Kept well inside the mouth so no mask is needed.
            let tongue = ellipse(center: CGPoint(x: 0, y: -w * 0.33), size: CGSize(width: w * 0.5, height: w * 0.22))
            return MouthShapes(fill: path, tongue: tongue)
        case .flat:
            let path = CGMutablePath()
            path.move(to: CGPoint(x: -w * 0.36, y: 0))
            path.addLine(to: CGPoint(x: w * 0.36, y: 0))
            return MouthShapes(stroke: path)
        case .frown:
            let path = CGMutablePath()
            path.move(to: CGPoint(x: -w * 0.42, y: -w * 0.14))
            path.addQuadCurve(to: CGPoint(x: w * 0.42, y: -w * 0.14), control: CGPoint(x: 0, y: w * 0.3))
            return MouthShapes(stroke: path)
        case .wobble:
            let path = CGMutablePath()
            path.move(to: CGPoint(x: -w * 0.5, y: 0))
            path.addQuadCurve(to: CGPoint(x: -w * 0.17, y: 0), control: CGPoint(x: -w * 0.33, y: w * 0.2))
            path.addQuadCurve(to: CGPoint(x: w * 0.17, y: 0), control: CGPoint(x: 0, y: -w * 0.2))
            path.addQuadCurve(to: CGPoint(x: w * 0.5, y: 0), control: CGPoint(x: w * 0.33, y: w * 0.2))
            return MouthShapes(stroke: path)
        case .oh:
            return MouthShapes(fill: ellipse(center: .zero, size: CGSize(width: w * 0.42, height: w * 0.5)))
        }
    }

    static func mouthStrokeWidth(width: CGFloat) -> CGFloat {
        width * 0.2
    }

    // MARK: Sprout (local, origin at the stem base, growing up)

    struct SproutShapes {
        var stem: CGPath
        var stemWidth: CGFloat
        var leaves: CGPath
        var veins: CGPath
        var veinWidth: CGFloat
        var bud: CGPath?
        var petals: CGPath?
        var flowerCenter: CGPath?
        /// The stem tip, where the leaves attach.
        var tip: CGPoint
    }

    static func sprout(stage: GrowthStage, droop: Double, size s: CGFloat) -> SproutShapes {
        let d = clamp(droop)
        let stemLength = s * [0.07, 0.085, 0.10, 0.11][stage.rawValue]
        let leafLength = s * [0.12, 0.13, 0.14, 0.14][stage.rawValue]

        // The stem bends toward the viewer's right as the leaf wilts.
        let bend = d * 70 * .pi / 180
        let tip = CGPoint(x: stemLength * sin(bend), y: stemLength * cos(bend))
        let stem = CGMutablePath()
        stem.move(to: .zero)
        stem.addQuadCurve(to: tip, control: CGPoint(x: 0, y: stemLength * 0.6))

        let leaves = CGMutablePath()
        let veins = CGMutablePath()
        func addLeaf(angle: Double, mirrored: Bool, scale: CGFloat = 1) {
            let length = leafLength * scale
            var transform = CGAffineTransform(translationX: tip.x, y: tip.y)
                .rotated(by: angle * .pi / 180)
            if mirrored {
                transform = transform.scaledBy(x: 1, y: -1)
            }
            leaves.addPath(leafShape(length: length, width: length * 0.62), transform: transform)
            let vein = CGMutablePath()
            vein.move(to: CGPoint(x: length * 0.14, y: 0))
            vein.addQuadCurve(to: CGPoint(x: length * 0.74, y: length * 0.03), control: CGPoint(x: length * 0.45, y: length * 0.05))
            veins.addPath(vein, transform: transform)
        }

        switch stage {
        case .seedling:
            addLeaf(angle: 52 - d * 88, mirrored: false)
        case .sprout:
            addLeaf(angle: 34 - d * 80, mirrored: false)
            addLeaf(angle: 146 + d * 66, mirrored: true, scale: 0.9)
        case .bud, .bloom:
            addLeaf(angle: 22 - d * 72, mirrored: false)
            addLeaf(angle: 158 + d * 58, mirrored: true, scale: 0.92)
        }

        var shapes = SproutShapes(
            stem: stem,
            stemWidth: s * 0.022,
            leaves: leaves,
            veins: veins,
            veinWidth: s * 0.008,
            tip: tip
        )

        // The bud or flower sits on the stem tip, carried along as it bends.
        let headCenter = CGPoint(x: tip.x + sin(bend) * s * 0.03, y: tip.y + cos(bend) * s * 0.03)
        if stage == .bud {
            shapes.bud = ellipse(center: headCenter, size: CGSize(width: s * 0.065, height: s * 0.08), rotation: -Double(bend) * 180 / .pi)
        } else if stage == .bloom {
            let petals = CGMutablePath()
            let petalSize = CGSize(width: s * 0.05, height: s * 0.062)
            for index in 0..<5 {
                let angle = Double(index) / 5 * 2 * .pi + .pi / 2
                let center = CGPoint(
                    x: headCenter.x + cos(angle) * s * 0.034,
                    y: headCenter.y + sin(angle) * s * 0.034
                )
                petals.addPath(ellipse(center: center, size: petalSize, rotation: angle * 180 / .pi - 90))
            }
            shapes.petals = petals
            let r = s * 0.024
            shapes.flowerCenter = CGPath(ellipseIn: CGRect(x: headCenter.x - r, y: headCenter.y - r, width: r * 2, height: r * 2), transform: nil)
        }
        return shapes
    }

    /// An almond leaf along +x, slightly asymmetric so it looks grown, not drawn.
    static func leafShape(length l: CGFloat, width w: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.move(to: .zero)
        path.addCurve(to: CGPoint(x: l, y: 0), control1: CGPoint(x: l * 0.22, y: w * 0.66), control2: CGPoint(x: l * 0.72, y: w * 0.56))
        path.addCurve(to: .zero, control1: CGPoint(x: l * 0.7, y: -w * 0.42), control2: CGPoint(x: l * 0.26, y: -w * 0.46))
        path.closeSubpath()
        return path
    }

    // MARK: Accessories (local, centred)

    static func sweatDrop(radius r: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: r * 1.7))
        path.addCurve(to: CGPoint(x: r, y: 0), control1: CGPoint(x: r * 0.3, y: r * 1.15), control2: CGPoint(x: r, y: r * 0.6))
        path.addArc(center: .zero, radius: r, startAngle: 0, endAngle: .pi, clockwise: true)
        path.addCurve(to: CGPoint(x: 0, y: r * 1.7), control1: CGPoint(x: -r, y: r * 0.6), control2: CGPoint(x: -r * 0.3, y: r * 1.15))
        path.closeSubpath()
        return path
    }

    /// A thermometer sticking out of the mouth toward the viewer's right.
    static func thermometer(length l: CGFloat) -> (stick: CGPath, bulb: CGPath) {
        let width = l * 0.2
        let stick = CGPath(
            roundedRect: CGRect(x: 0, y: -width / 2, width: l, height: width),
            cornerWidth: width / 2, cornerHeight: width / 2,
            transform: nil
        )
        let r = width * 0.75
        let bulb = CGPath(ellipseIn: CGRect(x: l - r * 0.6, y: -r, width: r * 2, height: r * 2), transform: nil)
        return (stick, bulb)
    }

    static func crown(width w: CGFloat) -> (band: CGPath, jewels: CGPath) {
        let h = w * 0.72
        let band = CGMutablePath()
        band.move(to: CGPoint(x: -w / 2, y: 0))
        band.addLine(to: CGPoint(x: w / 2, y: 0))
        band.addLine(to: CGPoint(x: w / 2, y: h * 0.62))
        band.addLine(to: CGPoint(x: w * 0.24, y: h * 0.32))
        band.addLine(to: CGPoint(x: 0, y: h))
        band.addLine(to: CGPoint(x: -w * 0.24, y: h * 0.32))
        band.addLine(to: CGPoint(x: -w / 2, y: h * 0.62))
        band.closeSubpath()
        let jewels = CGMutablePath()
        let r = w * 0.08
        for point in [CGPoint(x: -w / 2, y: h * 0.62), CGPoint(x: 0, y: h), CGPoint(x: w / 2, y: h * 0.62)] {
            jewels.addEllipse(in: CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2))
        }
        return (band, jewels)
    }

    /// A four-pointed sparkle with curved sides.
    static func sparkle(radius r: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let inner = r * 0.16
        path.move(to: CGPoint(x: 0, y: r))
        path.addQuadCurve(to: CGPoint(x: r, y: 0), control: CGPoint(x: inner, y: inner))
        path.addQuadCurve(to: CGPoint(x: 0, y: -r), control: CGPoint(x: inner, y: -inner))
        path.addQuadCurve(to: CGPoint(x: -r, y: 0), control: CGPoint(x: -inner, y: -inner))
        path.addQuadCurve(to: CGPoint(x: 0, y: r), control: CGPoint(x: -inner, y: inner))
        path.closeSubpath()
        return path
    }

    /// A rounded "Z" for the sleeping animation, as a stroke path.
    static func zGlyph(size z: CGFloat) -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -z / 2, y: z / 2))
        path.addLine(to: CGPoint(x: z / 2, y: z / 2))
        path.addLine(to: CGPoint(x: -z / 2, y: -z / 2))
        path.addLine(to: CGPoint(x: z / 2, y: -z / 2))
        return path
    }

    // MARK: Helpers

    static func ellipse(center: CGPoint, size: CGSize, rotation degrees: Double = 0) -> CGPath {
        var transform = CGAffineTransform(translationX: center.x, y: center.y).rotated(by: degrees * .pi / 180)
        return CGPath(
            ellipseIn: CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height),
            transform: &transform
        )
    }
}

nonisolated func lerp(_ a: CGFloat, _ b: CGFloat, _ t: Double) -> CGFloat {
    a + (b - a) * CGFloat(t)
}

nonisolated func clamp(_ value: Double, _ low: Double = 0, _ high: Double = 1) -> Double {
    min(high, max(low, value))
}

nonisolated func clamp(_ value: CGFloat, _ low: CGFloat, _ high: CGFloat) -> CGFloat {
    min(high, max(low, value))
}
