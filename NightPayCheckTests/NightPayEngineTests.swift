import Testing
import Foundation
@testable import NightPayCheckCore

private func utc(_ string: String, zone: String = "America/Chicago") -> Date {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd HH:mm"
    f.timeZone = TimeZone(identifier: zone)!
    return f.date(from: string)!
}

private func rates(base: String = "38", night: String = "4.50", weekend: String = "3.00", weekStart: Int = 2) -> RateSet3 {
    var r = RateSet3()
    r.baseRate = Decimal(string: base)!
    r.nightDiff = Decimal(string: night)!
    r.weekendDiff = Decimal(string: weekend)!
    r.nightStartMinute = 19 * 60
    r.nightEndMinute = 7 * 60
    r.weekStartsOn = weekStart
    return r
}

private func shift(_ start: String, _ end: String, zone: String = "America/Chicago", breakMinutes: Int = 30) -> NightShift {
    NightShift(plannedStart: utc(start, zone: zone), plannedEnd: utc(end, zone: zone),
               timeZoneID: zone, plannedBreakMinutes: breakMinutes)
}

private func period(_ start: String, _ end: String, zone: String = "America/Chicago") -> DateInterval {
    DateInterval(start: utc(start, zone: zone), end: utc(end, zone: zone))
}

@Suite("NightPayCheck mandatory fixtures")
struct NightPayEngineTests {
    @Test("19:00-07:00 +30m unpaid = 11.5h paid")
    func standardNight() throws {
        let s = shift("2026-11-06 19:00", "2026-11-07 07:00")
        let e = try NightPayEngine.estimate(shifts: [s], rates: rates(night: "0", weekend: "0"),
            period: period("2026-11-02 00:00", "2026-11-16 00:00"), timeZoneID: "America/Chicago", currency: "USD")
        #expect(e.paidMinutes == 690)
        #expect(e.workedMinutes == 690)
    }

    @Test("Fri-Sat midnight split credits weekend correctly")
    func midnightSplit() throws {
        // Friday night into Saturday: minutes after Sat 00:00 earn weekend diff.
        let s = shift("2026-11-06 19:00", "2026-11-07 07:00")
        let e = try NightPayEngine.estimate(shifts: [s], rates: rates(),
            period: period("2026-11-02 00:00", "2026-11-16 00:00"), timeZoneID: "America/Chicago", currency: "USD")
        let weekend = e.lines.filter { $0.kind == "Weekend differential" }.reduce(0) { $0 + $1.minutes }
        // 00:00-07:00 minus 30m break at end (06:30-07:00 unpaid) = 390 min
        #expect(weekend == 390)
        let night = e.lines.filter { $0.kind == "Night differential" }.reduce(0) { $0 + $1.minutes }
        #expect(night == 690)
    }

    @Test("Biweekly boundary Sun-Mon allocates correctly")
    func biweeklyBoundary() throws {
        let sun = shift("2026-11-08 19:00", "2026-11-09 07:00")
        let first = try NightPayEngine.estimate(shifts: [sun], rates: rates(night: "0", weekend: "0"),
            period: period("2026-10-26 00:00", "2026-11-09 00:00"), timeZoneID: "America/Chicago", currency: "USD")
        let second = try NightPayEngine.estimate(shifts: [sun], rates: rates(night: "0", weekend: "0"),
            period: period("2026-11-09 00:00", "2026-11-23 00:00"), timeZoneID: "America/Chicago", currency: "USD")
        #expect(first.paidMinutes + second.paidMinutes == 690)
        #expect(first.paidMinutes == 300) // 19:00-24:00 minus 0 break (break at end)
        #expect(second.paidMinutes == 390)
    }

    @Test("Spring DST forward uses real elapsed time")
    func springDST() throws {
        // America/Chicago springs forward 2026-03-08 02:00→03:00.
        // 19:00 Sat → 07:00 Sun spans the jump: 11h elapsed - 30m = 10.5h paid.
        var s = NightShift(plannedStart: utc("2026-03-07 19:00"), plannedEnd: utc("2026-03-08 07:00"),
                           timeZoneID: "America/Chicago", plannedBreakMinutes: 30)
        try s.validate()
        let e = try NightPayEngine.estimate(shifts: [s], rates: rates(night: "0", weekend: "0"),
            period: period("2026-03-02 00:00", "2026-03-16 00:00"), timeZoneID: "America/Chicago", currency: "USD")
        #expect(e.paidMinutes == 630)
    }

