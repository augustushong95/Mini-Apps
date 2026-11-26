#if DEBUG
import AppKit
import CoreMotion
import Observation

/// Milestone 0 diagnostics: records whether headphone motion keeps arriving
/// while the app is in the background, and which quiet signals the sandbox
/// lets us read. Keeps only counts and angles on screen; nothing is saved.
@Observable
final class SensorLabRecorder {
    struct Bucket: Identifiable {
        let start: Date
        var samples = 0
        var activeSeconds = 0
        var lockedSeconds = 0
        var screensAsleepSeconds = 0
        var longestGap: TimeInterval = 0
        var id: Date { start }
    }

    struct LogLine: Identifiable {
        let id = UUID()
        let time: Date
        let text: String
    }

    struct Live {
        var gravityPitch: Double = 0
        var gravityRoll: Double = 0
        var attitude = SIMD3<Double>(repeating: 0)
        var gravity = SIMD3<Double>(repeating: 0)
        var sensor: HeadSample.Sensor = .unknown
        var rate: Double = 0
    }

    enum SignStep: Equatable {
        case idle, neutral, down, right, done
    }

    let hub: MotionHub

    private(set) var isRecording = false
    private(set) var startedAt: Date?
    private(set) var buckets: [Bucket] = []
    private(set) var log: [LogLine] = []
    private(set) var live = Live()
    private(set) var totalSamples = 0
    private(set) var gapsOverOneSecond = 0
    private(set) var longestGap: TimeInterval = 0

    private(set) var audio = AudioInputProbe.Snapshot(inputProcesses: [], runningInputDevices: [], processListAvailable: false)
    private(set) var camera = CameraProbe.Snapshot(deviceCount: 0, runningDevices: [])
    private(set) var display = DisplayProbe.Snapshot(isMirroring: false, frontmostCoversScreen: false, frontmostApp: nil)
    private(set) var idleSeconds: TimeInterval = 0
    private(set) var isLocked = false
    private(set) var screensAsleep = false
    private(set) var sawLockNotification = false

    private(set) var signStep: SignStep = .idle
    private(set) var pitchDownSign: Double?
    private(set) var rollRightSign: Double?

    var holdsActivity = false {
        didSet { updateActivityAssertion() }
    }

    @ObservationIgnored private var subscriptions: [MotionSubscription] = []
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var lastTimestamp: TimeInterval?
    @ObservationIgnored private var recentSampleTimes: [Date] = []
    @ObservationIgnored private var lastLiveUpdate = Date.distantPast
    @ObservationIgnored private var latestSample: HeadSample?
    @ObservationIgnored private var neutralGravity: SIMD3<Double>?
    @ObservationIgnored private var activity: NSObjectProtocol?
    @ObservationIgnored private var tick = 0

    init(hub: MotionHub) {
        self.hub = hub
        observeSystem()
        pollSignals()
    }

    // MARK: Recording

