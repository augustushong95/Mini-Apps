import SwiftUI

/// A one-off act for Mochi to perform, triggered by giving `PetView` a new value.
struct PetReaction: Equatable {
    let act: PetAct
    let id = UUID()
    let createdAt = Date.now

    /// Reactions are moments: a view that appears later doesn't replay an
    /// old one.
    var isFresh: Bool { Date.now.timeIntervalSince(createdAt) < 1.5 }

    static func == (lhs: PetReaction, rhs: PetReaction) -> Bool {
        lhs.id == rhs.id
    }
}

/// Mochi in SwiftUI, backed by the Core Animation `PetLayerView`.
struct PetView: NSViewRepresentable {
    var pose: PetPose
    var reaction: PetReaction?
    /// Which pool of idle acts Mochi picks from.
    var mood: PetMood = .happy
    var animatesIdle = true

    func makeNSView(context: Context) -> PetLayerView {
        let view = PetLayerView()
        view.idleAnimationsEnabled = animatesIdle
        view.mood = mood
        view.apply(pose, animated: false)
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.image)
        return view
    }

    func updateNSView(_ view: PetLayerView, context: Context) {
        if view.idleAnimationsEnabled != animatesIdle {
            view.idleAnimationsEnabled = animatesIdle
        }
        view.mood = mood
        if view.pose != pose {
            view.apply(pose, animated: !context.transaction.disablesAnimations)
        }
        if let reaction, reaction != context.coordinator.lastReaction {
            context.coordinator.lastReaction = reaction
            if reaction.isFresh {
                view.perform(reaction.act)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var lastReaction: PetReaction?
    }
}
