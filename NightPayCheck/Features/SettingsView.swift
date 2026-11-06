import SwiftUI
import UniformTypeIdentifiers
import UserNotifications
import StoreKit

struct SettingsView: View {
    @Environment(NightStore.self) private var store
    @State private var preferences = PayPreferences()
    @State private var exportDoc: ExportDocument?
    @State private var exporting = false
    @State private var exportingCSV = false
    @State private var csvDoc: ExportDocument?
    @State private var importing = false
    @State private var pendingRestore: Data?
    @State private var confirmingRestore = false
    @State private var confirmingDelete = false
    @State private var reminderStatus: String?
    @State private var date = Date()

    private var period: DateInterval { NightPayEngine.payPeriod(containing: date, preferences: store.data.preferences) }

    var body: some View {
        NightPage {
            NightSection {
                NavigationLink { RatesView() } label: {
                    HStack {
                        Label("Pay rates", systemImage: "banknote").font(.headline)
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption.bold())
                    }.frame(minHeight: 44)
                }
                Divider()
                NightSettingsGroup(title: "Pay cycle", symbol: "calendar") {
                    Text("Week starts").font(.subheadline.weight(.medium))
                    Picker("Week starts", selection: $preferences.weekAnchorMonday) {
                        Text("Monday").tag(true)
                        Text("Sunday").tag(false)
                    }.pickerStyle(.segmented).padding(.vertical, 8)
                    Picker("Time zone", selection: $preferences.timeZoneID) {
                        ForEach(TimeZone.knownTimeZoneIdentifiers, id: \.self) { Text($0.replacingOccurrences(of: "_", with: " ")).tag($0) }
                    }.pickerStyle(.menu).padding(.vertical, 8)
                    DatePicker("A pay period starts", selection: $preferences.periodAnchor, displayedComponents: .date)
                        .padding(.vertical, 8)
                    Button("Save preferences") {
                        store.update {
                            $0.preferences.weekAnchorMonday = preferences.weekAnchorMonday
                            $0.preferences.timeZoneID = preferences.timeZoneID
                            $0.preferences.periodAnchor = preferences.periodAnchor
                            $0.rates.weekStartsOn = preferences.weekAnchorMonday ? 2 : 1
                        }
                    }.font(.subheadline.weight(.semibold))
                    Text("Biweekly, USD only. Time-zone changes affect day boundaries. Saved shift instants stay fixed.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Divider()
                NightSettingsGroup(title: "Unlock", symbol: "key") {
                    PaywallCard()
                }
                Divider()
                NightSettingsGroup(title: "Reminders", symbol: "bell") {
                    Button("Schedule shift reminders") {
                        Task {
                            do {
                                let count = try await ReminderService.enable(shifts: store.data.shifts)
                                reminderStatus = "\(count) reminders scheduled, one hour before each upcoming night."
                            } catch { reminderStatus = error.localizedDescription }
                        }
                    }
                    Button("Turn off reminders", role: .destructive) {
                        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
                        reminderStatus = "Reminders removed."
                    }
                    if let reminderStatus { Text(reminderStatus).font(.caption) }
                    Text("End-of-period nudge and next-night reminder. Delivery depends on iOS notification settings.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Divider()
                NightSettingsGroup(title: "Records", symbol: "archivebox") {
                    Button("Export JSON backup", systemImage: "square.and.arrow.up") {
                        do { exportDoc = ExportDocument(contents: try ExportService.backup(store.data)); exporting = true }
                        catch { store.error = error.localizedDescription }
                    }
                    DatePicker("CSV period", selection: $date, displayedComponents: .date)
                    Button("Export this period as CSV", systemImage: "table") {
                        do { csvDoc = ExportDocument(contents: try ExportService.csv(data: store.data, period: period)); exportingCSV = true }
                        catch { store.error = error.localizedDescription }
                    }
                    Button("Restore from backup", systemImage: "arrow.down.doc") { importing = true }
                    Text("Backups contain schedule, notes, rates, and comparisons in an unencrypted file. Restore replaces all records.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Divider()
                NightSettingsGroup(title: "Privacy", symbol: "lock") {
                    Text("Offline. No account. No tracking SDK. Roster photos and text stay on this device; only files you export leave through a destination you choose.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("Delete all local records", role: .destructive) { confirmingDelete = true }
                }
            }
            NightCard {
                Text("NightPayCheck · Private night-shift gross checker\nConfigured rules are estimates, not tax or payroll advice.").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
        .onAppear { preferences = store.data.preferences }
        .fileExporter(isPresented: $exporting, document: exportDoc, contentType: .json, defaultFilename: "NightPayCheck-backup") { result in
            if case .failure(let e) = result { store.error = e.localizedDescription }
        }
        .fileExporter(isPresented: $exportingCSV, document: csvDoc, contentType: .commaSeparatedText, defaultFilename: "NightPayCheck-calculations") { result in
            if case .failure(let e) = result { store.error = e.localizedDescription }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get()
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= NightAppData.maxBackupSize else { throw InputError.invalid("Choose a backup smaller than 25 MB.") }
                let contents = try Data(contentsOf: url)
                let candidate = try JSONDecoder().decode(NightAppData.self, from: contents)
                try candidate.validate()
                pendingRestore = contents; confirmingRestore = true
            } catch { store.error = "Backup could not be opened: \(error.localizedDescription)" }
        }
        .confirmationDialog("Replace all records with this backup?", isPresented: $confirmingRestore, titleVisibility: .visible) {
            Button("Replace and restore", role: .destructive) {
                if let pendingRestore, store.restore(pendingRestore) {
                    preferences = store.data.preferences
                    UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
                }
                pendingRestore = nil
            }
            Button("Cancel", role: .cancel) { pendingRestore = nil }
        }
        .confirmationDialog("Delete all shifts, settings, and comparisons? This cannot be undone.", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete all records", role: .destructive) {
                if store.update({ $0 = NightAppData() }) { UNUserNotificationCenter.current().removeAllPendingNotificationRequests() }
            }
        }
    }
}

struct PaywallCard: View {
    @Environment(NightStore.self) private var store
    @State private var product: Product?
    @State private var status = "Free: 2 pay-period checks. Lifetime unlock $6.99."
    @State private var busy = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(min(store.data.completedChecks, 2)) of 2 free checks used").font(.headline)
            Text(status).font(.caption).foregroundStyle(.secondary)
            HStack {
                Button(busy ? "Working…" : "Buy lifetime unlock") { Task { await buy() } }.disabled(busy || product == nil)
                Button("Restore") { Task { await restore() } }.disabled(busy)
            }.font(.subheadline.weight(.semibold))
            Text("One-time purchase, works offline after first validation. Free checker stays usable for the current period.").font(.caption).foregroundStyle(.secondary)
        }
        .task {
            do { product = try await Product.products(for: ["com.fujidevv.nightpaycheck.lifetime"]).first }
            catch { status = "Store unavailable offline — your saved records still work." }
        }
    }
    private func buy() async {
        guard let product else { return }
        busy = true; defer { busy = false }
        do {
            if case .success(let verification) = try await product.purchase() {
                if case .verified(let transaction) = verification { await transaction.finish(); status = "Unlocked. Thank you." }
            }
        } catch { status = error.localizedDescription }
    }
    private func restore() async {
        busy = true; defer { busy = false }
        do {
            try await AppStore.sync()
            for await result in Transaction.currentEntitlements {
                if case .verified = result { status = "Purchase restored."; return }
            }
            status = "No purchase found."
        } catch { status = error.localizedDescription }
    }
}

struct RecoveryView: View {
    @Environment(NightStore.self) private var store
    @State private var importing = false
    @State private var contents: Data?
    @State private var confirming = false
    var body: some View {
        ScrollView {
            ContentUnavailableView {
                Label("Your records need recovery", systemImage: "externaldrive.badge.exclamationmark")
            } description: {
                Text("Saved records couldn't be read. They have not been replaced. Restart the app or restore a backup.")
            } actions: {
                Button("Choose a JSON backup") { importing = true }.buttonStyle(.borderedProminent)
            }.frame(maxWidth: 600).frame(maxWidth: .infinity).padding(.vertical, 32)
        }
        .tint(NightTheme.accent)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get()
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let payload = try Data(contentsOf: url)
                let data = try JSONDecoder().decode(NightAppData.self, from: payload)
                try data.validate()
                contents = payload; confirming = true
            } catch { store.error = error.localizedDescription }
        }
        .confirmationDialog("Replace the unreadable records with this backup?", isPresented: $confirming, titleVisibility: .visible) {
            Button("Restore backup", role: .destructive) {
                if let contents, store.restore(contents) { }
                self.contents = nil
            }
            Button("Cancel", role: .cancel) { contents = nil }
        }
    }
}
