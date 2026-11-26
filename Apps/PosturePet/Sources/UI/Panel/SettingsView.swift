import AppKit
import CoreMotion
import MenuBarKit
import SwiftUI

struct SettingsView: View {
    let engine: PetEngine
    let pro: ProStore
    let router: PanelRouter
    let actions: PanelActions

    @State private var name = ""
    @State private var confirmingReset = false
    @State private var showsMore = false

    private var settings: Preferences { engine.settings }

    private var motionDenied: Bool {
        engine.motion.authorization == .denied || engine.motion.authorization == .restricted
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                VStack(spacing: 0) {
                    SettingsRow("timer", "Break every") {
                        Picker("Break every", selection: Binding(
                            get: { settings.breakMinutes },
                            set: { settings.breakMinutes = $0; engine.tick() }
                        )) {
                            ForEach(Preferences.breakChoices, id: \.self) { minutes in
                                Text("\(minutes) min").tag(minutes)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                    SettingsRow("moon.fill", "Wind down at") {
                        DatePicker("Wind down at", selection: windDownBinding, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                            .datePickerStyle(.field)
                            .fixedSize()
                    }
                    SettingsRow("macwindow.on.rectangle", "Show on desktop") {
                        Toggle("Show on desktop", isOn: Binding(
                            get: { settings.desktopPetEnabled },
                            set: { settings.desktopPetEnabled = $0 }
                        ))
                        .labelsHidden()
                        .toggleStyle(.petSwitch)
                    }
                    SettingsRow("power", "Launch at login") {
                        LaunchAtLoginToggle()
                            .labelsHidden()
                            .toggleStyle(.petSwitch)
                    }
                    SettingsRow("scope", "Re-centre") {
                        Button(engine.hasAnyBaseline ? "Re-centre" : "Set up", action: actions.recenter)
                            .buttonStyle(.pill(.soft))
                            .disabled(!engine.motion.isSupported || motionDenied)
                    }
                    .help("Sit the way you normally sit well, so \(engine.pet.name) can mirror you")
                    if motionDenied {
                        SettingsRow("airpods", "Motion access is off", tint: Color(Palette.coral)) {
                            Button("Open Settings", action: openMotionPrivacy)
                                .buttonStyle(.pill(.soft, tint: Color(Palette.coral)))
                        }
                    }
                }
                .card(padding: 4)

                Button {
                    withAnimation(Theme.Motion.quick) { showsMore.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Text("More")
                            .font(.rounded(12, .semibold))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .rotationEffect(.degrees(showsMore ? 90 : 0))
                        Spacer()
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel(showsMore ? "Hide more settings" : "Show more settings")

                if showsMore {
                    more
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(14)
        }
        .scrollIndicators(.never)
        .onAppear { name = engine.pet.name }
        .onDisappear { engine.rename(to: name) }
        .confirmationDialog("Reset all of \(engine.pet.name)'s data?", isPresented: $confirmingReset) {
            Button("Reset", role: .destructive, action: resetEverything)
        } message: {
            Text("This clears history, growth, dewdrops and calibration. It can't be undone.")
        }
    }

    /// Everything people rarely change.
    private var more: some View {
        VStack(spacing: 0) {
            SettingsRow("dial.medium", "Sensitivity") {
                Picker("Sensitivity", selection: Binding(
                    get: { settings.sensitivity },
                    set: { settings.sensitivity = $0; engine.applySensitivity() }
                )) {
                    ForEach(PostureSensitivity.allCases, id: \.self) { level in
                        Text(level.title).tag(level)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .fixedSize()
            }
            .help("How far your head must drop, and for how long, before it counts as slumping")
            SettingsRow("eye.slash", "Hide when busy") {
                Toggle("Hide when busy", isOn: Binding(
                    get: { settings.hideDesktopPetWhenQuiet },
                    set: { settings.hideDesktopPetWhenQuiet = $0 }
                ))
                .labelsHidden()
                .toggleStyle(.petSwitch)
                .disabled(!settings.desktopPetEnabled)
            }
            .help("Hide the desktop \(engine.pet.name) during calls, full-screen apps and Quiet")
            SettingsRow("speaker.wave.2.fill", "Game sounds") {
                Toggle("Game sounds", isOn: Binding(
                    get: { settings.soundsEnabled },
                    set: { settings.soundsEnabled = $0 }
                ))
                .labelsHidden()
                .toggleStyle(.petSwitch)
            }
            SettingsRow("character.cursor.ibeam", "Name") {
                TextField("Name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 130)
                    .onSubmit { engine.rename(to: name) }
            }
            SettingsRow("crown.fill", "Pro") {
                if pro.isPro {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(Theme.accent)
                        .help("Pro is unlocked")
                } else {
                    HStack(spacing: 6) {
                        Button("Restore") { Task { await pro.restore() } }
                            .buttonStyle(.pill(.plain))
                        Button("Unlock") {
                            withAnimation(Theme.Motion.quick) { router.showsPaywall = true }
                        }
                        .buttonStyle(.pill(.soft, tint: Color(Palette.coral)))
                    }
                }
            }
            SettingsRow("arrow.counterclockwise", "Reset all data", tint: Color(Palette.coral)) {
                Button("Reset…") { confirmingReset = true }
                    .buttonStyle(.pill(.plain))
            }
        }
        .card(padding: 4)
    }

    private var windDownBinding: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: settings.windDownMinutes / 60, minute: settings.windDownMinutes % 60, second: 0, of: .now) ?? .now
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                settings.windDownMinutes = (parts.hour ?? 22) * 60 + (parts.minute ?? 0)
                engine.tick()
            }
        )
    }

    private func openMotionPrivacy() {
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Motion",
            "x-apple.systempreferences:com.apple.preference.security?Privacy",
        ]
        for string in urls {
            if let url = URL(string: string), NSWorkspace.shared.open(url) { return }
        }
    }

    private func resetEverything() {
        engine.resetAllData()
        name = engine.pet.name
    }
}

struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.rounded(10, .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            VStack(spacing: 0) {
                content
            }
            .card(padding: 4)
        }
    }
}

struct SettingsRow<Control: View>: View {
    let symbol: String
    let title: String
    var tint: Color = .secondary
    @ViewBuilder let control: Control

    init(_ symbol: String, _ title: String, tint: Color = .secondary, @ViewBuilder control: () -> Control) {
        self.symbol = symbol
        self.title = title
        self.tint = tint
        self.control = control()
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 20)
            Text(title)
                .font(.rounded(12.5))
                .lineLimit(1)
                .fixedSize()
            Spacer(minLength: 8)
            control
        }
        .padding(.horizontal, 8)
        .frame(minHeight: 34)
    }
}

/// What ⌘, opens. Settings live in the panel; this points there.
struct SettingsSceneView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "leaf.fill")
                .font(.system(size: 28))
                .foregroundStyle(Theme.accent)
            Text("Settings live in \(AppInfo.name)'s panel.")
                .font(.petHeadline)
            Button("Open Settings") {
                // Capture this window first: opening the panel makes the
                // panel key, and closing "the key window" would close it.
                let settingsWindow = NSApp.keyWindow
                settingsWindow?.close()
                NotificationCenter.default.post(name: .openPanelSettings, object: nil)
            }
            .buttonStyle(.pill)
        }
        .padding(28)
        .frame(width: 320)
        .fontDesign(.rounded)
    }
}

extension Notification.Name {
    static let openPanelSettings = Notification.Name("PosturePetOpenPanelSettings")
}
