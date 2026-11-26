import SwiftUI
import MenuBarKit

struct ArcadeListView: View {
    let engine: PetEngine
    let pro: ProStore
    let router: PanelRouter
    let actions: PanelActions

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                Text("Neck Arcade")
                    .font(.petTitle)

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

                Label("Stop if anything hurts.", systemImage: "heart.text.square")
                    .font(.petCaption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
            .padding(14)
        }
        .scrollIndicators(.never)
    }
}

/// A game: icon, name, best score, and a lock if it needs Pro. What it is
/// and how to play show on hover (and on the game's own countdown).
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

                Text(game.title)
                    .font(.petHeadline)
                Spacer(minLength: 4)
                if locked {
                    Label("Pro", systemImage: "lock.fill")
                        .font(.rounded(11, .bold))
                        .foregroundStyle(Color(Palette.sun))
                } else {
                    if let best {
                        Label("\(best)", systemImage: "trophy.fill")
                            .font(.rounded(12, .semibold))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(Theme.accent)
                }
            }
            .card(padding: 10)
        }
        .buttonStyle(PressableStyle())
        .onHover { inside in
            withAnimation(Theme.Motion.bouncy) { hovering = inside }
        }
        .help("\(game.tagline) \(game.headControl), or \(game.keyControl).")
        .accessibilityLabel("\(game.title). \(game.tagline)\(locked ? " Requires Pro." : "")")
    }
}
