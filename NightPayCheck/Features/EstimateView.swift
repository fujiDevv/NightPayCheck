import SwiftUI

struct EstimateView: View {
    @Environment(NightStore.self) private var store
    @State private var date = Date()

    private var period: DateInterval { NightPayEngine.payPeriod(containing: date, preferences: store.data.preferences) }

    var body: some View {
        NightPage {
            NightPeriodPicker(date: $date, period: period)
            if store.data.rates.baseRate == 0 {
                NightSection {
                    Text("Add your hourly rate").font(.title3.bold())
                    Text("Enter your base rate and any night or weekend extras to estimate your gross pay.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    NavigationLink("Set pay rates") { RatesView() }.buttonStyle(NightPrimaryButton())
                }
            } else {
                switch store.estimate(period: period) {
                case .failure(let error):
                    NightSection { Label(error.localizedDescription, systemImage: "exclamationmark.triangle") }
                case .success(let estimate):
                    VStack(alignment: .leading, spacing: 12) {
                        Text("ESTIMATED GROSS").font(.caption.weight(.semibold)).tracking(1.4).foregroundStyle(.white.opacity(0.75))
                        Text(store.money(estimate.total)).font(.system(.largeTitle, weight: .bold)).monospacedDigit()
                            .accessibilityIdentifier("estimatedGross")
                        Text("\(estimate.actualShiftCount) actual · \(estimate.projectedShiftCount) planned shifts")
                            .font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.8))
                        LabeledContent("Paid time", value: hoursText(estimate.paidMinutes))
                        LabeledContent("Worked, excl. unpaid breaks", value: hoursText(estimate.workedMinutes))
                    }
                    .padding(22)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(.white)
                    .background(Color(white: 0.07), in: RoundedRectangle(cornerRadius: 20))
                    NightSection("Calculation breakdown") {
                        if estimate.lines.isEmpty { Text("No paid shifts in this period.").foregroundStyle(.secondary) }
                        ForEach(grouped(estimate)) { row in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(row.kind).font(.headline)
                                Text(store.money(row.amount)).font(.title3.weight(.semibold)).monospacedDigit()
                                Text("\(hoursText(row.minutes)) × \(store.money(row.rate))/hour")
                                    .font(.caption).foregroundStyle(.secondary)
                            }.padding(.vertical, 4)
                        }
                        NavigationLink("How is this calculated?") {
                            PayMathView(period: period)
                        }.font(.subheadline.weight(.semibold))
                    }
                    NightSection {
                        DisclosureGroup("Estimate assumptions") {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Actual hours replace planned hours where recorded. Unrecorded shifts are projections.")
                                Text("Times, weekend days, and the 40-hour week use \(store.data.preferences.timeZoneID).")
                                Text(NightPayExplanation.precedence)
                                Text("Each line is rounded half up to the cent, then summed. Gross pay only — no taxes, no legal advice.")
                                Text(NightPayExplanation.disclaimer).font(.footnote).foregroundStyle(.secondary)
                            }.font(.footnote).foregroundStyle(.secondary).padding(.top, 8)
                        }
                    }
                    NavigationLink {
                        CompareView(periodOverride: period)
                    } label: {
                        HStack { Spacer(); Text("Compare a payslip"); Image(systemName: "arrow.right"); Spacer() }
                            .font(.headline).frame(minHeight: 52).foregroundStyle(Color(uiColor: .systemBackground)).background(Color.primary, in: Capsule())
                    }.buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("Estimate")
        .navigationBarTitleDisplayMode(.large)
        .environment(\.timeZone, store.calendar.timeZone)
    }

    private struct GroupRow: Identifiable {
        var id: String { kind }
        var kind: String; var minutes: Int; var rate: Decimal; var amount: Decimal
    }
    private func grouped(_ e: NightEstimate) -> [GroupRow] {
        var out: [GroupRow] = []
        for kind in ["Regular", "Overtime", "Night differential", "Weekend differential"] {
            let ls = e.lines.filter { $0.kind == kind }
            guard !ls.isEmpty else { continue }
            let minutes = ls.reduce(0) { $0 + $1.minutes }
            let amount = ls.reduce(Decimal.zero) { $0 + $1.amount }
            // Weighted display rate = amount / hours (informational only)
            let rate: Decimal = minutes > 0 ? amount * 60 / Decimal(minutes) : 0
            out.append(GroupRow(kind: kind, minutes: minutes, rate: rate, amount: amount))
        }
        return out
    }
}

struct PayMathView: View {
    @Environment(NightStore.self) private var store
    let period: DateInterval
    var body: some View {
        NightPage {
            NightSection("Your configured rules") {
                LabeledContent("Base", value: "\(store.money(store.data.rates.baseRate))/hr")
                LabeledContent("Night", value: "+\(store.money(store.data.rates.nightDiff))/hr (19:00–07:00 default)")
                LabeledContent("Weekend", value: "+\(store.money(store.data.rates.weekendDiff))/hr (Sat–Sun)")
                LabeledContent("Overtime", value: "40h/week @ 1.5× base")
            }
            NightSection("Worked example (fictional rates)") {
                Text("Mon 19:00–07:00, 30m unpaid = 11.5h. Base $38, night +$4.50 → 11.5×38 = $437.00 + 11.5×4.50 = $51.75 → $488.75.")
                Text("Weekend counts per minute: Fri night includes Sat 00:00–06:30 (390 min × $3.00 = $19.50), so Fri = $508.25. Sat night = $523.25. Fri + Sat + Mon = $1,520.25 with no OT.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            NightSection("Review checklist") {
                ForEach(NightPayExplanation.varianceChecklist(), id: \.id) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title).font(.headline)
                        Text(item.detail).font(.subheadline).foregroundStyle(.secondary)
                    }.padding(.vertical, 4)
                }
            }
        }.navigationTitle("How it works")
    }
}
