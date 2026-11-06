import Foundation
import SwiftData
import Observation

@Model
final class NightSnapshot {
    var key: String
    var payload: Data
    init(payload: Data) { self.key = "primary"; self.payload = payload }
}

@MainActor @Observable
final class NightStore {
    private(set) var data = NightAppData()
    private(set) var revision = 0
    var error: String?
    private var context: ModelContext?
    private var snapshot: NightSnapshot?
    @ObservationIgnored private var cachedEstimate: (period: DateInterval, result: Result<NightEstimate, Error>)?

    func estimate(period: DateInterval) -> Result<NightEstimate, Error> {
        let current = data
        if let cachedEstimate, cachedEstimate.period == period { return cachedEstimate.result }
        let result = Result {
            try NightPayEngine.estimate(shifts: current.shifts, rates: current.rates, period: period,
                timeZoneID: current.preferences.timeZoneID, currency: current.preferences.currency)
        }
        cachedEstimate = (period, result)
        return result
    }

    private(set) var loaded = false
    private(set) var recoveryRequired = false

    func load(_ context: ModelContext) {
        guard !loaded else { return }
        self.context = context
        do {
            if let saved = try context.fetch(FetchDescriptor<NightSnapshot>()).first {
                snapshot = saved
                let decoded = try JSONDecoder().decode(NightAppData.self, from: saved.payload)
                try decoded.validate()
                cachedEstimate = nil
                data = decoded
                revision += 1
            }
            loaded = true
        } catch {
            loaded = true
            recoveryRequired = true
            self.error = "Your saved data could not be opened: \(error.localizedDescription)"
        }
    }

    @discardableResult
    func update(_ change: (inout NightAppData) throws -> Void) -> Bool {
        guard loaded, let context else { error = "Local storage is not available. Reopen the app to retry."; return false }
        guard !recoveryRequired || snapshot != nil else {
            error = "The existing storage could not be inspected. Restart the app before restoring a backup."
            return false
        }
        do {
            var candidate = data
            try change(&candidate)
            try candidate.validate()
            let payload = try JSONEncoder().encode(candidate)
            if let snapshot { snapshot.payload = payload }
            else {
                let record = NightSnapshot(payload: payload)
                context.insert(record)
                snapshot = record
            }
            try context.save()
            cachedEstimate = nil
            data = candidate
            revision += 1
            recoveryRequired = false
            return true
        } catch {
            context.rollback()
            snapshot = (try? context.fetch(FetchDescriptor<NightSnapshot>()))?.first
            self.error = error.localizedDescription
            return false
        }
    }

    func restore(_ contents: Data) -> Bool {
        do {
            guard contents.count <= NightAppData.maxBackupSize else { throw InputError.invalid("Choose a backup smaller than 25 MB.") }
            let decoded = try JSONDecoder().decode(NightAppData.self, from: contents)
            try decoded.validate()
            return update { $0 = decoded }
        } catch { self.error = "Backup was not restored: \(error.localizedDescription)"; return false }
    }

    var calendar: Calendar { NightPayEngine.calendar(data.preferences.timeZoneID) }
    func money(_ value: Decimal) -> String {
        Money.format(value, currency: data.preferences.currency, localeID: data.preferences.localeID)
    }
}
