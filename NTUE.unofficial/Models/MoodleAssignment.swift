import SwiftUI

/// One enrolled Moodle course (e.g. `1142_0328_電腦網路`).
nonisolated struct MoodleCourse: Identifiable, Hashable, Codable {
    let id: Int
    let fullName: String
    let shortName: String

    /// The `學年+學期` prefix, e.g. "1142" (114 學年 第 2 學期).
    var semesterCode: String {
        let head = fullName.prefix { $0 != "_" }
        return head.count == 4 ? String(head) : ""
    }

    /// Course name without the `1142_0328_` prefix → "電腦網路".
    var displayName: String {
        let parts = fullName.split(separator: "_", maxSplits: 2, omittingEmptySubsequences: false)
        return parts.count == 3 ? String(parts[2]) : fullName
    }
}

/// Submission state for one assignment, derived from the Moodle index table.
nonisolated enum MoodleSubmissionState {
    case submitted          // 已繳交…
    case draft              // 草稿（尚未繳交）
    case notSubmitted       // 未繳交 / 沒有繳交的作業
    case none               // 無線上繳交 / 未知

    init(statusText: String) {
        if statusText.contains("已繳交") { self = .submitted }
        else if statusText.contains("草稿") { self = .draft }
        else if statusText.contains("未繳交") || statusText.contains("沒有繳交") { self = .notSubmitted }
        else { self = .none }
    }

    var color: Color {
        switch self {
        case .submitted: return Color(red: 0.13, green: 0.55, blue: 0.30) // green
        case .draft: return Color(red: 0.96, green: 0.60, blue: 0.20)     // orange
        case .notSubmitted: return Color(red: 0.80, green: 0.22, blue: 0.22) // red
        case .none: return .secondary
        }
    }
}

/// One assignment row in a course's `/mod/assign/index.php` table.
nonisolated struct MoodleAssignment: Identifiable, Hashable, Codable {
    let id: Int             // module id → /mod/assign/view.php?id=
    let name: String
    let dueDate: Date?
    let dueText: String
    let statusText: String
    let gradeText: String

    var url: URL { URL(string: "https://md.ntue.edu.tw/mod/assign/view.php?id=\(id)")! }
    var state: MoodleSubmissionState { MoodleSubmissionState(statusText: statusText) }

    /// Has a real grade (not "-" / empty).
    var isGraded: Bool {
        let g = gradeText.trimmingCharacters(in: .whitespaces)
        return !g.isEmpty && g != "-"
    }

    /// Past due and still not handed in.
    var isOverdue: Bool {
        guard let dueDate, state == .notSubmitted || state == .draft else { return false }
        return dueDate < Date()
    }
}

/// Assignments grouped under one course (for the 作業 tab).
nonisolated struct MoodleCourseAssignments: Identifiable, Codable {
    let course: MoodleCourse
    let assignments: [MoodleAssignment]
    var id: Int { course.id }

    var outstandingCount: Int {
        assignments.filter { $0.state == .notSubmitted || $0.state == .draft }.count
    }
}

/// One course announcement (a discussion in a course's 公告 forum).
nonisolated struct MoodleAnnouncement: Identifiable, Hashable, Codable {
    let id: Int            // discussion id → /mod/forum/discuss.php?d=
    let courseName: String
    let subject: String
    let author: String
    let date: Date?
    let dateText: String

    var url: URL { URL(string: "https://md.ntue.edu.tw/mod/forum/discuss.php?d=\(id)")! }
}

/// A single upcoming deadline for the 首頁 widget (from the calendar action events).
nonisolated struct MoodleDeadline: Identifiable, Hashable, Codable {
    let id: Int
    let name: String
    let courseName: String
    let due: Date
    let overdue: Bool
    let url: URL
    /// 這門課屬於哪個學期(課程全名前綴,例 "1142")。舊版留下來的快取沒有
    /// 這個欄位 → nil,那時只能靠截止日判斷是不是上學期的。
    var semesterCode: String?

    /// 上一個(或更早)學期留下來的作業。沒交的舊作業會一直掛在 Moodle 的
    /// 行事曆上,首頁/小工具/提醒不該再把它們算成「待繳」—— 開學後那只是一排
    /// 永遠消不掉的紅色「已逾期」。
    /// - Parameters:
    ///   - currentTermCode: 本學期代碼,例 "1151"。
    ///   - termStart: 本學期開學日;行事曆沒涵蓋現在時傳 nil,那就只認學期代碼。
    ///
    /// 兩邊都問不出來就當作本學期 —— 寧可多顯示一筆,也不要把真的作業藏起來。
    func belongsToPastSemester(currentTermCode: String, termStart: Date?) -> Bool {
        if let semesterCode, semesterCode.count == 4, currentTermCode.count == 4 {
            return semesterCode < currentTermCode    // 都是四位數字,字串比較即可
        }
        guard let termStart else { return false }
        return due < termStart
    }
}
