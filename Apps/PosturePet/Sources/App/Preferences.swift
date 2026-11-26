import Foundation
import Observation

/// User preferences, stored in UserDefaults.
@Observable
final class Preferences {
    @ObservationIgnored private let defaults: UserDefaults

    var breakMinutes: Int {
        didSet { defaults.set(breakMinutes, forKey: Keys.breakMinutes) }
    }

    var sensitivity: PostureSensitivity {
        didSet { defaults.set(sensitivity.rawValue, forKey: Keys.sensitivity) }
    }

    /// Minutes after midnight when the evening wind-down starts.
    var windDownMinutes: Int {
        didSet { defaults.set(windDownMinutes, forKey: Keys.windDown) }
    }

    var desktopPetEnabled: Bool {
        didSet { defaults.set(desktopPetEnabled, forKey: Keys.desktopPet) }
    }

    var hideDesktopPetWhenQuiet: Bool {
        didSet { defaults.set(hideDesktopPetWhenQuiet, forKey: Keys.hideWhenQuiet) }
    }

    var soundsEnabled: Bool {
        didSet { defaults.set(soundsEnabled, forKey: Keys.sounds) }
    }

    /// Manual quiet ("Quiet for 1 hour") ends at this time.
    var quietUntil: Date? {
        didSet { defaults.set(quietUntil, forKey: Keys.quietUntil) }
    }

    static let breakChoices = [30, 45, 50, 60, 90]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Keys.breakMinutes: 50,
            Keys.windDown: 22 * 60,
            Keys.desktopPet: true,
            Keys.hideWhenQuiet: true,
            Keys.sounds: true,
        ])
        breakMinutes = defaults.integer(forKey: Keys.breakMinutes)
        sensitivity = PostureSensitivity(rawValue: defaults.string(forKey: Keys.sensitivity) ?? "") ?? .normal
        windDownMinutes = defaults.integer(forKey: Keys.windDown)
        desktopPetEnabled = defaults.bool(forKey: Keys.desktopPet)
        hideDesktopPetWhenQuiet = defaults.bool(forKey: Keys.hideWhenQuiet)
        soundsEnabled = defaults.bool(forKey: Keys.sounds)
        quietUntil = defaults.object(forKey: Keys.quietUntil) as? Date
    }

    var breakInterval: TimeInterval {
        TimeInterval(breakMinutes * 60)
    }

    /// Desktop pet positions, keyed by display arrangement.
    func desktopPetOrigin(for arrangement: String) -> CGPoint? {
        guard let stored = defaults.dictionary(forKey: Keys.desktopPetPositions)?[arrangement] as? [Double],
              stored.count == 2
        else { return nil }
        return CGPoint(x: stored[0], y: stored[1])
    }

    func setDesktopPetOrigin(_ origin: CGPoint, for arrangement: String) {
        var positions = defaults.dictionary(forKey: Keys.desktopPetPositions) ?? [:]
        positions[arrangement] = [Double(origin.x), Double(origin.y)]
        defaults.set(positions, forKey: Keys.desktopPetPositions)
    }

    func resetAll() {
        for key in [Keys.breakMinutes, Keys.sensitivity, Keys.windDown, Keys.desktopPet, Keys.hideWhenQuiet,
                    Keys.sounds, Keys.quietUntil, Keys.desktopPetPositions] {
            defaults.removeObject(forKey: key)
        }
        breakMinutes = defaults.integer(forKey: Keys.breakMinutes)
        sensitivity = .normal
        windDownMinutes = defaults.integer(forKey: Keys.windDown)
        desktopPetEnabled = defaults.bool(forKey: Keys.desktopPet)
        hideDesktopPetWhenQuiet = defaults.bool(forKey: Keys.hideWhenQuiet)
        soundsEnabled = defaults.bool(forKey: Keys.sounds)
        quietUntil = nil
    }

    private enum Keys {
        static let breakMinutes = "breakMinutes"
        static let sensitivity = "postureSensitivity"
        static let windDown = "windDownMinutes"
        static let desktopPet = "desktopPetEnabled"
        static let hideWhenQuiet = "hideDesktopPetWhenQuiet"
        static let sounds = "soundsEnabled"
        static let quietUntil = "quietUntil"
        static let desktopPetPositions = "desktopPetPositions"
    }
}
