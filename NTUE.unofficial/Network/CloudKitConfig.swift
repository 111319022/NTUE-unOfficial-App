import Foundation
import CloudKit

/// Central place for the CloudKit container + the App Group cache the remote
/// config is mirrored into. Everything the app pulls from CloudKit is **public,
/// read-only** data you maintain from the CloudKit Dashboard (學期行事曆、校園
/// 活動、強制更新設定) — so it can be changed without shipping an app update.
enum CloudKitConfig {
    /// Must match `com.apple.developer.icloud-container-identifiers` in the
    /// app's entitlements and the container created in the CloudKit Dashboard.
    static let containerID = "iCloud.com.rayhsu63.NTUE-unofficial"

    static var container: CKContainer { CKContainer(identifier: containerID) }

    /// The database everyone reads from (and that you write to in the Dashboard).
    static var publicDB: CKDatabase { container.publicCloudDatabase }

    // MARK: Record types (mirror these names in the Dashboard schema)

    enum RecordType {
        static let academicTerm = "AcademicTerm"
        static let calendarEvent = "CalendarEvent"
        static let appConfig = "AppConfig"
        /// A "clientlist" record whose `ids` field lists the recordNames of all
        /// records of a given type — lets us enumerate without CKQuery (and so
        /// without needing a queryable index on recordName in the schema).
        static let manifest = "Manifest"
    }

    /// Fixed recordNames we fetch by ID (no queryable index required).
    static let appConfigRecordName = "current"

    enum Manifest {
        static let events = "manifest-CalendarEvent"
        static let terms = "manifest-AcademicTerm"
    }

    /// App Group UserDefaults — shared so a future widget could read the same
    /// cached calendar. The remote data is mirrored here as JSON so the rest of
    /// the app can read it synchronously (e.g. `AcademicCalendar.countdown()`).
    static let defaults = UserDefaults(suiteName: "group.com.rayhsu63.NTUE-unofficial")
        ?? .standard

    enum CacheKey {
        static let terms = "remote_academic_terms"
        static let events = "remote_calendar_events"
        static let appConfig = "remote_app_config"
        static let lastRefresh = "remote_config_last_refresh"
    }
}
