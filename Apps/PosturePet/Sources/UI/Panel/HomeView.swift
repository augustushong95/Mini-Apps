import SwiftUI

struct HomeView: View {
    let engine: PetEngine
    let router: PanelRouter
    let actions: PanelActions

    var body: some View {
        VStack(spacing: Theme.Space.m) {
            HabitatCard(engine: engine)
            BreakCard(engine: engine, actions: actions)
            HStack(spacing: Theme.Space.s) {
                postureTile
                breaksTile
                happinessTile
            }
            StatusRow(engine: engine, router: router, actions: actions)
        }
        .padding(14)
    }

    private var postureTile: some View {
        let record = engine.today
        let value = record.goodPostureFraction.map { "\(Int(($0 * 100).rounded()))%" } ?? "–"
        let detail = record.measuredSeconds >= 60 ? "of \(Duration.seconds(record.measuredSeconds).compact)" : "not measured"
        return StatTile(symbol: "figure.stand", title: "Sitting well", value: value, detail: detail, tint: Color(Palette.sky))
    }

    private var breaksTile: some View {
        let breaks = engine.today.breaks
        return StatTile(
            symbol: "figure.cooldown",
            title: "Breaks",
            value: "\(breaks)",
            detail: breaks >= PetBrain.breakGoal ? "goal met" : "goal \(PetBrain.breakGoal)",
            tint: Color(Palette.sun)
        )
    }

    private var happinessTile: some View {
        StatTile(
            symbol: "heart.fill",
            title: "Happiness",
            value: "\(engine.happiness)",
            detail: engine.streak > 0 ? "\(engine.streak)-day streak" : "today",
            tint: Color(Palette.coral)
        )
    }
}

/// Mochi in its little world, with its name, stage, streak and treats.
struct HabitatCard: View {
    let engine: PetEngine

    var body: some View {
        HabitatView(isNight: engine.isLate) {
            ZStack(alignment: .top) {
                PetView(pose: engine.pose, reaction: engine.reaction)
                    .frame(width: 150, height: 150)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .offset(y: 12)
                    .onTapGesture { engine.pet(react: .hop) }
                    .accessibilityLabel("\(engine.pet.name), \(engine.mood.title.lowercased())")

                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(engine.pet.name)
                            .font(.rounded(17, .bold))
                        Text(engine.pet.stage.name)
                            .font(.petCaption)
                            .opacity(0.7)
                    }
                    .foregroundStyle(engine.isLate ? Color.white : Color(Palette.ink))
                    Spacer()
                    HStack(spacing: 6) {
                        if engine.streak > 0 {
                            InfoChip(text: "\(engine.streak)", symbol: "flame.fill", tint: Color(Palette.coral))
                                .help("\(engine.streak)-day streak")
                        }
                        Button {
                            engine.feed()
                        } label: {
                            InfoChip(text: "\(engine.pet.treats)", symbol: "drop.fill", tint: Color(Palette.sky))
                                .contentTransition(.numericText(countsDown: true))
                        }
                        .buttonStyle(PressableStyle())
                        .disabled(engine.pet.treats == 0)
                        .help(engine.pet.treats == 0 ? "Win dewdrops in the Neck Arcade" : "Feed \(engine.pet.name) a dewdrop")
                        .accessibilityLabel("\(engine.pet.treats) dewdrops. Feed \(engine.pet.name).")
                    }
                }
                .padding(12)

                SpeechTail(text: engine.mood.line, isNight: engine.isLate)
                    .padding(.top, 54)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 16)
                    .id(engine.mood)
                    .transition(.scale(scale: 0.8, anchor: .bottomLeading).combined(with: .opacity))
            }
        }
        .frame(height: 212)
        .animation(Theme.Motion.bouncy, value: engine.mood)
    }
}

/// A little speech bubble for Mochi's status line.
private struct SpeechTail: View {
    let text: String
    let isNight: Bool

    var body: some View {
        Text(text)
            .font(.rounded(12, .semibold))
            .foregroundStyle(Color(Palette.ink))
            .multilineTextAlignment(.leading)
            .frame(maxWidth: 130, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.white.opacity(isNight ? 0.9 : 0.95), in: BubbleShape())
            .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
    }
}

/// A rounded bubble with a small tail at the bottom left.
nonisolated struct BubbleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path(roundedRect: rect, cornerRadius: 12, style: .continuous)
        path.move(to: CGPoint(x: rect.minX + 14, y: rect.maxY - 1))
        path.addQuadCurve(to: CGPoint(x: rect.minX + 4, y: rect.maxY + 8), control: CGPoint(x: rect.minX + 14, y: rect.maxY + 6))
        path.addQuadCurve(to: CGPoint(x: rect.minX + 26, y: rect.maxY - 1), control: CGPoint(x: rect.minX + 18, y: rect.maxY + 6))
        path.closeSubpath()
        return path
    }
}

/// Time to the next break, or the invitation to take one.
struct BreakCard: View {
    let engine: PetEngine
    let actions: PanelActions

