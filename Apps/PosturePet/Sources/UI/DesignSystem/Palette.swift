import AppKit
import SwiftUI

/// Every colour in the app. Character colours stay the same in light and dark
/// mode (Mochi is Mochi); UI colours adapt.
enum Palette {
    // MARK: Mochi

    static let mochiTop = NSColor(hex: 0xFFF9EF)
    static let mochiBottom = NSColor(hex: 0xFDE4C8)
    static let mochiOutline = NSColor(hex: 0xE3B88E)
    static let mochiPaleTop = NSColor(hex: 0xF5F5EC)
    static let mochiPaleBottom = NSColor(hex: 0xE2E5D3)
    static let ink = NSColor(hex: 0x3B2A26)
    static let blush = NSColor(hex: 0xFF8FA0)
    static let leaf = NSColor(hex: 0x76C779)
    static let leafDark = NSColor(hex: 0x4FA358)
    static let leafVein = NSColor(hex: 0xB9E8B4)
    static let leafWilted = NSColor(hex: 0xBFC77A)
    static let petal = NSColor(hex: 0xFFB2C8)
    static let petalCenter = NSColor(hex: 0xFFD36B)
    static let bud = NSColor(hex: 0xFF9DB8)
    static let sweat = NSColor(hex: 0x9FD8FF)
    static let gold = NSColor(hex: 0xFFC94D)
    static let goldDark = NSColor(hex: 0xE5A22A)
    static let thermometerBulb = NSColor(hex: 0xFF6B6B)

    // MARK: UI

    /// Brand accent: Mochi's leaf, deepened for contrast on light backgrounds.
    static let accent = dynamic(light: 0x3FAE6A, dark: 0x6BD48F)
    static let accentSoft = dynamic(light: 0xE3F5E8, dark: 0x1F3A2A)
    static let coral = dynamic(light: 0xFF7D6E, dark: 0xFF9486)
    static let sun = dynamic(light: 0xF5A623, dark: 0xFFC25C)
    static let sky = dynamic(light: 0x5AA9E6, dark: 0x7CC0F2)
    static let lavender = dynamic(light: 0x8C7AE6, dark: 0xA99BF0)

    static let textPrimary = NSColor.labelColor
    static let textSecondary = NSColor.secondaryLabelColor
    static let cardFill = dynamic(light: 0xFFFFFF, dark: 0x2A2A2E, lightAlpha: 0.72, darkAlpha: 0.7)
    static let cardStroke = dynamic(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.06, darkAlpha: 0.08)
    static let panelSolid = dynamic(light: 0xF7F4EE, dark: 0x1E1E21)

    // MARK: Habitat scenes

    static let daySkyTop = dynamic(light: 0xDDF1FF, dark: 0x243447)
    static let daySkyBottom = dynamic(light: 0xFFF3E2, dark: 0x3A3A4A)
    static let nightSkyTop = NSColor(hex: 0x262B57)
    static let nightSkyBottom = NSColor(hex: 0x4A4C8C)
    static let grass = dynamic(light: 0xCDEAC0, dark: 0x3E5A3C)
    static let grassDark = dynamic(light: 0xB2DDA3, dark: 0x34503A)

    private static func dynamic(
        light: UInt32, dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1
    ) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(hex: dark, alpha: darkAlpha)
                : NSColor(hex: light, alpha: lightAlpha)
        }
    }
}

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }

    /// Linear blend in sRGB, for animating between two colours.
    func mixed(with other: NSColor, _ amount: CGFloat) -> NSColor {
        let t = max(0, min(1, amount))
        guard let a = usingColorSpace(.sRGB), let b = other.usingColorSpace(.sRGB) else { return self }
        return NSColor(
            srgbRed: a.redComponent + (b.redComponent - a.redComponent) * t,
            green: a.greenComponent + (b.greenComponent - a.greenComponent) * t,
            blue: a.blueComponent + (b.blueComponent - a.blueComponent) * t,
            alpha: a.alphaComponent + (b.alphaComponent - a.alphaComponent) * t
        )
    }
}

extension Color {
    init(_ color: NSColor) {
        self.init(nsColor: color)
    }
}
