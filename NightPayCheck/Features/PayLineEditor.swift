import SwiftUI
import FoundationModels

struct PayLineEditor: View {
    let estimate: NightEstimate
    @Binding var lines: [MatchedPayLine]
    @State private var label = ""
    @State private var category: PayCategory?
    @State private var amount = ""
    @State private var suggestion: String?
    @State private var working = false

    var body: some View {
        DisclosureGroup("Match a payslip line") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Compare one total per category. Combine split lines first. Enter 0 only if you confirmed there is no separate payment for that category.")
                    .font(.footnote)
                TextField("Employer label or missing line", text: $label)
                if SystemLanguageModel.default.availability == .available {
                    Button("Suggest category on device") {
                        Task { await suggest() }
                    }.disabled(label.isEmpty || working)
                }
                if let suggestion { Text(suggestion).font(.footnote) }
                Picker("Category", selection: $category) {
                    Text("Choose category").tag(nil as PayCategory?)
                    ForEach(PayCategory.allCases, id: \.self) { Text($0.rawValue).tag(Optional($0)) }
                }
                TextField("Total paid for category (USD)", text: $amount).keyboardType(.decimalPad)
                Button("Confirm category total") {
                    guard let category, let paid = Money.parseGross(amount, locale: .current) else { return }
                    lines.removeAll { $0.category == category }
                    lines.append(MatchedPayLine(category: category, label: label, paid: paid, estimate: estimate))
                    label = ""; amount = ""; self.category = nil; suggestion = nil
                }.disabled(label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || category == nil || Money.parseGross(amount, locale: .current) == nil)
            }.textFieldStyle(.roundedBorder).padding(.vertical, 8)
        }.onChange(of: label) { suggestion = nil }
    }

    private func suggest() async {
        let source = label
        working = true
        defer { working = false }
        do {
            let session = LanguageModelSession(instructions: "Classify the supplied payroll label. Respond with exactly one of Regular, Overtime, Night differential, Weekend differential or Unknown. Use Unknown for ambiguous or combined lines.")
            let response = try await session.respond(to: String(source.prefix(120)))
            guard label == source else { return }
            let match = PayCategory(rawValue: response.content.trimmingCharacters(in: .whitespacesAndNewlines))
            suggestion = match.map { "Suggested category: \($0.rawValue). Select it if it fits your payslip." } ?? "Choose the category manually."
        } catch { if label == source { suggestion = "Suggestion unavailable. Choose the category manually." } }
    }
}