    var body: some View {
        let breaks = engine.breaks
        HStack(spacing: Theme.Space.m) {
            ZStack {
                ProgressRing(progress: engine.isLate ? 1 : breaks.progress, tint: tint, lineWidth: 6)
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(tint)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.petHeadline)
                    .contentTransition(.numericText())
                Text(subtitle)
                    .font(.petCaption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if breaks.phase != .sitting, !engine.isLate {
                Menu {
                    Button("Snooze 10 minutes", action: actions.snooze)
                    Button("I took a break", action: actions.tookBreak)
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 22, height: 22)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel("More break options")
            }
            Button {
                actions.play(.leafGlide)
            } label: {
                Label("Play", systemImage: "play.fill")
            }
            .buttonStyle(.pill(breaks.phase == .due ? .prominent : .soft, tint: breaks.phase == .due ? Color(Palette.coral) : Theme.accent))
            .help("Play a 60-second stretch game")
        }
        .card()
        .animation(Theme.Motion.spring, value: breaks.phase)
    }

    private var tint: Color {
        if engine.isLate { return Color(Palette.lavender) }
        switch engine.breaks.phase {
        case .sitting: return Theme.accent
        case .due: return Color(Palette.coral)
        case .snoozed: return Color(Palette.sun)
        }
    }

    private var symbol: String {
        if engine.isLate { return "moon.fill" }
        switch engine.breaks.phase {
        case .sitting: return "timer"
        case .due: return "figure.cooldown"
        case .snoozed: return "zzz"
        }
    }

    private var title: String {
        if engine.isLate { return "Time to wind down" }
        let breaks = engine.breaks
        switch breaks.phase {
        case .sitting:
            let minutes = Int((breaks.remaining() / 60).rounded(.up))
            return minutes <= 1 ? "Stretch in a minute" : "Next stretch in \(minutes) min"
        case .due:
            return "\(engine.pet.name) is stiff!"
        case .snoozed:
            return "Snoozed"
        }
    }

    private var subtitle: String {
        if engine.isLate { return "\(engine.pet.name) is getting sleepy" }
        let sitting = Duration.seconds(engine.breaks.sittingSeconds).compact
        switch engine.breaks.phase {
        case .sitting:
            return engine.breaks.sittingSeconds < 60 ? "Fresh from a break" : "Sitting for \(sitting)"
        case .due:
            return "A 60-second game stretches your neck"
        case .snoozed:
            return "Sitting for \(sitting)"
        }
    }
}

/// One line of context under the stats: quiet, re-centre, or AirPods status.
private struct StatusRow: View {
    let engine: PetEngine
    let router: PanelRouter
    let actions: PanelActions

    var body: some View {
        if let reason = engine.quiet.reason {
            row(symbol: reason.symbol, tint: Color(Palette.lavender), title: reason.title, detail: reason.detail) {
                if case .manual = reason {
                    Button("Resume") { engine.setQuiet(until: nil) }
                        .buttonStyle(.pill(.soft, tint: Color(Palette.lavender)))
                }
            }
        } else if engine.needsRecenter {
            row(symbol: "scope", tint: Color(Palette.sky), title: "New screen setup", detail: "Re-centre so Mochi knows how you sit here") {
                Button("Re-centre", action: actions.recenter)
                    .buttonStyle(.pill(.soft, tint: Color(Palette.sky)))
            }
        } else if !engine.hasAnyBaseline || !engine.motion.canStream || !engine.motion.isSupported {
            row(symbol: "airpods", tint: .secondary, title: "Timer mode", detail: "AirPods let me mirror you") {
                Button("Set up") { router.tab = .settings }
                    .buttonStyle(.pill(.plain))
            }
        } else {
            row(symbol: postureSymbol, tint: Color(Palette.sky), title: postureTitle, detail: postureDetail) { EmptyView() }
        }
    }

    private var postureSymbol: String {
        engine.motion.connection == .connected ? "airpods" : "airpods"
    }

    private var postureTitle: String {
        switch engine.posture.state {
        case .upright: "Sitting tall"
        case .slouching: "Head down for \(Duration.seconds(engine.posture.slouchDuration).compact)"
        case .unknown: engine.motion.connection == .connected ? "Listening for your posture" : "AirPods not connected"
        }
    }

    private var postureDetail: String {
        switch engine.posture.state {
        case .upright, .slouching: "\(engine.pet.name) is mirroring you"
        case .unknown: engine.motion.connection == .connected ? "Sit as you normally would" : "Mochi will mirror you when they're back"
        }
    }

    private func row<Accessory: View>(
        symbol: String, tint: Color, title: String, detail: String, @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.14), in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.rounded(12, .semibold))
                Text(detail).font(.rounded(11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            accessory()
        }
        .card(padding: 10)
    }
}

extension Duration {
    /// "1h 20m", "35 min", "45 s".
    var compact: String {
        let seconds = Int(components.seconds)
        if seconds < 60 { return "\(seconds) s" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes) min" }
        return "\(minutes / 60)h \(minutes % 60)m"
    }
}
