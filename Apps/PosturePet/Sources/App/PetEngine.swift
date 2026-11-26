import AppKit
import Observation
import OSLog

/// The app's clock. Normally real time; debug builds can speed it up to walk
/// through a day in minutes.
final class AppClock {
    private(set) var scale: Double = 1
    private var anchorReal = Date.now
    private var anchorVirtual = Date.now

    var now: Date {
        anchorVirtual.addingTimeInterval(Date.now.timeIntervalSince(anchorReal) * scale)
    }

    func setScale(_ scale: Double) {
        anchorVirtual = now
        anchorReal = .now
        self.scale = scale
    }

    /// Jumps forward, for tests and debug (a day rollover, a week of growth).
    func advance(by seconds: TimeInterval) {
        anchorVirtual = anchorVirtual.addingTimeInterval(seconds)
    }
}

/// Ties sensing, timers and Mochi's rules together and publishes what the
/// UI shows. Every rule lives in a pure type (`PostureClassifier`,
/// `BreakScheduler`, `NudgePolicy`, `PetBrain`); this class only feeds them
/// and keeps the results.
@Observable
final class PetEngine {
    let settings: Preferences
    let motion: MotionHub
    let quiet: QuietDetector
    @ObservationIgnored let store: StateStore
    @ObservationIgnored let clock = AppClock()

    // MARK: Published state

    private(set) var mood: PetMood = .happy
    private(set) var pose = PetPose()
    private(set) var posture = PostureReading.unknown
    private(set) var today: DayRecord
    private(set) var happiness = 100
    private(set) var streak = 0
    private(set) var breaks: BreakScheduler
    private(set) var pet: PetProfile
    private(set) var isPresent = true
    private(set) var isLate = false
    private(set) var reaction: PetReaction?
    /// No baseline yet for the current screens (a new monitor, say).
    private(set) var needsRecenter = false
    private(set) var hasAnyBaseline = false
    private(set) var isOnboarded: Bool
    /// Best score per game (keyed by `ArcadeGame.rawValue`).
    private(set) var bestScores: [String: Int]

    /// The panel, a game or onboarding is on screen: bubbles wait.
    var isBusy = false {
        didSet {
            if oldValue, !isBusy { evaluateNudges() }
        }
    }

    /// Posture is ignored while a game uses head movement as input.
    var isPostureSuspended = false {
        didSet {
            guard oldValue != isPostureSuspended else { return }
            classifier?.reset()
            posture = .unknown
            updatePose()
        }
    }

    @ObservationIgnored var onNudge: ((NudgeKind) -> Void)?
    @ObservationIgnored var onPoseChange: ((PetPose, _ breakDue: Bool) -> Void)?
    @ObservationIgnored var onGrow: ((GrowthStage) -> Void)?

    // MARK: Private

    @ObservationIgnored private var classifier: PostureClassifier?
    /// The last few seconds of samples, for calibration.
    @ObservationIgnored private(set) var recentSamples: [HeadSample] = []
    @ObservationIgnored private var pending = PostureTotals()
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var subscriptions: [MotionSubscription] = []
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var currentDay: PetDay
    @ObservationIgnored private var lastAccounting: Date?
    @ObservationIgnored private var lastPosturePublish: TimeInterval = 0
    @ObservationIgnored private var displayArrangement = DisplayArrangement.current()
    @ObservationIgnored private var lastReportedPose: (PetPose, Bool)?
    /// Keeps App Nap from delaying the tick timer (idle sleep is still allowed).
    @ObservationIgnored private var timingActivity: NSObjectProtocol?
    @ObservationIgnored private var sleptSinceLastTick = false
    @ObservationIgnored private var lastTickAt: Date?
    @ObservationIgnored private let idleSeconds: @MainActor () -> TimeInterval

    static let tickInterval: TimeInterval = 5

    private struct PostureTotals {
        var measured: Double = 0
        var good: Double = 0
        var slouch: Double = 0
    }

