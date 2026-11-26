#if DEBUG
import AppKit
import SwiftUI

/// A scripted session with simulated AirPods, driving the real app: posture
/// mirroring, slump detection, nudges, a break and a head-steered game. A
/// checklist window shows each step and whether it passed. The user's real
/// data is restored afterwards.
@Observable
final class AirPodsDemo {
    struct Step: Identifiable {
        let id: Int
        let title: String
        let detail: String
        var result: Bool?
    }

    enum Status {
        case running, finished
    }

    private(set) var steps: [Step] = []
    private(set) var current: Int?
    private(set) var status: Status = .running
    private(set) var stepProgress = 0.0
    private(set) var pitch = 0.0
    private(set) var roll = 0.0

    var passed: Int { steps.filter { $0.result == true }.count }
    var failed: Int { steps.filter { $0.result == false }.count }

    @ObservationIgnored var onFinish: ((String) -> Void)?
    @ObservationIgnored private unowned let model: AppModel
    @ObservationIgnored private var script: [ScriptStep] = []
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var stepElapsed = 0.0
    @ObservationIgnored private var headClock: TimeInterval = 50_000
    @ObservationIgnored private var savedState: SavedState?
    /// Acts seen during the reactions step.
    @ObservationIgnored private var reactions: [PetAct] = []

    static let tick = 0.04

    /// One step: what the simulated head does, what happens at the start,
    /// and how to tell it worked.
    private struct ScriptStep {
        let title: String
        let detail: String
        let duration: Double
        /// Head angle (pitch, roll) over the step's elapsed time; nil sends nothing.
        var head: ((Double) -> (Double, Double))?
        /// How much faster the AirPods' clock runs than real time.
        var speed: Double = 1
        var start: () -> Void = {}
        let check: () -> Bool
    }

    init(model: AppModel) {
        self.model = model
    }

    // MARK: Running

