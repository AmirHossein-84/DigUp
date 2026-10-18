import Foundation

/// The hours of the day indexing may run in, when someone would rather DigUp read files only at night: from `start`
/// to `end`, in minutes after midnight, local time. A window that crosses midnight (23:00 to 07:00) is fine; one that
/// starts and ends at the same minute is open all day.
///
/// Off by default: everything indexes as soon as it can. Search works at any hour either way.
public struct IndexingHours: Sendable, Equatable {
    public var enabled: Bool
    public var start: Int
    public var end: Int

    public static let defaultStart = 1 * 60
    public static let defaultEnd = 7 * 60

    public init(enabled: Bool = false, start: Int = defaultStart, end: Int = defaultEnd) {
        self.enabled = enabled
        self.start = Self.clamped(start)
        self.end = Self.clamped(end)
    }

    /// Whether indexing may run at `date`.
    public func isOpen(at date: Date, calendar: Calendar = .current) -> Bool {
        guard enabled, start != end else { return true }
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        return start < end ? (start <= minute && minute < end) : (minute >= start || minute < end)
    }

    /// Alias for isOpen for API compatibility.
    public func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        isOpen(at: date, calendar: calendar)
    }

    /// The next moment after `date` that the window opens or closes, or nil when it never does (off, or all day).
    public func nextChange(after date: Date, calendar: Calendar = .current) -> Date? {
        guard enabled, start != end else { return nil }
        return [start, end]
            .compactMap { minute in
                calendar.nextDate(after: date, matching: DateComponents(hour: minute / 60, minute: minute % 60, second: 0),
                                  matchingPolicy: .nextTime)
            }
            .min()
    }

    /// "01:00" in the user's own time format.
    public static func timeText(_ minute: Int, calendar: Calendar = .current) -> String {
        let date = calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: Date()) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }

    /// Parse a string like "01:00-07:00", "1:00-7:00", "60-420", or "1-7".
    public static func parse(_ text: String) -> IndexingHours? {
        let parts = text.split(separator: "-").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2 else { return nil }
        func parseMinute(_ str: String) -> Int? {
            if str.contains(":") {
                let timeParts = str.split(separator: ":")
                guard timeParts.count == 2, let h = Int(timeParts[0]), let m = Int(timeParts[1]) else { return nil }
                return h * 60 + m
            }
            guard let val = Int(str) else { return nil }
            return val < 24 ? val * 60 : val
        }
        guard let start = parseMinute(parts[0]), let end = parseMinute(parts[1]) else { return nil }
        return IndexingHours(enabled: true, start: start, end: end)
    }

    private static func clamped(_ minute: Int) -> Int {
        min(max(minute, 0), 24 * 60 - 1)
    }
}
