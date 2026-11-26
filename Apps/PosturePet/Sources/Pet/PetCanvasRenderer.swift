import SwiftUI

/// Draws Mochi into a SwiftUI `Canvas` from the same geometry as the
/// Core Animation view, for games that place Mochi every frame.
enum PetCanvasRenderer {
    /// Draws Mochi in a square of side `size` whose bottom centre (where
    /// Mochi sits) is at `foot`. `squash` < 1 squashes, > 1 stretches.
    static func draw(
        _ pose: PetPose, in context: GraphicsContext, foot: CGPoint, size: CGFloat, squash: CGFloat = 1
    ) {
        let layout = PetGeometry.layout(for: pose, size: size)
        var ctx = context
        // Canvas is y-down; Mochi's geometry is y-up. Flip around the foot.
        ctx.translateBy(x: foot.x, y: foot.y)
        ctx.scaleBy(x: 1 / sqrt(squash), y: -squash)
        ctx.translateBy(x: -layout.pivot.x, y: -layout.pivot.y)

        // Ground shadow.
        let shadow = Path(ellipseIn: layout.shadowRect)
        ctx.fill(shadow, with: .radialGradient(
            Gradient(colors: [.black.opacity(0.16), .black.opacity(0)]),
            center: CGPoint(x: layout.shadowRect.midX, y: layout.shadowRect.midY),
            startRadius: 0,
            endRadius: layout.shadowRect.width / 2
        ))

        // Sprout behind the body.
        let sprout = PetGeometry.sprout(stage: pose.stage, droop: pose.leafDroop, size: size)
        var sproutCtx = ctx
        sproutCtx.translateBy(x: layout.crown.x, y: layout.crown.y - size * 0.018)
        sproutCtx.rotate(by: .radians(Double(layout.sproutRotation)))
        sproutCtx.stroke(Path(sprout.stem), with: .color(Color(Palette.leafDark)),
                         style: StrokeStyle(lineWidth: sprout.stemWidth, lineCap: .round))
        sproutCtx.fill(Path(sprout.leaves), with: .color(Color(Palette.leaf)))
        sproutCtx.stroke(Path(sprout.veins), with: .color(Color(Palette.leafVein)),
                         style: StrokeStyle(lineWidth: sprout.veinWidth, lineCap: .round))
        if let bud = sprout.bud { sproutCtx.fill(Path(bud), with: .color(Color(Palette.bud))) }
        if let petals = sprout.petals { sproutCtx.fill(Path(petals), with: .color(Color(Palette.petal))) }
        if let center = sprout.flowerCenter { sproutCtx.fill(Path(center), with: .color(Color(Palette.petalCenter))) }

        // Body with a soft top light, outline and gloss.
        let body = Path(layout.body)
        ctx.fill(body, with: .color(Color(Palette.mochiBottom.mixed(with: Palette.mochiPaleBottom, CGFloat(pose.paleness)))))
        let glowCenter = CGPoint(x: layout.centerX - layout.bodyWidth * 0.04, y: layout.base + layout.bodyHeight * 0.6)
        var clipped = ctx
        clipped.clip(to: body)
        clipped.fill(body, with: .radialGradient(
            Gradient(colors: [Color(Palette.mochiTop), Color(Palette.mochiTop).opacity(0)]),
            center: glowCenter,
            startRadius: 0,
            endRadius: layout.bodyWidth * 0.45
        ))
        ctx.stroke(body, with: .color(Color(Palette.mochiOutline).opacity(0.72)), lineWidth: size * 0.013)
        ctx.fill(Path(layout.highlight), with: .color(.white.opacity(0.75)))

        // Blush.
        for center in layout.blushCenters {
            let rect = CGRect(x: center.x - layout.blushSize.width / 2, y: center.y - layout.blushSize.height / 2,
                              width: layout.blushSize.width, height: layout.blushSize.height)
            ctx.fill(Path(ellipseIn: rect), with: .radialGradient(
                Gradient(colors: [Color(Palette.blush).opacity(0.75 * pose.blush), Color(Palette.blush).opacity(0)]),
                center: center, startRadius: 0, endRadius: layout.blushSize.width / 2
            ))
        }

        // Eyes.
        for (center, shape) in zip(layout.eyeCenters, PetGeometry.eyeShapes(for: pose.eyes)) {
            var eye = ctx
            eye.translateBy(x: center.x, y: center.y)
            if shape.isStroked {
                let width = PetGeometry.eyeStrokeWidth(size: layout.eyeSize) * (shape == .spiral ? 0.5 : 1)
                eye.stroke(Path(PetGeometry.eyeStroke(shape, size: layout.eyeSize)), with: .color(Color(Palette.ink)),
                           style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
            } else {
                eye.fill(Path(PetGeometry.eyeFill(shape, size: layout.eyeSize, openness: pose.eyeOpenness)), with: .color(Color(Palette.ink)))
                if case .round(let scale) = shape, pose.eyeOpenness > 0.3 {
                    let size = CGSize(width: layout.eyeSize.width * scale, height: layout.eyeSize.height * scale)
                    eye.fill(Path(PetGeometry.eyeHighlights(size: size, openness: pose.eyeOpenness, gaze: pose.gaze)), with: .color(.white))
                }
            }
        }

        // Mouth.
        var mouth = ctx
        mouth.translateBy(x: layout.mouthCenter.x, y: layout.mouthCenter.y)
        let shapes = PetGeometry.mouth(pose.mouth, width: layout.mouthWidth)
        if let fill = shapes.fill { mouth.fill(Path(fill), with: .color(Color(Palette.ink))) }
        if let tongue = shapes.tongue { mouth.fill(Path(tongue), with: .color(Color(hex: 0xFF8C96))) }
        if let stroke = shapes.stroke {
            mouth.stroke(Path(stroke), with: .color(Color(Palette.ink)),
                         style: StrokeStyle(lineWidth: PetGeometry.mouthStrokeWidth(width: layout.mouthWidth), lineCap: .round, lineJoin: .round))
        }
    }
}
