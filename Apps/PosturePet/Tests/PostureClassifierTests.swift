import Foundation
import Testing
@testable import PosturePet

/// A sample whose gravity-derived pitch and roll equal the given degrees.
func headSample(pitch: Double, roll: Double = 0, at time: TimeInterval, sensor: HeadSample.Sensor = .left) -> HeadSample {
    .synthetic(pitch: pitch, roll: roll, timestamp: time, sensor: sensor)
}

struct PostureClassifierTests {
    private func classifier(_ sensitivity: PostureSensitivity = .normal) -> PostureClassifier {
        PostureClassifier(baseline: PostureBaseline(pitch: 0, roll: 0, capturedAt: .now), sensitivity: sensitivity)
    }

    /// Feeds samples at 25 Hz holding `pitch` for `duration` seconds, starting at `start`.
    @discardableResult
    private func hold(
        _ c: inout PostureClassifier, pitch: Double, roll: Double = 0, from start: TimeInterval, for duration: TimeInterval
    ) -> (PostureReading, TimeInterval) {
        var covered: TimeInterval = 0
        var time = start
        var reading = c.reading
        while time <= start + duration {
            let result = c.update(headSample(pitch: pitch, roll: roll, at: time))
            reading = result.reading
            covered += result.covered
            time += 0.04
        }
        return (reading, covered)
    }

    @Test func helperProducesRequestedAngles() {
        let sample = headSample(pitch: -20, roll: 10, at: 0)
        #expect(abs(sample.gravityPitch - -20) < 0.001)
        #expect(abs(sample.gravityRoll - 10) < 0.5)
    }

    @Test func sittingWellIsUpright() {
        var c = classifier()
        let (reading, _) = hold(&c, pitch: -5, from: 0, for: 300)
        #expect(reading.state == .upright)
        #expect(reading.mirror?.uprightness ?? 0 > 0.9)
    }

    @Test func aGlanceDownIsNotASlump() {
        var c = classifier()
        hold(&c, pitch: 0, from: 0, for: 10)
        let (down, _) = hold(&c, pitch: -30, from: 10, for: 60)
        #expect(down.state == .upright)
        let (back, _) = hold(&c, pitch: 0, from: 70.04, for: 10)
        #expect(back.state == .upright)
        // The dwell clock reset, so another minute down still isn't a slump.
        let (again, _) = hold(&c, pitch: -30, from: 80.08, for: 60)
        #expect(again.state == .upright)
    }

    @Test func stayingDownBecomesASlump() {
        var c = classifier()
        let (reading, _) = hold(&c, pitch: -26, from: 0, for: 125)
        #expect(reading.state == .slouching)
        #expect(reading.slouchDuration > 0)
        #expect(reading.mirror?.uprightness ?? 1 < 0.2)
    }

    @Test func dippingBetweenTheLinesKeepsTheDwellClock() {
        var c = classifier()
        hold(&c, pitch: -22, from: 0, for: 60)
        // 15° down: above the 12° exit line, so the clock keeps running.
        hold(&c, pitch: -15, from: 60.04, for: 30)
        let (reading, _) = hold(&c, pitch: -22, from: 90.08, for: 35)
        #expect(reading.state == .slouching)
    }

    @Test func hysteresisHoldsASlumpUntilClearlyBackUp() {
        var c = classifier()
        hold(&c, pitch: -26, from: 0, for: 125)
        // Between the lines: still slouching.
        let (between, _) = hold(&c, pitch: -15, from: 125.04, for: 20)
        #expect(between.state == .slouching)
        // Above the exit line, but not yet for the recovery time.
        let (brief, _) = hold(&c, pitch: -5, from: 145.08, for: 2)
        #expect(brief.state == .slouching)
        let (recovered, _) = hold(&c, pitch: -5, from: 147.12, for: 6)
        #expect(recovered.state == .upright)
    }

    @Test func extremeAnglesAreUnknown() {
        var c = classifier()
        hold(&c, pitch: 0, from: 0, for: 5)
        let (lyingBack, _) = hold(&c, pitch: 70, from: 5.04, for: 10)
        #expect(lyingBack.state == .unknown)
        #expect(lyingBack.mirror == nil)
        let (sideways, _) = hold(&c, pitch: 0, roll: 50, from: 15.08, for: 10)
        #expect(sideways.state == .unknown)
        // Once settled, unknown time isn't measured.
        let (_, covered) = hold(&c, pitch: 0, roll: 50, from: 25.12, for: 10)
        #expect(covered == 0)
    }

    @Test func aLongGapForgetsTheSlump() {
        var c = classifier()
        hold(&c, pitch: -26, from: 0, for: 125)
        #expect(c.reading.state == .slouching)
        let (after, covered) = hold(&c, pitch: -26, from: 200, for: 1)
        #expect(after.state == .upright, "The dwell clock restarted")
        #expect(covered < 1.1)
    }

    @Test func switchingBudsRestarts() {
        var c = classifier()
        hold(&c, pitch: -26, from: 0, for: 125)
        let result = c.update(headSample(pitch: -26, at: 125.1, sensor: .right))
        #expect(result.reading.state == .upright)
        #expect(result.covered == 0)
    }

    @Test func coveredTimeMatchesElapsedTime() {
        var c = classifier()
        let (_, covered) = hold(&c, pitch: 0, from: 0, for: 60)
        #expect(abs(covered - 60) < 0.1)
    }

    @Test func sensitivityChangesTheThreshold() {
        var gentle = classifier(.gentle)
        var strict = classifier(.strict)
        let (g, _) = hold(&gentle, pitch: -16, from: 0, for: 200)
        let (s, _) = hold(&strict, pitch: -16, from: 0, for: 200)
        #expect(g.state == .upright)
        #expect(s.state == .slouching)
    }
}
