import SwiftUI

/// Shared sizes and colours. The app uses system materials, SF Symbols and
/// standard controls, so it looks at home in light, dark and tinted modes.
enum Theme {
    static let cardRadius: CGFloat = 14
    static let thumbnailRadius: CGFloat = 8
    static let cardPadding: CGFloat = 12

    static func color(for category: FindingCategory) -> Color {
        switch category {
        case .secret: .red
        case .personal: .purple
        case .internalInfo: .blue
        case .custom: .indigo
        case .face: .pink
        case .manual: .gray
        }
    }
}

/// "Secret 2" with the category's symbol, on a soft tint.
struct CategoryChip: View {
    let category: FindingCategory
    let count: Int

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: category.symbolName)
                .font(.system(size: 9, weight: .semibold))
            Text("\(category.chipTitle) \(count)")
                .font(.caption.weight(.medium))
                .monospacedDigit()
        }
        .foregroundStyle(Theme.color(for: category))
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Theme.color(for: category).opacity(0.13), in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(count) \(category.title.lowercased())")
    }
}

/// The rounded, translucent background of floating cards and panels.
struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }
}

extension View {
    func cardBackground() -> some View { modifier(CardBackground()) }
}

/// A soft moving highlight over a placeholder while something loads.
/// Still (just a tint) when Reduce Motion is on.
struct Shimmer: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1

    var body: some View {
        GeometryReader { geometry in
            if reduceMotion {
                Color.primary.opacity(0.04)
            } else {
                LinearGradient(
                    colors: [.clear, Color.primary.opacity(0.07), .clear],
                    startPoint: .leading, endPoint: .trailing
                )
                .frame(width: geometry.size.width * 0.6)
                .offset(x: phase * geometry.size.width * 1.3)
                .onAppear {
                    withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: false)) { phase = 1 }
                }
            }
        }
        .allowsHitTesting(false)
    }
}

/// A small round close button, like a notification's.
struct CloseButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 18, height: 18)
                .background(.quaternary, in: Circle())
        }
        .buttonStyle(.plain)
        .help("Close (Esc)")
        .accessibilityLabel("Close")
    }
}

/// The main action in floating cards. Stays in the accent colour even when
/// the card doesn't have keyboard focus (where system prominent buttons
/// turn grey), so the next step is always obvious.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(isEnabled ? Color.white : Color.secondary)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isEnabled ? Color.accentColor : Color.primary.opacity(0.08))
            )
            .opacity(configuration.isPressed ? 0.8 : 1)
            .contentShape(Rectangle())
    }
}

/// A secondary action next to `PrimaryButtonStyle`.
struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isEnabled ? Color.primary : Color.secondary)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.14 : 0.08))
            )
            .contentShape(Rectangle())
    }
}
