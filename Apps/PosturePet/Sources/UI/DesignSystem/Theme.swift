import SwiftUI

/// Spacing, shapes, type and motion shared by every view.
enum Theme {
    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
    }

    enum Radius {
        static let small: CGFloat = 10
        static let card: CGFloat = 16
        static let panel: CGFloat = 22
    }

    enum Motion {
        /// The default for things moving into place.
        static let spring = Animation.spring(response: 0.42, dampingFraction: 0.8)
        /// Bouncier, for celebratory moments.
        static let bouncy = Animation.spring(response: 0.5, dampingFraction: 0.62)
        static let quick = Animation.spring(response: 0.26, dampingFraction: 0.9)
    }

    static let accent = Color(Palette.accent)
}

/// SF Rounded throughout: friendly, and it matches Mochi.
extension Font {
    static func rounded(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    static let petTitle = rounded(20, .bold)
    static let petHeadline = rounded(14, .semibold)
    static let petBody = rounded(13)
    static let petCaption = rounded(11, .medium)
    static let petNumber = rounded(22, .bold)
}

extension PetMood {
    var tint: Color {
        switch self {
        case .happy: Color(Palette.accent)
        case .tired: Color(Palette.sun)
        case .slumped: Color(Palette.sky)
        case .sleepy: Color(Palette.lavender)
        case .sick: Color(Palette.coral)
        }
    }
}

// MARK: Card

struct CardBackground: ViewModifier {
    var padding: CGFloat = Theme.Space.m
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(reduceTransparency ? Color(Palette.panelSolid) : Color(Palette.cardFill))
                    .overlay {
                        RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                            .strokeBorder(Color(Palette.cardStroke), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
            }
    }
}

extension View {
    func card(padding: CGFloat = Theme.Space.m) -> some View {
        modifier(CardBackground(padding: padding))
    }
}

// MARK: Buttons

struct PillButtonStyle: ButtonStyle {
    enum Kind {
        case prominent, soft, plain
    }

    var kind: Kind = .prominent
    var tint: Color = Theme.accent
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.rounded(13, .semibold))
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .foregroundStyle(foreground)
            .background(background, in: Capsule())
            .overlay {
                if kind == .plain {
                    Capsule().inset(by: 0.5).stroke(Color.primary.opacity(0.14), lineWidth: 1)
                }
            }
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .opacity(isEnabled ? 1 : 0.45)
            .animation(Theme.Motion.quick, value: configuration.isPressed)
            .contentShape(Capsule())
    }

    private var foreground: Color {
        switch kind {
        case .prominent: .white
        case .soft: tint
        case .plain: .primary
        }
    }

    private var background: Color {
        switch kind {
        case .prominent: tint
        case .soft: tint.opacity(0.14)
        case .plain: .clear
        }
    }
}

extension ButtonStyle where Self == PillButtonStyle {
    static var pill: PillButtonStyle { PillButtonStyle() }
    static func pill(_ kind: PillButtonStyle.Kind, tint: Color = Theme.accent) -> PillButtonStyle {
        PillButtonStyle(kind: kind, tint: tint)
    }
}

/// A plain button that gently shrinks while pressed.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(Theme.Motion.quick, value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}

// MARK: Switch

/// A switch that always shows Mochi's accent. AppKit's switch turns grey
/// whenever the app isn't frontmost, which a menu bar app almost never is.
struct PetSwitchStyle: ToggleStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(Theme.Motion.quick) { configuration.isOn.toggle() }
        } label: {
            Capsule()
                .fill(configuration.isOn ? Theme.accent : Color.primary.opacity(0.16))
                .frame(width: 34, height: 20)
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle()
                        .fill(.white)
                        .shadow(color: .black.opacity(0.18), radius: 1.5, y: 1)
                        .padding(2)
                }
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.4)
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
        }
    }
}

extension ToggleStyle where Self == PetSwitchStyle {
    static var petSwitch: PetSwitchStyle { PetSwitchStyle() }
}

// MARK: Chips and badges

struct MoodChip: View {
    let mood: PetMood

    var body: some View {
        Label(mood.title, systemImage: mood.symbol)
            .font(.rounded(11, .semibold))
            .foregroundStyle(mood.tint)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(mood.tint.opacity(0.14), in: Capsule())
            .contentTransition(.interpolate)
            .accessibilityLabel("Mood: \(mood.title)")
    }
}

struct InfoChip: View {
    let text: String
    let symbol: String
    var tint: Color = .secondary

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.rounded(11, .semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.thinMaterial, in: Capsule())
    }
}

struct LockBadge: View {
    var body: some View {
        Image(systemName: "lock.fill")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white)
            .padding(5)
            .background(Color(Palette.sun), in: Circle())
            .accessibilityLabel("Pro")
    }
}

// MARK: Progress ring

struct ProgressRing: View {
    var progress: Double
    var tint: Color = Theme.accent
    var lineWidth: CGFloat = 8

    var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.15), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, progress)))
                .stroke(
                    AngularGradient(colors: [tint.opacity(0.75), tint], center: .center, startAngle: .degrees(0), endAngle: .degrees(360 * max(0.001, min(1, progress)))),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
        .animation(Theme.Motion.spring, value: progress)
    }
}

// MARK: Stat tile

struct StatTile: View {
    let symbol: String
    let title: String
    let value: String
    var detail: String?
    var tint: Color = Theme.accent

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            Text(value)
                .font(.rounded(18, .bold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.petCaption)
                    .foregroundStyle(.secondary)
                if let detail {
                    Text(detail)
                        .font(.rounded(10))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 10)
        .accessibilityElement(children: .combine)
    }
}

// MARK: Section header

struct SectionHeader: View {
    let title: String
    var trailing: String?

    var body: some View {
        HStack {
            Text(title)
                .font(.petHeadline)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.petCaption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
