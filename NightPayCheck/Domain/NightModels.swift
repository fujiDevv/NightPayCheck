import Foundation

enum InputError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case .invalid(let message) = self { message } else { nil } }
}

enum SupportedDates {
    static func contains(_ date: Date) -> Bool {
        date.timeIntervalSince1970.isFinite && (-2_208_988_800...7_289_654_400).contains(date.timeIntervalSince1970)
    }
}

struct NightBreak: Codable, Identifiable, Equatable {
    var id = UUID()
    var start: Date
    var end: Date
    var paid = false
}

struct ShiftChange: Codable, Identifiable {
    var id = UUID()
    var changedAt = Date()
    var summary: String
}

struct NightShift: Codable, Identifiable {
    var id = UUID()
    var title: String = "Night shift"
    var plannedStart: Date
    var plannedEnd: Date
    var actualStart: Date?
    var actualEnd: Date?
    var timeZoneID: String
    var plannedBreakMinutes = 30
    var plannedBreakPaid = false
    var actualBreakMinutes: Int?
    var actualBreakPaid: Bool?
    var note = ""
    var changes: [ShiftChange] = []
    var sourceQuote = ""

    var start: Date { actualStart ?? plannedStart }
    var end: Date { actualEnd ?? plannedEnd }
    var breakMinutes: Int { actualBreakMinutes ?? plannedBreakMinutes }
    var breakPaid: Bool { actualBreakPaid ?? plannedBreakPaid }
    var isActual: Bool { actualStart != nil }

    /// Break is a single interval ending at shift end by default (meal at end of
    /// a 12h night). Materialized on demand so DST / midnight splits stay exact.
    func breakInterval() -> NightBreak? {
        guard breakMinutes > 0 else { return nil }
        let end = end
        let start = end.addingTimeInterval(TimeInterval(-breakMinutes * 60))
        guard start >= self.start else { return nil }
        return NightBreak(start: start, end: end, paid: breakPaid)
    }

    func validate() throws {
        guard TimeZone(identifier: timeZoneID) != nil,
              plannedEnd > plannedStart,
              plannedEnd.timeIntervalSince(plannedStart) <= 16 * 3600,
              plannedEnd.timeIntervalSince(plannedStart) >= 4 * 3600,
              (actualStart == nil) == (actualEnd == nil) else {
            throw InputError.invalid("Each shift needs a valid time zone and a planned end 4–16 hours after its start.")
        }
        if let actualStart, let actualEnd {
            guard actualEnd > actualStart,
                  actualEnd.timeIntervalSince(actualStart) <= 16 * 3600,
                  actualEnd.timeIntervalSince(actualStart) >= 4 * 3600 else {
                throw InputError.invalid("Actual end must be 4–16 hours after actual start.")
            }
        }
        guard plannedBreakMinutes >= 0, plannedBreakMinutes <= 120,
              (actualBreakMinutes ?? 0) >= 0, (actualBreakMinutes ?? 0) <= 120 else {
            throw InputError.invalid("Meal break must be 0–120 minutes.")
        }
        for date in [plannedStart, plannedEnd, actualStart, actualEnd].compactMap({ $0 }) {
            guard SupportedDates.contains(date),
                  abs(date.timeIntervalSince1970.truncatingRemainder(dividingBy: 60)) < 0.001 else {
                throw InputError.invalid("Shift times must use whole minutes between 1900 and 2200.")
            }
        }
        if let pause = breakInterval(), pause.paid == false {
            // unpaid break must fit; paid breaks count as worked so they always fit
            guard pause.start >= start else {
                throw InputError.invalid("Break must fit inside the shift.")
            }
        }
    }
}

/// Locked 3-rate set for v1: base + night flat + weekend flat. No multipliers,
/// no double-time, no holidays. OT is fixed: weekly 40h @ 1.5x base.
struct RateSet3: Codable {
    var version = 1
    var baseRate: Decimal = 0
    var nightDiff: Decimal = 0
    var weekendDiff: Decimal = 0
    var nightStartMinute = 19 * 60
    var nightEndMinute = 7 * 60
    /// 2 = Monday (Gregorian), 1 = Sunday. Biweekly anchor decides period edges.
    var weekStartsOn = 2

    func validate() throws {
        guard version == 1, !baseRate.isNaN, !nightDiff.isNaN, !weekendDiff.isNaN,
              baseRate >= 0, baseRate <= 1_000_000,
              nightDiff >= 0, nightDiff <= 1_000,
              weekendDiff >= 0, weekendDiff <= 1_000,
              (0..<1440).contains(nightStartMinute), (0..<1440).contains(nightEndMinute),
              weekStartsOn == 1 || weekStartsOn == 2 else {
            throw InputError.invalid("Check your three rates, night window, and week start (Sunday or Monday).")
        }
    }
}

