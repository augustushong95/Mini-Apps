import CoreGraphics
import Foundation
import Testing
@testable import PosturePet

/// Mochi's behavior: the act catalog, the director that picks acts, and the
/// lines it says.
struct BehaviorTests {
    // MARK: Catalog

    @Test(arguments: PetSituation.all)
    func everySituationHasEnoughVariety(_ situation: PetSituation) {
        let acts = Set(BehaviorDirector.pool(for: situation).map(\.act))
        let needed = situation.isEveryday ? 3 : 2
        #expect(acts.count >= needed, "\(situation) has only \(acts.count) acts")
    }

    @Test(arguments: PetSituation.all)
    func everydaySituationsStillReactWithReduceMotion(_ situation: PetSituation) {
        guard situation.isEveryday else { return }
        let faceOnly = BehaviorDirector.pool(for: situation).filter { $0.act.script.isFaceOnly }
        #expect(!faceOnly.isEmpty, "\(situation) goes silent with Reduce Motion")
    }

    @Test func thereAreDozensOfActsAndEveryOneIsUsed() {
        #expect(PetAct.allCases.count >= 45)
        let used = Set(PetSituation.all.flatMap { BehaviorDirector.pool(for: $0).map(\.act) })
        let unused = Set(PetAct.allCases).subtracting(used)
        #expect(unused.isEmpty, "Never chosen: \(unused)")
    }

    @Test(arguments: PetAct.allCases)
    func scriptsStayInsideTheirDuration(_ act: PetAct) {
        let script = act.script
        #expect(script.duration > 0.5 && script.duration <= 3.2, "Acts are short")
        #expect(script.faces.allSatisfy { $0.at >= 0 && $0.at < script.duration })
        #expect(script.effects.allSatisfy { $0.at >= 0 && $0.at < script.duration })
        #expect(script.motions.allSatisfy { $0.at >= 0 && $0.at < script.duration })
        #expect(!script.faces.isEmpty || !script.motions.isEmpty || !script.effects.isEmpty, "Does something")
    }

    @Test func weightsArePositive() {
        for situation in PetSituation.all {
            #expect(BehaviorDirector.pool(for: situation).allSatisfy { $0.weight > 0 })
        }
    }

    // MARK: Director

    @Test func neverRepeatsTheLastThree() {
        var director = BehaviorDirector(seed: 7)
        var history: [PetAct] = []
        for step in 0..<400 {
            guard let act = director.pick(.idle(.happy), now: Double(step) * 1000) else {
                Issue.record("No act")
                return
            }
            #expect(!history.suffix(3).contains(act), "Repeated \(act)")
            history.append(act)
        }
        #expect(Set(history).count >= 10, "Uses the whole pool over time")
    }

    @Test func smallPoolsStillAvoidTheVeryLastAct() {
        var director = BehaviorDirector(seed: 3)
        var last: PetAct?
        for step in 0..<100 {
            let act = director.pick(.airPodsConnected, now: Double(step) * 100)
            #expect(act != nil)
            #expect(act != last)
            last = act
        }
    }

    @Test func rareActsWaitOutTheirCooldown() {
        var director = BehaviorDirector(seed: 11)
        var rollTimes: [Double] = []
        var now = 0.0
        while now < 3000 {
            if director.pick(.idle(.happy), now: now) == .roll {
                rollTimes.append(now)
            }
            now += 5
        }
        let gaps = zip(rollTimes.dropFirst(), rollTimes).map { $0 - $1 }
        #expect(!rollTimes.isEmpty)
        #expect(gaps.allSatisfy { $0 >= PetAct.roll.script.cooldown })
    }

    @Test func reduceMotionOnlyPicksFaceOnlyActs() {
        var director = BehaviorDirector(seed: 5)
        director.reduceMotion = true
        for situation in PetSituation.all {
            for step in 0..<20 {
                if let act = director.pick(situation, now: Double(step) * 100) {
                    #expect(act.script.isFaceOnly, "\(act) moves Mochi")
                }
            }
        }
    }

    @Test func sameSeedSameChoices() {
        var a = BehaviorDirector(seed: 42)
        var b = BehaviorDirector(seed: 42)
        let first = (0..<30).map { a.pick(.tapped, now: Double($0) * 50) }
        let second = (0..<30).map { b.pick(.tapped, now: Double($0) * 50) }
        #expect(first == second)
    }

