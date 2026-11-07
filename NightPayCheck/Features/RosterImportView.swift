import SwiftUI
import PhotosUI

private struct UnresolvedRosterLine: Identifiable {
    let id = UUID()
    var text: String
}

struct RosterImportView: View {
    @Environment(NightStore.self) private var store
    let period: DateInterval
    @State private var rosterText = ""
    @State private var drafts: [NightDraft] = []
    @State private var excluded: [String] = []
    @State private var unresolved: [UnresolvedRosterLine] = []
    @State private var error: String?
    @State private var week: Int?
    @State private var photo: PhotosPickerItem?
    @State private var cropping: RosterPhoto?
    @State private var original: RosterPhoto?
    @State private var preview: UIImage?
    @State private var busy = false
    @State private var reviewed = false
    @State private var savedSummary: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Choose a week for weekday-only entries, then review the dates and meal breaks before saving.")
                .font(.subheadline).foregroundStyle(.secondary)
            Picker("Roster week", selection: $week) {
                Text("Choose roster week").tag(nil as Int?)
                Text(weekLabel(0)).tag(Optional(0))
                Text(weekLabel(1)).tag(Optional(1))
            }
            PhotosPicker(selection: $photo, matching: .images) {
                Label("Choose roster photo", systemImage: "photo.badge.magnifyingglass")
            }.disabled(busy)
            if let original {
                Button("Adjust crop") { cropping = original }
            }
            if let preview {
                DisclosureGroup("View source image") {
                    Image(uiImage: preview).resizable().scaledToFit()
                        .accessibilityLabel("Selected roster area")
                }
            }
            TextEditor(text: $rosterText)
                .frame(height: 140)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.2)))
                .accessibilityLabel("Roster text").accessibilityIdentifier("rosterText")
            Text("One dated shift per line, for example Fri 19:00–07:00. Table cells without a day need your correction.")
                .font(.caption).foregroundStyle(.secondary)
            Button("Build drafts") { build() }
                .disabled(week == nil || busy)
                .accessibilityIdentifier("buildDrafts")
            if let error, drafts.isEmpty { Label(error, systemImage: "exclamationmark.triangle").font(.footnote) }
            if !excluded.isEmpty {
                DisclosureGroup("\(excluded.count) excluded lines") {
                    Text("Headings, days off, and text without readable shift times. Check these for missed entries.")
                        .font(.caption)
                    ForEach(Array(excluded.enumerated()), id: \.offset) { _, line in Text(line).font(.caption) }
                }
            }
            if !unresolved.isEmpty {
                Text("\(unresolved.count) lines need a date or correction").font(.headline)
                ForEach(unresolved) { line in
                    VStack(alignment: .leading) {
                        TextField("Correct this shift", text: unresolvedText(line), axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                        HStack {
                            Button("Retry line") { retry(line.id) }
                            Button("Exclude line") {
                                excluded.append(line.text)
                                unresolved.removeAll { $0.id == line.id }
                                reviewed = false
                            }
                        }.font(.subheadline)
                    }
                }
            }
            ForEach(drafts) { draft in
                NightSection {
                    Text(draft.source).font(.caption).foregroundStyle(.secondary)
                    DatePicker("Shift date", selection: draftValue(draft, \.day),
                               in: period.start...period.end.addingTimeInterval(-1), displayedComponents: .date)
                    MinuteField(title: "Starts", minute: draftValue(draft, \.startMinute))
                    MinuteField(title: "Ends", minute: draftValue(draft, \.endMinute))
                    Text("An end at or before the start falls on the following day.").font(.caption)
                    Stepper("Meal: \(draft.breakMinutes) minutes", value: draftValue(draft, \.breakMinutes), in: 0...120, step: 5)
                    Toggle("Paid meal", isOn: draftValue(draft, \.breakPaid))
                    Button("Remove draft", role: .destructive) { drafts.removeAll { $0.id == draft.id } }
                }
            }
            if !drafts.isEmpty {
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .accessibilityIdentifier("rosterSaveError")
                }
                Toggle("I checked each date, time, meal and excluded line against my roster", isOn: $reviewed)
                    .font(.subheadline)
                Button("Save \(drafts.count) confirmed shifts") { save() }
                    .disabled(!reviewed || !unresolved.isEmpty)
                    .accessibilityIdentifier("saveDrafts")
                    .buttonStyle(NightPrimaryButton())
            }
        }
        .padding(.top, 12)
        .onChange(of: period) { reset() }
        .onChange(of: drafts) { reviewed = false; error = nil }
        .onChange(of: week) { drafts = []; unresolved = []; excluded = []; reviewed = false; error = nil }
        .onChange(of: rosterText) { drafts = []; unresolved = []; excluded = []; reviewed = false; error = nil }
        .onChange(of: photo) { _, item in
            guard let item else { return }
            busy = true
            Task {
                defer { busy = false; photo = nil }
                do {
                    guard let data = try await item.loadTransferable(type: Data.self),
                          data.count <= 20_000_000, let image = UIImage(data: data) else {
                        throw InputError.invalid("Choose a readable roster photo smaller than 20 MB.")
                    }
                    let source = RosterPhoto(image: image)
                    cropping = source
                } catch { self.error = error.localizedDescription }
            }
        }
        .alert("Roster saved", isPresented: Binding(get: { savedSummary != nil }, set: { if !$0 { savedSummary = nil } })) {
            Button("OK") { savedSummary = nil }
        } message: { Text(savedSummary ?? "") }
        .sheet(item: $cropping) { source in
            NavigationStack {
                RosterPhotoCropView(photo: source) { image, text in
                    original = source
                    preview = image
                    rosterText = text
                    reviewed = false
                }
            }
        }
    }

    private func draftValue<Value>(_ draft: NightDraft, _ keyPath: WritableKeyPath<NightDraft, Value>) -> Binding<Value> {
        Binding(
            get: { (drafts.first { $0.id == draft.id } ?? draft)[keyPath: keyPath] },
            set: { value in
                guard let index = drafts.firstIndex(where: { $0.id == draft.id }) else { return }
                drafts[index][keyPath: keyPath] = value
            }
        )
    }

    private func unresolvedText(_ line: UnresolvedRosterLine) -> Binding<String> {
        Binding(
            get: { unresolved.first { $0.id == line.id }?.text ?? line.text },
            set: { value in
                guard let index = unresolved.firstIndex(where: { $0.id == line.id }) else { return }
                unresolved[index].text = value
            }
        )
    }

    private func weekLabel(_ offset: Int) -> String {
        let start = store.calendar.date(byAdding: .day, value: offset * 7, to: period.start)!
        let end = store.calendar.date(byAdding: .day, value: 6, to: start)!
        let formatter = DateFormatter()
        formatter.timeZone = store.calendar.timeZone
        formatter.dateFormat = "MMM d"
        return "\(formatter.string(from: start)) – \(formatter.string(from: end))"
    }

    private func build() {
        guard let week else { return }
        do {
            let result = try NightDraftParser.review(rosterText, period: period,
                                                     timeZoneID: store.data.preferences.timeZoneID, weekOffset: week)
            drafts = result.drafts; excluded = result.excluded; unresolved = result.unresolved.map { UnresolvedRosterLine(text: $0) }
            reviewed = false
            error = drafts.isEmpty && unresolved.isEmpty ? "No shifts found. Check the excluded lines or enter a shift manually." : nil
        } catch { self.error = error.localizedDescription }
    }

    private func retry(_ id: UUID) {
        guard let index = unresolved.firstIndex(where: { $0.id == id }), let week else { return }
        do {
            let parsed = try NightDraftParser.parse(unresolved[index].text, period: period,
                                                   timeZoneID: store.data.preferences.timeZoneID, weekOffset: week)
            guard drafts.count + parsed.count <= 14 else { throw InputError.invalid("Review up to 14 shifts at once.") }
            drafts.append(contentsOf: parsed)
            unresolved.remove(at: index)
            error = nil; reviewed = false
        } catch { self.error = error.localizedDescription }
    }

    private func save() {
        do {
            let shifts = try NightDraftParser.materialize(drafts, timeZoneID: store.data.preferences.timeZoneID,
                                                         existing: store.data.shifts)
            guard shifts.allSatisfy({ $0.plannedStart >= period.start && $0.plannedStart < period.end }) else {
                throw InputError.invalid("Each shift must start in the selected pay period.")
            }
            let alreadyRecorded = drafts.count - shifts.count
            if store.update({ $0.shifts.append(contentsOf: shifts); $0.shifts.sort { $0.plannedStart < $1.plannedStart } }) {
                reset()
                savedSummary = "\(shifts.count) shifts added. \(alreadyRecorded) already recorded. Existing actual hours and edit history were retained."
            }
        } catch { self.error = error.localizedDescription }
    }

    private func reset() {
        drafts = []; rosterText = ""; unresolved = []; excluded = []
        reviewed = false; error = nil; preview = nil; original = nil; week = nil
    }
}
