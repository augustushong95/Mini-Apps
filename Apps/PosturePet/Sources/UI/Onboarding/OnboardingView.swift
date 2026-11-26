import MenuBarKit
import SwiftUI

struct OnboardingView: View {
    @Bindable var model: OnboardingModel

    static let size = NSSize(width: 460, height: 560)

    var body: some View {
        VStack(spacing: 0) {
            if model.steps.count > 1 {
                StepDots(count: model.steps.count, index: model.step.rawValue)
                    .padding(.top, 18)
            }
            ZStack {
                content
                    .id(model.step)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(Theme.Motion.spring, value: model.step)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(PanelBackground())
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
        }
        .fontDesign(.rounded)
        .tint(Theme.accent)
    }

    @ViewBuilder
    private var content: some View {
        switch model.step {
        case .hello: HelloStep(model: model)
        case .airPods: AirPodsStep(model: model)
        case .calibrate: CalibrateStep(model: model)
        case .rhythm: RhythmStep(model: model)
        case .home: HomeStep(model: model)
        case .finish: FinishStep(model: model)
        }
    }
}

// MARK: Shared pieces

private struct StepDots: View {
    let count: Int
    let index: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { dot in
                Capsule()
                    .fill(dot == index ? Theme.accent : Color.primary.opacity(0.15))
                    .frame(width: dot == index ? 18 : 6, height: 6)
            }
        }
        .animation(Theme.Motion.spring, value: index)
        .accessibilityLabel("Step \(index + 1) of \(count)")
    }
}

private struct StepLayout<Hero: View, Body: View, Buttons: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var hero: Hero
    @ViewBuilder var content: Body
    @ViewBuilder var buttons: Buttons

    var body: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 8)
            hero
            VStack(spacing: 6) {
                Text(title)
                    .font(.rounded(22, .bold))
                    .multilineTextAlignment(.center)
                Text(subtitle)
                    .font(.rounded(13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 36)
            content
            Spacer(minLength: 8)
            HStack(spacing: 10) {
                buttons
            }
            .padding(.bottom, 26)
        }
        .padding(.horizontal, 24)
    }
}

// MARK: Steps

private struct HelloStep: View {
    @Bindable var model: OnboardingModel
    @State private var hatched = false
    @State private var reaction: PetReaction?

    private var pose: PetPose {
        var pose = PetMood.happy.pose(stage: .seedling, posture: nil)
        if !hatched {
            pose.eyes = .closed
            pose.mouth = .oh
        }
        return pose
    }

    var body: some View {
        StepLayout(
            title: hatched ? "Hello! I'm your posture pet." : "Something's sprouting…",
            subtitle: "I mirror how you sit and grow when you take breaks."
        ) {
            PetView(pose: pose, reaction: reaction)
                .frame(width: 170, height: 170)
                .scaleEffect(hatched ? 1 : 0.55)
                .rotationEffect(.degrees(hatched ? 0 : -6))
                .onTapGesture { reaction = PetReaction(act: .boing) }
        } content: {
            VStack(alignment: .leading, spacing: 6) {
                Text("What should I be called?")
                    .font(.petCaption)
                    .foregroundStyle(.secondary)
                TextField("Mochi", text: $model.name)
                    .textFieldStyle(.roundedBorder)
                    .font(.rounded(15))
                    .onSubmit(model.next)
            }
            .frame(width: 240)
            .opacity(hatched ? 1 : 0)
        } buttons: {
            Button("Continue", action: model.next)
                .buttonStyle(.pill)
                .keyboardShortcut(.defaultAction)
                .disabled(!hatched)
        }
        .task {
            try? await Task.sleep(for: .milliseconds(700))
            withAnimation(Theme.Motion.bouncy) { hatched = true }
            reaction = PetReaction(act: .victoryHop)
        }
    }
}

