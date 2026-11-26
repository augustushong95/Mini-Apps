import SwiftUI

struct ArcadeView: View {
    let session: GameSession
    let engine: PetEngine
    let close: () -> Void

    static let size = NSSize(width: 664, height: 470)

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                GameCanvas(session: session)
                    .frame(width: World.width, height: World.height)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .accessibilityLabel("\(session.game.title) game")

                if session.phase == .playing || isPaused {
                    HUD(session: session)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .padding(10)
                }

                overlay
                    .animation(Theme.Motion.spring, value: session.phase)
            }
            .frame(width: World.width, height: World.height)
            .padding(.top, 12)

            footer
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(PanelBackground())
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
        }
        .fontDesign(.rounded)
    }

    private var isPaused: Bool {
        if case .paused = session.phase { return true }
        return false
    }

    @ViewBuilder
    private var overlay: some View {
        switch session.phase {
        case .rangeCheck(let step):
            RangeCheckCard(session: session, step: step)
                .transition(.scale(scale: 0.9).combined(with: .opacity))
        case .countdown(let count):
            CountdownCard(session: session, engine: engine, count: count)
                .transition(.opacity)
        case .paused(let reason):
            PausedCard(session: session, reason: reason, close: close)
                .transition(.scale(scale: 0.9).combined(with: .opacity))
        case .finished(let result):
            ResultsCard(session: session, engine: engine, result: result, close: close)
                .transition(.scale(scale: 0.9).combined(with: .opacity))
        case .playing:
            EmptyView()
        }
    }

    /// The controls, only while playing (the countdown says them itself).
    private var footer: some View {
        HStack(spacing: 8) {
            if session.phase == .playing || isPaused {
                Image(systemName: session.usesHead ? "airpods" : "keyboard")
                    .foregroundStyle(Theme.accent)
                Text(session.usesHead ? session.game.headControl : session.game.keyControl)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Esc: pause")
                    .foregroundStyle(.tertiary)
            }
        }
        .font(.rounded(11.5, .medium))
        .padding(.horizontal, 18)
        .frame(maxHeight: .infinity)
    }
}

/// Draws the game world, scaled to fit.
private struct GameCanvas: View {
    let session: GameSession

    var body: some View {
        Canvas { context, size in
            var ctx = context
            ctx.scaleBy(x: size.width / World.width, y: size.height / World.height)
            session.sim.draw(in: ctx, time: session.time)
        }
    }
}

private struct HUD: View {
    let session: GameSession

    var body: some View {
        HStack(spacing: 8) {
            InfoChip(text: session.game.title, symbol: session.game.symbol, tint: .primary)
            Spacer()
            InfoChip(text: "\(session.sim.score)", symbol: session.game == .starFloat ? "star.fill" : "drop.fill",
                     tint: session.game == .starFloat ? Color(Palette.sun) : Color(Palette.sky))
                .contentTransition(.numericText())
                .animation(Theme.Motion.quick, value: session.sim.score)
            TimerChip(remaining: session.sim.remaining, total: type(of: session.sim).duration)
            Button {
                session.pause()
            } label: {
                Image(systemName: "pause.fill")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 26, height: 26)
                    .background(.thinMaterial, in: Circle())
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("Pause")
        }
    }
}

private struct TimerChip: View {
    let remaining: TimeInterval
    let total: TimeInterval

    var body: some View {
        HStack(spacing: 5) {
            ProgressRing(progress: remaining / total, tint: remaining < 10 ? Color(Palette.coral) : Theme.accent, lineWidth: 3)
                .frame(width: 14, height: 14)
            Text("\(Int(remaining.rounded(.up)))s")
                .font(.rounded(11, .semibold))
                .monospacedDigit()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.thinMaterial, in: Capsule())
    }
}

/// A frosted card in the middle of the game area.
private struct OverlayCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            Color.black.opacity(0.18)
            VStack(spacing: 12) {
                content
            }
            .padding(22)
            .frame(width: 320)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct CountdownCard: View {
    let session: GameSession
    let engine: PetEngine
    let count: Int

    var body: some View {
        OverlayCard {
            PetView(pose: session.mirrorPose)
                .frame(width: 90, height: 90)
            Text("\(count)")
                .font(.rounded(46, .heavy))
                .foregroundStyle(Theme.accent)
                .contentTransition(.numericText(countsDown: true))
                .id(count)
            Label(session.usesHead ? session.game.headControl : session.game.keyControl,
                  systemImage: session.usesHead ? "airpods" : "keyboard")
                .font(.petHeadline)
            if session.usesHead, !engine.store.state.onboarding.safetyNoteShown {
                Label("Move gently. Stop if anything hurts.", systemImage: "heart.text.square")
                    .font(.petCaption)
                    .foregroundStyle(Color(Palette.coral))
                    .onDisappear {
                        engine.store.update { $0.onboarding.safetyNoteShown = true }
                    }
            }
        }
    }
}

