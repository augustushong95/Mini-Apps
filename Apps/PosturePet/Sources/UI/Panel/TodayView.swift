import Charts
import SwiftUI
import MenuBarKit

struct TodayView: View {
    let engine: PetEngine
    let pro: ProStore
    let router: PanelRouter

    @State private var range: HistoryRange = .week
    @State private var hovered: PetDay?

    enum HistoryRange: String, CaseIterable, Identifiable {
        case week = "7 days"
        case month = "30 days"
        var id: Self { self }
        var days: Int { self == .week ? 7 : 30 }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Space.m) {
                summaryCard
                historyCard
            }
            .padding(14)
        }
        .scrollIndicators(.never)
    }

    private var summaryCard: some View {
        let record = engine.today
        return HStack(spacing: Theme.Space.l) {
            ZStack {
                ProgressRing(progress: Double(engine.happiness) / 100, tint: Color(Palette.coral), lineWidth: 10)
                VStack(spacing: 0) {
                    Text("\(engine.happiness)")
                        .font(.rounded(28, .bold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Image(systemName: "heart.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Color(Palette.coral))
                }
            }
            .frame(width: 104, height: 104)
            .help("Today's happiness, out of 100")
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Happiness \(engine.happiness)")

            VStack(alignment: .leading, spacing: 12) {
                Text(engine.today.day.noon().formatted(.dateTime.weekday(.wide).month().day()))
                    .font(.petCaption)
                    .foregroundStyle(.secondary)
                summaryRow("figure.stand", Color(Palette.sky), "Posture", postureText(record))
                summaryRow("figure.cooldown", Color(Palette.sun), "Breaks", "\(record.breaks)/\(PetBrain.breakGoal)")
                summaryRow("flame.fill", Color(Palette.coral), "Streak", "\(engine.streak)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 14)
    }

    private func postureText(_ record: DayRecord) -> String {
        guard let fraction = record.goodPostureFraction else { return "–" }
        return "\(Int((fraction * 100).rounded()))%"
    }

    private func summaryRow(_ symbol: String, _ tint: Color, _ title: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 18)
            Text(title)
                .font(.rounded(12))
                .foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text(value)
                .font(.rounded(12, .semibold))
                .monospacedDigit()
        }
    }

    // MARK: History

    private struct Point: Identifiable {
        let day: PetDay
        let happiness: Int
        let breaks: Int
        let isToday: Bool
        var id: PetDay { day }
        var date: Date { day.noon() }
    }

    private var points: [Point] {
        let today = engine.today.day
        let byDay = Dictionary(engine.store.state.days.map { ($0.day, $0) }, uniquingKeysWith: { _, last in last })
        return (0..<range.days).reversed().map { offset in
            let day = today.adding(days: -offset)
            let happiness: Int
            let breaks: Int
            if offset == 0 {
                happiness = engine.happiness
                breaks = engine.today.breaks
            } else {
                happiness = byDay[day].flatMap { $0.activeSeconds > 0 ? $0.happiness : nil } ?? 0
                breaks = byDay[day]?.breaks ?? 0
            }
            return Point(day: day, happiness: happiness, breaks: breaks, isToday: offset == 0)
        }
    }

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack {
                Text("Happiness")
                    .font(.petHeadline)
                Spacer()
                Picker("Range", selection: $range) {
                    ForEach(HistoryRange.allCases) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .onChange(of: range) { _, newValue in
                    if newValue == .month, !pro.isPro {
                        range = .week
                        withAnimation(Theme.Motion.quick) { router.showsPaywall = true }
                    }
                }
            }

            Chart(points) { point in
                BarMark(
                    x: .value("Day", point.date, unit: .day),
                    y: .value("Happiness", point.happiness)
                )
                .foregroundStyle(point.isToday || point.day == hovered ? Color(Palette.coral) : Color(Palette.coral).opacity(0.45))
                .clipShape(RoundedRectangle(cornerRadius: range == .week ? 5 : 2, style: .continuous))
                .annotation(position: .top, spacing: 4) {
                    if point.day == hovered {
                        Text("♥ \(point.happiness) · \(point.breaks) breaks")
                            .font(.rounded(10, .semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.thinMaterial, in: Capsule())
                            .fixedSize()
                    }
                }
            }
            .chartYScale(domain: 0...115)
            .chartYAxis(.hidden)
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                guard let plot = proxy.plotFrame else { return }
                                let x = location.x - geometry[plot].origin.x
                                if let date: Date = proxy.value(atX: x) {
                                    hovered = PetDay(containing: date.addingTimeInterval(12 * 3600))
                                }
                            case .ended:
                                hovered = nil
                            }
                        }
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: range == .week ? 1 : 7)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
                        .font(.rounded(9))
                }
            }
            .frame(height: 120)
            .animation(Theme.Motion.spring, value: range)
            .accessibilityLabel("Happiness over the last \(range.days) days")
        }
        .card(padding: 14)
    }
}
