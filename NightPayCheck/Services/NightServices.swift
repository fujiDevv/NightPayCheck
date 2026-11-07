import Foundation
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

struct ExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .commaSeparatedText] }
    var contents: Data
    init(contents: Data) { self.contents = contents }
    init(configuration: ReadConfiguration) throws { contents = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: contents) }
}

enum ExportService {
    static func backup(_ data: NightAppData) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let contents = try encoder.encode(data)
        guard contents.count <= NightAppData.maxBackupSize else {
            throw InputError.invalid("This backup exceeds the 25 MB restore limit.")
        }
        return contents
    }

    static func csv(data: NightAppData, period: DateInterval) throws -> Data {
        let estimate = try NightPayEngine.estimate(shifts: data.shifts, rates: data.rates, period: period,
            timeZoneID: data.preferences.timeZoneID, currency: data.preferences.currency)
        let formatter = ISO8601DateFormatter()
        func cell(_ text: String) -> String {
            let safe = ["=", "+", "-", "@", "\t", "\r"].contains(where: text.hasPrefix) ? "'" + text : text
            return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        var rows = [["shift_id", "planned_start", "planned_end", "effective_start", "effective_end",
                     "time_zone", "status", "type", "minutes", "hourly_rate", "amount", "currency", "notes", "rule_version"]]
        for shift in data.shifts.sorted(by: { $0.start < $1.start }) where shift.end > period.start && shift.start < period.end {
            for line in estimate.lines.filter({ $0.shiftID == shift.id }) {
                rows.append([shift.id.uuidString, formatter.string(from: shift.plannedStart),
                    formatter.string(from: shift.plannedEnd), formatter.string(from: shift.start), formatter.string(from: shift.end),
                    shift.timeZoneID, shift.isActual ? "Actual" : "Planned", line.kind, String(line.minutes),
                    NSDecimalNumber(decimal: line.hourlyRate).stringValue, NSDecimalNumber(decimal: line.amount).stringValue,
                    data.preferences.currency, shift.note, "1"])
            }
        }
        return Data(rows.map { $0.map(cell).joined(separator: ",") }.joined(separator: "\r\n").utf8)
    }
}

@MainActor enum ReminderService {
    static func enable(shifts: [NightShift]) async throws -> Int {
        let center = UNUserNotificationCenter.current()
        guard try await center.requestAuthorization(options: [.alert, .sound, .badge]) else {
            throw InputError.invalid("Notifications are disabled. You can allow them in iOS Settings.")
        }
        center.removeAllPendingNotificationRequests()
        var count = 0
        // Next-night reminder (1h before) for upcoming shifts, capped at 60.
        for shift in shifts.filter({ $0.plannedStart.addingTimeInterval(-3600) > Date() })
            .sorted(by: { $0.plannedStart < $1.plannedStart }).prefix(60) {
            let content = UNMutableNotificationContent()
            content.title = "Night shift tonight"
            content.body = "Your night shift starts in one hour. Confirm actuals after."
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: shift.plannedStart.addingTimeInterval(-3600).timeIntervalSinceNow, repeats: false)
            try await center.add(UNNotificationRequest(identifier: shift.id.uuidString, content: content, trigger: trigger))
            count += 1
        }
        return count
    }
}

import StoreKit

@MainActor @Observable
final class LifetimeAccess {
    static let productID = "com.fujidevv.nightpaycheck.lifetime"
    private(set) var unlocked = false
    private(set) var checked = false

    func refresh() async {
        var found = false
        for await entitlement in Transaction.currentEntitlements {
            if case .verified(let transaction) = entitlement,
               transaction.productID == Self.productID, transaction.revocationDate == nil {
                found = true
            }
        }
        unlocked = found
        checked = true
    }

    func observe() async {
        let listener = Task {
            for await update in Transaction.updates {
                if case .verified(let transaction) = update, transaction.productID == Self.productID {
                    await refresh()
                    await transaction.finish()
                }
            }
        }
        defer { listener.cancel() }
        await refresh()
        await withTaskCancellationHandler { await listener.value } onCancel: { listener.cancel() }
    }
}
