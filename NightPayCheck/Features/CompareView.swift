import SwiftUI

struct CompareView: View {
    @Environment(NightStore.self) private var store
    @Environment(LifetimeAccess.self) private var access
    @State private var lines: [MatchedPayLine] = []
    @State private var otherRules = false
    @State private var date = Date()
    @State private var payslip = ""
    var periodOverride: DateInterval?

    private var period: DateInterval {
        periodOverride ?? NightPayEngine.payPeriod(containing: date, preferences: store.data.preferences)
    }

    var body: some View {
        NightPage {
            if periodOverride == nil {
                NightPeriodPicker(date: $date, period: period)
            } else {
                NightSection {
                    Text(periodLabel).font(.subheadline.weight(.semibold))
                    Text("Comparing this pay period.").font(.caption).foregroundStyle(.secondary)
                }
            }
            switch store.estimate(period: period) {
            case .failure(let error):
                NightSection { Label(error.localizedDescription, systemImage: "exclamationmark.triangle") }
            case .success(let estimate):
                NightSection("Estimated gross") {
                    Text(store.money(estimate.total)).font(.system(.largeTitle, weight: .bold)).monospacedDigit()
                        .accessibilityIdentifier("estimateTotal")
                    Text("\(estimate.actualShiftCount) actual · \(estimate.projectedShiftCount) planned · \(hoursText(estimate.paidMinutes)) paid")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if !access.unlocked && savedEntry == nil && store.data.comparisons.count >= 2 {
                    NightSection("Check another pay period") {
                        if access.checked { PaywallCard() } else { ProgressView("Checking lifetime access") }
                    }
                } else if store.data.rates.baseRate == 0 || estimate.paidMinutes == 0 {
                    NightSection("Before comparing") {
                        if store.data.rates.baseRate == 0 {
                            NavigationLink("Set your base pay rate") { RatesView() }
                        }
                        if estimate.paidMinutes == 0 {
                            Text("Add worked shifts for this pay period in Roster.")
                        }
                    }
                } else {
                    NightSection {
                        TextField("Payslip gross (USD)", text: $payslip)
                            .keyboardType(.decimalPad).textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("payslipGross")
                        if let entered = Money.parseGross(payslip, locale: Locale.current) {
                            let rounded = Money.rounded(entered, currency: "USD")
                            let variance = rounded - estimate.total
                            Text(variance == 0 ? "Matches your configured estimate." : "\(store.money(abs(variance))) \(variance < 0 ? "below" : "above") your configured estimate\(pct(variance, base: estimate.total))")
                                .font(.headline).accessibilityIdentifier("varianceLabel")
                            if estimate.projectedShiftCount > 0 {
                                Text("This estimate includes planned shifts. Review clock times and meals in Roster before relying on the difference.").font(.footnote)
                            }
                            PayLineEditor(estimate: estimate, lines: $lines)
                            let entry = comparison(gross: rounded, estimate: estimate)
                            ForEach(entry.matchedLines ?? []) { line in
                                HStack {
                                    lineSummary(line)
                                    Spacer()
                                    Button("Remove") { lines.removeAll { $0.category == line.category } }
                                        .accessibilityLabel("Remove \(line.category.rawValue)")
                                }
                            }
                            if lines.isEmpty {
                                Text("Gross alone cannot identify a missing premium. Match a payslip line to investigate.").font(.footnote)
                            } else {
                                Text("Remaining difference: \(store.money(entry.remainingDifference))")
                                    .font(.headline)
                            }
                            Toggle("Other pay rules apply this period", isOn: $otherRules)
                            if otherRules {
                                Text("Holiday pay, bonuses, daily or blended overtime can affect this comparison. Review these separately.").font(.footnote)
                            }
                            Button("Save comparison") {
                                if store.update({ data in
                                    data.comparisons.removeAll { $0.periodStart == period.start && $0.periodEnd == period.end }
                                    data.comparisons.append(entry)
                                    data.completedChecks = data.comparisons.count
                                }) { resetDraft() }
                            }.buttonStyle(NightPrimaryButton()).accessibilityIdentifier("saveComparison")
                        } else if !payslip.isEmpty {
                            Text("Enter a nonnegative amount using your keyboard's decimal separator, without grouping separators.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    } header: { Text("Enter payslip gross") } footer: {
                        Text("A variance is a prompt to review your inputs, not a conclusion about your employer's payroll. \(NightPayExplanation.disclaimer)")
                    }
                }
                NightSection {
                    DisclosureGroup("Review checklist") {
                        ForEach(NightPayExplanation.varianceChecklist(), id: \.id) { item in
                            VStack(alignment: .leading, spacing: 4) {
                                Label(item.title, systemImage: "checklist").font(.headline)
                                Text(item.detail).font(.subheadline).foregroundStyle(.secondary)
                            }.padding(.vertical, 4)
                        }
                    }
                }
                let saved = store.data.comparisons.filter { $0.periodStart == period.start && $0.periodEnd == period.end }
                if !saved.isEmpty {
                    NightSection("Saved for this period") {
                        ForEach(saved) { entry in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Payslip: \(store.money(entry.gross))").font(.headline)
                                Text("Estimate when saved: \(store.money(entry.estimatedAtEntry))").font(.caption)
                                ForEach(entry.matchedLines ?? []) { line in lineSummary(line) }
                                if !(entry.matchedLines ?? []).isEmpty {
                                    Text("Remaining difference: \(store.money(entry.remainingDifference))")
                                }
                                if entry.hasOtherRules == true { Text("Other pay rules flagged for review.") }
                                Button("Revise with current estimate") {
                                    payslip = entry.gross.formatted(.number.grouping(.never))
                                    lines = entry.matchedLines ?? []
                                    otherRules = entry.hasOtherRules ?? false
                                }
                                Text("Saved \(entry.recordedAt.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .onChange(of: period) { resetDraft() }
        .navigationTitle("Compare")
        .navigationBarTitleDisplayMode(.large)
        .environment(\.timeZone, store.calendar.timeZone)
    }

    private var savedEntry: PayslipCompare? {
        store.data.comparisons.first { $0.periodStart == period.start && $0.periodEnd == period.end }
    }

    private func resetDraft() {
        payslip = ""; lines = []; otherRules = false
    }

    private func comparison(gross: Decimal, estimate: NightEstimate) -> PayslipCompare {
        let current = lines.map {
            MatchedPayLine(category: $0.category, label: $0.label, paid: $0.paid, estimate: estimate)
        }
        return PayslipCompare(periodStart: period.start, periodEnd: period.end, gross: gross,
                              estimatedAtEntry: estimate.total, matchedLines: current, hasOtherRules: otherRules)
    }

    private func lineSummary(_ line: MatchedPayLine) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(line.label) · \(line.category.rawValue)").font(.headline)
            Text("\(hoursText(line.minutes)) estimated · \(store.money(line.expected)) expected")
            Text("\(store.money(line.paid)) on payslip · \(store.money(line.difference)) difference")
        }.font(.footnote)
    }

    private var periodLabel: String {
        let f = DateFormatter(); f.dateStyle = .medium; f.timeZone = store.calendar.timeZone
        return "\(f.string(from: period.start)) – \(f.string(from: period.end.addingTimeInterval(-1)))"
    }
    private func pct(_ v: Decimal, base: Decimal) -> String {
        guard base != 0 else { return "" }
        let d = (NSDecimalNumber(decimal: v).doubleValue / NSDecimalNumber(decimal: base).doubleValue) * 100
        return String(format: " (%+.1f%%)", d)
    }
}
