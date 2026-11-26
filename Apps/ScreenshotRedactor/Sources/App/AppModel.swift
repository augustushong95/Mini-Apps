import AppKit
import MenuBarKit
import Observation
import OSLog
import UniformTypeIdentifiers

/// The composition root: creates the app's long-lived objects, wires them
/// together, and decides what's on screen.
final class AppModel {
    static let proProductID = "screenshotredactor.pro"

    let preferences: Preferences
    let folder: FolderAccess
    let allowance: DailyAllowance
    let pro: ProStore
    let library: Library
    let exporter: Exporter
    let preview: PreviewController
    let editor: EditorWindowController
    let hotKeys = HotKeyCenter()
    lazy var capture = CaptureController()

    private let statusItem = StatusItemController(autosaveName: "ScreenshotRedactor", placeholderSymbol: "eye.slash")
    private let panelModel: MenuPanelModel
    private lazy var panel = makePanel()
    private lazy var settings = SettingsWindowController(model: self)
    private lazy var paywall = PaywallController(pro: pro)
    private var onboarding: OnboardingController?

    private var watcher: ScreenshotWatcher?
    private var lastArrival: (date: Date, burstID: UUID)?
    private var observers: [NSObjectProtocol] = []
    private var iconTimer: Task<Void, Never>?

    #if DEBUG
    private lazy var debug = DebugTools(model: self)
    #endif

    init(defaults: UserDefaults = .standard) {
        preferences = Preferences(defaults: defaults)
        folder = FolderAccess(preferences: preferences)
        allowance = DailyAllowance(defaults: defaults)
        pro = ProStore(productID: Self.proProductID, debugDefaults: defaults)
        let pro = pro
        library = Library(preferences: preferences, includesCustomRules: { pro.isPro })
        exporter = Exporter(allowance: allowance, preferences: preferences)
        preview = PreviewController(exporter: exporter, allowance: allowance, preferences: preferences)
        editor = EditorWindowController(exporter: exporter, allowance: allowance)
        panelModel = MenuPanelModel(library: library, allowance: allowance)

        Exporter.removeLeftoverFiles()
        wire()
        updateWatching()
        registerHotKey()

        #if DEBUG
        let automated = debug.isAutomated
        #else
        let automated = false
        #endif
        if !preferences.onboardingCompleted, !automated {
            showOnboarding()
        }
        #if DEBUG
        debug.handleLaunchArguments()
        #endif
    }

    // MARK: Wiring

