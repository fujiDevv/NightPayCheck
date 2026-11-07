import SwiftUI
import PhotosUI
import Vision

struct ConfirmView: View {
    @Environment(NightStore.self) private var store
    @State private var date = Date()
    @State private var rosterText = ""
    @State private var drafts: [NightDraft] = []
    @State private var draftError: String?
    @State private var editing: NightShift?
    @State private var adding = false
    @State private var importingRoster = false
    @State private var photo: PhotosPickerItem?
    @State private var busy = false

    private var period: DateInterval { NightPayEngine.payPeriod(containing: date, preferences: store.data.preferences) }
    private var shifts: [NightShift] {
        store.data.shifts.filter { $0.end > period.start && $0.start < period.end }.sorted { $0.start < $1.start }
    }

    var body: some View {
        NightPage {
            NightPeriodPicker(date: $date, period: period)
            NightSection("Shifts this period") {
                if shifts.isEmpty {
                    HStack(spacing: 16) {
                        NightOwl(height: 82)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("No shifts yet").font(.headline)
                            Text("Add a shift or import your roster for this pay period.")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }
                ForEach(shifts) { shift in
                    Button { editing = shift } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Image(systemName: shift.isActual ? "moon.stars.fill" : "moon").foregroundStyle(.primary)
                                Text(shift.title).font(.headline)
                                Spacer()
                                Text(shift.isActual ? "Actual" : "Planned").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            }
                            Text("\(shift.start.formatted(date: .abbreviated, time: .shortened)) → \(shift.end.formatted(date: .abbreviated, time: .shortened))")
                                .font(.subheadline)
                            Text("Meal: \(shift.breakMinutes)m \(shift.breakPaid ? "paid" : "unpaid")")
                                .font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 6)
                    }.buttonStyle(.plain)
                }
            }
            Button { adding = true } label: {
                Label("Add a shift", systemImage: "plus")
            }.buttonStyle(NightPrimaryButton())
            NightSection {
                DisclosureGroup("Import roster", isExpanded: $importingRoster) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Paste one shift per line or read a roster photo. Review the drafts before saving.")
                            .font(.subheadline).foregroundStyle(.secondary)
                        PhotosPicker(selection: $photo, matching: .images) {
                            Label("Choose roster photo", systemImage: "photo.badge.magnifyingglass")
                        }.disabled(busy)
                        TextEditor(text: $rosterText)
                            .frame(minHeight: 90).overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.secondary.opacity(0.2)))
                            .accessibilityLabel("Roster text").accessibilityIdentifier("rosterText")
                        Text("Example: Fri 19:00-07:00")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("Build drafts") {
                            do {
                                drafts = try NightDraftParser.parse(rosterText, period: period, timeZoneID: store.data.preferences.timeZoneID)
                                draftError = nil
                            } catch { draftError = error.localizedDescription; drafts = [] }
                        }.accessibilityIdentifier("buildDrafts")

                        if let draftError { Label(draftError, systemImage: "exclamationmark.triangle").font(.footnote) }
                        if !drafts.isEmpty {
                            Text("\(drafts.count) drafts — review each time, then save all.").font(.headline)
                            ForEach(drafts) { draft in
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(draft.source).font(.subheadline.weight(.semibold))
                                        Text("\(dayLabel(draft.day)) · \(clockLabel(draft.startMinute)) → \(clockLabel(draft.endMinute))")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button { drafts.removeAll { $0.id == draft.id } } label: {
                                        Image(systemName: "trash").frame(minWidth: 44, minHeight: 44)
                                    }.accessibilityLabel("Remove draft")
                                }.padding(.vertical, 4)
                            }
                            Button("Save \(drafts.count) confirmed shifts") {
                                do {
                                    let materialized = try NightDraftParser.materialize(drafts, timeZoneID: store.data.preferences.timeZoneID, existing: store.data.shifts)
                                    if store.update({ $0.shifts.append(contentsOf: materialized); $0.shifts.sort { $0.plannedStart < $1.plannedStart } }) {
                                        drafts = []; rosterText = ""
                                    }
                                } catch { store.error = error.localizedDescription }
                            }
                            .accessibilityIdentifier("saveDrafts")
                            .font(.headline)
                        }
                    }.padding(.top, 12)
                }.font(.headline)
                Divider()
                NavigationLink { RatesView() } label: {
                    HStack {
                        Text("Pay rates").font(.headline)
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption.bold())
                    }.frame(minHeight: 44)
                }.buttonStyle(.plain)
            }
        }
        .navigationTitle("Roster")
        .navigationBarTitleDisplayMode(.large)
        .onChange(of: period) { drafts = []; draftError = nil }
        .environment(\.timeZone, store.calendar.timeZone)
        .onChange(of: photo) { _, item in
            guard let item else { return }
            busy = true
            Task {
                defer { busy = false }
                do {
                    guard let data = try await item.loadTransferable(type: Data.self) else {
                        throw InputError.invalid("This photo couldn't be opened.")
                    }
                    rosterText = try await recognize(data)
                } catch { store.error = error.localizedDescription }
            }
        }
        .sheet(item: $editing) { shift in NavigationStack { ShiftEditView(shift: shift) } }
        .sheet(isPresented: $adding) { NavigationStack { ShiftEditView(shift: nil, defaultDate: date) } }
    }

    private func dayLabel(_ day: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "E MMM d"; f.timeZone = store.calendar.timeZone
        return f.string(from: day)
    }
    private func clockLabel(_ minute: Int) -> String {
        String(format: "%02d:%02d", minute / 60, minute % 60)
    }
    private func recognize(_ data: Data) async throws -> String {
        guard data.count <= 20_000_000 else { throw InputError.invalid("Choose a roster photo smaller than 20 MB.") }
        return try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            try VNImageRequestHandler(data: data).perform([request])
            let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
            guard !text.isEmpty else { throw InputError.invalid("No readable text found. Try a clearer photo or type the shifts.") }
            return text
        }.value
    }
}

