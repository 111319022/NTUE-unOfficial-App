import Foundation
import CloudKit

/// One academic term. The semester can end at 16 weeks (課程結束) or 18 weeks
/// (學期結束) depending on the student's programme, so we keep both.
struct AcademicTerm: Codable, Hashable {
    let code: String        // "1152"
    let name: String        // "115 學年度 第 2 學期"
    let start: Date
    let end16: Date
    let end18: Date
}

extension AcademicTerm {
    /// Build from a CloudKit record; nil if a required field is missing.
    ///
    /// CloudKit record type: `AcademicTerm`
    ///   code   String   — 學期代碼，例：`1151`
    ///   name   String   — 顯示名稱，例：`115 學年度 第 1 學期`
    ///   start  Date/Time — 開學日
    ///   end16  Date/Time — 課程結束（16 週）
    ///   end18  Date/Time — 學期結束（18 週）
    init?(record: CKRecord) {
        guard let code = record["code"] as? String,
              let name = record["name"] as? String,
              let start = record["start"] as? Date,
              let end16 = record["end16"] as? Date,
              let end18 = record["end18"] as? Date else { return nil }
        self.init(code: code, name: name, start: start, end16: end16, end18: end18)
    }

    func apply(to record: CKRecord) {
        record["code"] = code
        record["name"] = name
        record["start"] = start
        record["end16"] = end16
        record["end18"] = end18
    }
}

/// 學期倒數 source.
///
/// The term dates come from CloudKit (公開資料庫，你在 Dashboard 維護),快取在
/// App Group,離線或尚未設定時 fall back 到下面的 `fallbackTerms`。要更新學期
/// 日期時,改 CloudKit 即可,不必發新版 App。`fallbackTerms` 只是保底,建議每
/// 年順手更新一次。
enum AcademicCalendar {
    /// Offline fallback — used until CloudKit has been fetched at least once.
    static let fallbackTerms: [AcademicTerm] = [
        term("1142", "114 學年度 第 2 學期", start: "2026-02-16", end16: "2026-06-05", end18: "2026-06-19"),
        term("1151", "115 學年度 第 1 學期", start: "2026-09-07", end16: "2026-12-24", end18: "2027-01-08"),
        term("1152", "115 學年度 第 2 學期", start: "2027-02-15", end16: "2027-06-04", end18: "2027-06-18"),
    ]

    /// The terms in effect right now: the cached CloudKit copy if we have one,
    /// otherwise the built-in fallback.
    static var terms: [AcademicTerm] {
        cachedRemoteTerms ?? fallbackTerms
    }

    // MARK: Remote cache (written by RemoteConfigService)

    static var cachedRemoteTerms: [AcademicTerm]? {
        guard let data = CloudKitConfig.defaults.data(forKey: CloudKitConfig.CacheKey.terms),
              let terms = try? JSONDecoder().decode([AcademicTerm].self, from: data),
              !terms.isEmpty else { return nil }
        return terms.sorted { $0.start < $1.start }
    }

    static func cacheRemoteTerms(_ terms: [AcademicTerm]) {
        guard let data = try? JSONEncoder().encode(terms) else { return }
        CloudKitConfig.defaults.set(data, forKey: CloudKitConfig.CacheKey.terms)
    }

    /// Whether the user's programme runs 18-week semesters (toggle in 其他服務).
    /// Defaults to 16 weeks.
    static var uses18Weeks: Bool { UserDefaults.standard.bool(forKey: "use18Week") }

    /// The chosen semester-end date for a term, per the 16/18-week preference.
    static func end(of term: AcademicTerm) -> Date {
        uses18Weeks ? term.end18 : term.end16
    }

    /// What to show in the 學期倒數 widget right now.
    enum Countdown {
        case during(term: AcademicTerm, daysLeft: Int)   // 上課中
        case beforeStart(term: AcademicTerm, days: Int)  // 放假中,距離開學
        case unknown                                     // 行事曆未涵蓋
    }

    static func countdown(now: Date = Date()) -> Countdown {
        let cal = Calendar(identifier: .gregorian)
        let today = cal.startOfDay(for: now)
        // In a term right now?
        if let t = terms.first(where: { today >= cal.startOfDay(for: $0.start) && today <= cal.startOfDay(for: end(of: $0)) }) {
            let days = cal.dateComponents([.day], from: today, to: cal.startOfDay(for: end(of: t))).day ?? 0
            return .during(term: t, daysLeft: max(days, 0))
        }
        // Otherwise count down to the next upcoming term.
        if let next = terms.filter({ cal.startOfDay(for: $0.start) > today })
            .min(by: { $0.start < $1.start }) {
            let days = cal.dateComponents([.day], from: today, to: cal.startOfDay(for: next.start)).day ?? 0
            return .beforeStart(term: next, days: max(days, 0))
        }
        return .unknown
    }

    /// Whether classes are in session on `date` (between 開學 and 學期結束, per
    /// the 16/18-week preference). Returns `nil` when the date falls outside the
    /// calendar we actually know about, so callers can choose *not* to hide
    /// classes when the calendar is stale/unmaintained rather than blanking a
    /// real timetable.
    static func isInSession(_ date: Date) -> Bool? {
        let cal = Calendar(identifier: .gregorian)
        let day = cal.startOfDay(for: date)
        let known = terms
        guard let earliest = known.map({ cal.startOfDay(for: $0.start) }).min(),
              let latest = known.map({ cal.startOfDay(for: $0.end18) }).max(),
              day >= earliest, day <= latest else { return nil }
        return known.contains { day >= cal.startOfDay(for: $0.start) && day <= cal.startOfDay(for: end(of: $0)) }
    }

    private static func term(_ code: String, _ name: String, start: String, end16: String, end18: String) -> AcademicTerm {
        AcademicTerm(code: code, name: name, start: date(start), end16: date(end16), end18: date(end18))
    }

    private static func date(_ s: String) -> Date {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Asia/Taipei")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: s) ?? Date()
    }
}
