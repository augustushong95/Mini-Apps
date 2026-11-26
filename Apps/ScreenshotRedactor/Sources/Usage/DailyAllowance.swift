import Foundation
import Observation

/// The free tier: 5 redactions a day. A redaction is the first copy, drag
/// or save of a capture; exporting it again, scanning and previewing are
/// free, and so is the built-in sample. The screenshots ⌘⇧3 writes for each
/// display count as one. Pro is unlimited.
@Observable
final class DailyAllowance {
    static let freePerDay = 5

    var isUnlimited = false
    private(set) var usedToday = 0

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private var countedBursts: Set<UUID> = []

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init, calendar: Calendar = .current) {
        self.defaults = defaults
        self.now = now
        self.calendar = calendar
        refresh()
    }

    var remaining: Int { max(0, Self.freePerDay - usedToday) }

    /// Read-only (safe to call while views are drawn): today's count as of
    /// now, even if the day changed since the last `refresh()`.
    func canExport(_ document: RedactionDocument) -> Bool {
        isUnlimited || document.isSample || isCounted(document) || currentUsed < Self.freePerDay
    }

    private var currentUsed: Int {
        let lastSeen = defaults.object(forKey: Keys.lastSeen) as? Date ?? .distantPast
        let today = dayKey(max(now(), lastSeen))
        return defaults.string(forKey: Keys.day) == today ? defaults.integer(forKey: Keys.used) : 0
    }

    /// Call after an export succeeded.
    func recordExport(_ document: RedactionDocument) {
        refresh()
        guard !isUnlimited, !document.isSample, !isCounted(document) else {
            markCounted(document)
            return
        }
        usedToday += 1
        defaults.set(usedToday, forKey: Keys.used)
        markCounted(document)
    }

    private func isCounted(_ document: RedactionDocument) -> Bool {
        document.exportCounted || document.burstID.map(countedBursts.contains) == true
    }

    private func markCounted(_ document: RedactionDocument) {
        document.exportCounted = true
        if let burst = document.burstID { countedBursts.insert(burst) }
    }

    /// Starts a new day's count when the date changes. Uses the latest time
    /// ever seen, so turning the clock back doesn't hand out a fresh day.
    func refresh() {
        let lastSeen = defaults.object(forKey: Keys.lastSeen) as? Date ?? .distantPast
        let effective = max(now(), lastSeen)
        if effective > lastSeen { defaults.set(effective, forKey: Keys.lastSeen) }
        let today = dayKey(effective)
        if defaults.string(forKey: Keys.day) != today {
            defaults.set(today, forKey: Keys.day)
            defaults.set(0, forKey: Keys.used)
        }
        let used = defaults.integer(forKey: Keys.used)
        if used != usedToday { usedToday = used }
    }

    /// When the count starts over (local midnight), for "More at midnight".
    var resetsAt: Date {
        let lastSeen = defaults.object(forKey: Keys.lastSeen) as? Date ?? now()
        let start = calendar.startOfDay(for: max(now(), lastSeen))
        return calendar.date(byAdding: .day, value: 1, to: start) ?? start
    }

    private func dayKey(_ date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private enum Keys {
        static let day = "AllowanceDay"
        static let used = "AllowanceUsed"
        static let lastSeen = "AllowanceLastSeen"
    }
}