private struct RangeCheckCard: View {
    let session: GameSession
    let step: GameSession.RangeStep

    var body: some View {
        OverlayCard {
            Text("Find your comfy range")
                .font(.petTitle)
            Text("Just once, so games never ask for more than is comfortable.")
                .font(.petCaption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            PetView(pose: session.mirrorPose)
                .frame(width: 96, height: 96)
            Text(step.instruction)
                .font(.petHeadline)
                .multilineTextAlignment(.center)
                .id(step)
                .transition(.push(from: .trailing).combined(with: .opacity))
            ProgressView(value: session.stepProgress)
                .tint(Theme.accent)
            HStack {
                Text("Step \(step.rawValue + 1) of 4")
                    .font(.petCaption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Skip") { session.skipRangeCheck() }
                    .buttonStyle(.pill(.plain))
            }
        }
        .animation(Theme.Motion.spring, value: step)
    }
}

private struct PausedCard: View {
    let session: GameSession
    let reason: GameSession.PauseReason
    let close: () -> Void

    var body: some View {
        OverlayCard {
            Image(systemName: reason == .headphonesDisconnected ? "airpods" : "pause.circle.fill")
                .font(.system(size: 34))
                .foregroundStyle(Theme.accent)
            Text(reason.message)
                .font(.petHeadline)
                .multilineTextAlignment(.center)
            HStack(spacing: 8) {
                Button("End round") { session.endRound() }
                    .buttonStyle(.pill(.plain))
                Button {
                    session.resume()
                } label: {
                    Label("Resume", systemImage: "play.fill")
                }
                .buttonStyle(.pill)
                .keyboardShortcut(.defaultAction)
            }
        }
    }
}

private struct ResultsCard: View {
    let session: GameSession
    let engine: PetEngine
    let result: GameResult
    let close: () -> Void

    @State private var celebration = PetReaction(act: .cheer)

    private var pose: PetPose {
        var pose = PetMood.happy.pose(stage: engine.pet.stage, posture: nil)
        pose.eyes = .happy
        pose.mouth = .grin
        pose.accessories = [.sparkles]
        return pose
    }

    private var treatName: String {
        session.game == .starFloat ? "stars" : "dewdrops"
    }

    private var moveName: String {
        switch session.game {
        case .leafGlide: result.stats.moves == 1 ? "tilt" : "tilts"
        case .puddleHop: result.stats.moves == 1 ? "nod" : "nods"
        case .starFloat: result.stats.moves == 1 ? "look-up" : "look-ups"
        }
    }

    var body: some View {
        OverlayCard {
            PetView(pose: pose, reaction: celebration)
                .frame(width: 100, height: 100)
            Text("+\(result.score) \(treatName)")
                .font(.rounded(26, .heavy))
                .foregroundStyle(session.game == .starFloat ? Color(Palette.sun) : Color(Palette.sky))
            Text(stretchLine)
                .font(.petBody)
                .foregroundStyle(.secondary)
            // At most one chip: a new best beats a counted break.
            if session.isNewBest {
                InfoChip(text: "New best!", symbol: "trophy.fill", tint: Color(Palette.sun))
            } else if result.countsAsBreak {
                InfoChip(text: "+1 break", symbol: "figure.cooldown", tint: Theme.accent)
            }
            HStack(spacing: 8) {
                Button("Done", action: close)
                    .buttonStyle(.pill(.plain))
                Button {
                    session.playAgain()
                } label: {
                    Label("Play again", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.pill)
            }
        }
    }

    private var stretchLine: String {
        let held = Int(result.stats.heldSeconds.rounded())
        var parts = ["\(result.stats.moves) \(moveName)"]
        if held > 0 {
            parts.append("\(held) s held")
        }
        return parts.joined(separator: " · ")
    }
}