    @Test("Break at end subtracts once")
    func breakOnce() throws {
        let s = shift("2026-11-06 19:00", "2026-11-07 07:00", breakMinutes: 30)
        let e = try NightPayEngine.estimate(shifts: [s], rates: rates(night: "0", weekend: "0"),
            period: period("2026-11-02 00:00", "2026-11-16 00:00"), timeZoneID: "America/Chicago", currency: "USD")
        #expect(e.paidMinutes == 690)
        let none = shift("2026-11-06 19:00", "2026-11-07 07:00", breakMinutes: 0)
        let e2 = try NightPayEngine.estimate(shifts: [none], rates: rates(night: "0", weekend: "0"),
            period: period("2026-11-02 00:00", "2026-11-16 00:00"), timeZoneID: "America/Chicago", currency: "USD")
        #expect(e2.paidMinutes == 720)
    }

    @Test("40h edge: no OT at exactly 40h, OT after")
    func overtimeEdge() throws {
        // 3x12 = 34.5h paid, + one 8h evening (7.5 paid) = 42h → 2h OT.
        let shifts = [
            shift("2026-11-02 19:00", "2026-11-03 07:00"),
            shift("2026-11-03 19:00", "2026-11-04 07:00"),
            shift("2026-11-04 19:00", "2026-11-05 07:00"),
            shift("2026-11-05 19:00", "2026-11-06 03:00", breakMinutes: 30), // 7.5 paid
        ]
        let e = try NightPayEngine.estimate(shifts: shifts, rates: rates(night: "0", weekend: "0"),
            period: period("2026-11-02 00:00", "2026-11-16 00:00"), timeZoneID: "America/Chicago", currency: "USD")
        let ot = e.lines.filter { $0.kind == "Overtime" }.reduce(0) { $0 + $1.minutes }
        #expect(ot == 120)
        // Exactly 40h → no OT: 4x10h paid = 40h (19:00–05:00 next day, no break).
        let flat = (0..<4).map { i in
            shift("2026-11-0\(2 + i) 19:00", "2026-11-0\(3 + i) 05:00", breakMinutes: 0)
        }
        let e2 = try NightPayEngine.estimate(shifts: flat, rates: rates(night: "0", weekend: "0"),
            period: period("2026-11-02 00:00", "2026-11-16 00:00"), timeZoneID: "America/Chicago", currency: "USD")
        #expect(e2.lines.filter { $0.kind == "Overtime" }.isEmpty)
    }

    @Test("Night + weekend same minute both add")
    func stacking() throws {
        let s = shift("2026-11-07 19:00", "2026-11-08 07:00") // Saturday night
        let e = try NightPayEngine.estimate(shifts: [s], rates: rates(),
            period: period("2026-11-02 00:00", "2026-11-16 00:00"), timeZoneID: "America/Chicago", currency: "USD")
        let night = e.lines.filter { $0.kind == "Night differential" }.reduce(0) { $0 + $1.minutes }
        let weekend = e.lines.filter { $0.kind == "Weekend differential" }.reduce(0) { $0 + $1.minutes }
        #expect(night == 690 && weekend == 690)
    }