    func start() {
        guard !isRecording else { return }
        isRecording = true
        startedAt = .now
        buckets = [Bucket(start: Self.minuteStart(.now))]
        totalSamples = 0
        gapsOverOneSecond = 0
        longestGap = 0
        lastTimestamp = nil
        record("Recording started")

        subscriptions = [
            hub.subscribe { [weak self] sample in self?.receive(sample) },
            hub.observeEvents { [weak self] event in self?.record("Motion: \(event)") },
        ]
        hub.setDemand(.diagnostics, active: true)

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.secondTick() }
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        guard isRecording else { return }
        isRecording = false
        hub.setDemand(.diagnostics, active: false)
        subscriptions.forEach { $0.cancel() }
        subscriptions = []
        timer?.invalidate()
        timer = nil
        record("Recording stopped")
    }

    private func receive(_ sample: HeadSample) {
        let now = Date.now
        totalSamples += 1
        if let lastTimestamp {
            let gap = sample.timestamp - lastTimestamp
            if gap > 1 { gapsOverOneSecond += 1 }
            longestGap = max(longestGap, gap)
            currentBucket { $0.longestGap = max($0.longestGap, gap) }
        }
        lastTimestamp = sample.timestamp
        currentBucket { $0.samples += 1 }
        latestSample = sample

        recentSampleTimes.append(now)
        if now.timeIntervalSince(lastLiveUpdate) >= 0.1 {
            lastLiveUpdate = now
            recentSampleTimes.removeAll { now.timeIntervalSince($0) > 1 }
            live = Live(
                gravityPitch: sample.gravityPitch,
                gravityRoll: sample.gravityRoll,
                attitude: sample.attitude,
                gravity: sample.gravity,
                sensor: sample.sensor,
                rate: Double(recentSampleTimes.count)
            )
        }
    }

    private func secondTick() {
        tick += 1
        let active = NSApp.isActive
        currentBucket { bucket in
            if active { bucket.activeSeconds += 1 }
            if isLocked { bucket.lockedSeconds += 1 }
            if screensAsleep { bucket.screensAsleepSeconds += 1 }
        }
        if tick.isMultiple(of: 2) {
            pollSignals()
        }
    }

    private func currentBucket(_ update: (inout Bucket) -> Void) {
        guard isRecording else { return }
        let minute = Self.minuteStart(.now)
        if buckets.last?.start != minute {
            buckets.append(Bucket(start: minute))
        }
        update(&buckets[buckets.count - 1])
    }

    private static func minuteStart(_ date: Date) -> Date {
        Date(timeIntervalSinceReferenceDate: (date.timeIntervalSinceReferenceDate / 60).rounded(.down) * 60)
    }

    // MARK: Signals

    private func pollSignals() {
        idleSeconds = IdleProbe.secondsSinceLastInput()

        let newAudio = AudioInputProbe.snapshot()
        if newAudio.isMicInUse != audio.isMicInUse {
            record("Mic \(newAudio.isMicInUse ? "in use" : "free") — processes: \(newAudio.inputProcesses), devices: \(newAudio.runningInputDevices)")
        }
        audio = newAudio

        let newCamera = CameraProbe.snapshot()
        if newCamera.isCameraInUse != camera.isCameraInUse {
            record("Camera \(newCamera.isCameraInUse ? "in use" : "off") — \(newCamera.runningDevices)")
        }
        camera = newCamera

        let newDisplay = DisplayProbe.snapshot()
        if newDisplay.isMirroring != display.isMirroring {
            record("Display mirroring \(newDisplay.isMirroring ? "on" : "off")")
        }
        if newDisplay.frontmostCoversScreen != display.frontmostCoversScreen {
            record("Full-screen front app \(newDisplay.frontmostCoversScreen ? "yes" : "no") (\(newDisplay.frontmostApp ?? "?"))")
        }
        display = newDisplay
    }

    private func observeSystem() {
        let workspace = NSWorkspace.shared.notificationCenter
        let workspaceEvents: [(Notification.Name, String)] = [
            (NSWorkspace.willSleepNotification, "Mac will sleep"),
            (NSWorkspace.didWakeNotification, "Mac woke"),
            (NSWorkspace.screensDidSleepNotification, "Screens slept"),
            (NSWorkspace.screensDidWakeNotification, "Screens woke"),
            (NSWorkspace.sessionDidResignActiveNotification, "Session resigned (user switch)"),
            (NSWorkspace.sessionDidBecomeActiveNotification, "Session active"),
        ]
        for (name, text) in workspaceEvents {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if name == NSWorkspace.screensDidSleepNotification { self.screensAsleep = true }
                    if name == NSWorkspace.screensDidWakeNotification { self.screensAsleep = false }
                    self.record(text)
                }
            })
        }

        let distributed = DistributedNotificationCenter.default()
        for (name, locked) in [("com.apple.screenIsLocked", true), ("com.apple.screenIsUnlocked", false)] {
            observers.append(distributed.addObserver(forName: .init(name), object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.isLocked = locked
                    self.sawLockNotification = true
                    self.record(locked ? "Screen locked" : "Screen unlocked")
                }
            })
        }

        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.record("App became active") }
        })
        observers.append(center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.record("App resigned active") }
        })
    }

    private func record(_ text: String) {
        log.append(LogLine(time: .now, text: text))
        if log.count > 400 {
            log.removeFirst(log.count - 400)
        }
    }

    private func updateActivityAssertion() {
        if holdsActivity, activity == nil {
            activity = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiatedAllowingIdleSystemSleep],
                reason: "Sensor Lab background test"
            )
            record("Activity assertion on")
        } else if !holdsActivity, let activity {
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
            record("Activity assertion off")
        }
    }

    // MARK: Sign check

    /// Walks neutral → look down → tilt right, capturing gravity at each step
    /// to confirm which way pitch and roll go.
    func advanceSignCheck() {
        guard let sample = latestSample else {
            record("Sign check needs live motion")
            return
        }
        switch signStep {
        case .idle, .done:
            signStep = .neutral
        case .neutral:
            neutralGravity = sample.gravity
            signStep = .down
        case .down:
            if let neutral = neutralGravity {
                let neutralPitch = degrees(atan2(neutral.y, -neutral.z))
                let downPitch = degrees(atan2(sample.gravity.y, -sample.gravity.z))
                pitchDownSign = downPitch < neutralPitch ? 1 : -1
                record("Sign check: raw pitch neutral \(Int(neutralPitch))°, down \(Int(downPitch))° → pitchSign \(pitchDownSign ?? 0)")
            }
            signStep = .right
        case .right:
            if let neutral = neutralGravity {
                let neutralRoll = degrees(atan2(neutral.x, -neutral.z))
                let rightRoll = degrees(atan2(sample.gravity.x, -sample.gravity.z))
                rollRightSign = rightRoll > neutralRoll ? 1 : -1
                record("Sign check: raw roll neutral \(Int(neutralRoll))°, right \(Int(rightRoll))° → rollSign \(rollRightSign ?? 0)")
            }
            signStep = .done
        }
    }

    // MARK: Report

    var report: String {
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        let duration = startedAt.map { Int(Date.now.timeIntervalSince($0) / 60) } ?? 0
        let average = buckets.isEmpty ? 0 : Double(totalSamples) / max(1, Date.now.timeIntervalSince(startedAt ?? .now))
        let time = Date.FormatStyle(date: .omitted, time: .standard)

        var lines = [
            "Posture Pet Sensor Lab report",
            "macOS \(os)",
            "Motion: supported=\(hub.isSupported) auth=\(hub.authorization.labName) connection=\(hub.connection) stream=\(hub.stream)\(hub.lastError.map { " error=\($0)" } ?? "")",
            "Session: \(duration) min, samples=\(totalSamples), average \(String(format: "%.1f", average)) Hz, gaps>1s=\(gapsOverOneSecond), longest gap=\(String(format: "%.2f", longestGap)) s",
            "Activity assertion: \(holdsActivity)",
            "Sign check: pitchDownSign=\(pitchDownSign.map { "\($0)" } ?? "not run") rollRightSign=\(rollRightSign.map { "\($0)" } ?? "not run")",
            "Signals now: idle=\(Int(idleSeconds)) s, mic processes=\(audio.inputProcesses) (process list visible: \(audio.processListAvailable)), mic devices=\(audio.runningInputDevices), cameras seen=\(camera.deviceCount) running=\(camera.runningDevices), mirroring=\(display.isMirroring), full-screen front=\(display.frontmostCoversScreen), lock notifications seen=\(sawLockNotification)",
            "",
            "Minutes (time · samples · app active s · locked s · screens asleep s · longest gap):",
        ]
        lines += buckets.map { bucket in
            "\(bucket.start.formatted(time)) · \(bucket.samples) · \(bucket.activeSeconds) · \(bucket.lockedSeconds) · \(bucket.screensAsleepSeconds) · \(String(format: "%.2f", bucket.longestGap))"
        }
        lines += ["", "Events:"]
        lines += log.map { "\($0.time.formatted(time))  \($0.text)" }
        return lines.joined(separator: "\n")
    }
}

extension CMAuthorizationStatus {
    var labName: String {
        switch self {
        case .notDetermined: "not determined"
        case .restricted: "restricted"
        case .denied: "denied"
        case .authorized: "authorized"
        @unknown default: "unknown"
        }
    }
}
#endif