    private func wire() {
        statusItem.onPrimaryClick = { [unowned self] in togglePanel() }
        statusItem.menuProvider = { [unowned self] in makeMenu() }

        preview.onEdit = { [unowned self] document in openEditor(document) }
        preview.onUpgrade = { [unowned self] in showPaywall() }
        editor.onUpgrade = { [unowned self] in showPaywall() }
        editor.onPaste = { [unowned self] in pasteImage() }

        library.onRulesTimedOut = { [unowned self] ids in disableTimedOutRules(ids) }

        panelModel.actions = MenuPanelModel.Actions(
            setWatching: { [unowned self] on in setWatching(on) },
            chooseFolder: { [unowned self] in closePanel(); chooseFolder() },
            capture: { [unowned self] in closePanel(); startCapture() },
            openImage: { [unowned self] in closePanel(); openImage() },
            pasteImage: { [unowned self] in closePanel(); pasteImage() },
            open: { [unowned self] document in closePanel(); preview.show([document]) },
            dragFile: { [unowned self] document in exporter.dragFile(for: document) },
            dragEnded: { [unowned self] document, dropped in if dropped { exporter.dragCompleted(document) } },
            openFiles: { [unowned self] urls in closePanel(); open(urls) },
            clearRecent: { [unowned self] in clearRecent() },
            settings: { [unowned self] in closePanel(); showSettings() },
            upgrade: { [unowned self] in closePanel(); showPaywall() },
            quit: { NSApp.terminate(nil) }
        )

        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.reconnectFolder() }
            })
        }

        observeChanges { [weak self] in self?.syncState() }
        observeChanges { [weak self] in self?.updateIcon() }
    }

    /// Re-runs `body` whenever anything it read from an `@Observable` changes.
    private func observeChanges(_ body: @escaping @MainActor () -> Void) {
        withObservationTracking(body) { [weak self] in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.observeChanges(body) }
            }
        }
    }

    /// Keeps derived state in step with settings and the purchase.
    private func syncState() {
        allowance.isUnlimited = pro.isPro
        panelModel.isPro = pro.isPro
        panelModel.shortcut = preferences.hotKey
        _ = preferences.boxColor
        _ = preferences.showsLabels
        library.applyStyle()
        panelModel.watchStatus = watchStatus
    }

    private var watchStatus: MenuPanelModel.WatchStatus {
        switch folder.status {
        case .notChosen: .notChosen
        case .unavailable: .unavailable(folder.displayName)
        case .available: preferences.watchesFolder ? .watching(folder.displayName) : .paused(folder.displayName)
        }
    }

    // MARK: Menu bar

    private func updateIcon() {
        let scanning = library.recent.contains { $0.state == .scanning }
        let state: StatusIcon.State
        if case .unavailable = folder.status {
            state = .attention
        } else if scanning {
            state = .scanning(phase: 0)
        } else if !preferences.watchesFolder || folder.url == nil {
            state = .paused
        } else {
            state = .watching
        }
        let label: String
        switch state {
        case .attention: label = "\(AppInfo.name): can't reach the screenshot folder"
        case .scanning: label = "\(AppInfo.name): checking a screenshot"
        case .paused: label = "\(AppInfo.name): paused"
        case .watching: label = "\(AppInfo.name): watching for screenshots"
        }
        statusItem.setImage(StatusIcon.image(state), accessibilityLabel: label)

        iconTimer?.cancel()
        if scanning {
            iconTimer = Task { [weak self] in
                var phase = 0
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(450))
                    phase += 1
                    self?.statusItem.setImage(StatusIcon.image(.scanning(phase: phase)), accessibilityLabel: label)
                }
            }
        }
    }

    private func makePanel() -> PanelController {
        let controller = PanelController(size: NSSize(width: MenuPanelView.width, height: 420), content: MenuPanelView(model: panelModel))
        return controller
    }

    func showPanel() {
        allowance.refresh()
        panelModel.watchStatus = watchStatus
        let size = panel.fittingSize
        let anchor = statusItem.screenFrame ?? PanelPlacement.fallbackAnchor()
        panel.show(at: PanelPlacement.below(anchor, size: size))
    }

    private func togglePanel() {
        if panel.isVisible { panel.close() } else { showPanel() }
    }

    private func closePanel() {
        if panel.isVisible { panel.close(animated: false) }
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        if folder.url != nil {
            let title = preferences.watchesFolder ? "Pause Watching" : "Resume Watching"
            menu.addItem(ClosureMenuItem(title) { [unowned self] in setWatching(!preferences.watchesFolder) })
        } else {
            menu.addItem(ClosureMenuItem("Choose Screenshot Folder…") { [unowned self] in chooseFolder() })
        }
        menu.addItem(.separator())
        let captureItem = ClosureMenuItem("Capture Area") { [unowned self] in startCapture() }
        if let combo = preferences.hotKey {
            captureItem.keyEquivalent = combo.menuKeyEquivalent
            captureItem.keyEquivalentModifierMask = combo.modifiers
        }
        menu.addItem(captureItem)
        menu.addItem(ClosureMenuItem("Open Image…") { [unowned self] in openImage() })
        menu.addItem(ClosureMenuItem("Redact Clipboard Image") { [unowned self] in pasteImage() })
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("Settings…", key: ",") { [unowned self] in showSettings() })
        if !pro.isPro {
            menu.addItem(ClosureMenuItem("Upgrade to Pro…") { [unowned self] in showPaywall() })
        }
        menu.addItem(ClosureMenuItem("About \(AppInfo.name)") {
            NSApp.activate()
            NSApp.orderFrontStandardAboutPanel(nil)
        })
        #if DEBUG
        menu.addItem(.separator())
        menu.addItem(debug.menuItem())
        #endif
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("Quit \(AppInfo.name)", key: "q") { NSApp.terminate(nil) })
        return menu
    }

    // MARK: Watching

    func setWatching(_ on: Bool) {
        preferences.watchesFolder = on
        updateWatching()
    }

    /// Starts, restarts or stops the folder watcher to match the settings.
    func updateWatching() {
        guard preferences.watchesFolder, let url = folder.url else {
            watcher?.stop()
            watcher = nil
            return
        }
        guard watcher?.folder != url || watcher?.isRunning != true else { return }
        watcher?.stop()
        let watcher = ScreenshotWatcher(folder: url)
        watcher.onScreenshot = { [unowned self] arrival in handle(arrival) }
        watcher.onFolderChanged = { [unowned self] in reconnectFolder() }
        watcher.start()
        self.watcher = watcher
    }

    /// After wake, a mount, or the folder moving: open the bookmark again.
    private func reconnectFolder() {
        folder.resolve()
        if watcher?.folder != folder.url {
            watcher?.stop()
            watcher = nil
        }
        updateWatching()
        watcher?.rescan()
    }

    func chooseFolder() {
        if folder.choose() {
            preferences.watchesFolder = true
            watcher?.stop()
            watcher = nil
            updateWatching()
        }
    }

    private func handle(_ arrival: ScreenshotWatcher.Arrival) {
        // ⌘⇧3 with several displays writes one file per display at once.
        var burstID: UUID?
        if arrival.captureType == "display" {
            if let last = lastArrival, abs(arrival.created.timeIntervalSince(last.date)) < 2 {
                burstID = last.burstID
            } else {
                burstID = UUID()
            }
            lastArrival = (arrival.created, burstID!)
        }
        let name = arrival.url.deletingPathExtension().lastPathComponent
        Task {
            do {
                let loaded = try await ImageLoader.loadInBackground(contentsOf: arrival.url)
                let document = library.add(loaded, origin: .screenshot(arrival.url, arrival.identity), name: name,
                                           burstID: burstID, globalRect: arrival.globalRect)
                present(document, takesFocus: false)
            } catch {
                Logger.app.error("Couldn't read a new screenshot: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Shows a new capture on the card and copies it when the scan is done
    /// if the user chose that.
    private func present(_ document: RedactionDocument, takesFocus: Bool) {
        if let burst = document.burstID, preview.isVisible, preview.model.documents.first?.burstID == burst {
            preview.append(document)
        } else {
            preview.show([document], takesFocus: takesFocus)
        }
        guard preferences.readyAction == .copyAutomatically else { return }
        Task {
            await library.waitForScans()
            guard document.state == .ready else { return }
            preview.copyAutomatically(document)
        }
    }

    // MARK: Other ways in

    func openImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.prompt = "Redact"
        panel.message = "Choose images to redact. They're read on this Mac only."
        NSApp.activate()
        guard panel.runModal() == .OK else { return }
        open(panel.urls)
    }

    func open(_ urls: [URL]) {
        for url in urls.prefix(Library.maximumRecent) {
            Task {
                do {
                    let loaded = try await ImageLoader.loadInBackground(contentsOf: url)
                    let document = library.add(loaded, origin: .file(url), name: url.deletingPathExtension().lastPathComponent)
                    present(document, takesFocus: true)
                } catch {
                    showProblem("Couldn't open \(url.lastPathComponent)", detail: (error as? LocalizedError)?.errorDescription)
                }
            }
        }
    }

    /// Redacts the image on the clipboard (⌃⌘⇧4 screenshots go there). Only
    /// on request: the app never reads the clipboard on its own.
    func pasteImage() {
        let pasteboard = NSPasteboard.general
        let types: [NSPasteboard.PasteboardType] = [.png, .tiff, NSPasteboard.PasteboardType(UTType.jpeg.identifier), NSPasteboard.PasteboardType(UTType.heic.identifier)]
        guard let type = pasteboard.availableType(from: types), let data = pasteboard.data(forType: type) else {
            showProblem("There's no image on the clipboard", detail: "Copy an image, or take a screenshot with ⌃⇧⌘4, then try again.")
            return
        }
        Task {
            do {
                let loaded = try await ImageLoader.loadInBackground(data: data)
                let name = "Clipboard \(Date().formatted(date: .abbreviated, time: .shortened))"
                let document = library.add(loaded, origin: .clipboard, name: name.replacingOccurrences(of: ":", with: "."))
                present(document, takesFocus: true)
            } catch {
                showProblem("The clipboard image couldn't be read", detail: nil)
            }
        }
    }

    func openSample() {
        let sample = SampleScreenshot.demo()
        let document = library.add(ImageLoader.load(sample.image, dpi: 144), origin: .sample, name: "Sample")
        Task {
            await library.waitForScans()
            if document.state == .ready { openEditor(document) }
        }
    }

    func openEditor(_ document: RedactionDocument) {
        preview.close()
        editor.open(document)
    }

    private func clearRecent() {
        if let current = preview.currentDocument { preview.closeIfShowing(current) }
        editor.close()
        library.clear()
    }

    // MARK: Capture shortcut

    func registerHotKey() {
        hotKeys.register(preferences.hotKey) { [weak self] in self?.startCapture() }
    }

    func startCapture() {
        capture.start { [weak self] result in
            guard let self else { return }
            switch result {
            case .captured(let image, let rect):
                let name = "Capture \(Date().formatted(date: .numeric, time: .standard))".replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: ".")
                let document = library.add(image, origin: .capture, name: name, globalRect: rect)
                present(document, takesFocus: true)
            case .cancelled:
                break
            case .needsPermission:
                showSettings(tab: .general)
            case .failed(let message):
                showProblem("Couldn't capture the screen", detail: message)
            }
        }
    }

    // MARK: Windows

    func showSettings(tab: SettingsTab = .general) {
        settings.show(tab: tab)
    }

    func showPaywall() {
        paywall.show()
    }

    func showOnboarding() {
        let controller = OnboardingController(model: self)
        controller.onFinish = { [weak self] in
            self?.preferences.onboardingCompleted = true
            self?.onboarding = nil
        }
        onboarding = controller
        controller.show()
    }

    private func disableTimedOutRules(_ ids: Set<UUID>) {
        var detection = preferences.detection
        for index in detection.customRules.indices where ids.contains(detection.customRules[index].id) {
            detection.customRules[index].isEnabled = false
        }
        preferences.detection = detection
        showProblem("A rule took too long and was turned off", detail: "One of your patterns took too long to run, so it was skipped and switched off. You can fix it in Settings › Your Rules.")
    }

    func showProblem(_ message: String, detail: String?) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail ?? ""
        alert.alertStyle = .warning
        NSApp.activate()
        alert.runModal()
    }

    func prepareForTermination() {
        watcher?.stop()
        hotKeys.unregister()
    }
}

extension KeyCombo {
    /// The key as an `NSMenuItem` key equivalent (lowercase letter or digit).
    var menuKeyEquivalent: String {
        let name = Self.keyName(keyCode)
        return name.count == 1 ? name.lowercased() : ""
    }
}