private struct AirPodsStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        StepLayout(
            title: "Mirror me with AirPods",
            subtitle: "Your AirPods tell me how your head tilts."
        ) {
            ZStack {
                Circle()
                    .fill(Theme.accent.opacity(0.12))
                    .frame(width: 140, height: 140)
                Image(systemName: "airpods.pro")
                    .font(.system(size: 54))
                    .foregroundStyle(Theme.accent)
                    .symbolEffect(.pulse, isActive: model.waitingForMotion)
            }
        } content: {
            Label("Stays on this Mac. Never saved.", systemImage: "lock.shield.fill")
                .font(.rounded(12))
                .foregroundStyle(.secondary)
                .labelStyle(TintedLabelStyle())
                .help("Works with AirPods Pro, AirPods (3rd generation and later), AirPods Max and some Beats. macOS will ask to allow Motion & Fitness access.")

            if !model.motion.isSupported {
                Text("This Mac can't read headphone motion. I'll use a break timer instead.")
                    .font(.petCaption)
                    .foregroundStyle(Color(Palette.coral))
            } else if model.motion.authorization == .denied || model.motion.authorization == .restricted {
                Text("Motion access is turned off for Posture Pet in System Settings › Privacy & Security.")
                    .font(.petCaption)
                    .foregroundStyle(Color(Palette.coral))
                    .multilineTextAlignment(.center)
            }
        } buttons: {
            Button("I don't have AirPods", action: model.skipAirPods)
                .buttonStyle(.pill(.plain))
            Button {
                model.startMotion()
                model.next()
            } label: {
                Label("Connect", systemImage: "airpods")
            }
            .buttonStyle(.pill)
            .keyboardShortcut(.defaultAction)
            .disabled(!model.motionAvailable)
        }
    }
}

private struct CalibrateStep: View {
    @Bindable var model: OnboardingModel

    private var pose: PetPose {
        var pose = PetMood.happy.pose(stage: model.engine.pet.stage, posture: model.mirror)
        switch model.captureState {
        case .success:
            pose.eyes = .happy
            pose.mouth = .grin
            pose.accessories = [.sparkles]
        case .failed:
            pose.mouth = .oh
        default:
            break
        }
        return pose
    }

    private var subtitle: String {
        if model.motion.authorization == .denied || model.motion.authorization == .restricted {
            return "Motion access is off. You can turn it on later in System Settings."
        }
        return switch model.captureState {
        case .idle:
            model.waitingForMotion
                ? "Put your AirPods in."
                : "Sit well and look at the middle of your screen."
        case .capturing: "Hold still for a moment…"
        case .success: "Got it! I'll mirror you from here."
        case .failed: "You moved a little. Try again?"
        }
    }

    var body: some View {
        StepLayout(title: model.recenterOnly ? "Re-centre" : "Show me how you sit", subtitle: subtitle) {
            ZStack {
                ProgressRing(progress: model.captureProgress, tint: Theme.accent, lineWidth: 6)
                    .frame(width: 176, height: 176)
                    .opacity(model.captureState == .capturing ? 1 : 0)
                PetView(pose: pose)
                    .frame(width: 150, height: 150)
            }
        } content: {
            EmptyView()
        } buttons: {
            switch model.captureState {
            case .idle, .capturing:
                if !model.recenterOnly {
                    Button("Skip", action: model.next)
                        .buttonStyle(.pill(.plain))
                }
                Button("I'm sitting well", action: model.capture)
                    .buttonStyle(.pill)
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.waitingForMotion || model.captureState == .capturing)
            case .failed:
                Button("Try again", action: model.retryCapture)
                    .buttonStyle(.pill)
                    .keyboardShortcut(.defaultAction)
            case .success:
                Button(model.recenterOnly ? "Done" : "Continue", action: model.next)
                    .buttonStyle(.pill)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .animation(Theme.Motion.spring, value: model.captureState)
    }
}

private struct RhythmStep: View {
    @Bindable var model: OnboardingModel

    private var windDown: Binding<Date> {
        Binding(
            get: {
                let minutes = model.preferences.windDownMinutes
                return Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now) ?? .now
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                model.preferences.windDownMinutes = (parts.hour ?? 22) * 60 + (parts.minute ?? 0)
            }
        )
    }

