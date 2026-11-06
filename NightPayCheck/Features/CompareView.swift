import SwiftUI

struct CompareView: View {
    @Environment(NightStore.self) private var store
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
                NightSection {
                    TextField("Payslip gross (USD)", text: $payslip)
                        .keyboardType(.decimalPad).textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("payslipGross")
                    if let entered = Money.parseGross(payslip, locale: Locale.current) {
                        let rounded = Money.rounded(entered, currency: "USD")
                        let variance = rounded - estimate.total
                        Text(variance == 0 ? "Matches your configured estimate." : "\(store.money(abs(variance))) \(variance < 0 ? "below" : "above") your configured estimate\(pct(variance, base: estimate.total))")
                            .font(.headline).accessibilityIdentifier("varianceLabel")
                        Text("Check the pay-period dates, actual hours, paid-break treatment, premium eligibility, and entered rates.")
                            .font(.footnote).foregroundStyle(.secondary)
                        Button("Save comparison") {
                            let entry = PayslipCompare(periodStart: period.start, periodEnd: period.end,
                                gross: rounded, estimatedAtEntry: estimate.total)
                            if store.update({ data in
                                data.comparisons.removeAll { $0.periodStart == period.start && $0.periodEnd == period.end }
                                data.comparisons.append(entry)
                                data.completedChecks += 1
                            }) { payslip = "" }
                        }.buttonStyle(NightPrimaryButton()).accessibilityIdentifier("saveComparison")
                    } else if !payslip.isEmpty {
                        Text("Enter a nonnegative amount using your keyboard's decimal separator, without grouping separators.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                } header: { Text("Enter payslip gross") } footer: {
                    Text("A variance is a prompt to review your inputs, not a conclusion about your employer's payroll. \(NightPayExplanation.disclaimer)")
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
                                Text("Saved \(entry.recordedAt.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Compare")
        .navigationBarTitleDisplayMode(.large)
        .environment(\.timeZone, store.calendar.timeZone)
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
