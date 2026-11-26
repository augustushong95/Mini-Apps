import Foundation

/// A calendar day as Mochi counts it: from 04:00 to 04:00 local time, so
/// working past midnight still belongs to the evening it started in and
/// doesn't split a day or break a streak.
nonisolated struct PetDay: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    static let startHour = 4

    let year: Int
    let month: Int
    let day: Int

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    init(containing date: Date, calendar: Calendar = .current) {
        let hour = calendar.component(.hour, from: date)
        var anchor = calendar.startOfDay(for: date)
        if hour < Self.startHour {
            anchor = calendar.date(byAdding: .day, value: -1, to: anchor) ?? anchor
        }
        let parts = calendar.dateComponents([.year, .month, .day], from: anchor)
        self.init(year: parts.year ?? 2000, month: parts.month ?? 1, day: parts.day ?? 1)
    }

    /// Noon on this day, a time that exists in every time zone and DST change.
    func noon(in calendar: Calendar = .current) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? .now
    }

    /// When this pet day begins (04:00 local time).
    func start(in calendar: Calendar = .current) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: Self.startHour)) ?? .now
    }

    func adding(days: Int, calendar: Calendar = .current) -> PetDay {
        let date = calendar.date(byAdding: .day, value: days, to: noon(in: calendar)) ?? noon(in: calendar)
        return PetDay(calendarDayOf: date, calendar: calendar)
    }

    /// Whole days from `self` to `other` (positive when `other` is later).
    func days(until other: PetDay, calendar: Calendar = .current) -> Int {
        calendar.dateComponents([.day], from: noon(in: calendar), to: other.noon(in: calendar)).day ?? 0
    }

    private init(calendarDayOf date: Date, calendar: Calendar) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year ?? 2000, month: parts.month ?? 1, day: parts.day ?? 1)
    }

    static func < (lhs: PetDay, rhs: PetDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }
}
