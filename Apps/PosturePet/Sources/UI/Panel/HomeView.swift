import SwiftUI

struct HomeView: View {
    let engine: PetEngine
    let router: PanelRouter
    let actions: PanelActions

    var body: some View {
        VStack(spacing: Theme.Space.m) {
            HabitatCard(engine: engine, actions: actions)
            BreakCard(engine: engine, actions: actions)
            HStack(spacing: Theme.Space.s) {
                postureTile
                breaksTile
                happinessTile
            }
        }
        .padding(14)
    }

    private var postureTile: some View {
        let record = engine.today
        let value = record.goodPostureFraction.map { "\(Int(($0 * 100).rounded()))%" } ?? "–"
        return StatTile(symbol: "figure.stand", title: "Posture", value: value, tint: Color(Palette.sky))
            .help(record.measuredSeconds >= 60
                  ? "Sat well \(Duration.seconds(record.goodPostureSeconds).compact) of \(Duration.seconds(record.measuredSeconds).compact) today"
                  : "Measured with AirPods")
    }

    private var breaksTile: some View {
        StatTile(symbol: "figure.cooldown", title: "Breaks", value: "\(engine.today.breaks)", tint: Color(Palette.sun))
            .help("Today's goal: \(PetBrain.breakGoal)")
    }

    private var happinessTile: some View {
        StatTile(symbol: "heart.fill", title: "Happy", value: "\(engine.happiness)", tint: Color(Palette.coral))
            .help("Today's happiness, out of 100")
    }
}

/// Mochi in its little world: name and stage, streak, dewdrops (tap to feed),
/// a few status icons when they matter, and what Mochi is saying.
struct HabitatCard: View {
    let engine: PetEngine
    let actions: PanelActions

    var body: some View {
        HabitatView(isNight: engine.isLate) {
            ZStack(alignment: .top) {
                PetView(pose: engine.pose, reaction: engine.reaction, mood: engine.mood)
                    .frame(width: 168, height: 168)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .offset(y: 14)
                    .onTapGesture { engine.react(to: .tapped) }
                    .accessibilityLabel("\(engine.pet.name), \(engine.mood.title.lowercased())")
                    .accessibilityAddTraits(.isButton)

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
                        StatusIcons(engine: engine, actions: actions)
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
                        .help(engine.pet.treats == 0 ? "Win dewdrops in the Arcade" : "Feed \(engine.pet.name)")
                        .accessibilityLabel("\(engine.pet.treats) dewdrops. Feed \(engine.pet.name).")
                    }
                }
                .padding(12)

                SpeechTail(text: engine.line, isNight: engine.isLate)
                    .padding(.top, 58)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 16)
                    .id(engine.line)
                    .transition(.scale(scale: 0.8, anchor: .bottomLeading).combined(with: .opacity))
            }
        }
        .frame(height: 262)
        .animation(Theme.Motion.bouncy, value: engine.line)
    }
}

/// Small icons that appear only when something needs attention. Each says
/// what it means on hover and does the obvious thing on click.
private struct StatusIcons: View {
    let engine: PetEngine
    let actions: PanelActions

    var body: some View {
        if let reason = engine.quiet.reason {
            icon("moon.fill", tint: Color(Palette.lavender), help: "\(reason.title): \(reason.detail)") {
                if case .manual = reason { engine.setQuiet(until: nil) }
            }
        }
        if engine.needsRecenter {
            icon("scope", tint: Color(Palette.sky), help: "New screen setup: click to re-centre", action: actions.recenter)
        } else if engine.hasAnyBaseline, engine.motion.connection != .connected {
            icon("airpods", tint: .secondary, help: "AirPods not connected") {}
        }
    }

    private func icon(_ symbol: String, tint: Color, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .background(.thinMaterial, in: Circle())
        }
        .buttonStyle(PressableStyle())
        .help(help)
        .accessibilityLabel(help)
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

/// Time to the next break, or the invitation to take one: one line.
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

            Text(title)
                .font(.petHeadline)
                .contentTransition(.numericText())
                .lineLimit(1)
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
            Button(action: actions.playSuggested) {
                Label("Play", systemImage: "play.fill")
            }
            .buttonStyle(.pill(breaks.phase == .due ? .prominent : .soft, tint: breaks.phase == .due ? Color(Palette.coral) : Theme.accent))
        }
        .card()
        .help("Sitting for \(Duration.seconds(engine.breaks.sittingSeconds).compact)")
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
        if engine.isLate { return "Wind down" }
        let breaks = engine.breaks
        switch breaks.phase {
        case .sitting:
            let minutes = Int((breaks.remaining() / 60).rounded(.up))
            return minutes <= 1 ? "Break in a minute" : "Break in \(minutes) min"
        case .due:
            return "Break time!"
        case .snoozed:
            return "Snoozed"
        }
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
