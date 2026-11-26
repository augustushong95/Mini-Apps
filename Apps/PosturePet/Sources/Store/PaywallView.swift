import SwiftUI
import MenuBarKit

/// The Pro offer, shown inside the panel. Only ever opened by the user
/// tapping something locked; there are no pop-up paywalls.
struct PaywallView: View {
    let pro: ProStore
    let engine: PetEngine
    var close: () -> Void

    @State private var appeared = false

    private var royalPose: PetPose {
        var pose = PetMood.happy.pose(stage: engine.pet.stage, posture: nil)
        pose.eyes = .happy
        pose.mouth = .grin
        pose.accessories = [.crown, .sparkles]
        return pose
    }

    var body: some View {
        ZStack {
            Color.black.opacity(appeared ? 0.25 : 0)
                .onTapGesture(perform: close)

            VStack(spacing: Theme.Space.m) {
                HStack {
                    Spacer()
                    Button(action: close) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .frame(width: 24, height: 24)
                            .background(.quaternary, in: Circle())
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityLabel("Close")
                }

                PetView(pose: royalPose)
                    .frame(width: 120, height: 120)
                    .padding(.top, -16)

                VStack(spacing: 4) {
                    Text("Posture Pet Pro")
                        .font(.petTitle)
                    Text("One-time purchase")
                        .font(.petBody)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 10) {
                    perk("gamecontroller.fill", "Puddle Hop and Star Float", Color(Palette.sky))
                    perk("chart.bar.xaxis", "30-day history", Color(Palette.accent))
                    perk("sparkles", "Future pets and goodies", Color(Palette.sun))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()

                Button {
                    Task { await pro.purchase() }
                } label: {
                    HStack {
                        if pro.isPurchasing {
                            ProgressView().controlSize(.small)
                        }
                        Text(pro.product == nil ? "Unlock Pro" : "Unlock for \(pro.priceText)")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.pill(.prominent, tint: Color(Palette.coral)))
                .disabled(pro.isPurchasing)

                if let message = pro.message {
                    Text(message)
                        .font(.petCaption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Button("Restore purchase") {
                    Task { await pro.restore() }
                }
                .buttonStyle(.plain)
                .font(.petCaption)
                .foregroundStyle(.secondary)
            }
            .padding(18)
            .background(PanelBackground())
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
            .shadow(color: .black.opacity(0.2), radius: 20, y: 8)
            .padding(16)
            .offset(y: appeared ? 0 : 40)
            .opacity(appeared ? 1 : 0)
        }
        .onAppear {
            withAnimation(Theme.Motion.spring) { appeared = true }
        }
        .onChange(of: pro.isPro) { _, isPro in
            if isPro {
                engine.react(to: .celebrate)
                close()
            }
        }
    }

    private func perk(_ symbol: String, _ title: String, _ tint: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 26, height: 26)
                .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(title).font(.rounded(13, .semibold))
        }
    }

}
