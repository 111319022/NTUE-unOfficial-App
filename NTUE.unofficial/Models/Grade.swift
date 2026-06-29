import Foundation

/// One course's grade for a semester, decoded from the iNTUE DataTables JSON island.
struct Grade: Identifiable, Hashable {
    let id = UUID()
    let courseCode: String       // SemesterCourseNo
    let department: String       // StudyCourseCategoryName
    let courseName: String       // SemesterCourseName
    let required: String         // Choose  (必修 / 選修)
    let category: String         // CourseClassName
    let credits: String          // Credit
    let classGroup: String       // StudyClassName
    let instructor: String       // Teacher
    let score: String            // Score
    let passed: String           // IsPass  (是 / 否)
    let note: String             // Memo
    let withdrawDate: String     // StopDate

    var scoreValue: Double? { Double(score) }
    var creditsValue: Double? { Double(credits) }
    var isPassed: Bool { passed.contains("是") }
    var isRequired: Bool { required.contains("必") }
    var hasScore: Bool { scoreValue != nil }
}

/// Basic student profile parsed from the page header (學號 / 姓名 …).
struct StudentInfo: Equatable, Codable {
    var studentId: String = ""
    var name: String = ""
    var department: String = ""
    var className: String = ""

    var isEmpty: Bool { studentId.isEmpty && name.isEmpty }
}

/// A selectable academic year + semester (scraped from the page's <select> options).
struct SemesterSelection: Identifiable, Hashable {
    var year: String       // e.g. "114"  (民國年)
    var semester: String   // "1" 上學期 / "2" 下學期 / "3" 暑期

    var id: String { "\(year)-\(semester)" }

    var semesterLabel: String {
        switch semester {
        case "1": return "上學期"
        case "2": return "下學期"
        case "3": return "暑期"
        default:  return "第\(semester)學期"
        }
    }

    var displayLabel: String { "\(year) 學年度 \(semesterLabel)" }
    var shortLabel: String { "\(year) \(semesterLabel)" }
}
