import AppKit
import Testing
@testable import PosturePet

/// Mochi's look: moods, poses, shapes and the menu bar icon.
struct AppearanceTests {
    @Test(arguments: PetMood.allCases)
    func everyMoodHasItsExpression(_ mood: PetMood) {
        let pose = mood.pose(stage: .sprout, posture: nil)
        switch mood {
        case .happy:
            #expect(pose.eyes == .open && pose.mouth == .smile && pose.accessories.isEmpty)
        case .tired:
            #expect(pose.eyeOpenness < 1 && pose.accessories.contains(.sweat))
        case .slumped:
            #expect(pose.uprightness < 0.5 && pose.gaze.dy < 0)
        case .sleepy:
            #expect(pose.eyes == .closed && pose.accessories.contains(.zzz))
        case .sick:
            #expect(pose.paleness == 1 && pose.accessories.contains(.thermometer))
        }
        #expect(pose.stage == .sprout)
    }

    @Test func livePostureDrivesTheBodyExceptWhenAsleep() {
        let slumped = PostureMirror(uprightness: 0.1, tilt: 12)
        let awake = PetMood.happy.pose(stage: .bud, posture: slumped)
        #expect(awake.uprightness == 0.1)
        #expect(awake.tilt == 12)
        #expect(awake.leafDroop > 0.8)

        let asleep = PetMood.sleepy.pose(stage: .bud, posture: slumped)
        #expect(asleep.uprightness == 0.9, "Sleeping Mochi doesn't mirror")
        #expect(asleep.tilt == 0)
    }

    @Test func quantizingIgnoresJitter() {
        var a = PetPose()
        a.uprightness = 0.801
        a.tilt = 4.2
        var b = a
        b.uprightness = 0.803
        b.tilt = 3.9
        #expect(a.quantized == b.quantized)
    }

    @Test(arguments: GrowthStage.allCases)
    func bodyAndSproutFitTheCanvas(_ stage: GrowthStage) {
        for uprightness in [0.0, 0.5, 1.0] {
            for tilt in [-18.0, 0, 18] {
                var pose = PetMood.happy.pose(stage: stage, posture: nil)
                pose.uprightness = uprightness
                pose.tilt = tilt
                let size: CGFloat = 200
                let layout = PetGeometry.layout(for: pose, size: size)
                let bounds = layout.body.boundingBoxOfPath
                #expect(bounds.minX >= 0 && bounds.maxX <= size)
                #expect(abs(bounds.minY - layout.base) < 0.5, "The base stays on the ground when leaning")
                let sprout = PetGeometry.sprout(stage: stage, droop: pose.leafDroop, size: size)
                #expect(layout.crown.y + sprout.leaves.boundingBoxOfPath.maxY <= size)
            }
        }
    }

    @Test func eyesAreSymmetricWhenLookingAhead() {
        let layout = PetGeometry.layout(for: PetPose(), size: 200)
        let middle = (layout.eyeCenters[0].x + layout.eyeCenters[1].x) / 2
        #expect(abs(middle - layout.centerX) < 0.01)
        #expect(layout.eyeCenters[0].y == layout.eyeCenters[1].y)
    }

    @Test func leaningDropsTheEyeOnThatSide() {
        var pose = PetPose()
        pose.tilt = 14
        let layout = PetGeometry.layout(for: pose, size: 200)
        #expect(layout.eyeCenters[1].y < layout.eyeCenters[0].y, "Right eye lower when leaning right")
        #expect(layout.crown.x > layout.centerX, "The dome slides right")
    }

    @Test func eachStageGrowsItsOwnSprout() {
        let seedling = PetGeometry.sprout(stage: .seedling, droop: 0, size: 200)
        let bud = PetGeometry.sprout(stage: .bud, droop: 0, size: 200)
        let bloom = PetGeometry.sprout(stage: .bloom, droop: 0, size: 200)
        #expect(seedling.bud == nil && seedling.petals == nil)
        #expect(bud.bud != nil && bud.petals == nil)
        #expect(bloom.petals != nil && bloom.flowerCenter != nil)
        let wilted = PetGeometry.sprout(stage: .seedling, droop: 1, size: 200)
        #expect(wilted.tip.x > seedling.tip.x, "A drooping stem bends over")
    }

    @Test func menuBarIconIsATemplateThatMatchesTheBar() {
        let image = MenuBarIconRenderer.image(for: PetPose())
        #expect(image.isTemplate, "Adapts to light, dark and tinted menu bars")
        #expect(image.size == NSSize(width: 24, height: 18))
        #expect(MenuBarIconRenderer.image(for: PetPose()) === image, "Cached")
    }

    @Test func breakBadgeIsHiddenWhileAsleep() {
        let sleepy = PetMood.sleepy.pose(stage: .sprout, posture: nil)
        #expect(!MenuBarIconRenderer.Key(pose: sleepy, badge: true).badge)
        #expect(MenuBarIconRenderer.Key(pose: PetPose(), badge: true).badge)
    }

    @Test func petViewRendersEveryMoodWithoutAWindow() {
        for mood in PetMood.allCases {
            let view = PetLayerView(frame: NSRect(x: 0, y: 0, width: 160, height: 160))
            view.idleAnimationsEnabled = false
            view.apply(mood.pose(stage: .bloom, posture: nil), animated: false)
            #expect(view.pose.eyes == mood.pose(stage: .bloom, posture: nil).eyes)
            let canvas = view.layer?.sublayers?.first
            #expect(canvas != nil, "Mochi's layer tree is in place")
            #expect((canvas?.bounds.width ?? 0) == 160)
        }
    }
}
