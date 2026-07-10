import Foundation
import CloudKit

/// Developer-only helper that writes starter records into the **Development** public
/// database. Its real purpose is to auto-create the CloudKit *schema* (record
/// types + fields, including the manifests) so you don't have to type them by
/// hand. Run it once from a debug build, then in CloudKit Console press
/// "Deploy Schema Changes…" to promote the schema to Production, and afterwards
/// maintain the real records from the in-app 管理後台.
///
/// Requires the device/simulator to be signed into iCloud (Settings → Apple ID).
enum CloudKitSeeder {
    struct Summary { let terms: Int; let events: Int; let config: Bool }

    static func seedAll() async throws -> Summary {
        // Reuse CloudKitAdmin so the type manifests are built alongside the
        // records — otherwise the manifest-based reads would find nothing.
        for term in AcademicCalendar.fallbackTerms {
            try await CloudKitAdmin.save(term: term)
        }
        for event in sampleEvents {
            try await CloudKitAdmin.save(event: event)
        }
        try await CloudKitAdmin.save(config: sampleConfig)
        return Summary(terms: AcademicCalendar.fallbackTerms.count,
                       events: sampleEvents.count, config: true)
    }

    // MARK: Sample data

    private static var sampleEvents: [CalendarEvent] {
        let raw: [(String, CalendarEvent.Category, String, String?, String?)] = [
            ("開學典禮", .ceremony, "2026-09-07", nil, "上午於大禮堂舉行"),
            ("加退選開始", .registration, "2026-09-07", "2026-09-18", nil),
            ("期中考週", .exam, "2026-11-09", "2026-11-13", nil),
            ("校慶運動會", .general, "2026-11-21", nil, "全校停課一天"),
            ("期末考週", .exam, "2026-12-21", "2026-12-25", nil),
            ("寒假開始", .holiday, "2027-01-19", nil, nil),
        ]
        return raw.enumerated().map { (i, s) in
            let (title, cat, start, end, note) = s
            return CalendarEvent(id: "event-sample-\(i)", title: title, date: date(start),
                                 endDate: end.map(date), category: cat, note: note, allDay: true)
        }
    }

    /// A benign AppConfig so the type exists and the gate stays off.
    private static var sampleConfig: AppConfig {
        var cfg = AppConfig()
        cfg.minVersion = "0.0.0"   // below any real version → no gate
        cfg.latestVersion = AppConfig.currentVersion
        cfg.updateTitle = "請更新 App"
        cfg.updateMessage = "目前版本已停止支援，請更新到最新版本以繼續使用。"
        cfg.updateURL = "https://apps.apple.com/tw/app/"
        return cfg
    }

    private static func date(_ s: String) -> Date {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Asia/Taipei")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: s) ?? Date()
    }
}