struct ShiftEditView: View {
    @Environment(NightStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var shift: NightShift?
    var defaultDate = Date()
    @State private var start: Date = Date()
    @State private var end: Date = Date()
    @State private var breakMinutes = 30
    @State private var breakPaid = false
    @State private var workedBreak = 30
    @State private var workedBreakPaid = false
    @State private var recordActuals = false
    @State private var actualStart: Date = Date()
    @State private var actualEnd: Date = Date()
    @State private var note = ""
    @State private var confirmDelete = false
    @State private var error: String?

    var body: some View {
        NightPage {
            NightSection("Planned 12-hour night") {
                DatePicker("Starts", selection: $start)
                DatePicker("Ends", selection: $end)
                Stepper("Meal break: \(breakMinutes) minutes", value: $breakMinutes, in: 0...120, step: 5)
                Toggle("Paid break", isOn: $breakPaid)
                Text("Default 30 minutes unpaid. Break is taken at the end of the shift for calculation.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            NightSection {
                Toggle("Record actual hours", isOn: $recordActuals)
                if recordActuals {
                    DatePicker("Actual start", selection: $actualStart)
                    DatePicker("Actual end", selection: $actualEnd)
                    Stepper("Actual meal: \(workedBreak) minutes", value: $workedBreak, in: 0...120, step: 5)
                    Toggle("Actual break was paid", isOn: $workedBreakPaid)
                }
            } header: { Text("Hours worked") } footer: {
                Text("Planned vs actual start/end is kept in history. Actuals replace planned hours in the estimate.")
            }
            NightSection("Note") { TextField("Optional note", text: $note, axis: .vertical).lineLimit(2...5) }
            if let error { Label(error, systemImage: "exclamationmark.triangle").font(.footnote) }
            Button("Save shift") { save() }.buttonStyle(NightPrimaryButton()).accessibilityIdentifier("saveShift")
            if shift != nil {
                Button("Delete shift", role: .destructive) { confirmDelete = true }.frame(minHeight: 44)
            }
        }
        .navigationTitle(shift == nil ? "New night shift" : "Shift details")
        .environment(\.timeZone, store.calendar.timeZone)
        .onAppear {
            if let shift {
                start = shift.plannedStart; end = shift.plannedEnd
                breakMinutes = shift.plannedBreakMinutes; breakPaid = shift.plannedBreakPaid
                workedBreak = shift.breakMinutes; workedBreakPaid = shift.breakPaid
                recordActuals = shift.isActual
                actualStart = shift.actualStart ?? shift.plannedStart
                actualEnd = shift.actualEnd ?? shift.plannedEnd
                note = shift.note
            } else {
                let day = store.calendar.startOfDay(for: defaultDate)
                start = store.calendar.date(byAdding: .hour, value: 19, to: day)!
                end = store.calendar.date(byAdding: .hour, value: 31, to: day)!
            }
        }
        .onChange(of: recordActuals) { _, enabled in
            if enabled, shift?.isActual != true {
                actualStart = start; actualEnd = end
                workedBreak = breakMinutes; workedBreakPaid = breakPaid
            }
        }
        .confirmationDialog("Delete this shift?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete shift", role: .destructive) {
                if let shift, store.update({ $0.shifts.removeAll { $0.id == shift.id } }) { dismiss() }
            }
        }
    }

    private func minute(_ date: Date) -> Date {
        Date(timeIntervalSince1970: floor(date.timeIntervalSince1970 / 60) * 60)
    }

    private func save() {
        do {
            var draft: NightShift
            if let shift { draft = shift } else {
                draft = NightShift(plannedStart: minute(start), plannedEnd: minute(end), timeZoneID: store.data.preferences.timeZoneID)
            }
            draft.plannedStart = minute(start); draft.plannedEnd = minute(end)
            draft.timeZoneID = store.data.preferences.timeZoneID
            draft.plannedBreakMinutes = breakMinutes; draft.plannedBreakPaid = breakPaid
            if recordActuals {
                draft.actualStart = minute(actualStart); draft.actualEnd = minute(actualEnd)
                draft.actualBreakMinutes = workedBreak; draft.actualBreakPaid = workedBreakPaid
            } else { draft.actualStart = nil; draft.actualEnd = nil; draft.actualBreakMinutes = nil; draft.actualBreakPaid = nil }
            draft.note = note
            try draft.validate()
            // Overlap check
            for other in store.data.shifts where other.id != draft.id {
                if draft.plannedStart < other.plannedEnd && draft.plannedEnd > other.plannedStart {
                    throw InputError.invalid("This shift overlaps another shift.")
                }
            }
            if shift == nil { draft.changes.append(ShiftChange(summary: "Created shift")) }
            else { draft.changes.append(ShiftChange(summary: "Edited shift times or break")) }
            if store.update({ data in
                if let i = data.shifts.firstIndex(where: { $0.id == draft.id }) { data.shifts[i] = draft }
                else { data.shifts.append(draft); data.shifts.sort { $0.plannedStart < $1.plannedStart } }
            }) { dismiss() }
        } catch { self.error = error.localizedDescription }
    }
}
