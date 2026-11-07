import Foundation

struct NightDraft: Identifiable, Equatable {
    var id = UUID()
    var day: Date
    var startMinute: Int
    var endMinute: Int
    var breakMinutes = 30
    var breakPaid = false
    var source: String
}

enum NightDraftParser {
    /// Parses dated shifts within a pay period. Weekday-only lines require a selected week.
    /// Accepted per line: optional weekday/date + a time range like 19:00-07:00,
    /// 7p-7a, 1900-0700. Unparseable lines are reported, never guessed.
    static func parse(_ text: String, period: DateInterval, timeZoneID: String, weekOffset: Int? = nil) throws -> [NightDraft] {
        guard weekOffset == nil || weekOffset == 0 || weekOffset == 1 else { throw InputError.invalid("Choose the first or second week.") }
        let calendar = NightPayEngine.calendar(timeZoneID)
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !lines.isEmpty else { throw InputError.invalid("Paste your roster text first — for example: Fri 19:00-07:00.") }
        guard lines.count <= 10 else { throw InputError.invalid("Import up to 10 shift lines at a time.") }
        // Candidate days: every day in the period.
        var days: [Date] = []
        var cursor = calendar.startOfDay(for: period.start)
        while cursor < period.end { days.append(cursor); cursor = calendar.date(byAdding: .day, value: 1, to: cursor)! }
        var drafts: [NightDraft] = []
        var failures: [String] = []
        for line in lines {
            do {
                drafts.append(try parseLine(line, days: days, weekOffset: weekOffset, calendar: calendar, period: period))
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

    struct Review {
        var drafts: [NightDraft] = []
        var excluded: [String] = []
        var unresolved: [String] = []
    }

    static func review(_ text: String, period: DateInterval, timeZoneID: String, weekOffset: Int) throws -> Review {
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !lines.isEmpty, lines.count <= 500 else { throw InputError.invalid("Enter up to 500 roster lines.") }
        var result = Review()
        for line in lines {
            if let drafts = try? parse(line, period: period, timeZoneID: timeZoneID, weekOffset: weekOffset) {
                result.drafts.append(contentsOf: drafts)
            } else {
                let lower = line.lowercased()
                let hasTime = !extractTimes(from: lower).isEmpty
                if hasTime { result.unresolved.append(line) }
                else { result.excluded.append(line) }
            }
        }
        guard result.drafts.count <= 14 else { throw InputError.invalid("Select one person's roster with up to 14 shifts.") }
        return result
    }

    private static func parseLine(_ line: String, days: [Date], weekOffset: Int?, calendar: Calendar, period: DateInterval) throws -> NightDraft {
        let lower = line.lowercased()
        // Time range: find two times.
        let withoutDates = lower
            .replacingOccurrences(of: #"\b\d{4}-\d{2}-\d{2}\b"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?<![:\d])\b\d{1,2}[/-]\d{1,2}\b(?![:\d])"#, with: "", options: .regularExpression)
        let times = extractTimes(from: withoutDates)
        guard times.count == 2 else { throw InputError.invalid("missing time range") }
        var matchedDay: Date?
        let isoPattern = #"\b\d{4}-\d{2}-\d{2}\b"#
        let shortPattern = #"(?<![:\d])\b\d{1,2}[/-]\d{1,2}\b(?![:\d])"#
        if let range = lower.range(of: isoPattern, options: .regularExpression) {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.timeZone = calendar.timeZone
            formatter.isLenient = false
            if let date = formatter.date(from: String(lower[range])) {
                matchedDay = days.first { calendar.isDate($0, inSameDayAs: date) }
            }
        } else if let range = lower.range(of: shortPattern, options: .regularExpression) {
            let parts = lower[range].replacingOccurrences(of: "-", with: "/").split(separator: "/").compactMap { Int($0) }
            if parts.count == 2 {
                matchedDay = days.first { calendar.component(.month, from: $0) == parts[0] && calendar.component(.day, from: $0) == parts[1] }
            }
        } else {
            let english = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
            let tokens = lower.components(separatedBy: CharacterSet.letters.inverted).filter { !$0.isEmpty }
            let weekdays = english.indices.filter { index in
                tokens.contains(english[index]) || tokens.contains(String(english[index].prefix(3)))
            }
            guard weekdays.count == 1, let index = weekdays.first else { throw InputError.invalid("ambiguous weekday") }
            let candidates = days.filter { calendar.component(.weekday, from: $0) == index + 1 }
            if let weekOffset {
                let start = calendar.date(byAdding: .day, value: weekOffset * 7, to: period.start)!
                let end = calendar.date(byAdding: .day, value: 7, to: start)!
                matchedDay = candidates.first { $0 >= start && $0 < end }
            } else if candidates.count == 1 { matchedDay = candidates.first }
        }
        guard let day = matchedDay else { throw InputError.invalid("missing day") }
        return NightDraft(day: day, startMinute: times[0], endMinute: times[1], source: line)
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
            let looksLikeTime = full.contains(":") || suffix != nil || (group(2) != nil && full.filter(\.isNumber).count == 4)
            if !looksLikeTime { continue }
            if suffix == nil, !full.contains(":"), full.filter(\.isNumber).count == 4 {
                // 1900 style
                let v = Int(full.filter(\.isNumber))!
                hour = v / 100; let m2 = v % 100
                guard (0...23).contains(hour), (0...59).contains(m2) else { continue }
                results.append(hour * 60 + m2)
                continue
            }
            if let suffix {
                guard (1...12).contains(hour) else { continue }
                if suffix == "pm", hour < 12 { hour += 12 }
                if suffix == "am", hour == 12 { hour = 0 }
            } else if (0...23).contains(hour) {
                // 24h without suffix
            } else { continue }
            guard (0...23).contains(hour) else { continue }
            results.append(hour * 60 + mm)

        }
        return results
    }

    static func materialize(_ drafts: [NightDraft], timeZoneID: String, existing: [NightShift]) throws -> [NightShift] {
        let calendar = NightPayEngine.calendar(timeZoneID)
        var results: [NightShift] = []
        guard (1...14).contains(drafts.count) else { throw InputError.invalid("Confirm 1–14 shifts at a time.") }
        for draft in drafts {
            guard SupportedDates.contains(draft.day),
                  (0..<1440).contains(draft.startMinute), (0..<1440).contains(draft.endMinute) else {
                throw InputError.invalid("Check each draft date and time.")
            }
            let endDay = draft.endMinute <= draft.startMinute
                ? calendar.date(byAdding: .day, value: 1, to: draft.day)! : draft.day
            let start = try NightPayEngine.wallTime(day: draft.day, minute: draft.startMinute, calendar: calendar)
            let end = try NightPayEngine.wallTime(day: endDay, minute: draft.endMinute, calendar: calendar)
            var shift = NightShift(plannedStart: start, plannedEnd: end, timeZoneID: timeZoneID)
            shift.plannedBreakMinutes = draft.breakMinutes
            shift.plannedBreakPaid = draft.breakPaid
            shift.sourceQuote = draft.source
            try shift.validate()
            // An existing planned interval with the same meal settings already
            // represents this roster entry. Preserve its actuals and history.
            let alreadyRecorded = existing.contains {
                $0.plannedStart == shift.plannedStart && $0.plannedEnd == shift.plannedEnd &&
                $0.timeZoneID == shift.timeZoneID &&
                $0.plannedBreakMinutes == shift.plannedBreakMinutes &&
                $0.plannedBreakPaid == shift.plannedBreakPaid
            }
            if alreadyRecorded { continue }
            shift.changes = [ShiftChange(summary: "Reviewed and confirmed roster draft")]
            results.append(shift)
        }
        for draft in results {
            for other in existing + results where other.id != draft.id {
                if draft.plannedStart < other.plannedEnd && draft.plannedEnd > other.plannedStart {
                    let formatter = DateFormatter()
                    formatter.locale = Locale(identifier: "en_US")
                    formatter.timeZone = calendar.timeZone
                    formatter.dateFormat = "MMM d, h:mm a"
                    let kind = existing.contains { $0.id == other.id } ? "saved" : "draft"
                    throw InputError.invalid("The draft starting \(formatter.string(from: draft.plannedStart)) overlaps the \(kind) shift starting \(formatter.string(from: other.plannedStart)). Adjust or remove the conflicting shift before saving.")
                }
            }
        }
        return results.sorted { $0.plannedStart < $1.plannedStart }
    }
}
