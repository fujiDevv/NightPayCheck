import SwiftUI

struct RatesView: View {
    @Environment(NightStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var rates = RateSet3()

    var body: some View {
        NightPage {
            NightSection("Your 3 rates (USD / hour)") {
                DecimalRow(title: "Base rate", value: $rates.baseRate, suffix: "USD / hr")
                Divider()
                DecimalRow(title: "Night extra", value: $rates.nightDiff, suffix: "USD / hr")
                Divider()
                DecimalRow(title: "Weekend extra", value: $rates.weekendDiff, suffix: "USD / hr")
                Text("Weekend means Saturday and Sunday. The same minute can earn both night and weekend extras.")
                    .font(.caption).foregroundStyle(.secondary).padding(.vertical, 8)
            } footer: {
                Text("Example: base $38, night +$4.50, weekend +$3.00 → one Mon 19:00–07:00 night ≈ $488.75 (no weekend minutes).")
            }
            NightSection("Night window") {
                HStack {
                    MinuteField(title: "Starts", minute: $rates.nightStartMinute)
                    Divider()
                    MinuteField(title: "Ends", minute: $rates.nightEndMinute)
                }
                Text("Default 19:00 → 07:00. Equal start and end means all day. Confirm against your facility — some use 23:00–07:00.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            NightSection("Overtime + week start") {
                HStack {
                    Text("Weekly overtime").font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("40h @ 1.5× base").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                }.padding(.vertical, 8)
                Divider()
                Picker("Week starts", selection: $rates.weekStartsOn) {
                    Text("Monday").tag(2)
                    Text("Sunday").tag(1)
                }.pickerStyle(.segmented).padding(.vertical, 8)
                Text(NightPayExplanation.precedence).font(.caption).foregroundStyle(.secondary).padding(.bottom, 8)
            }
            NightSection("Live sample") {
                Text(sampleText).font(.subheadline.monospacedDigit())
                Text("One 19:00–07:00 shift, 30m unpaid = 11.5 paid hours.").font(.caption).foregroundStyle(.secondary)
            }
            Button("Save rates") {
                if store.update({
                    $0.rates = rates
                    $0.preferences.weekAnchorMonday = rates.weekStartsOn == 2
                }) { dismiss() }
            }.buttonStyle(NightPrimaryButton()).accessibilityIdentifier("saveRates")
            Text("One-time setup. Changing rates recalculates all estimates; saved payslip entries keep their original estimate.")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .navigationTitle("Rates")
        .onAppear {
            rates = store.data.rates
            rates.weekStartsOn = store.data.preferences.weekAnchorMonday ? 2 : 1
        }
    }

    private var sampleText: String {
        let hrs: Decimal = 11.5
        let total = hrs * rates.baseRate + hrs * rates.nightDiff
        let formatted = store.money(Money.rounded(total, currency: "USD"))
        return "11.5h × base + 11.5h × night = \(formatted)"
    }
}

struct DecimalRow: View {
    var title: String
    @Binding var value: Decimal
    var suffix = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline) {
                TextField(title, value: $value, format: .number).keyboardType(.decimalPad)
                    .font(.system(.body, weight: .semibold)).monospacedDigit().accessibilityLabel(title)
                Text(suffix).font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 12)
    }
}

struct MinuteField: View {
    var title: String
    @Binding var minute: Int
    private var date: Binding<Date> {
        Binding(get: { Date(timeIntervalSince1970: TimeInterval(minute * 60)) }, set: {
            let cal = Calendar(identifier: .gregorian)
            var c = cal; c.timeZone = TimeZone(identifier: "GMT")!
            minute = c.component(.hour, from: $0) * 60 + c.component(.minute, from: $0)
        })
    }
    var body: some View {
        DatePicker(title, selection: date, displayedComponents: .hourAndMinute)
            .environment(\.timeZone, TimeZone(identifier: "GMT")!).padding(.vertical, 8)
    }
}
