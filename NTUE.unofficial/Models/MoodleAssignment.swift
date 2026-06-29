import SwiftUI

/// One enrolled Moodle course (e.g. `1142_0328_電腦網路`).
struct MoodleCourse: Identifiable, Hashable {
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
enum MoodleSubmissionState {
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
struct MoodleAssignment: Identifiable, Hashable {
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
struct MoodleCourseAssignments: Identifiable {
    let course: MoodleCourse
    let assignments: [MoodleAssignment]
    var id: Int { course.id }

    var outstandingCount: Int {
        assignments.filter { $0.state == .notSubmitted || $0.state == .draft }.count
    }
}

/// A single upcoming deadline for the 首頁 widget (from the calendar action events).
struct MoodleDeadline: Identifiable, Hashable {
    let id: Int
    let name: String
    let courseName: String
    let due: Date
    let overdue: Bool
    let url: URL
}
