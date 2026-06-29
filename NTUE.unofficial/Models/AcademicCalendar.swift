import Foundation

/// One academic term with its real class start / end (期末考結束) dates.
struct AcademicTerm {
    let code: String        // "1142"
    let name: String        // "114 學年度 第 2 學期"
    let start: Date
    let end: Date
}

/// 學期倒數 source.
///
/// ⚠️ 手動維護：Moodle 的課程 enddate 是被灌水的(顯示到 7/30),不能當學期結束。
/// 每學期請依「學校行事曆」更新下面的日期即可,App 其他地方會自動跟著算。
enum AcademicCalendar {
    static let terms: [AcademicTerm] = [
        term("1142", "114 學年度 第 2 學期", start: "2026-02-16", end: "2026-06-19"),
        term("1151", "115 學年度 第 1 學期", start: "2026-09-14", end: "2027-01-15"),
        term("1152", "115 學年度 第 2 學期", start: "2027-02-22", end: "2027-06-18"),
    ]

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
        if let t = terms.first(where: { today >= cal.startOfDay(for: $0.start) && today <= cal.startOfDay(for: $0.end) }) {
            let days = cal.dateComponents([.day], from: today, to: cal.startOfDay(for: t.end)).day ?? 0
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

    private static func term(_ code: String, _ name: String, start: String, end: String) -> AcademicTerm {
        AcademicTerm(code: code, name: name, start: date(start), end: date(end))
    }

    private static func date(_ s: String) -> Date {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Asia/Taipei")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: s) ?? Date()
    }
}
