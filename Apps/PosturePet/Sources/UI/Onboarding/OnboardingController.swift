import AppKit
import Observation
import MenuBarKit

/// First-run setup (or just re-centring posture) in a centred window.
final class OnboardingController {
    var onFinish: (() -> Void)?

    private let panel: FloatingPanel
    private let model: OnboardingModel

    init(engine: PetEngine, preferences: Preferences, recenterOnly: Bool = false) {
        model = OnboardingModel(engine: engine, preferences: preferences, recenterOnly: recenterOnly)
        panel = FloatingPanel(size: OnboardingView.size, canBecomeKey: true, level: .floating)
        panel.setContent(OnboardingView(model: model))
        model.onDone = { [weak self] in self?.finish() }
        // Esc only closes re-centring; first-run setup needs finishing.
        panel.onCancel = { [weak self] in
            guard let self, recenterOnly else { return }
            finish()
        }
    }

    func show() {
        NSApp.activate()
        panel.present(at: PanelPlacement.centered(size: OnboardingView.size), animated: true)
        panel.makeKey()
    }

    func bringToFront() {
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
    }

    private func finish() {
        model.stop()
        panel.dismiss(animated: true) { [weak self] in
            self?.onFinish?()
        }
    }
}

@Observable
final class OnboardingModel {
    enum Step: Int, CaseIterable {
        case hello, airPods, calibrate, rhythm, home, finish
    }

    enum CaptureState: Equatable {
        case idle, capturing, success, failed
    }

    let engine: PetEngine
    let preferences: Preferences
    let recenterOnly: Bool

    var step: Step
    var name: String
    var wantsDesktopPet = true
    private(set) var captureState: CaptureState = .idle
    private(set) var captureProgress: Double = 0
    /// Live head angles relative to where the head was when the step opened.
    private(set) var mirror = PostureMirror.neutral
    private(set) var waitingForMotion = false

    @ObservationIgnored var onDone: (() -> Void)?
    @ObservationIgnored private var subscription: MotionSubscription?
    @ObservationIgnored private var reference: (pitch: Double, roll: Double)?
    @ObservationIgnored private var lastMirrorUpdate: TimeInterval = 0
    @ObservationIgnored private var captureTimer: Timer?

    init(engine: PetEngine, preferences: Preferences, recenterOnly: Bool) {
        self.engine = engine
        self.preferences = preferences
        self.recenterOnly = recenterOnly
        step = recenterOnly ? .calibrate : .hello
        name = engine.pet.name
        wantsDesktopPet = preferences.desktopPetEnabled
        if recenterOnly {
            startMotion()
        }
    }

    var motion: MotionHub { engine.motion }

    var steps: [Step] {
        recenterOnly ? [.calibrate] : Step.allCases
    }

    var motionAvailable: Bool {
        motion.isSupported && motion.canStream
    }

    // MARK: Navigation

    func next() {
        switch step {
        case .hello:
            engine.rename(to: name)
            step = .airPods
        case .airPods:
            step = .calibrate
        case .calibrate:
            if recenterOnly {
                onDone?()
            } else {
                step = .rhythm
            }
        case .rhythm:
            step = .home
        case .home:
            preferences.desktopPetEnabled = wantsDesktopPet
            step = .finish
        case .finish:
            engine.completeOnboarding(name: name)
            onDone?()
        }
    }

    func back() {
        guard let previous = Step(rawValue: step.rawValue - 1), !recenterOnly else { return }
        step = previous
    }

    /// "I don't have AirPods": timer mode, and keyboard games.
    func skipAirPods() {
        stopMotion()
        step = .rhythm
    }

    // MARK: Motion

    /// Starts streaming. The first time, macOS asks for motion access here,
    /// right after the screen that explains why.
    func startMotion() {
        waitingForMotion = true
        engine.beginCalibration()
        subscription = motion.subscribe { [weak self] sample in
            self?.handle(sample)
        }
    }

    private func stopMotion() {
        subscription?.cancel()
        subscription = nil
        engine.endCalibration()
        waitingForMotion = false
    }

    func stop() {
        captureTimer?.invalidate()
        stopMotion()
    }

    private func handle(_ sample: HeadSample) {
        waitingForMotion = false
        if reference == nil {
            reference = (sample.gravityPitch, sample.gravityRoll)
        }
        guard let reference, sample.timestamp - lastMirrorUpdate >= 1.0 / 15 else { return }
        lastMirrorUpdate = sample.timestamp
        let down = max(0, reference.pitch - sample.gravityPitch)
        mirror = PostureMirror(
            uprightness: clamp(1 - (down - 4) / 22),
            tilt: clamp(sample.gravityRoll - reference.roll, -18, 18)
        )
    }

    // MARK: Calibration

    /// Holds still for three seconds, then saves the sitting position.
    func capture() {
        guard captureState != .capturing else { return }
        captureState = .capturing
        captureProgress = 0
        let start = Date.now
        captureTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.captureProgress = min(1, Date.now.timeIntervalSince(start) / 3)
                guard self.captureProgress >= 1 else { return }
                self.captureTimer?.invalidate()
                self.captureTimer = nil
                if self.engine.captureBaseline() {
                    self.captureState = .success
                    self.reference = nil
                } else {
                    self.captureState = .failed
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        captureTimer = timer
    }

    func retryCapture() {
        captureState = .idle
        captureProgress = 0
    }
}
