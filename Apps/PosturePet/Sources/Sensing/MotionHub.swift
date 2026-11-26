import AppKit
import CoreMotion
import Observation
import OSLog

/// Owns the app's single `CMHeadphoneMotionManager`.
///
/// Core Motion allows one update handler per manager, so a second caller of
/// `startDeviceMotionUpdates` would silently replace the first. Everything that
/// wants head motion goes through here instead: it states a `Demand`, and the
/// hub streams while any demand is active and fans samples out to subscribers.
@Observable
final class MotionHub {
    enum Demand: Hashable, CaseIterable {
        case posture, game, calibration, diagnostics
    }

    enum Connection: Equatable {
        case unknown, connected, disconnected
    }

    enum Stream: Equatable {
        /// Not streaming because nothing asked for motion, or it isn't possible.
        case idle
        /// Streaming, inside the warm-up window whose samples are discarded.
        case warmingUp
        case live
        /// Streaming, but no sample for longer than `stallInterval`.
        case stalled
    }

    /// Whether this Mac supports headphone motion at all (or simulated
    /// AirPods are on, in debug builds).
    var isSupported: Bool { isSimulating || hardwareSupported }
    private(set) var authorization: CMAuthorizationStatus
    private(set) var connection: Connection = .unknown
    private(set) var stream: Stream = .idle
    /// The latest error from Core Motion, for display.
    private(set) var lastError: String?
    /// Debug builds: samples come from `debugInject` instead of AirPods.
    private(set) var isSimulating = false

    var isLive: Bool { stream == .live }
    /// The user has allowed motion access. Only onboarding and re-centring
    /// may start motion before this, since starting is what shows the prompt.
    var isAuthorized: Bool { authorization == .authorized }
    var canStream: Bool {
        isSupported && authorization != .denied && authorization != .restricted
    }

    /// Samples older than this many seconds after a start are discarded:
    /// the first readings after (re)connecting jump around.
    @ObservationIgnored let warmUpInterval: TimeInterval = 0.5
    @ObservationIgnored let stallInterval: TimeInterval = 2

    @ObservationIgnored private let manager = CMHeadphoneMotionManager()
    @ObservationIgnored private let hardwareSupported: Bool
    /// False in tests and snapshot runs: starting real motion from a process
    /// macOS can't attribute a usage string to gets it terminated.
    @ObservationIgnored private let streamingEnabled: Bool
    @ObservationIgnored private let delegateProxy = MotionDelegateProxy()
    @ObservationIgnored private var demands: Set<Demand> = []
    @ObservationIgnored private var subscribers: [UUID: (HeadSample) -> Void] = [:]
    @ObservationIgnored private var startedAt: Date?
    @ObservationIgnored private(set) var lastSampleAt: Date?
    @ObservationIgnored private var watchdog: Timer?
    @ObservationIgnored private var eventHandlers: [UUID: (Event) -> Void] = [:]

    /// Lifecycle events, for the Sensor Lab and for consumers that reset state.
    enum Event: Equatable {
        case connected, disconnected, started, stopped, stalled, resumed
        case error(String)
    }

    init(streamingEnabled: Bool = true) {
        self.streamingEnabled = streamingEnabled
        hardwareSupported = manager.isDeviceMotionAvailable
        authorization = CMHeadphoneMotionManager.authorizationStatus()

        delegateProxy.onConnect = { [weak self] in self?.didConnect() }
        delegateProxy.onDisconnect = { [weak self] in self?.didDisconnect() }
        manager.delegate = delegateProxy
        if hardwareSupported, streamingEnabled {
            manager.startConnectionStatusUpdates()
        }
    }

    // MARK: Demand

    func setDemand(_ demand: Demand, active: Bool) {
        if active {
            demands.insert(demand)
        } else {
            demands.remove(demand)
        }
        reconcile()
    }

    func hasDemand(_ demand: Demand) -> Bool {
        demands.contains(demand)
    }

    /// Re-reads the authorization status, which the user can change in
    /// System Settings at any time.
    func refreshAuthorization() {
        guard !isSimulating else { return }
        // Observers are notified on every assignment, so only assign changes.
        let status = CMHeadphoneMotionManager.authorizationStatus()
        if status != authorization {
            authorization = status
        }
        reconcile()
    }

    // MARK: Subscribing

    /// Calls `handler` on the main actor for every live sample until the
    /// returned token is cancelled or released.
    func subscribe(_ handler: @escaping (HeadSample) -> Void) -> MotionSubscription {
        let id = UUID()
        subscribers[id] = handler
        return MotionSubscription { [weak self] in self?.subscribers[id] = nil }
    }

    func observeEvents(_ handler: @escaping (Event) -> Void) -> MotionSubscription {
        let id = UUID()
        eventHandlers[id] = handler
        return MotionSubscription { [weak self] in self?.eventHandlers[id] = nil }
    }

    // MARK: Streaming

    private var wantsStream: Bool {
        !demands.isEmpty && canStream
    }

    private func reconcile() {
        guard streamingEnabled, !isSimulating else { return }
        if wantsStream, !manager.isDeviceMotionActive {
            start()
        } else if !wantsStream, manager.isDeviceMotionActive {
            stop()
        }
    }