    /// - Parameters:
    ///   - quietSignals: calls and full-screen apps; injectable for tests.
    ///   - idleSeconds: time since the last keyboard or mouse input; injectable for tests.
    init(
        settings: Preferences,
        motion: MotionHub,
        store: StateStore = StateStore(),
        quietSignals: @escaping @MainActor () -> QuietReason? = QuietDetector.liveSignals,
        idleSeconds: @escaping @MainActor () -> TimeInterval = IdleProbe.secondsSinceLastInput
    ) {
        self.settings = settings
        self.motion = motion
        self.store = store
        self.idleSeconds = idleSeconds
        quiet = QuietDetector(settings: settings, systemSignals: quietSignals)

        let now = Date.now
        let day = PetDay(containing: now)
        currentDay = day
        today = store.state.record(for: day) ?? DayRecord(day: day)
        breaks = store.state.scheduler
        pet = store.state.pet
        isOnboarded = store.state.onboarding.completed
        bestScores = store.state.bestScores
        breaks.setInterval(settings.breakInterval, now: now)

        rebuildClassifier()
        subscriptions.append(motion.subscribe { [weak self] sample in self?.handle(sample) })
        subscriptions.append(motion.observeEvents { [weak self] event in self?.handle(event) })
        observeSystem()
        recomputeDerived()
        timingActivity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep],
            reason: "Posture Pet's break timer"
        )
        startTimer()
        tick()
    }

    // MARK: Ticking

    private func startTimer() {
        timer?.invalidate()
        let timer = Timer(timeInterval: Self.tickInterval / clock.scale, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = min(1, Self.tickInterval / clock.scale * 0.2)
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Advances everything to now. Runs every few seconds and after any
    /// system event that changes time (wake, clock change, day change).
    func tick() {
        let now = clock.now
        let day = PetDay(containing: now)
        if day != currentDay {
            rollOver(to: day)
        }

        quiet.refresh(now: now)
        let idle = idleSeconds()
        isPresent = Presence.isPresent(
            idleSeconds: idle * clock.scale,
            motionLive: motion.isLive,
            postureKnown: posture.state != .unknown
        )
        isLate = PetBrain.isLate(now, windDownMinutes: settings.windDownMinutes)

        // A late tick with input during the gap and no sleep was a delayed
        // timer (App Nap), not time away.
        let gap = lastTickAt.map { now.timeIntervalSince($0) } ?? 0
        let gapWasPresent = !sleptSinceLastTick && idle * clock.scale < gap && gap < BreakScheduler.breakAfterAway
        sleptSinceLastTick = false
        lastTickAt = now

        if let last = lastAccounting {
            let dt = now.timeIntervalSince(last)
            if dt > 0, dt <= BreakScheduler.maxTickGap || gapWasPresent, isPresent {
                today.activeSeconds += dt
                if isLate { today.lateSeconds += dt }
            }
        }
        lastAccounting = now
        flushPostureTotals()

        if breaks.interval != settings.breakInterval {
            breaks.setInterval(settings.breakInterval, now: now)
        }
        for event in breaks.tick(now: now, present: isPresent, gapWasPresent: gapWasPresent) {
            handle(event)
        }

        recomputeDerived()
        evaluateNudges()
        // Motion access can be turned on or off in System Settings at any time.
        motion.refreshAuthorization()
        updateMotionDemand(idleSeconds: idle * clock.scale)
        save()
    }

    private func rollOver(to day: PetDay) {
        flushPostureTotals()
        save()
        currentDay = day
        today = store.state.record(for: day) ?? DayRecord(day: day)
        lastAccounting = nil

        var updated = store.state.pet
        let grew = PetBrain.evaluateGrowth(pet: &updated, days: store.state.days, today: day)
        pet = updated
        store.update { $0.pet = updated }
        if grew {
            reaction = PetReaction(kind: .celebrate)
            onGrow?(updated.stage)
        }
    }

    private func recomputeDerived() {
        happiness = PetBrain.happiness(for: today, interval: settings.breakInterval)
        today.happiness = happiness
        var days = store.state.days.filter { $0.day != currentDay }
        days.append(today)
        streak = PetBrain.streak(days: days, today: currentDay)
        updateMood()
    }

    private func updateMood() {
        let inputs = PetBrain.MoodInputs(
            isLate: isLate,
            posture: isPostureSuspended ? .unknown : posture.state,
            breakPhase: breaks.phase,
            sittingSeconds: breaks.sittingSeconds,
            interval: breaks.interval
        )
        let newMood = PetBrain.mood(inputs)
        if newMood != mood {
            if newMood == .sick { reaction = PetReaction(kind: .wobble) }
            mood = newMood
        }
        updatePose()
    }

    private func updatePose() {
        let mirror = isPostureSuspended ? nil : posture.mirror
        let newPose = mood.pose(stage: pet.stage, posture: mirror).quantized
        if newPose != pose {
            pose = newPose
        }
        let due = breaks.phase != .sitting
        if lastReportedPose?.0 != pose || lastReportedPose?.1 != due {
            lastReportedPose = (pose, due)
            onPoseChange?(pose, due)
        }
    }

    private func save() {
        let today = today
        let breaks = breaks
        store.update { state in
            state.withRecord(for: today.day) { $0 = today }
            state.scheduler = breaks
        }
    }

    /// Writes immediately (sleep and quit).
    func flush() {
        flushPostureTotals()
        save()
        store.flush()
    }

    // MARK: Breaks

    private func handle(_ event: BreakEvent) {
        switch event {
        case .becameDue:
            break
        case .completed(_, let counted):
            if counted {
                today.breaks += 1
            }
            store.update { $0.nudges.invitesThisCycle = 0 }
            if mood == .sick || mood == .tired {
                reaction = PetReaction(kind: .hop)
            }
        }
    }

    /// Records a break taken through the app.
    func recordBreak(_ kind: BreakKind) {
        let event = breaks.completeBreak(kind, at: clock.now)
        handle(event)
        if kind == .game {
            today.gamesPlayed += 1
        }
        recomputeDerived()
        save()
    }

    func snoozeBreak(minutes: Double = 10) {
        let now = clock.now
        breaks.snooze(until: now.addingTimeInterval(minutes * 60), now: now)
        recomputeDerived()
        save()
    }

    // MARK: Treats

    func addTreats(_ count: Int) {
        guard count > 0 else { return }
        pet.treats += count
        today.treatsEarned += count
        let pet = pet
        store.update { $0.pet = pet }
        save()
    }

    /// Feeds Mochi one treat. Returns false when there are none.
    @discardableResult
    func feed() -> Bool {
        guard pet.treats > 0 else { return false }
        pet.treats -= 1
        today.treatsFed += 1
        reaction = PetReaction(kind: .chew)
        let pet = pet
        store.update { $0.pet = pet }
        recomputeDerived()
        save()
        return true
    }

    /// Keeps the higher of the saved best and `score`.
    func recordScore(_ score: Int, for game: String) {
        guard score > bestScores[game] ?? 0 else { return }
        bestScores[game] = score
        store.update { $0.bestScores[game] = score }
    }

    func pet(react kind: PetReaction.Kind) {
        reaction = PetReaction(kind: kind)
    }

    func rename(to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        pet.name = trimmed.isEmpty ? "Mochi" : String(trimmed.prefix(20))
        let pet = pet
        store.update { $0.pet = pet }
    }

    // MARK: Nudges

    func evaluateNudges() {
        guard isOnboarded else { return }
        let now = clock.now
        let context = NudgeContext(
            now: now,
            day: currentDay,
            isQuiet: quiet.isQuiet,
            isBusy: isBusy,
            userPresent: isPresent,
            breakPhase: breaks.phase,
            slouchDuration: posture.state == .slouching ? posture.slouchDuration : 0,
            isLate: isLate,
            postureNudgesFrom: store.state.onboarding.nudgesFrom
        )
        let history = store.state.nudges
        guard let kind = NudgePolicy.next(context, history: history, invitesThisCycle: history.invitesThisCycle) else {
            return
        }
        // Signals can change between ticks; check once more right before showing.
        guard quiet.refresh(now: now) == nil else { return }
        store.update { state in
            NudgePolicy.record(kind, in: &state.nudges, context: context)
            if kind == .breakInvite {
                state.nudges.invitesThisCycle += 1
            }
        }
        onNudge?(kind)
    }

    func setQuiet(until date: Date?) {
        settings.quietUntil = date
        quiet.refresh(now: clock.now)
    }

    // MARK: Posture

    private func handle(_ sample: HeadSample) {
        recentSamples.append(sample)
        if let first = recentSamples.first, sample.timestamp - first.timestamp > 4 {
            recentSamples.removeAll { sample.timestamp - $0.timestamp > 3 }
        }
        guard !isPostureSuspended, var classifier else { return }
        let (reading, covered) = classifier.update(sample)
        self.classifier = classifier

        switch reading.state {
        case .upright:
            pending.measured += covered
            pending.good += covered
        case .slouching:
            pending.measured += covered
            pending.slouch += covered
        case .unknown:
            break
        }

        // Publish at most ~8 times a second, or at once when the state changes.
        let stateChanged = reading.state != posture.state
        if stateChanged || sample.timestamp - lastPosturePublish >= 0.125 {
            lastPosturePublish = sample.timestamp
            posture = reading
            if stateChanged {
                updateMood()
            } else {
                updatePose()
            }
        }
    }

    private func handle(_ event: MotionHub.Event) {
        switch event {
        case .disconnected, .stalled, .stopped:
            classifier?.reset()
            posture = .unknown
            updateMood()
        case .connected, .started, .resumed, .error:
            break
        }
    }

    private func flushPostureTotals() {
        guard pending.measured > 0 else { return }
        today.measuredSeconds += pending.measured
        today.goodPostureSeconds += pending.good
        today.slouchSeconds += pending.slouch
        pending = PostureTotals()
    }

    private func rebuildClassifier() {
        let calibration = store.state.calibration
        hasAnyBaseline = !calibration.baselines.isEmpty
        needsRecenter = hasAnyBaseline && calibration.baselines[displayArrangement] == nil
        if let baseline = calibration.baseline(for: displayArrangement) {
            classifier = PostureClassifier(baseline: baseline, sensitivity: settings.sensitivity)
        } else {
            classifier = nil
        }
        posture = .unknown
    }

    func applySensitivity() {
        classifier?.sensitivity = settings.sensitivity
    }

    private func updateMotionDemand(idleSeconds: TimeInterval) {
        let wanted = isOnboarded
            && classifier != nil
            && !isLate
            && (isPresent || idleSeconds < BreakScheduler.breakAfterAway)
        motion.setDemand(.posture, active: wanted)
    }

    // MARK: Calibration

    /// Starts streaming for calibration (this is what shows the motion
    /// permission prompt the first time).
    func beginCalibration() {
        motion.setDemand(.calibration, active: true)
    }

    func endCalibration() {
        motion.setDemand(.calibration, active: false)
    }

    /// Average head angle over the last two seconds, or nil when there's
    /// too little data or the head was moving.
    func steadyAngles(over seconds: TimeInterval = 2) -> (pitch: Double, roll: Double)? {
        guard let latest = recentSamples.last, motion.isLive else { return nil }
        let window = recentSamples.filter { latest.timestamp - $0.timestamp <= seconds }
        guard window.count >= 15 else { return nil }
        let pitches = window.map(\.gravityPitch)
        let rolls = window.map(\.gravityRoll)
        let pitch = pitches.reduce(0, +) / Double(pitches.count)
        let roll = rolls.reduce(0, +) / Double(rolls.count)
        let spread = (pitches.max() ?? 0) - (pitches.min() ?? 0)
        guard spread < 6 else { return nil }
        return (pitch, roll)
    }

    /// Saves the current head angle as "sitting well" for these screens.
    @discardableResult
    func captureBaseline() -> Bool {
        guard let angles = steadyAngles() else { return false }
        let baseline = PostureBaseline(pitch: angles.pitch, roll: angles.roll, capturedAt: clock.now)
        let arrangement = displayArrangement
        store.update { $0.calibration.baselines[arrangement] = baseline }
        rebuildClassifier()
        updateMotionDemand(idleSeconds: 0)
        return true
    }

    // MARK: Onboarding

    func completeOnboarding(name: String) {
        rename(to: name)
        let day = currentDay
        store.update { state in
            state.onboarding.completed = true
            if state.pet.adoptedOn == nil {
                state.pet.adoptedOn = day
            }
            // The first day is for learning: no posture nudges until tomorrow.
            state.onboarding.nudgesFrom = state.onboarding.nudgesFrom ?? day.adding(days: 1)
        }
        pet = store.state.pet
        isOnboarded = true
        store.flush()
        tick()
    }

    /// Starts Mochi over: history, growth, treats and calibration are
    /// cleared. Onboarding stays done; Mochi is adopted again today.
    func resetAllData() {
        let day = currentDay
        let name = pet.name
        store.update { state in
            state = SavedState()
            state.onboarding.completed = true
            state.onboarding.safetyNoteShown = true
            state.onboarding.nudgesFrom = day.adding(days: 1)
            state.pet.name = name
            state.pet.adoptedOn = day
        }
        store.flush()
        reloadFromStore()
    }

    /// Re-reads every published value from the store (after a reset, or a
    /// debug restore).
    private func reloadFromStore() {
        today = store.state.record(for: currentDay) ?? DayRecord(day: currentDay)
        breaks = store.state.scheduler
        breaks.setInterval(settings.breakInterval, now: clock.now)
        pet = store.state.pet
        bestScores = store.state.bestScores
        isOnboarded = store.state.onboarding.completed
        pending = PostureTotals()
        rebuildClassifier()
        recomputeDerived()
    }

    /// Re-sends the current pose to `onPoseChange` (after wiring it up).
    func publishPose() {
        lastReportedPose = nil
        updatePose()
    }

    // MARK: System events

    private func observeSystem() {
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.sleptSinceLastTick = true
                self?.flush()
            }
        })
        observers.append(workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        })
        let center = NotificationCenter.default
        for name in [Notification.Name.NSSystemClockDidChange, .NSSystemTimeZoneDidChange, .NSCalendarDayChanged] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            })
        }
        observers.append(center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let arrangement = DisplayArrangement.current()
                guard arrangement != self.displayArrangement else { return }
                self.displayArrangement = arrangement
                self.rebuildClassifier()
            }
        })
    }

    // MARK: Debug

    #if DEBUG
    func setTimeScale(_ scale: Double) {
        clock.setScale(scale)
        lastAccounting = nil
        startTimer()
        tick()
    }

    func debugSimulate(_ sample: HeadSample) {
        if classifier == nil {
            // Simulated posture needs a baseline; use "straight ahead".
            let arrangement = displayArrangement
            store.update { $0.calibration.baselines[arrangement] = PostureBaseline(pitch: 0, roll: 0, capturedAt: .now) }
            rebuildClassifier()
        }
        handle(sample)
    }

    /// Adds sitting time; enough of it makes a break due, then makes Mochi sick.
    func debugAddSitting(minutes: Double) {
        for event in breaks.debugAddSitting(minutes * 60, now: clock.now) {
            handle(event)
        }
        recomputeDerived()
        evaluateNudges()
    }

    func debugSetStage(_ stage: GrowthStage) {
        pet.stage = stage
        let pet = pet
        store.update { $0.pet = pet }
        updatePose()
    }

    /// Puts back a copy of the state taken earlier (the AirPods demo uses
    /// this so it leaves no trace in the real stats).
    func debugRestore(_ state: SavedState) {
        store.update { $0 = state }
        store.flush()
        reloadFromStore()
    }

    func debugResetOnboarding() {
        store.update { $0.onboarding = OnboardingProgress() }
        isOnboarded = false
    }
    #endif
}

/// Identifies the current set of screens, so posture baselines can be kept
/// per setup (laptop alone vs. an external monitor).
enum DisplayArrangement {
    static func current() -> String {
        let ids = NSScreen.screens.compactMap {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
        }
        return ids.sorted().map(String.init).joined(separator: "+")
    }
}
