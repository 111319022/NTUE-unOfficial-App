import Foundation
import CloudKit
import Observation

/// Pulls the app's remotely-maintained data from CloudKit's **public** database:
///   • 學期行事曆 (`AcademicTerm`)      → mirrored into `AcademicCalendar`
///   • 校園活動行事曆 (`CalendarEvent`)  → `events`
///   • 強制更新設定 (`AppConfig`)        → `appConfig`
///
/// Everything is cached in the App Group so the UI paints instantly from the
/// last-known copy and refreshes in the background (stale-while-revalidate).
/// If CloudKit is unreachable or empty, the app keeps the cache / built-in
/// fallback — it never breaks offline.
@Observable
@MainActor
final class RemoteConfigService {
    static let shared = RemoteConfigService()

    private(set) var events: [CalendarEvent]
    private(set) var appConfig: AppConfig
    private(set) var isRefreshing = false
    private(set) var lastError: String?

    private init() {
        events = Self.loadCachedEvents()
        appConfig = Self.loadCachedConfig()
    }

    /// Upcoming events (today onward), soonest first.
    func upcomingEvents(now: Date = Date(), limit: Int? = nil) -> [CalendarEvent] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let list = events
            .filter { cal.startOfDay(for: $0.endDate ?? $0.date) >= today }
            .sorted { $0.date < $1.date }
        if let limit { return Array(list.prefix(limit)) }
        return list
    }

    // MARK: - Refresh

    /// Fetch all three record types. Best-effort: one failing part doesn't stop
    /// the others, and any failure leaves the existing cache intact.
    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        lastError = nil

        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.refreshTerms() }
            group.addTask { await self.refreshEvents() }
            group.addTask { await self.refreshConfig() }
        }
        CloudKitConfig.defaults.set(Date(), forKey: CloudKitConfig.CacheKey.lastRefresh)
    }

    private func refreshTerms() async {
        do {
            let records = try await CloudKitStore.fetchList(manifest: CloudKitConfig.Manifest.terms)
            let terms = records.compactMap(AcademicTerm.init(record:))
            guard !terms.isEmpty else { return }
            AcademicCalendar.cacheRemoteTerms(terms.sorted { $0.start < $1.start })
        } catch {
            recordError(error, context: "學期")
        }
    }

    private func refreshEvents() async {
        do {
            let records = try await CloudKitStore.fetchList(manifest: CloudKitConfig.Manifest.events)
            let list = records.compactMap(CalendarEvent.init(record:)).sorted { $0.date < $1.date }
            events = list
            if let data = try? JSONEncoder().encode(list) {
                CloudKitConfig.defaults.set(data, forKey: CloudKitConfig.CacheKey.events)
            }
        } catch {
            recordError(error, context: "行事曆活動")
        }
    }

    private func refreshConfig() async {
        do {
            let id = CKRecord.ID(recordName: CloudKitConfig.appConfigRecordName)
            let record = try await CloudKitConfig.publicDB.record(for: id)
            let config = AppConfig(record: record)
            appConfig = config
            if let data = try? JSONEncoder().encode(config) {
                CloudKitConfig.defaults.set(data, forKey: CloudKitConfig.CacheKey.appConfig)
            }
        } catch let error as CKError where error.code == .unknownItem {
            // No AppConfig record yet — treat as "no force-update configured".
        } catch {
            recordError(error, context: "App 設定")
        }
    }

    // MARK: - CloudKit helpers

    private func recordError(_ error: Error, context: String) {
        // A missing record type (before you've seeded / deployed the schema)
        // is expected — don't surface it as a user-facing error.
        if let ck = error as? CKError, ck.code == .unknownItem { return }
        lastError = "\(context)更新失敗：\(error.localizedDescription)"
    }

    // MARK: - Cache loading

    private static func loadCachedEvents() -> [CalendarEvent] {
        guard let data = CloudKitConfig.defaults.data(forKey: CloudKitConfig.CacheKey.events),
              let list = try? JSONDecoder().decode([CalendarEvent].self, from: data) else { return [] }
        return list.sorted { $0.date < $1.date }
    }

    private static func loadCachedConfig() -> AppConfig {
        guard let data = CloudKitConfig.defaults.data(forKey: CloudKitConfig.CacheKey.appConfig),
              let config = try? JSONDecoder().decode(AppConfig.self, from: data) else { return AppConfig() }
        return config
    }
}
