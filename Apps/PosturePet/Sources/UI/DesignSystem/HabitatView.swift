import SwiftUI

/// Mochi's little world behind it: a sky that turns to night after the
/// wind-down time, soft hills and a patch of grass to sit on.
struct HabitatView<Content: View>: View {
    var isNight: Bool
    @ViewBuilder var content: Content

    var body: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(
                colors: isNight
                    ? [Color(Palette.nightSkyTop), Color(Palette.nightSkyBottom)]
                    : [Color(Palette.daySkyTop), Color(Palette.daySkyBottom)],
                startPoint: .top,
                endPoint: .bottom
            )

            if isNight {
                StarField()
                    .transition(.opacity)
            } else {
                Clouds()
                    .transition(.opacity)
            }

            Hills(isNight: isNight)
            content
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card + 2, style: .continuous))
        .animation(.easeInOut(duration: 0.8), value: isNight)
    }
}

private struct Hills: View {
    var isNight: Bool

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            ZStack(alignment: .bottom) {
                Ellipse()
                    .fill(isNight ? Color(hex: 0x3B4A6B) : Color(Palette.grassDark).opacity(0.65))
                    .frame(width: w * 0.9, height: h * 0.42)
                    .offset(x: -w * 0.32, y: h * 0.2)
                Ellipse()
                    .fill(isNight ? Color(hex: 0x34425F) : Color(Palette.grassDark).opacity(0.5))
                    .frame(width: w * 0.85, height: h * 0.38)
                    .offset(x: w * 0.36, y: h * 0.2)
                Ellipse()
                    .fill(isNight ? Color(hex: 0x445A7A) : Color(Palette.grass))
                    .frame(width: w * 1.5, height: h * 0.4)
                    .offset(y: h * 0.24)
            }
            .frame(width: w, height: h, alignment: .bottom)
        }
        .allowsHitTesting(false)
    }
}

private struct Clouds: View {
    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            ZStack {
                // In open sky: clear of the name, the chips and the speech bubble.
                Cloud().frame(width: 58, height: 20).position(x: w * 0.16, y: h * 0.46)
                Cloud().frame(width: 42, height: 15).position(x: w * 0.88, y: h * 0.6).opacity(0.8)
            }
        }
        .allowsHitTesting(false)
    }
}

private struct Cloud: View {
    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            ZStack {
                Capsule().frame(width: w, height: h * 0.62).offset(y: h * 0.19)
                Circle().frame(width: h * 0.78).offset(x: -w * 0.14, y: -h * 0.02)
                Circle().frame(width: h * 0.95).offset(x: w * 0.1, y: -h * 0.08)
            }
            .frame(width: w, height: h)
            .foregroundStyle(.white.opacity(0.85))
        }
    }
}

private struct StarField: View {
    private static let stars: [(CGFloat, CGFloat, CGFloat)] = [
        (0.08, 0.12, 2.2), (0.18, 0.3, 1.4), (0.27, 0.08, 1.8), (0.4, 0.22, 1.2), (0.52, 0.06, 2.0),
        (0.63, 0.28, 1.5), (0.72, 0.1, 2.4), (0.84, 0.24, 1.3), (0.93, 0.08, 1.8), (0.34, 0.38, 1.1),
        (0.78, 0.4, 1.2), (0.12, 0.44, 1.0),
    ]

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(Self.stars.indices, id: \.self) { index in
                    let star = Self.stars[index]
                    Circle()
                        .fill(.white.opacity(0.85))
                        .frame(width: star.2 * 1.4, height: star.2 * 1.4)
                        .position(x: proxy.size.width * star.0, y: proxy.size.height * star.1)
                }
                Image(systemName: "moon.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Color(hex: 0xFFE9A8))
                    .position(x: proxy.size.width * 0.86, y: proxy.size.height * 0.2)
            }
        }
        .allowsHitTesting(false)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(NSColor(hex: hex))
    }
}