    var body: some View {
        StepLayout(
            title: "Our rhythm",
            subtitle: "When to take breaks, and when to stop for the day."
        ) {
            Image(systemName: "clock.badge.checkmark.fill")
                .font(.system(size: 60))
                .foregroundStyle(Theme.accent, Color(Palette.sun))
                .frame(height: 120)
        } content: {
            VStack(spacing: 14) {
                VStack(spacing: 6) {
                    Text("Stretch every")
                        .font(.petCaption)
                        .foregroundStyle(.secondary)
                    Picker("Stretch every", selection: Binding(
                        get: { model.preferences.breakMinutes },
                        set: { model.preferences.breakMinutes = $0 }
                    )) {
                        ForEach(Preferences.breakChoices, id: \.self) { minutes in
                            Text("\(minutes) min").tag(minutes)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 320)
                }
                HStack {
                    Text("Wind down at")
                        .font(.petBody)
                    DatePicker("Wind down at", selection: windDown, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .datePickerStyle(.field)
                        .fixedSize()
                }
            }
        } buttons: {
            Button("Back", action: model.back)
                .buttonStyle(.pill(.plain))
            Button("Continue", action: model.next)
                .buttonStyle(.pill)
                .keyboardShortcut(.defaultAction)
        }
    }
}

private struct HomeStep: View {
    @Bindable var model: OnboardingModel

    var body: some View {
        StepLayout(
            title: "Where should I live?",
            subtitle: "I can also sit on your desktop, wherever you drag me."
        ) {
            EmptyView()
        } content: {
            HStack(spacing: 12) {
                choice(desktop: false, title: "Menu bar", symbol: "menubar.rectangle")
                choice(desktop: true, title: "Menu bar + desktop", symbol: "macwindow.on.rectangle")
            }
            .padding(.top, 8)
        } buttons: {
            Button("Back", action: model.back)
                .buttonStyle(.pill(.plain))
            Button("Continue", action: model.next)
                .buttonStyle(.pill)
                .keyboardShortcut(.defaultAction)
        }
    }

    private func choice(desktop: Bool, title: String, symbol: String) -> some View {
        let selected = model.wantsDesktopPet == desktop
        return Button {
            withAnimation(Theme.Motion.quick) { model.wantsDesktopPet = desktop }
        } label: {
            VStack(spacing: 10) {
                ZStack(alignment: .bottomTrailing) {
                    Image(systemName: symbol)
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(selected ? Theme.accent : .secondary)
                        .frame(height: 64)
                    if desktop {
                        PetView(pose: PetMood.happy.pose(stage: model.engine.pet.stage, posture: nil), animatesIdle: false)
                            .frame(width: 34, height: 34)
                            .offset(x: 10, y: 6)
                    }
                }
                Text(title).font(.rounded(13, .semibold))
            }
            .frame(width: 170, height: 150)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(selected ? Theme.accent.opacity(0.1) : Color.primary.opacity(0.04))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(selected ? Theme.accent : Color.primary.opacity(0.1), lineWidth: selected ? 2 : 1)
                    }
            }
        }
        .buttonStyle(PressableStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private struct FinishStep: View {
    @Bindable var model: OnboardingModel
    @State private var reaction = PetReaction(act: .victoryHop)

    var body: some View {
        StepLayout(
            title: "We're all set!",
            subtitle: "Click me in the menu bar any time."
        ) {
            PetView(pose: {
                var pose = PetMood.happy.pose(stage: model.engine.pet.stage, posture: nil)
                pose.eyes = .happy
                pose.mouth = .grin
                return pose
            }(), reaction: reaction)
            .frame(width: 150, height: 150)
        } content: {
            HStack {
                Text("Start \(AppInfo.name) when I log in")
                    .font(.petBody)
                Spacer()
                LaunchAtLoginToggle()
                    .labelsHidden()
                    .toggleStyle(.petSwitch)
            }
            .frame(width: 300)
            .card()
        } buttons: {
            Button("Back", action: model.back)
                .buttonStyle(.pill(.plain))
            Button("Let's go!", action: model.next)
                .buttonStyle(.pill)
                .keyboardShortcut(.defaultAction)
        }
    }
}

private struct TintedLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.icon
                .foregroundStyle(Theme.accent)
                .frame(width: 18)
            configuration.title
        }
    }
}
