import Charts
import SwiftUI

struct TodayView: View {
    let engine: PetEngine
    let pro: ProStore
    let router: PanelRouter

    @State private var range: HistoryRange = .week

    enum HistoryRange: String, CaseIterable, Identifiable {
        case week = "7 days"
        case month = "30 days"
        var id: Self { self }
        var days: Int { self == .week ? 7 : 30 }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Space.m) {
                header
                summaryCard
                historyCard
                if let yesterday {
                    yesterdayCard(yesterday)
                }
            }
            .padding(14)
        }
        .scrollIndicators(.never)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Today")
                .font(.petTitle)
            Spacer()
            Text(engine.today.day.noon().formatted(.dateTime.weekday(.wide).month().day()))
                .font(.petCaption)
                .foregroundStyle(.secondary)
        }
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
                    Text("happiness")
                        .font(.rounded(10, .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 104, height: 104)
            .accessibilityElement(children: .combine)

            VStack(alignment: .leading, spacing: 9) {
                summaryRow("figure.stand", Color(Palette.sky), "Sitting well", postureText(record))
                summaryRow("figure.cooldown", Color(Palette.sun), "Breaks", "\(record.breaks) of \(PetBrain.breakGoal)+")
                summaryRow("gamecontroller.fill", Color(Palette.lavender), "Games", "\(record.gamesPlayed)")
                summaryRow("drop.fill", Color(Palette.sky), "Dewdrops", "+\(record.treatsEarned)")
                summaryRow("flame.fill", Color(Palette.coral), "Streak", engine.streak == 1 ? "1 day" : "\(engine.streak) days")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 14)
    }

    private func postureText(_ record: DayRecord) -> String {
        guard let fraction = record.goodPostureFraction else { return "not measured" }
        return "\(Duration.seconds(record.goodPostureSeconds).compact) · \(Int((fraction * 100).rounded()))%"
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
            if offset == 0 {
                happiness = engine.happiness
            } else {
                happiness = byDay[day].flatMap { $0.activeSeconds > 0 ? $0.happiness : nil } ?? 0
            }
            return Point(day: day, happiness: happiness, isToday: offset == 0)
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
                .foregroundStyle(point.isToday ? Color(Palette.coral) : Color(Palette.coral).opacity(0.45))
                .clipShape(RoundedRectangle(cornerRadius: range == .week ? 5 : 2, style: .continuous))
            }
            .chartYScale(domain: 0...100)
            .chartYAxis {
                AxisMarks(values: [0, 50, 100]) { _ in
                    AxisGridLine().foregroundStyle(.quaternary)
                    AxisValueLabel().font(.rounded(9))
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

    // MARK: Yesterday

    private var yesterday: DayRecord? {
        let day = engine.today.day.adding(days: -1)
        return engine.store.state.record(for: day).flatMap { $0.activeSeconds >= 60 ? $0 : nil }
    }

    private func yesterdayCard(_ record: DayRecord) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "calendar")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Yesterday with \(engine.pet.name)")
                    .font(.rounded(12, .semibold))
                Text(yesterdaySummary(record))
                    .font(.rounded(11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .card(padding: 12)
    }

    private func yesterdaySummary(_ record: DayRecord) -> String {
        var parts = ["\(record.breaks) break\(record.breaks == 1 ? "" : "s")"]
        if let fraction = record.goodPostureFraction {
            parts.append("sat well \(Int((fraction * 100).rounded()))% of the time")
        }
        if let happiness = record.happiness {
            parts.append("happiness \(happiness)")
        }
        return parts.joined(separator: " · ")
    }
}
