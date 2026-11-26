import SwiftUI

/// The Neck Arcade's games. Each is 60 seconds and works a different
/// direction of neck movement; each also has keyboard controls.
enum ArcadeGame: String, CaseIterable, Identifiable, Codable {
    case leafGlide, puddleHop, starFloat

    var id: Self { self }

    var title: String {
        switch self {
        case .leafGlide: "Leaf Glide"
        case .puddleHop: "Puddle Hop"
        case .starFloat: "Star Float"
        }
    }

    var tagline: String {
        switch self {
        case .leafGlide: "Ride a falling leaf, catch the dew."
        case .puddleHop: "Hop the puddles on a rainy path."
        case .starFloat: "Float up and catch falling stars."
        }
    }

    /// What the movement stretches, in plain words.
    var stretch: String {
        switch self {
        case .leafGlide: "Side tilts"
        case .puddleHop: "Gentle nods"
        case .starFloat: "Looking up"
        }
    }

    var headControl: String {
        switch self {
        case .leafGlide: "Tilt your head left and right"
        case .puddleHop: "Nod down to hop"
        case .starFloat: "Look up to float"
        }
    }

    var keyControl: String {
        switch self {
        case .leafGlide: "← →"
        case .puddleHop: "Space"
        case .starFloat: "↑"
        }
    }

    var symbol: String {
        switch self {
        case .leafGlide: "leaf.fill"
        case .puddleHop: "drop.fill"
        case .starFloat: "star.fill"
        }
    }

    var isPro: Bool {
        self != .leafGlide
    }

    var colors: [Color] {
        switch self {
        case .leafGlide: [Color(hex: 0xBFE8C3), Color(hex: 0x7CCB8E)]
        case .puddleHop: [Color(hex: 0xBFE2FA), Color(hex: 0x6FB4E8)]
        case .starFloat: [Color(hex: 0x6E6BC4), Color(hex: 0x2E2F6B)]
        }
    }
}
