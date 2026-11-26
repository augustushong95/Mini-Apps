import AppKit

/// Draws Mochi as a template image for the menu bar: a solid silhouette
/// with the eyes cut out, so it matches light, dark and tinted menu bars like
/// any system icon. Drawn on demand at whatever scale the display needs.
enum MenuBarIconRenderer {
    static let size = NSSize(width: 24, height: 18)

    /// What the icon shows. Coarser than `PetPose` so near-identical poses
    /// share one cached image.
    struct Key: Hashable {
        var uprightness: Int  // tenths
        var tilt: Int         // 3° steps
        var eyes: PetPose.EyeStyle
        var openness: Int     // quarters
        var droop: Int        // quarters
        var stage: GrowthStage
        var sleeping: Bool
        var badge: Bool
        /// −1, 0 or 1: where the eyes look (for the occasional glance).
        var glance: Int

        init(pose: PetPose, badge: Bool) {
            uprightness = Int((clamp(pose.uprightness) * 10).rounded())
            tilt = Int((clamp(pose.tilt, -18, 18) / 3).rounded())
            eyes = pose.eyes
            openness = Int((clamp(pose.eyeOpenness) * 4).rounded())
            droop = Int((clamp(pose.leafDroop) * 4).rounded())
            stage = pose.stage
            sleeping = pose.accessories.contains(.zzz)
            self.badge = badge && !sleeping
            glance = pose.gaze.dx > 0.5 ? 1 : (pose.gaze.dx < -0.5 ? -1 : 0)
        }

        var pose: PetPose {
            var pose = PetPose()
            pose.uprightness = Double(uprightness) / 10
            pose.tilt = Double(tilt * 3)
            pose.eyes = eyes
            pose.eyeOpenness = Double(openness) / 4
            pose.leafDroop = Double(droop) / 4
            pose.stage = stage
            pose.gaze = CGVector(dx: Double(glance), dy: 0)
            return pose
        }
    }

    private static var cache: [Key: NSImage] = [:]

    static func image(for pose: PetPose, badge: Bool = false) -> NSImage {
        let key = Key(pose: pose, badge: badge)
        if let cached = cache[key] {
            return cached
        }
        let image = NSImage(size: size, flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            draw(key, in: context, rect: rect)
            return true
        }
        image.isTemplate = true
        if cache.count > 400 {
            cache.removeAll()
        }
        cache[key] = image
        return image
    }

    private static func draw(_ key: Key, in context: CGContext, rect: CGRect) {
        let pose = key.pose
        // Mochi's canvas is a square; at 22 pt its silhouette fills the 18 pt height.
        let side: CGFloat = 22
        let layout = PetGeometry.layout(for: pose, size: side)
        let black = CGColor(gray: 0, alpha: 1)

        context.saveGState()
        context.translateBy(x: rect.midX - side / 2 - (key.badge || key.sleeping ? 1.5 : 0), y: -1.4)

        context.setFillColor(black)
        context.setStrokeColor(black)

        // Sprout, drawn a little bolder than in colour so it reads at this size.
        let sprout = PetGeometry.sprout(stage: pose.stage, droop: pose.leafDroop, size: side)
        context.saveGState()
        context.translateBy(x: layout.crown.x, y: layout.crown.y - side * 0.03)
        context.rotate(by: layout.sproutRotation)
        context.addPath(sprout.stem)
        context.setLineWidth(max(1.3, sprout.stemWidth * 1.3))
        context.setLineCap(.round)
        context.strokePath()
        context.addPath(sprout.leaves)
        context.fillPath()
        if let bud = sprout.bud {
            context.addPath(bud)
            context.fillPath()
        }
        if let center = sprout.flowerCenter {
            // Petals are too fine at this size; a round blossom reads better.
            let blossom = center.boundingBoxOfPath.insetBy(dx: -side * 0.03, dy: -side * 0.03)
            context.fillEllipse(in: blossom)
        }
        context.restoreGState()

        context.addPath(layout.body)
        context.fillPath()

        // Eyes cut out of the silhouette, a bit larger than life to stay legible.
        context.setBlendMode(.clear)
        let eyeSize = CGSize(width: layout.eyeSize.width * 1.45, height: layout.eyeSize.height * 1.35)
        for (center, shape) in zip(layout.eyeCenters, PetGeometry.eyeShapes(for: pose.eyes)) {
            context.saveGState()
            context.translateBy(x: center.x + CGFloat(key.glance) * 0.6, y: center.y)
            if shape.isStroked {
                context.addPath(PetGeometry.eyeStroke(shape, size: eyeSize))
                context.setLineWidth(1.1)
                context.setLineCap(.round)
                context.strokePath()
            } else {
                context.addPath(PetGeometry.eyeFill(shape, size: eyeSize, openness: max(0.3, pose.eyeOpenness)))
                context.fillPath()
            }
            context.restoreGState()
        }
        context.restoreGState()

        context.setBlendMode(.normal)
        context.setFillColor(black)
        context.setStrokeColor(black)
        if key.sleeping {
            // A single small "z" above the right shoulder.
            context.saveGState()
            context.translateBy(x: rect.maxX - 3.2, y: rect.maxY - 4)
            context.addPath(PetGeometry.zGlyph(size: 3.6))
            context.setLineWidth(1.1)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.strokePath()
            context.restoreGState()
        } else if key.badge {
            // A dot that says "something's waiting for you" (a break is due).
            context.fillEllipse(in: CGRect(x: rect.maxX - 4.6, y: rect.maxY - 5.4, width: 4.2, height: 4.2))
        }
    }
}