    @Test("Overlapping shifts rejected")
    func overlap() throws {
        let a = shift("2026-11-06 19:00", "2026-11-07 07:00")
        let b = shift("2026-11-07 00:00", "2026-11-07 12:00")
        #expect(throws: Error.self) {
            try NightPayEngine.estimate(shifts: [a, b], rates: rates(),
                period: period("2026-11-02 00:00", "2026-11-16 00:00"), timeZoneID: "America/Chicago", currency: "USD")
        }
    }

    @Test("Spec 3x12 totals $1,520.25 with no OT (Fri night earns Sat weekend minutes)")
    func specExample() throws {
        // Per-minute weekend rule: Fri 19:00–07:00 includes Sat 00:00–06:30 = 390 weekend minutes.
        // Fri $508.25 + Sat $523.25 + Mon $488.75 = $1,520.25. The blueprint's $1,500.75
        // simplified weekend by start day; per-minute overlap (spec 7.2 formula) is authoritative.
        let shifts = [
            shift("2026-11-06 19:00", "2026-11-07 07:00"), // Fri night
            shift("2026-11-07 19:00", "2026-11-08 07:00"), // Sat night
            shift("2026-11-09 19:00", "2026-11-10 07:00"), // Mon night
        ]
        let e = try NightPayEngine.estimate(shifts: shifts, rates: rates(),
            period: period("2026-11-02 00:00", "2026-11-16 00:00"), timeZoneID: "America/Chicago", currency: "USD")
        #expect(e.total == Decimal(string: "1520.25")!)
    }

    @Test("Edited actuals recalc (actuals replace plan)")
    func actualsReplace() throws {
        var s = shift("2026-11-06 19:00", "2026-11-07 07:00")
        s.actualStart = utc("2026-11-06 19:00"); s.actualEnd = utc("2026-11-07 07:30")
        s.actualBreakMinutes = 30; s.actualBreakPaid = false
        let e = try NightPayEngine.estimate(shifts: [s], rates: rates(night: "0", weekend: "0"),
            period: period("2026-11-02 00:00", "2026-11-16 00:00"), timeZoneID: "America/Chicago", currency: "USD")
        #expect(e.paidMinutes == 720)
        #expect(e.actualShiftCount == 1 && e.projectedShiftCount == 0)
    }

    @Test("Same input → same output, no double count")
    func deterministic() throws {
        let shifts = [shift("2026-11-06 19:00", "2026-11-07 07:00"), shift("2026-11-07 19:00", "2026-11-08 07:00")]
        let p = period("2026-11-02 00:00", "2026-11-16 00:00")
        let a = try NightPayEngine.estimate(shifts: shifts, rates: rates(), period: p, timeZoneID: "America/Chicago", currency: "USD")
        let b = try NightPayEngine.estimate(shifts: shifts, rates: rates(), period: p, timeZoneID: "America/Chicago", currency: "USD")
        #expect(a.total == b.total && a.paidMinutes == b.paidMinutes)
        #expect(a.paidMinutes == 1380)
    }
}

@Suite("Payslip reconciliation")
struct ComparisonTests {
    @Test func confirmedCategoryAndResidualSurviveBackup() throws {
        let id = UUID()
        let estimate = NightEstimate(lines: [
            CalculationLine(shiftID: id, title: "Night", kind: "Regular", minutes: 720, hourlyRate: 30, amount: 360),
            CalculationLine(shiftID: id, title: "Night", kind: "Weekend differential", minutes: 720, hourlyRate: 3, amount: 36)
        ], paidMinutes: 720, workedMinutes: 720, actualShiftCount: 1, projectedShiftCount: 0)
        let line = MatchedPayLine(category: .weekend, label: "Weekend line absent", paid: 0, estimate: estimate)
        let dates = period("2026-11-02 00:00", "2026-11-16 00:00")
        var data = NightAppData()
        data.comparisons = [PayslipCompare(periodStart: dates.start, periodEnd: dates.end, gross: 350,
                                           estimatedAtEntry: estimate.total, matchedLines: [line], hasOtherRules: true)]
        let restored = try JSONDecoder().decode(NightAppData.self, from: JSONEncoder().encode(data))
        try restored.validate()
        #expect(restored.comparisons.first?.remainingDifference == -10)
        #expect(restored.comparisons.first?.matchedLines?.first?.difference == -36)
    }

    @Test func grossOnlyRecordRemainsReadable() throws {
        let json = #"{"id":"857CED14-1797-4EE7-A672-61CE9EFDC5C7","periodStart":0,"periodEnd":1209600,"gross":320,"estimatedAtEntry":350,"recordedAt":1}"#
        let entry = try JSONDecoder().decode(PayslipCompare.self, from: Data(json.utf8))
        #expect(entry.matchedLines == nil)
        #expect(entry.remainingDifference == -30)
    }
}

@Suite("Roster review")
struct RosterReviewTests {
    let zone = "America/Chicago"
    var dates: DateInterval { period("2026-11-02 00:00", "2026-11-16 00:00") }