    func start() {
        savedState = model.engine.store.state
        if !model.engine.isOnboarded {
            model.engine.completeOnboarding(name: model.engine.pet.name)
        }
        script = makeScript()
        steps = script.enumerated().map { Step(id: $0.offset, title: $0.element.title, detail: $0.element.detail) }
        begin(0)
        let timer = Timer(timeInterval: Self.tick, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.advance() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        guard status == .running else { return }
        finish()
    }

    private func begin(_ index: Int) {
        current = index
        stepElapsed = 0
        stepProgress = 0
        script[index].start()
    }

    private func advance() {
        guard let index = current else { return }
        let step = script[index]
        stepElapsed += Self.tick
        stepProgress = min(1, stepElapsed / step.duration)

        if let head = step.head {
            let (p, r) = head(stepElapsed)
            pitch = p
            roll = r
            headClock += Self.tick * step.speed
            model.motion.debugInject(.synthetic(pitch: p, roll: r, timestamp: headClock))
        }

        guard stepElapsed >= step.duration else { return }
        steps[index].result = step.check()
        if index + 1 < script.count {
            begin(index + 1)
        } else {
            finish()
        }
    }

    private func finish() {
        timer?.invalidate()
        timer = nil
        current = nil
        status = .finished

        // Leave no trace: close what the demo opened and put the data back.
        model.debugArcade?.close()
        model.debugHideBubble()
        model.motion.debugStopSimulation()
        if let savedState {
            model.engine.debugRestore(savedState)
        }

        let lines = steps.map { step in
            "\(step.result == true ? "PASS" : step.result == false ? "FAIL" : "SKIP")  \(step.id + 1). \(step.title)"
        }
        onFinish?((lines + ["", "\(passed)/\(steps.count) passed"]).joined(separator: "\n"))
    }

    // MARK: Script

    private func makeScript() -> [ScriptStep] {
        let model = self.model
        let engine = model.engine
        let motion = model.motion
        let upright: (Double) -> (Double, Double) = { _ in (0, 0) }

        return [
            ScriptStep(
                title: "AirPods 연결",
                detail: "시뮬레이션 AirPods를 연결합니다. 실제 AirPods와 같은 경로로 머리 움직임이 들어갑니다.",
                duration: 2, head: upright,
                start: { motion.debugStartSimulation() },
                check: { motion.isLive && motion.connection == .connected }
            ),
            ScriptStep(
                title: "바른 자세 저장",
                detail: "바르게 앉아 화면 가운데를 봅니다. 3초 뒤 이 자세를 기준으로 저장합니다.",
                duration: 3, head: upright,
                check: { engine.captureBaseline() }
            ),
            ScriptStep(
                title: "바르게 앉기 → Mochi도 꼿꼿이",
                detail: "패널을 열어 Mochi를 크게 봅니다. 바르게 앉아 있으면 Mochi도 꼿꼿하고 잎이 서 있습니다.",
                duration: 3, head: upright,
                start: { model.openPanel(tab: .home) },
                check: { engine.posture.state == .upright && engine.pose.uprightness >= 0.9 }
            ),
            ScriptStep(
                title: "여러 가지 반응",
                detail: "같은 상황이라도 매번 다른 동작을 합니다. 쓰다듬기, 먹이 주기, 축하, 자세 고침, 돌아옴, 아침 인사, 그리고 다섯 번 연속 쓰다듬으면 어지러워합니다.",
                duration: 13, head: upright,
                start: { [weak self] in
                    guard let self else { return }
                    reactions = []
                    engine.addTreats(2)
                    let script: [(Double, () -> Void)] = [
                        (0.2, { engine.react(to: .tapped) }),
                        (1.6, { engine.react(to: .tapped) }),
                        (3.0, { engine.feed() }),
                        (4.6, { engine.react(to: .celebrate) }),
                        (6.2, { engine.react(to: .satUp) }),
                        (7.8, { engine.react(to: .breakTaken) }),
                        (9.4, { engine.react(to: .goodMorning) }),
                        (11.0, { for _ in 0..<5 { engine.react(to: .tapped) } }),
                    ]
                    for (delay, action) in script {
                        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                            guard let self, status == .running else { return }
                            action()
                            if let act = engine.reaction?.act { reactions.append(act) }
                        }
                    }
                },
                check: { [weak self] in
                    guard let self else { return false }
                    let distinct = Set(reactions).count
                    let dizzy = BehaviorDirector.pool(for: .tappedALot).map(\.act).contains(reactions.last ?? .roll)
                    return reactions.count == 8 && distinct >= 7 && dizzy
                }
            ),
            ScriptStep(
                title: "고개를 오른쪽으로 → Mochi도 오른쪽으로",
                detail: "오른쪽 어깨 쪽으로 고개를 기울이면 Mochi의 몸이 같은 쪽으로 기웁니다.",
                duration: 3, head: { t in (0, min(14, t * 14)) },
                check: { engine.pose.tilt > 8 }
            ),
            ScriptStep(
                title: "고개를 왼쪽으로 → Mochi도 왼쪽으로",
                detail: "이번에는 왼쪽 어깨 쪽으로 기울입니다.",
                duration: 3, head: { t in (0, max(-14, 14 - t * 28)) },
                check: { engine.pose.tilt < -8 }
            ),
            ScriptStep(
                title: "천천히 구부정하게 → Mochi가 납작해짐",
                detail: "고개를 숙이면 Mochi가 납작해지고 머리의 잎이 처집니다.",
                duration: 4, head: { t in (max(-26, -t * 9), 0) },
                check: { engine.pose.uprightness < 0.3 && engine.pose.leafDroop > 0.6 }
            ),
            ScriptStep(
                title: "구부정한 자세 2분 유지 (12배속)",
                detail: "잠깐 숙이는 것은 무시하고, 2분 넘게 숙이고 있을 때만 '구부정'으로 판단합니다. 2분을 10초로 빨리 감습니다.",
                duration: 10.5, head: { _ in (-26, 0) }, speed: 12,
                check: { engine.posture.state == .slouching && engine.mood == .slumped }
            ),
            ScriptStep(
                title: "자세 알림 말풍선",
                detail: "패널을 닫으면 Mochi가 말풍선으로 자세를 고치자고 알려줍니다.",
                duration: 5, head: { _ in (-26, 0) },
                start: {
                    model.debugClosePanel()
                    model.showBubble(.posture)
                },
                check: { model.debugBubbleVisible }
            ),
            ScriptStep(
                title: "다시 바르게 → Mochi 회복",
                detail: "고개를 들고 몇 초 지나면 '구부정'이 풀리고 Mochi도 다시 꼿꼿해집니다.",
                duration: 7, head: upright,
                start: {
                    model.debugHideBubble()
                    model.openPanel(tab: .home)
                },
                check: { engine.posture.state == .upright && engine.mood != .slumped }
            ),
            ScriptStep(
                title: "50분 앉아 있음 → 휴식 초대",
                detail: "휴식할 때가 되면 Mochi가 뻐근해하고(땀방울) 게임을 하자고 말풍선을 띄웁니다.",
                duration: 5, head: upright,
                start: {
                    model.debugClosePanel()
                    engine.debugAddSitting(minutes: 51)
                    if !model.debugBubbleVisible {
                        model.showBubble(.breakInvite)
                    }
                },
                check: { engine.mood == .tired && engine.breaks.phase == .due && model.debugBubbleVisible }
            ),
            ScriptStep(
                title: "머리로 Leaf Glide 조종",
                detail: "카운트다운 뒤, 고개를 좌우로 기울이는 대로 Mochi가 잎을 타고 움직이며 이슬방울을 모읍니다.",
                duration: 15, head: { t in (0, 13 * sin(t * 1.3)) },
                start: {
                    model.debugHideBubble()
                    // Skip the one-time range check so the step shows play.
                    engine.store.update { state in
                        if state.calibration.range == nil { state.calibration.range = .default }
                    }
                    model.play(.leafGlide)
                },
                check: {
                    guard let session = model.debugArcade?.session else { return false }
                    return session.usesHead && session.sim.stats.moves >= 2
                }
            ),
            ScriptStep(
                title: "라운드 종료 → 결과",
                detail: "모은 이슬방울, 스트레칭 횟수와 기울인 채 버틴 시간을 보여줍니다.",
                duration: 4, head: upright,
                start: { model.debugArcade?.session.endRound() },
                check: {
                    if case .finished = model.debugArcade?.session.phase { return true }
                    return false
                }
            ),
            ScriptStep(
                title: "AirPods 빼기 → 따라 하기 멈춤",
                detail: "AirPods 연결이 끊기면 Mochi는 자세를 모른다고 보고, 엉뚱하게 '구부정'으로 판단하지 않습니다.",
                duration: 3, head: nil,
                start: {
                    model.debugArcade?.close()
                    motion.debugStopSimulation()
                },
                check: { engine.posture.state == .unknown && engine.mood != .slumped }
            ),
        ]
    }
}

