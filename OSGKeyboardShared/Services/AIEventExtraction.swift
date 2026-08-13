// AIEventExtraction.swift
// OSGKeyboard · Shared
//
// Parses the LLM's extract-events reply into Shortcut lines. Fail closed:
// empty / NONE / lines without a parseable start never become a run.
// Canonical line: start|end|title|location
// All-day uses end token ALLDAY so the companion Shortcut can branch.

import Foundation

public enum AIEventExtraction: Sendable {
    public static let maximumItems = 20
    public static let defaultDuration: TimeInterval = 3600
    /// End-field sentinel for all-day events (Shortcut If equals this).
    public static let allDaySentinel = "ALLDAY"

    private static let emptyTokens: Set<String> = [
        "none", "no", "n/a", "na", "nil", "null",
        "无", "没有", "没有日程", "没有事件", "无日程",
        "没有日期", "没有时间", "没有日期或时间", "没有日期和时间",
        "no events", "no event", "no calendar events",
        "no date", "no time", "no date or time", "no date and time",
    ]

    /// Lines to send to the companion Shortcut. Empty → do not run it.
    public static func lines(
        from raw: String,
        sourceClipboard: String? = nil,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [String] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        if isEmptyToken(trimmed) { return [] }

        var seen = Set<String>()
        var items: [String] = []
        for line in trimmed.components(separatedBy: .newlines) {
            guard let encoded = encodeLine(
                line,
                now: now,
                calendar: calendar
            ) else { continue }
            let key = encoded.lowercased()
            guard seen.insert(key).inserted else { continue }
            items.append(encoded)
            if items.count == maximumItems { break }
        }

        if items.count == 1, isWholeClipboardEcho(items[0], source: sourceClipboard) {
            return []
        }
        return items
    }

    // MARK: - Line

    private static func encodeLine(
        _ line: String,
        now: Date,
        calendar: Calendar
    ) -> String? {
        let fields = splitFields(line)
        guard fields.count >= 2 else { return nil }

        let startRaw = fields[0]
        let endRaw: String
        let titleRaw: String
        let locationRaw: String
        switch fields.count {
        case 2:
            endRaw = ""
            titleRaw = fields[1]
            locationRaw = ""
        case 3:
            // 3 fields: start|end|title if segment 2 is a time/empty;
            // otherwise start|title|location.
            if fields[1].isEmpty || parseInstant(fields[1], on: now, calendar: calendar) != nil {
                endRaw = fields[1]
                titleRaw = fields[2]
                locationRaw = ""
            } else {
                endRaw = ""
                titleRaw = fields[1]
                locationRaw = fields[2]
            }
        default:
            endRaw = fields[1]
            titleRaw = fields[2]
            locationRaw = fields[3]
        }

        let title = stripBullet(titleRaw)
        guard !title.isEmpty, !isEmptyToken(title) else { return nil }
        let location = locationRaw.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let start = parseInstant(startRaw, on: now, calendar: calendar) else {
            return nil
        }

        switch start {
        case .allDay(let day):
            return encode(
                start: formatDay(day, calendar: calendar),
                end: allDaySentinel,
                title: title,
                location: location
            )
        case .timed(let startDate, _):
            let endDate = resolveEnd(
                endRaw,
                start: startDate,
                calendar: calendar
            )
            return encode(
                start: formatMinute(startDate, calendar: calendar),
                end: formatMinute(endDate, calendar: calendar),
                title: title,
                location: location
            )
        }
    }

    /// Split on `|` and keep at most 4 fields; extra segments join into location.
    private static func splitFields(_ line: String) -> [String] {
        let parts = line
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard parts.count > 4 else { return parts }
        let location = parts[3...].joined(separator: "|")
        return [parts[0], parts[1], parts[2], location]
    }

    private static func encode(start: String, end: String, title: String, location: String) -> String {
        "\(start)|\(end)|\(title)|\(location)"
    }