struct PayPreferences: Codable {
    var currency = "USD"
    var localeID = Locale.current.identifier
    var timeZoneID = TimeZone.current.identifier
    var periodAnchor = Calendar.current.startOfDay(for: Date())
    var weekAnchorMonday = true
    var onboardingComplete = false
    var periodDays: Int { 14 }
}

enum PayCategory: String, Codable, CaseIterable {
    case regular = "Regular", overtime = "Overtime"
    case night = "Night differential", weekend = "Weekend differential"
}

struct MatchedPayLine: Codable, Identifiable {
    var id: PayCategory { category }
    let category: PayCategory
    let label: String
    let paid: Decimal
    let expected: Decimal
    let minutes: Int
    var difference: Decimal { paid - expected }

    init(category: PayCategory, label: String, paid: Decimal, estimate: NightEstimate) {
        self.category = category
        self.label = label
        self.paid = Money.rounded(paid, currency: "USD")
        let lines = estimate.lines.filter { $0.kind == category.rawValue }
        expected = lines.reduce(0) { $0 + $1.amount }
        minutes = lines.reduce(0) { $0 + $1.minutes }
    }
}

struct PayslipCompare: Codable, Identifiable {
    var id = UUID()
    var periodStart: Date
    var periodEnd: Date
    var gross: Decimal
    var estimatedAtEntry: Decimal
    var recordedAt = Date()
    var matchedLines: [MatchedPayLine]?
    var hasOtherRules: Bool?
    var remainingDifference: Decimal {
        gross - estimatedAtEntry - (matchedLines ?? []).reduce(0) { $0 + $1.difference }
    }
}

struct NightAppData: Codable {
    static let maxBackupSize = 25_000_000
    var schemaVersion = 1
    var preferences = PayPreferences()
    var shifts: [NightShift] = []
    var rates = RateSet3()
    var comparisons: [PayslipCompare] = []
    /// Free tier: 2 pay-period checks before the lifetime unlock prompt.
    var completedChecks = 0

    func validate() throws {
        guard schemaVersion == 1 else { throw InputError.invalid("This backup version is not supported.") }
        guard TimeZone(identifier: preferences.timeZoneID) != nil,
              preferences.currency == "USD",
              SupportedDates.contains(preferences.periodAnchor),
              Set(shifts.map(\.id)).count == shifts.count,
              Set(comparisons.map(\.id)).count == comparisons.count else {
            throw InputError.invalid("Backup contains invalid settings or duplicate identifiers.")
        }
        try rates.validate()
        for shift in shifts { try shift.validate() }
        for comparison in comparisons {
            let lines = comparison.matchedLines ?? []
            guard Set(lines.map(\.category)).count == lines.count,
                  lines.allSatisfy({ !$0.label.isEmpty && $0.minutes >= 0 && $0.paid >= 0 && $0.expected >= 0 }) else {
                throw InputError.invalid("A saved payslip line is invalid.")
            }
            guard SupportedDates.contains(comparison.periodStart),
                  SupportedDates.contains(comparison.periodEnd),
                  comparison.periodEnd > comparison.periodStart,
                  !comparison.gross.isNaN, !comparison.estimatedAtEntry.isNaN,
                  comparison.gross >= 0, comparison.estimatedAtEntry >= 0 else {
                throw InputError.invalid("A payslip comparison is invalid.")
            }
        }
    }
}

enum Money {
    static func parseGross(_ text: String, locale: Locale) -> Decimal? {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let separator = locale.decimalSeparator ?? "."
        let parts = input.components(separatedBy: separator)
        guard (1...2).contains(parts.count), !parts[0].isEmpty,
              parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy { ("0"..."9").contains($0) } }) else { return nil }
        return Decimal(string: parts.joined(separator: "."), locale: Locale(identifier: "en_US_POSIX"))
    }

    static func digits(_ currency: String) -> Int {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        return formatter.maximumFractionDigits
    }

    static func rounded(_ amount: Decimal, currency: String) -> Decimal {
        var source = amount
        var result = Decimal()
        NSDecimalRound(&result, &source, digits(currency), .plain)
        return result
    }

    static func format(_ amount: Decimal, currency: String, localeID: String = Locale.current.identifier) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: localeID)
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.minimumFractionDigits = digits(currency)
        formatter.maximumFractionDigits = digits(currency)
        return formatter.string(from: NSDecimalNumber(decimal: amount)) ?? "\(amount) \(currency)"
    }
}
