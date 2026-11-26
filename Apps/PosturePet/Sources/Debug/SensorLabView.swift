#if DEBUG
import AppKit
import SwiftUI

struct SensorLabView: View {
    @Bindable var recorder: SensorLabRecorder
    @State private var copied = false

    private var hub: MotionHub { recorder.hub }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 14) {
                    motionCard
                    liveCard
                    signCard
                }
                .frame(width: 300)
                VStack(alignment: .leading, spacing: 14) {
                    signalsCard
                    minutesCard
                }
            }
            logCard
        }
        .padding(18)
        .frame(minWidth: 760, minHeight: 680)
        .fontDesign(.rounded)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Sensor Lab").font(.title2.bold())
                Text("Milestone 0 device test. Nothing here is saved.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("Hold activity assertion", isOn: $recorder.holdsActivity)
                .toggleStyle(.switch)
                .controlSize(.small)
            Button(recorder.isRecording ? "Stop" : "Start recording") {
                recorder.isRecording ? recorder.stop() : recorder.start()
            }
            .keyboardShortcut(.defaultAction)
            Button(copied ? "Copied" : "Copy report") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(recorder.report, forType: .string)
                copied = true
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    copied = false
                }
            }
        }
    }

    private var motionCard: some View {
        LabCard("Motion") {
            LabRow("Supported", hub.isSupported ? "yes" : "no")
            LabRow("Authorization", hub.authorization.labName)
            LabRow("Headphones", "\(hub.connection)")
            LabRow("Stream", "\(hub.stream)")
            LabRow("Samples", "\(recorder.totalSamples)")
            LabRow("Gaps > 1 s", "\(recorder.gapsOverOneSecond)")
            LabRow("Longest gap", String(format: "%.2f s", recorder.longestGap))
            if let error = hub.lastError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
    }

    private var liveCard: some View {
        LabCard("Live") {
            LabRow("Rate", String(format: "%.0f Hz", recorder.live.rate))
            LabRow("Gravity pitch", String(format: "%+.1f°", recorder.live.gravityPitch))
            LabRow("Gravity roll", String(format: "%+.1f°", recorder.live.gravityRoll))
            LabRow(
                "Attitude p / r / y",
                String(
                    format: "%+.0f° %+.0f° %+.0f°",
                    degrees(recorder.live.attitude.x), degrees(recorder.live.attitude.y), degrees(recorder.live.attitude.z)
                )
            )
            LabRow(
                "Gravity x / y / z",
                String(format: "%+.2f %+.2f %+.2f", recorder.live.gravity.x, recorder.live.gravity.y, recorder.live.gravity.z)
            )
            LabRow("Sensor", "\(recorder.live.sensor)")
        }
    }

    private var signCard: some View {
        LabCard("Sign check") {
            Text(signInstruction).font(.callout)
            HStack {
                Button(recorder.signStep == .idle || recorder.signStep == .done ? "Begin" : "Capture") {
                    recorder.advanceSignCheck()
                }
                Spacer()
                Text("pitch \(recorder.pitchDownSign.map { "\(Int($0))" } ?? "–") · roll \(recorder.rollRightSign.map { "\(Int($0))" } ?? "–")")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var signInstruction: String {
        switch recorder.signStep {
        case .idle: "With motion live, tap Begin."
        case .neutral: "Sit normally and look at the screen, then tap Capture."
        case .down: "Look down at your keyboard, then tap Capture."
        case .right: "Tilt your head toward your right shoulder, then tap Capture."
        case .done: "Done. The result is in the report."
        }
    }

    private var signalsCard: some View {
        LabCard("Quiet signals (polled every 2 s)") {
            LabRow("Idle", "\(Int(recorder.idleSeconds)) s")
            LabRow("Mic processes", recorder.audio.inputProcesses.isEmpty ? "none" : recorder.audio.inputProcesses.joined(separator: ", "))
            LabRow("Process list visible", recorder.audio.processListAvailable ? "yes" : "no")
            LabRow("Mic devices running", recorder.audio.runningInputDevices.isEmpty ? "none" : recorder.audio.runningInputDevices.joined(separator: ", "))
            LabRow("Cameras seen / running", "\(recorder.camera.deviceCount) / \(recorder.camera.runningDevices.isEmpty ? "none" : recorder.camera.runningDevices.joined(separator: ", "))")
            LabRow("Display mirroring", recorder.display.isMirroring ? "yes" : "no")
            LabRow("Full-screen front app", recorder.display.frontmostCoversScreen ? "yes (\(recorder.display.frontmostApp ?? "?"))" : "no")
            LabRow("Lock notifications seen", recorder.sawLockNotification ? "yes" : "not yet")
        }
    }

    private var minutesCard: some View {
        LabCard("Samples per minute") {
            if recorder.buckets.isEmpty {
                Text("Start recording, then switch to another app and leave it for 30 minutes.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                MinuteBars(buckets: recorder.buckets)
                    .frame(height: 90)
                HStack(spacing: 12) {
                    Legend(color: .green, text: "app in front")
                    Legend(color: .blue, text: "in background")
                    Legend(color: .orange, text: "locked or asleep")
                }
                .font(.caption)
            }
        }
    }

    private var logCard: some View {
        LabCard("Events") {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(recorder.log) { line in
                            Text("\(line.time.formatted(date: .omitted, time: .standard))  \(line.text)")
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                                .id(line.id)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: recorder.log.last?.id) { _, id in
                    if let id { proxy.scrollTo(id, anchor: .bottom) }
                }
            }
            .frame(minHeight: 140)
        }
    }
}

private struct MinuteBars: View {
    let buckets: [SensorLabRecorder.Bucket]

    var body: some View {
        let shown = buckets.suffix(60)
        let peak = max(1, shown.map(\.samples).max() ?? 1)
        GeometryReader { proxy in
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(shown) { bucket in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(color(for: bucket))
                        .frame(height: max(2, proxy.size.height * CGFloat(bucket.samples) / CGFloat(peak)))
                        .help("\(bucket.start.formatted(date: .omitted, time: .shortened)): \(bucket.samples) samples")
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
    }

    private func color(for bucket: SensorLabRecorder.Bucket) -> Color {
        if bucket.lockedSeconds > 30 || bucket.screensAsleepSeconds > 30 { return .orange }
        return bucket.activeSeconds > 30 ? .green : .blue
    }
}

private struct Legend: View {
    let color: Color
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text).foregroundStyle(.secondary)
        }
    }
}

private struct LabCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct LabRow: View {
    let label: String
    let value: String

    init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value).monospacedDigit().multilineTextAlignment(.trailing)
        }
        .font(.callout)
    }
}
#endif
