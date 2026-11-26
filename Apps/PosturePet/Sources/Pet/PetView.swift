import SwiftUI

/// A one-off Mochi animation, triggered by giving `PetView` a new value.
struct PetReaction: Equatable {
    enum Kind {
        case hop, celebrate, wobble, chew
    }

    let kind: Kind
    let id = UUID()

    static func == (lhs: PetReaction, rhs: PetReaction) -> Bool {
        lhs.id == rhs.id
    }
}

/// Mochi in SwiftUI, backed by the Core Animation `PetLayerView`.
struct PetView: NSViewRepresentable {
    var pose: PetPose
    var reaction: PetReaction?
    var animatesIdle = true

    func makeNSView(context: Context) -> PetLayerView {
        let view = PetLayerView()
        view.idleAnimationsEnabled = animatesIdle
        view.apply(pose, animated: false)
        view.setAccessibilityElement(true)
        view.setAccessibilityRole(.image)
        return view
    }

    func updateNSView(_ view: PetLayerView, context: Context) {
        if view.idleAnimationsEnabled != animatesIdle {
            view.idleAnimationsEnabled = animatesIdle
        }
        if view.pose != pose {
            view.apply(pose, animated: !context.transaction.disablesAnimations)
        }
        if let reaction, reaction != context.coordinator.lastReaction {
            context.coordinator.lastReaction = reaction
            switch reaction.kind {
            case .hop: view.hop()
            case .celebrate: view.celebrate()
            case .wobble: view.wobble()
            case .chew: view.chew()
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
