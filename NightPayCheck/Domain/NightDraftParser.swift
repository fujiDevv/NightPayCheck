import Foundation

struct NightDraft: Identifiable {
    var id = UUID()
    var day: Date
    var startMinute: Int
    var endMinute: Int
    var source: String
}

enum NightDraftParser {
    /// Parses 1–6 night shifts from pasted roster text inside the pay period.
    /// Accepted per line: optional weekday/date + a time range like 19:00-07:00,
    /// 7p-7a, 1900-0700. Unparseable lines are reported, never guessed.
    static func parse(_ text: String, period: DateInterval, timeZoneID: String) throws -> [NightDraft] {
        let calendar = NightPayEngine.calendar(timeZoneID)
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !lines.isEmpty else { throw InputError.invalid("Paste your roster text first — for example: Fri 19:00-07:00.") }
        guard lines.count <= 10 else { throw InputError.invalid("Import up to 10 lines at a time; confirm 3–6 night shifts.") }
        // Candidate days: every day in the period.
        var days: [Date] = []
        var cursor = calendar.startOfDay(for: period.start)
        while cursor < period.end { days.append(cursor); cursor = calendar.date(byAdding: .day, value: 1, to: cursor)! }
        let weekdayNames = calendar.shortWeekdaySymbols // Sun..Sat, locale-aware
        var drafts: [NightDraft] = []
        var failures: [String] = []
        for line in lines {
            do {
                drafts.append(try parseLine(line, days: days, weekdayNames: weekdayNames, calendar: calendar, period: period))
            } catch {
                failures.append(line)
            }
        }
        if !failures.isEmpty {
            throw InputError.invalid("Could not read: \(failures.joined(separator: "; ")). Use one shift per line like “Fri 19:00-07:00” or “11/08 19:00-07:00”.")
        }
        guard (1...10).contains(drafts.count) else { throw InputError.invalid("No clear shifts found. Edit the text or add a shift manually.") }
        return drafts.sorted { $0.day < $1.day }
    }

    private static func parseLine(_ line: String, days: [Date], weekdayNames: [String], calendar: Calendar, period: DateInterval) throws -> NightDraft {
        let lower = line.lowercased()
        // Time range: find two times.
        let times = extractTimes(from: lower)
        guard times.count == 2 else { throw InputError.invalid("missing time range") }
        // Day: try M/D or weekday name; default to first unmatched day is unsafe → require explicit day.
        var matchedDay: Date?
        // M/D or M-D
        if let md = lower.range(of: #"\b(\d{1,2})[/-](\d{1,2})\b"#, options: .regularExpression) {
            let token = String(lower[md]).replacingOccurrences(of: "-", with: "/")
            let parts = token.split(separator: "/").compactMap { Int($0) }
            if parts.count == 2 {
                let year = calendar.component(.year, from: period.start)
                if let date = calendar.date(from: DateComponents(year: year, month: parts[0], day: parts[1])) {
                    let start = calendar.startOfDay(for: date)
                    if start >= calendar.startOfDay(for: period.start) && start < period.end { matchedDay = start }
                }
            }
        }
        if matchedDay == nil {
            for (index, name) in weekdayNames.enumerated() {
                // Gregorian weekday: 1=Sun..7=Sat; index 0=Sun
                if lower.contains(name.lowercased()) || lower.contains(fullWeekday(index, calendar: calendar)) {
                    let target = index + 1
                    matchedDay = days.first { calendar.component(.weekday, from: $0) == target }
                    break
                }
            }
        }
        // Also accept ISO yyyy-mm-dd
        if matchedDay == nil, let iso = lower.range(of: #"\b\d{4}-\d{2}-\d{2}\b"#, options: .regularExpression) {
            let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"; formatter.timeZone = calendar.timeZone
            if let date = formatter.date(from: String(lower[iso])) {
                let start = calendar.startOfDay(for: date)
                if start >= calendar.startOfDay(for: period.start) && start < period.end { matchedDay = start }
            }
        }
        guard let day = matchedDay else { throw InputError.invalid("missing day") }
        return NightDraft(day: day, startMinute: times[0], endMinute: times[1], source: line)
    }

    private static func fullWeekday(_ index: Int, calendar: Calendar) -> String {
        calendar.weekdaySymbols[index].lowercased()
    }

    /// Returns [startMinute, endMinute] in 0..<1440.
    static func extractTimes(from line: String) -> [Int] {
        // Normalize: 7p → 7pm, 7a → 7am
        let s = line.replacingOccurrences(of: #"(?<!m)(\b\d{1,2}(?::\d{2})?\s*[ap]\b)"#, with: "$1m", options: .regularExpression)
        let pattern = #"(\d{1,2})(?::?(\d{2}))?\s*(am|pm)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let matches = regex.matches(in: s, range: NSRange(s.startIndex..., in: s))
        var results: [Int] = []
        for m in matches {
            func group(_ i: Int) -> String? {
                let r = m.range(at: i); guard r.location != NSNotFound, let range = Range(r, in: s) else { return nil }
                return String(s[range])
            }
            guard let hStr = group(1), let h = Int(hStr) else { continue }
            let minStr = group(2) ?? "00"
            guard let mm = Int(minStr), (0...59).contains(mm) else { continue }
            let suffix = group(3)?.lowercased()
            var hour = h
            // Skip bare month/day numbers already consumed? Heuristic: times must be near : or am/pm or 4-digit.
            let full = (group(0) ?? "")
            let looksLikeTime = full.contains(":") || suffix != nil || (hStr.count == 4)
            if !looksLikeTime { continue }
            if hStr.count == 4, suffix == nil, !full.contains(":") {
                // 1900 style
                let v = Int(hStr)!
                hour = v / 100; let m2 = v % 100
                guard (0...23).contains(hour), (0...59).contains(m2) else { continue }
                results.append(hour * 60 + m2)
                continue
            }
            if let suffix {
                if suffix == "pm", hour < 12 { hour += 12 }
                if suffix == "am", hour == 12 { hour = 0 }
            } else if (0...23).contains(hour) {
                // 24h without suffix
            } else { continue }
            guard (0...23).contains(hour) else { continue }
            results.append(hour * 60 + mm)
            if results.count == 2 { break }
        }
        return results
    }

    static func materialize(_ drafts: [NightDraft], timeZoneID: String, existing: [NightShift]) throws -> [NightShift] {
        let calendar = NightPayEngine.calendar(timeZoneID)
        var results: [NightShift] = []
        for draft in drafts {
            let endDay = draft.endMinute <= draft.startMinute
                ? calendar.date(byAdding: .day, value: 1, to: draft.day)! : draft.day
            let start = try NightPayEngine.wallTime(day: draft.day, minute: draft.startMinute, calendar: calendar)
            let end = try NightPayEngine.wallTime(day: endDay, minute: draft.endMinute, calendar: calendar)
            var shift = NightShift(plannedStart: start, plannedEnd: end, timeZoneID: timeZoneID)
            shift.sourceQuote = draft.source
            try shift.validate()
            shift.changes = [ShiftChange(summary: "Reviewed and confirmed roster draft")]
            results.append(shift)
        }
        for draft in results {
            for other in existing + results where other.id != draft.id {
                if draft.plannedStart < other.plannedEnd && draft.plannedEnd > other.plannedStart {
                    throw InputError.invalid("A draft overlaps another shift. Adjust or remove it before saving.")
                }
            }
        }
        return results.sorted { $0.plannedStart < $1.plannedStart }
    }
}