    private func start() {
        lastError = nil
        startedAt = .now
        lastSampleAt = nil
        stream = .warmingUp
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            // Delivered on the main queue, so this hop is a no-op check.
            let sample = motion.map(HeadSample.init)
            let message = error.map { ($0 as NSError).localizedDescription }
            MainActor.assumeIsolated {
                self?.receive(sample, errorMessage: message)
            }
        }
        startWatchdog()
        emit(.started)
    }

    private func stop() {
        manager.stopDeviceMotionUpdates()
        watchdog?.invalidate()
        watchdog = nil
        startedAt = nil
        stream = .idle
        emit(.stopped)
    }

    /// Stops and starts again, which is the reliable way to pick motion back
    /// up after headphones reconnect.
    private func restart() {
        if manager.isDeviceMotionActive {
            manager.stopDeviceMotionUpdates()
        }
        watchdog?.invalidate()
        if wantsStream {
            start()
        } else {
            stream = .idle
        }
    }

    private func receive(_ sample: HeadSample?, errorMessage: String?) {
        if let errorMessage {
            lastError = errorMessage
            authorization = CMHeadphoneMotionManager.authorizationStatus()
            emit(.error(errorMessage))
            if !canStream {
                stop()
            }
            return
        }
        guard let sample, let startedAt else { return }

        let now = Date.now
        if authorization == .notDetermined {
            // The first sample means the user just allowed access.
            authorization = CMHeadphoneMotionManager.authorizationStatus()
        }
        guard now.timeIntervalSince(startedAt) >= warmUpInterval else { return }

        lastSampleAt = now
        if stream != .live {
            let wasStalled = stream == .stalled
            stream = .live
            if wasStalled { emit(.resumed) }
        }
        for subscriber in subscribers.values {
            subscriber(sample)
        }
    }

    private func startWatchdog() {
        watchdog?.invalidate()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkForStall() }
        }
        timer.tolerance = 0.3
        RunLoop.main.add(timer, forMode: .common)
        watchdog = timer
    }

    private func checkForStall() {
        guard stream == .live, let lastSampleAt else { return }
        if Date.now.timeIntervalSince(lastSampleAt) > stallInterval {
            stream = .stalled
            emit(.stalled)
        }
    }

    // MARK: Connection

    private func didConnect() {
        connection = .connected
        emit(.connected)
        // Headphones that reconnect (reseated, or back from an iPhone) need a
        // fresh start, and their first readings are discarded again.
        restart()
    }

    private func didDisconnect() {
        connection = .disconnected
        if stream != .idle {
            stream = .stalled
        }
        emit(.disconnected)
    }

    #if DEBUG
    fileprivate var subscribersForDebug: [(HeadSample) -> Void] { Array(subscribers.values) }
    fileprivate func emitForDebug(_ event: Event) { emit(event) }
    #endif

    private func emit(_ event: Event) {
        Logger.motion.debug("Motion event: \(String(describing: event), privacy: .public)")
        for handler in eventHandlers.values {
            handler(event)
        }
    }
}

#if DEBUG
extension MotionHub {
    /// Pretends a pair of AirPods is connected and allowed, so the whole
    /// pipeline (posture, mood, nudges, games, calibration) can be tested and
    /// demonstrated without a headset. Real motion is stopped meanwhile.
    func debugStartSimulation() {
        guard !isSimulating else { return }
        if manager.isDeviceMotionActive {
            manager.stopDeviceMotionUpdates()
        }
        isSimulating = true
        authorization = .authorized
        connection = .connected
        stream = .live
        emitForDebug(.connected)
    }

    /// Delivers one simulated sample to every subscriber, as AirPods would.
    func debugInject(_ sample: HeadSample) {
        guard isSimulating else { return }
        lastSampleAt = .now
        if stream != .live {
            stream = .live
        }
        for subscriber in subscribersForDebug {
            subscriber(sample)
        }
    }

    /// Takes the simulated AirPods out: listeners see a disconnect.
    func debugStopSimulation() {
        guard isSimulating else { return }
        isSimulating = false
        authorization = CMHeadphoneMotionManager.authorizationStatus()
        connection = .disconnected
        stream = .idle
        emitForDebug(.disconnected)
        refreshAuthorization()
    }
}
#endif

/// Cancels a `MotionHub` subscription when cancelled or released.
/// Owned by main-actor objects only, so it's always released on the main thread.
final class MotionSubscription {
    private var cancelAction: (@MainActor () -> Void)?

    init(_ cancel: @escaping @MainActor () -> Void) {
        cancelAction = cancel
    }

    func cancel() {
        cancelAction?()
        cancelAction = nil
    }

    deinit {
        if let cancelAction {
            MainActor.assumeIsolated { cancelAction() }
        }
    }
}

/// Receives Core Motion's delegate callbacks, which can arrive on any thread,
/// and forwards them to the main actor in order.
private nonisolated final class MotionDelegateProxy: NSObject, CMHeadphoneMotionManagerDelegate, @unchecked Sendable {
    // Set once on the main actor before the delegate is installed.
    var onConnect: (@MainActor () -> Void)?
    var onDisconnect: (@MainActor () -> Void)?

    func headphoneMotionManagerDidConnect(_ manager: CMHeadphoneMotionManager) {
        DispatchQueue.main.async { [self] in
            MainActor.assumeIsolated { onConnect?() }
        }
    }

    func headphoneMotionManagerDidDisconnect(_ manager: CMHeadphoneMotionManager) {
        DispatchQueue.main.async { [self] in
            MainActor.assumeIsolated { onDisconnect?() }
        }
    }
}

extension Logger {
    static let motion = Logger(subsystem: Bundle.main.bundleIdentifier ?? "PosturePet", category: "Motion")
    static let app = Logger(subsystem: Bundle.main.bundleIdentifier ?? "PosturePet", category: "App")
}