    @Test func weekdayRequiresWeekAndSecondWeekIsExplicit() throws {
        #expect(throws: (any Error).self) {
            try NightDraftParser.parse("Mon 19:00-07:00", period: dates, timeZoneID: zone)
        }
        let drafts = try NightDraftParser.parse("Mon 19:00-07:00", period: dates, timeZoneID: zone, weekOffset: 1)
        #expect(drafts.first?.day == utc("2026-11-09 00:00"))
    }

    @Test func dateOverridesWeekAndInvalidDateCannotFallBack() throws {
        let drafts = try NightDraftParser.parse("2026-11-03 1900-0700", period: dates, timeZoneID: zone, weekOffset: 1)
        #expect(drafts.first?.day == utc("2026-11-03 00:00"))
        #expect(drafts.first?.startMinute == 1140)
        #expect(throws: (any Error).self) {
            try NightDraftParser.parse("Mon 11/31 19:00-07:00", period: dates, timeZoneID: zone, weekOffset: 0)
        }
        #expect(throws: (any Error).self) {
            try NightDraftParser.parse("Mon 19:00-07:00 Tue 19:00-07:00", period: dates, timeZoneID: zone, weekOffset: 0)
        }
    }

    @Test func headersAndAmbiguousCellsStayVisible() throws {
        let review = try NightDraftParser.review("Team 1\nMonday Tuesday\nNight Off\n19:00-07:00\nFri 19:00-07:00",
                                                period: dates, timeZoneID: zone, weekOffset: 0)
        #expect(review.drafts.count == 1)
        #expect(review.excluded.count == 3)
        #expect(review.unresolved == ["19:00-07:00"])
    }

    @Test func editedMealsPersistAndOverlapsRejectWholeImport() throws {
        var drafts = try NightDraftParser.parse("Mon 19:00-07:00", period: dates, timeZoneID: zone, weekOffset: 0)
        drafts[0].breakMinutes = 45
        drafts[0].breakPaid = true
        let saved = try NightDraftParser.materialize(drafts, timeZoneID: zone, existing: [])
        #expect(saved.first?.plannedBreakMinutes == 45)
        #expect(saved.first?.plannedBreakPaid == true)
        #expect(try NightDraftParser.materialize(drafts, timeZoneID: zone, existing: saved).isEmpty)
        var overlapping = saved[0]
        overlapping.plannedStart = overlapping.plannedStart.addingTimeInterval(-3600)
        #expect(throws: (any Error).self) {
            try NightDraftParser.materialize(drafts, timeZoneID: zone, existing: [overlapping])
        }
    }
}

@Suite("Roster table columns")
struct RosterLayoutTests {
    @Test func oneRowUsesHeadersAndMultipleRowsRemainUnresolved() {
        let days = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        let headers = days.enumerated().map {
            RosterTextLayout.Cell(text: $0.element,
                                  bounds: CGRect(x: Double($0.offset) / 7 + 0.02, y: 0.8, width: 0.08, height: 0.03))
        }
        let shift = RosterTextLayout.Cell(text: "19:00-07:00",
                                         bounds: CGRect(x: 1.0 / 7 + 0.02, y: 0.6, width: 0.08, height: 0.03))
        #expect(RosterTextLayout.text(from: headers + [shift]).contains("Monday 19:00-07:00"))
        let another = RosterTextLayout.Cell(text: "19:00-07:00",
                                           bounds: CGRect(x: 1.0 / 7 + 0.02, y: 0.4, width: 0.08, height: 0.03))
        #expect(!RosterTextLayout.text(from: headers + [shift, another]).contains("Monday 19:00"))
        #expect(RosterTextLayout.text(from: [shift]) == shift.text)
    }
}

@Suite("Roster repeat import")
struct RosterRepeatImportTests {
    @Test func existingActualsSurviveAndOnlyNewShiftIsAdded() throws {
        let dates = period("2026-11-02 00:00", "2026-11-16 00:00")
        let drafts = try NightDraftParser.parse("Mon 19:00-07:00\nTue 19:00-07:00", period: dates,
                                               timeZoneID: "America/Chicago", weekOffset: 0)
        var existing = try NightDraftParser.materialize([drafts[0]], timeZoneID: "America/Chicago", existing: [])[0]
        existing.actualStart = existing.plannedStart
        existing.actualEnd = existing.plannedEnd.addingTimeInterval(600)
        let added = try NightDraftParser.materialize(drafts, timeZoneID: "America/Chicago", existing: [existing])
        #expect(added.count == 1)
        #expect(added[0].plannedStart == utc("2026-11-03 19:00"))
        #expect(existing.actualEnd == utc("2026-11-03 07:10"))
        #expect(try NightDraftParser.materialize(drafts, timeZoneID: "America/Chicago", existing: [existing] + added).isEmpty)
    }
}