    // MARK: - Time

    private enum Instant {
        case allDay(Date)
        case timed(Date, timeOnly: Bool)
    }

    private static func parseInstant(
        _ raw: String,
        on day: Date,
        calendar: Calendar
    ) -> Instant? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if text.caseInsensitiveCompare(allDaySentinel) == .orderedSame {
            return .allDay(calendar.startOfDay(for: day))
        }

        for format in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm"] {
            if let date = date(from: text, format: format, calendar: calendar) {
                return .timed(date, timeOnly: false)
            }
        }
        if let date = date(from: text, format: "yyyy-MM-dd", calendar: calendar) {
            return .allDay(calendar.startOfDay(for: date))
        }
        for format in ["HH:mm:ss", "HH:mm", "H:mm"] {
            if let parsed = date(from: text, format: format, calendar: calendar) {
                let parts = calendar.dateComponents([.hour, .minute, .second], from: parsed)
                guard let combined = calendar.date(
                    bySettingHour: parts.hour ?? 0,
                    minute: parts.minute ?? 0,
                    second: 0,
                    of: day
                ) else { return nil }
                return .timed(combined, timeOnly: true)
            }
        }
        return nil
    }

    private static func resolveEnd(
        _ raw: String,
        start: Date,
        calendar: Calendar
    ) -> Date {
        let fallback = start.addingTimeInterval(defaultDuration)
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.caseInsensitiveCompare(allDaySentinel) != .orderedSame else {
            return fallback
        }
        guard let parsed = parseInstant(trimmed, on: start, calendar: calendar) else {
            return fallback
        }
        let end: Date
        switch parsed {
        case .allDay(let day):
            // Date-only end with a timed start: use that calendar day at 23:59.
            end = calendar.date(bySettingHour: 23, minute: 59, second: 0, of: day) ?? fallback
        case .timed(let date, let timeOnly):
            if timeOnly, date <= start {
                end = calendar.date(byAdding: .day, value: 1, to: date) ?? fallback
            } else {
                end = date
            }
        }
        return end <= start ? fallback : end
    }

    private static func date(from text: String, format: String, calendar: Calendar) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.isLenient = false
        formatter.dateFormat = format
        return formatter.date(from: text)
    }

    private static func formatDay(_ date: Date, calendar: Calendar) -> String {
        format(date, "yyyy-MM-dd", calendar: calendar)
    }

    private static func formatMinute(_ date: Date, calendar: Calendar) -> String {
        format(date, "yyyy-MM-dd HH:mm", calendar: calendar)
    }

    private static func format(_ date: Date, _ format: String, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = format
        return formatter.string(from: date)
    }

    // MARK: - Tokens

    private static func isEmptyToken(_ text: String) -> Bool {
        let folded = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "。.!！"))
            .lowercased()
        return emptyTokens.contains(folded)
    }

    private static func stripBullet(_ line: String) -> String {
        var text = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefixes = ["- ", "* ", "• ", "、"]
        for prefix in prefixes where text.hasPrefix(prefix) {
            text = String(text.dropFirst(prefix.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let dotted = text.range(of: #"^\d+[\.\)、]\s*"#, options: .regularExpression) {
            text = String(text[dotted.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text
    }

    /// One long title that is essentially the clipboard body is not an event.
    private static func isWholeClipboardEcho(_ item: String, source: String?) -> Bool {
        guard let source, source.count > 80 else { return false }
        let fields = item.split(separator: "|", omittingEmptySubsequences: false)
        guard fields.count >= 3 else { return false }
        let title = String(fields[2])
        guard title.count > 80 else { return false }
        let a = collapse(title)
        let b = collapse(source)
        guard !a.isEmpty, !b.isEmpty else { return false }
        if a == b { return true }
        return a.contains(b) || b.contains(a)
    }

    private static func collapse(_ text: String) -> String {
        text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .lowercased()
    }
}
