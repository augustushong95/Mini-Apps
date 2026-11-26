import SwiftUI

struct ArcadeListView: View {
    let engine: PetEngine
    let pro: ProStore
    let router: PanelRouter
    let actions: PanelActions

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Neck Arcade")
                        .font(.petTitle)
                    Text("60-second games you steer with your head.")
                        .font(.petBody)
                        .foregroundStyle(.secondary)
                }

                ForEach(ArcadeGame.allCases) { game in
                    GameCard(
                        game: game,
                        best: engine.bestScores[game.rawValue],
                        locked: game.isPro && !pro.isPro
                    ) {
                        if game.isPro && !pro.isPro {
                            withAnimation(Theme.Motion.quick) { router.showsPaywall = true }
                        } else {
                            actions.play(game)
                        }
                    }
                }

                Label(
                    engine.motion.connection == .connected
                        ? "Move gently. Stop if anything hurts."
                        : "No AirPods? Every game works with the arrow keys.",
                    systemImage: engine.motion.connection == .connected ? "heart.text.square" : "keyboard"
                )
                .font(.petCaption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            }
            .padding(14)
        }
        .scrollIndicators(.never)
    }
}

private struct GameCard: View {
    let game: ArcadeGame
    let best: Int?
    let locked: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Space.m) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(LinearGradient(colors: game.colors, startPoint: .topLeading, endPoint: .bottomTrailing))
                    Image(systemName: game.symbol)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                        .scaleEffect(hovering ? 1.12 : 1)
                        .rotationEffect(.degrees(hovering ? -8 : 0))
                }
                .frame(width: 58, height: 58)
                .overlay(alignment: .topTrailing) {
                    if locked {
                        LockBadge().offset(x: 5, y: -5)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(game.title)
                        .font(.petHeadline)
                    Text(game.tagline)
                        .font(.rounded(11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Label(game.stretch, systemImage: "figure.mind.and.body")
                        Text("·")
                        Text(game.keyControl)
                    }
                    .font(.rounded(10, .medium))
                    .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 4) {
                    Image(systemName: locked ? "lock.fill" : "play.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(locked ? Color(Palette.sun) : Theme.accent)
                    if let best, !locked {
                        Text("Best \(best)")
                            .font(.rounded(10, .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .card(padding: 10)
        }
        .buttonStyle(PressableStyle())
        .onHover { inside in
            withAnimation(Theme.Motion.bouncy) { hovering = inside }
        }
        .accessibilityLabel("\(game.title). \(game.tagline)\(locked ? " Requires Pro." : "")")
    }
}
