import AppKit
import Observation
import SwiftUI

enum PanelTab: String, CaseIterable, Identifiable {
    case home, today, arcade, settings

    var id: Self { self }

    var title: String {
        switch self {
        case .home: "Home"
        case .today: "Today"
        case .arcade: "Arcade"
        case .settings: "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .home: "leaf.fill"
        case .today: "chart.bar.fill"
        case .arcade: "gamecontroller.fill"
        case .settings: "gearshape.fill"
        }
    }
}

/// Which tab the panel shows, and its sheets.
@Observable
final class PanelRouter {
    var tab: PanelTab = .home
    var showsPaywall = false
}

/// What the panel can ask the app to do.
struct PanelActions {
    var play: (ArcadeGame) -> Void
    var snooze: () -> Void
    var tookBreak: () -> Void
    var recenter: () -> Void
    var quit: () -> Void
}

struct PanelRootView: View {
    let engine: PetEngine
    let pro: ProStore
    @Bindable var router: PanelRouter
    let actions: PanelActions

    static let size = NSSize(width: 360, height: 572)

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                switch router.tab {
                case .home:
                    HomeView(engine: engine, router: router, actions: actions)
                        .transition(.opacity)
                case .today:
                    TodayView(engine: engine, pro: pro, router: router)
                        .transition(.opacity)
                case .arcade:
                    ArcadeListView(engine: engine, pro: pro, router: router, actions: actions)
                        .transition(.opacity)
                case .settings:
                    SettingsView(engine: engine, pro: pro, router: router, actions: actions)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .animation(Theme.Motion.quick, value: router.tab)

            TabBar(selection: $router.tab)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(PanelBackground())
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .overlay {
            if router.showsPaywall {
                PaywallView(pro: pro, engine: engine) {
                    withAnimation(Theme.Motion.quick) { router.showsPaywall = false }
                }
                .transition(.opacity)
            }
        }
        .background {
            // ⌘, and ⌘1–4 while the panel has focus. The key window gets key
            // equivalents before the main menu, so these win over "Settings…".
            Group {
                Button("") { router.tab = .settings }.keyboardShortcut(",")
                ForEach(Array(PanelTab.allCases.enumerated()), id: \.element) { index, tab in
                    Button("") { router.tab = tab }.keyboardShortcut(KeyEquivalent(Character("\(index + 1)")))
                }
            }
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
        }
        .fontDesign(.rounded)
        .tint(Theme.accent)
    }
}

/// Behind-window vibrancy that stays vivid even though the app is never
/// the frontmost one, with a solid fill when Reduce Transparency is on.
struct PanelBackground: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if reduceTransparency {
            Color(Palette.panelSolid)
        } else {
            VisualEffectBackground(material: .popover)
                .overlay(Color(Palette.panelSolid).opacity(0.35))
        }
    }
}

struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        // Our panels belong to an app that's rarely active; "active" keeps
        // the material from turning flat grey.
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}

struct TabBar: View {
    @Binding var selection: PanelTab
    @Namespace private var indicator

    var body: some View {
        HStack(spacing: 4) {
            ForEach(PanelTab.allCases) { tab in
                Button {
                    selection = tab
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 14, weight: .semibold))
                            .frame(height: 18)
                        Text(tab.title)
                            .font(.rounded(10, .semibold))
                    }
                    .foregroundStyle(selection == tab ? Theme.accent : Color.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background {
                        if selection == tab {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Theme.accent.opacity(0.13))
                                .matchedGeometryEffect(id: "tab", in: indicator)
                        }
                    }
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selection == tab ? .isSelected : [])
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.bar.opacity(0.5))
        .overlay(alignment: .top) {
            Divider().opacity(0.6)
        }
        .animation(Theme.Motion.spring, value: selection)
    }
}