    @Test func idleActsComeEveryTwelveToThirtyFiveSeconds() {
        var director = BehaviorDirector(seed: 9)
        for _ in 0..<200 {
            let delay = director.nextIdleDelay()
            #expect(delay >= 12 && delay <= 35)
        }
    }

    // MARK: Faces and shapes

    @Test(arguments: [PetPose.EyeStyle.open, .happy, .closed, .wink, .star, .dizzy, .wide])
    func everyEyeStyleStaysOnTheFace(_ style: PetPose.EyeStyle) {
        let layout = PetGeometry.layout(for: PetPose(), size: 200)
        let shapes = PetGeometry.eyeShapes(for: style)
        #expect(shapes.count == 2)
        for (shape, center) in zip(shapes, layout.eyeCenters) {
            let path = shape.isStroked
                ? PetGeometry.eyeStroke(shape, size: layout.eyeSize)
                : PetGeometry.eyeFill(shape, size: layout.eyeSize, openness: 1)
            var move = CGAffineTransform(translationX: center.x, y: center.y)
            let placed = path.copy(using: &move)!.boundingBoxOfPath
            let body = layout.body.boundingBoxOfPath
            #expect(body.contains(placed), "\(style) eye spills off the body")
            #expect(abs(placed.midX - layout.centerX) > layout.bodyWidth * 0.1, "Eyes don't meet in the middle")
        }
    }

    @Test func winkClosesOneEye() {
        let shapes = PetGeometry.eyeShapes(for: .wink)
        #expect(shapes[0] != shapes[1])
    }

    @Test(arguments: [PetPose.MouthStyle.smile, .grin, .flat, .frown, .wobble, .oh, .cat, .tongue, .yawn, .pout])
    func everyMouthFitsBetweenTheCheeks(_ style: PetPose.MouthStyle) {
        let layout = PetGeometry.layout(for: PetPose(), size: 200)
        let shapes = PetGeometry.mouth(style, width: layout.mouthWidth)
        let parts = [shapes.stroke, shapes.fill, shapes.tongue].compactMap { $0 }
        #expect(!parts.isEmpty)
        for part in parts {
            let box = part.boundingBoxOfPath
            #expect(box.width <= layout.bodyWidth * 0.3, "\(style) is too wide")
            #expect(box.maxY <= layout.eyeCenters[0].y - layout.mouthCenter.y, "\(style) reaches the eyes")
        }
    }

    @Test func faceOverlaysOnlyChangeWhatTheySay() {
        var pose = PetPose()
        pose.uprightness = 0.4
        pose.tilt = 9
        let face = PetFace(eyes: .star, mouth: .grin)
        let result = face.applied(to: pose)
        #expect(result.eyes == .star && result.mouth == .grin)
        #expect(result.uprightness == 0.4 && result.tilt == 9, "Posture mirroring keeps going")
        #expect(result.eyeOpenness == pose.eyeOpenness)
    }

    @Test(arguments: [Character("!"), "?", "♪"])
    func effectGlyphsAreDrawable(_ character: Character) {
        let box = PetGeometry.glyph(character, size: 20).boundingBoxOfPath
        #expect(!box.isEmpty && box.height > 8)
        #expect(abs(box.midX) < 1 && abs(box.midY) < 1, "Centred")
    }

    // MARK: Lines

    @Test(arguments: PetMood.allCases)
    func eachMoodHasManyLines(_ mood: PetMood) {
        #expect(Set(PetLines.pool(for: mood, hour: 10)).count >= 8)
        #expect(PetLines.pool(for: mood, hour: 10).allSatisfy { $0.count <= 28 }, "Fits the bubble")
    }

    @Test func linesNeverRepeatBackToBack() {
        var rotator = PetLines.Rotator(seed: 1)
        var last = ""
        for _ in 0..<200 {
            let line = rotator.next(from: PetLines.pool(for: .happy, hour: 9))
            #expect(line != last)
            last = line
        }
    }

    @Test func bubbleTitlesVary() {
        for kind in [NudgeKind.breakInvite, .posture, .windDown] {
            #expect(PetLines.bubbleTitles(for: kind).count >= 3)
        }
    }
}