/// The demo's checklist window.
struct AirPodsDemoView: View {
    let demo: AirPodsDemo
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "airpods.pro")
                    .foregroundStyle(Theme.accent)
                Text("AirPods 시뮬레이션 테스트")
                    .font(.petHeadline)
                Spacer()
                Text("\(demo.passed)/\(demo.steps.count)")
                    .font(.rounded(13, .bold))
                    .monospacedDigit()
                    .foregroundStyle(demo.failed > 0 ? Color(Palette.coral) : Theme.accent)
            }

            if let index = demo.current {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(index + 1). \(demo.steps[index].title)")
                        .font(.rounded(14, .bold))
                    Text(demo.steps[index].detail)
                        .font(.rounded(12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    ProgressView(value: demo.stepProgress)
                        .tint(Theme.accent)
                }
                .card()
                HeadGauge(pitch: demo.pitch, roll: demo.roll)
            } else {
                Text(demo.failed == 0
                     ? "모든 단계 통과. 실제 데이터는 테스트 전 상태로 되돌렸습니다."
                     : "\(demo.failed)개 단계 실패. 실제 데이터는 테스트 전 상태로 되돌렸습니다.")
                    .font(.rounded(12, .semibold))
                    .card()
            }

            VStack(alignment: .leading, spacing: 5) {
                ForEach(demo.steps) { step in
                    HStack(spacing: 8) {
                        statusIcon(step)
                            .frame(width: 16)
                        Text(step.title)
                            .font(.rounded(11.5, step.id == demo.current ? .semibold : .regular))
                            .foregroundStyle(step.result == nil && step.id != demo.current ? .secondary : .primary)
                            .lineLimit(1)
                    }
                }
            }

            HStack {
                Spacer()
                Button(demo.status == .running ? "중지" : "닫기") {
                    demo.stop()
                    close()
                }
                .buttonStyle(.pill(.plain))
            }
        }
        .padding(16)
        .frame(width: 340)
        .background(PanelBackground())
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
        .fontDesign(.rounded)
    }

    @ViewBuilder
    private func statusIcon(_ step: AirPodsDemo.Step) -> some View {
        if let result = step.result {
            Image(systemName: result ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(result ? Theme.accent : Color(Palette.coral))
        } else if step.id == demo.current {
            ProgressView().controlSize(.mini)
        } else {
            Image(systemName: "circle")
                .foregroundStyle(.tertiary)
        }
    }
}

/// Where the simulated head is pointing: a dot that moves with tilt (x) and
/// nod (y).
private struct HeadGauge: View {
    let pitch: Double
    let roll: Double

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.primary.opacity(0.06))
                Circle().strokeBorder(Color.primary.opacity(0.12))
                Path { path in
                    path.move(to: CGPoint(x: 30, y: 4))
                    path.addLine(to: CGPoint(x: 30, y: 56))
                    path.move(to: CGPoint(x: 4, y: 30))
                    path.addLine(to: CGPoint(x: 56, y: 30))
                }
                .stroke(Color.primary.opacity(0.1))
                Circle()
                    .fill(Theme.accent)
                    .frame(width: 12, height: 12)
                    .offset(x: CGFloat(roll / 30 * 24), y: CGFloat(-pitch / 30 * 24))
                    .animation(.linear(duration: 0.08), value: pitch)
                    .animation(.linear(duration: 0.08), value: roll)
            }
            .frame(width: 60, height: 60)
            VStack(alignment: .leading, spacing: 3) {
                Text("시뮬레이션 머리 각도")
                    .font(.rounded(11, .semibold))
                    .foregroundStyle(.secondary)
                Text(String(format: "숙임 %+.0f° · 기울기 %+.0f°", pitch, roll))
                    .font(.rounded(13, .semibold))
                    .monospacedDigit()
            }
        }
    }
}
#endif
