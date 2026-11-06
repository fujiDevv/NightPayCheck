import Foundation

struct CalculationLine: Identifiable {
    var id: String { "\(shiftID)-\(kind)" }
    var shiftID: UUID
    var title: String
    var kind: String // Regular, Overtime, Night differential, Weekend differential
    var minutes: Int
    var hourlyRate: Decimal
    var amount: Decimal
}

struct NightEstimate {
    var lines: [CalculationLine]
    var paidMinutes: Int
    var workedMinutes: Int
    var actualShiftCount: Int
    var projectedShiftCount: Int
    var total: Decimal { lines.reduce(0) { $0 + $1.amount } }
}

enum NightPayEngine {
    static let weeklyOTMinutes = 2400 // 40h
    static let overtimeMultiplier = Decimal(string: "1.5")!

    static func calendar(_ zone: String) -> Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(identifier: zone) ?? .gmt
        return result
    }

    /// Minute-resolution engine. UTC instants determine elapsed time; the pay
    /// time zone classifies each minute (night window, weekend, OT week).
    /// Rules locked for v1: weekly 40h OT @ 1.5x base replaces regular;
    /// night + weekend flat differentials ADD and can apply to the same minute.
    static func estimate(shifts: [NightShift], rates: RateSet3, period: DateInterval,
                         timeZoneID: String, currency: String) throws -> NightEstimate {
        try rates.validate()
        guard SupportedDates.contains(period.start), SupportedDates.contains(period.end),
              period.end > period.start, period.duration <= 15 * 86400,
              period.start.timeIntervalSince1970.truncatingRemainder(dividingBy: 60) == 0,
              period.end.timeIntervalSince1970.truncatingRemainder(dividingBy: 60) == 0,
              TimeZone(identifier: timeZoneID) != nil, currency == "USD" else {
            throw InputError.invalid("Choose a valid biweekly pay period and US time zone.")
        }
        let calendar = calendar(timeZoneID)
        let startDay = calendar.startOfDay(for: period.start)
        let weekday = calendar.component(.weekday, from: startDay)
        let weekOffset = (weekday - rates.weekStartsOn + 7) % 7
        let contextStart = calendar.date(byAdding: .day, value: -weekOffset, to: startDay)!
        let relevant = shifts.filter { $0.end > contextStart && $0.start < period.end }.sorted { $0.start < $1.start }
        var previousEnd: Date?
        for shift in relevant {
            try shift.validate()
            if let previousEnd, shift.start < previousEnd {
                throw InputError.invalid("One shift overlaps another. Adjust the times before estimating pay.")
            }
            previousEnd = shift.end
        }
        var weekly: [Date: Int] = [:]
        var lines: [CalculationLine] = []
        var paid = 0, worked = 0, actualCount = 0, projectedCount = 0
        for shift in relevant {
            var counts: [String: Int] = [:]
            var ratesByKind: [String: Decimal] = [:]
            let pause = shift.breakInterval()
            var instant = max(shift.start, contextStart)
            let stop = min(shift.end, period.end)
            var included = false
            while instant < stop {
                let inPeriod = instant >= period.start
                let onBreak = pause.map { instant >= $0.start && instant < $0.end } ?? false
                let isPaidBreak = onBreak && (pause?.paid == true)
                if inPeriod {
                    if !onBreak { worked += 1 }
                    else if isPaidBreak { worked += 1 }
                }
                if !onBreak || isPaidBreak {
                    let day = calendar.startOfDay(for: instant)
                    let weekDay = calendar.component(.weekday, from: instant)
                    let offset = (weekDay - rates.weekStartsOn + 7) % 7
                    let week = calendar.date(byAdding: .day, value: -offset, to: day)!
                    let weekMinutes = weekly[week, default: 0]
                    let isOT = weekMinutes >= weeklyOTMinutes
                    weekly[week] = weekMinutes + 1
                    if inPeriod {
                        paid += 1
                        let kind = isOT ? "Overtime" : "Regular"
                        counts[kind, default: 0] += 1
                        ratesByKind[kind] = rates.baseRate * (isOT ? overtimeMultiplier : 1)
                        let minute = calendar.component(.hour, from: instant) * 60 + calendar.component(.minute, from: instant)
                        let isNight: Bool
                        if rates.nightStartMinute == rates.nightEndMinute { isNight = true }
                        else if rates.nightStartMinute < rates.nightEndMinute {
                            isNight = minute >= rates.nightStartMinute && minute < rates.nightEndMinute
                        } else { isNight = minute >= rates.nightStartMinute || minute < rates.nightEndMinute }
                        // Weekend = Saturday (7) or Sunday (1) in pay time zone.
                        let isWeekend = weekDay == 1 || weekDay == 7
                        if isNight, rates.nightDiff > 0 {
                            counts["Night differential", default: 0] += 1
                            ratesByKind["Night differential"] = rates.nightDiff
                        }
                        if isWeekend, rates.weekendDiff > 0 {
                            counts["Weekend differential", default: 0] += 1
                            ratesByKind["Weekend differential"] = rates.weekendDiff
                        }
                    }
                }
                instant = instant.addingTimeInterval(60)
            }
            if included == false, stop > max(shift.start, contextStart), max(shift.start, period.start) < min(shift.end, period.end) {
                included = true
            }
            if included { if shift.isActual { actualCount += 1 } else { projectedCount += 1 } }
            for kind in ["Regular", "Overtime", "Night differential", "Weekend differential"] {
                guard let minutes = counts[kind], let rate = ratesByKind[kind] else { continue }
                lines.append(CalculationLine(shiftID: shift.id, title: shiftTitle(shift, calendar: calendar), kind: kind,
                    minutes: minutes, hourlyRate: rate,
                    amount: Money.rounded(Decimal(minutes) * rate / 60, currency: currency)))
            }
        }
        return NightEstimate(lines: lines, paidMinutes: paid, workedMinutes: worked,
                             actualShiftCount: actualCount, projectedShiftCount: projectedCount)
    }

    private static func shiftTitle(_ shift: NightShift, calendar: Calendar) -> String {
        let day = calendar.startOfDay(for: shift.start)
        let formatter = DateFormatter()
        formatter.dateFormat = "E MMM d"
        formatter.timeZone = calendar.timeZone
        return "\(shift.title) · \(formatter.string(from: day))"
    }

    static func payPeriod(containing date: Date, preferences: PayPreferences) -> DateInterval {
        let calendar = calendar(preferences.timeZoneID)
        let anchor = calendar.startOfDay(for: preferences.periodAnchor)
        let delta = calendar.dateComponents([.day], from: anchor, to: calendar.startOfDay(for: date)).day!
        let index = Int(floor(Double(delta) / 14.0))
        let start = calendar.date(byAdding: .day, value: index * 14, to: anchor)!
        return DateInterval(start: start, end: calendar.date(byAdding: .day, value: 14, to: start)!)
    }

    static func wallTime(day: Date, minute: Int, calendar: Calendar) throws -> Date {
        let midnight = calendar.startOfDay(for: day)
        let components = DateComponents(hour: minute / 60, minute: minute % 60, second: 0)
        let first = calendar.nextDate(after: midnight.addingTimeInterval(-1), matching: components,
                                      matchingPolicy: .strict, repeatedTimePolicy: .first)
        let last = calendar.nextDate(after: midnight.addingTimeInterval(-1), matching: components,
                                     matchingPolicy: .strict, repeatedTimePolicy: .last)
        guard let first, let last, calendar.isDate(first, inSameDayAs: day), first == last else {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeZone = calendar.timeZone
            throw InputError.invalid("A shift time is skipped or repeated by daylight saving on \(formatter.string(from: midnight)). Pick an unambiguous time or add the shift manually.")
        }
        return first
    }
}

struct NightPayExplanation {
    static let disclaimer = "This explains your configured estimate. A difference alone cannot establish why an employer paid a different amount."
    static let precedence = "Overtime replaces regular pay for minutes past 40 hours in the week. Night and weekend differentials add on top — the same minute can earn both."

    static func varianceChecklist() -> [(id: String, title: String, detail: String)] {
        [
            ("break", "Meal break counted?", "Confirm the 30-minute unpaid break was actually unpaid on each shift."),
            ("window", "Night window 19:00–07:00?", "Check whether your facility counts nights as 19–07 or a narrower window like 23–07."),
            ("weekend", "Weekend Sat–Sun rule?", "Weekend means Saturday and Sunday here. Confirm your facility uses the same definition."),
            ("week", "Monday vs Sunday OT week?", "Overtime resets weekly. Confirm your week starts Monday or Sunday to match payroll."),
            ("rates", "Rate change mid-period?", "Confirm base, night, and weekend rates did not change during this pay period."),
        ]
    }
}
