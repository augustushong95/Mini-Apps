import Foundation
import Testing
@testable import PosturePet

/// Saving state, settings, quiet mode and presence.
@Suite(.serialized)
struct StorageAndSettingsTests {
    private func tempFolder() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "PosturePetStore-\(UUID().uuidString)")
    }

    // MARK: StateStore

    @Test func stateIsSavedAndReadBack() {
        let folder = tempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = StateStore(folder: folder)
        store.update { state in
            state.pet.name = "Bean"
            state.pet.treats = 7
            state.withRecord(for: PetDay(year: 2026, month: 11, day: 26)) { $0.breaks = 3 }
        }
        store.flush()

        let reopened = StateStore(folder: folder)
        #expect(reopened.state.pet.name == "Bean")
        #expect(reopened.state.pet.treats == 7)
        #expect(reopened.state.record(for: PetDay(year: 2026, month: 11, day: 26))?.breaks == 3)
        #expect(reopened.state.savedAt != nil)
    }

    @Test func aCorruptFileIsKeptAsideAndTheAppStartsFresh() throws {
        let folder = tempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("{ not json".utf8).write(to: folder.appending(path: "PosturePet.json"))

        let store = StateStore(folder: folder)
        #expect(store.state == SavedState())
        let files = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        #expect(files.contains { $0.contains("corrupt") }, "Backup kept for support")
    }

    @Test func historyIsCappedAtAboutAYear() {
        var state = SavedState()
        let start = PetDay(year: 2025, month: 1, day: 1)
        for offset in 0..<(SavedState.maxDays + 20) {
            state.withRecord(for: start.adding(days: offset)) { $0.breaks = 1 }
        }
        #expect(state.days.count == SavedState.maxDays)
        #expect(state.days.first?.day == start.adding(days: 20), "The oldest days go first")
        #expect(state.days == state.days.sorted { $0.day < $1.day })
    }

    // MARK: Preferences

    private func preferences() -> (Preferences, String) {
        let suite = "PosturePetPrefs-\(UUID().uuidString)"
        return (Preferences(defaults: UserDefaults(suiteName: suite)!), suite)
    }

    @Test func defaultSettings() {
        let (prefs, suite) = preferences()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        #expect(prefs.breakMinutes == 50)
        #expect(prefs.breakInterval == 3000)
        #expect(prefs.windDownMinutes == 22 * 60)
        #expect(prefs.sensitivity == .normal)
        #expect(prefs.desktopPetEnabled)
        #expect(prefs.hideDesktopPetWhenQuiet)
        #expect(prefs.soundsEnabled)
        #expect(prefs.quietUntil == nil)
    }

    @Test func settingsPersistAndReset() {
        let (prefs, suite) = preferences()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        prefs.breakMinutes = 30
        prefs.sensitivity = .strict
        prefs.desktopPetEnabled = false
        let reloaded = Preferences(defaults: UserDefaults(suiteName: suite)!)
        #expect(reloaded.breakMinutes == 30)
        #expect(reloaded.sensitivity == .strict)
        #expect(!reloaded.desktopPetEnabled)

        reloaded.resetAll()
        #expect(reloaded.breakMinutes == 50)
        #expect(reloaded.sensitivity == .normal)
        #expect(reloaded.desktopPetEnabled)
    }

    @Test func desktopPetRemembersAPositionPerScreenSetup() {
        let (prefs, suite) = preferences()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        prefs.setDesktopPetOrigin(CGPoint(x: 100, y: 40), for: "1")
        prefs.setDesktopPetOrigin(CGPoint(x: 900, y: 600), for: "1+2")
        #expect(prefs.desktopPetOrigin(for: "1") == CGPoint(x: 100, y: 40))
        #expect(prefs.desktopPetOrigin(for: "1+2") == CGPoint(x: 900, y: 600))
        #expect(prefs.desktopPetOrigin(for: "3") == nil)
    }

    // MARK: Quiet and presence

    @Test func manualQuietEndsByItself() {
        let (prefs, suite) = preferences()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let quiet = QuietDetector(settings: prefs, systemSignals: { nil })
        let until = Date.now.addingTimeInterval(3600)
        prefs.quietUntil = until
        #expect(quiet.refresh() == .manual(until: until))
        #expect(quiet.refresh(now: until.addingTimeInterval(1)) == nil)
        #expect(prefs.quietUntil == nil, "Cleared once it's over")
    }

    @Test func callsAndFullScreenAppsMeanQuiet() {
        let (prefs, suite) = preferences()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        var signal: QuietReason? = .call(app: "com.apple.FaceTime")
        let quiet = QuietDetector(settings: prefs, systemSignals: { signal })
        #expect(quiet.refresh() == .call(app: "com.apple.FaceTime"))
        #expect(quiet.isQuiet)
        signal = .fullScreen(app: "com.apple.TV")
        #expect(quiet.refresh() == .fullScreen(app: "com.apple.TV"))
        signal = nil
        #expect(quiet.refresh() == nil)
        #expect(!quiet.isQuiet)
    }

    @Test func manualQuietWinsOverOtherSignals() {
        let (prefs, suite) = preferences()
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let quiet = QuietDetector(settings: prefs, systemSignals: { .call(app: nil) })
        let until = Date.now.addingTimeInterval(600)
        prefs.quietUntil = until
        #expect(quiet.refresh() == .manual(until: until))
    }

    @Test func presenceRules() {
        // Typing or using the mouse: present.
        #expect(Presence.isPresent(idleSeconds: 30, motionLive: false, postureKnown: false))
        // Watching a video with AirPods in: still sitting.
        #expect(Presence.isPresent(idleSeconds: 300, motionLive: true, postureKnown: true))
        // No input and no head data: away.
        #expect(!Presence.isPresent(idleSeconds: 300, motionLive: false, postureKnown: false))
        // Head data alone stops counting after 15 minutes.
        #expect(!Presence.isPresent(idleSeconds: 16 * 60, motionLive: true, postureKnown: true))
    }
}
