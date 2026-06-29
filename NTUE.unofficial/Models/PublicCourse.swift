import Foundation

/// A generic id/name option used for the filter pickers.
struct NamedOption: Identifiable, Hashable {
    let id: String      // option value
    let name: String    // display text
}

/// A course returned by 公開課表查詢 (b09120).
struct PublicCourse: Identifiable, Hashable {
    let id = UUID()
    let courseNo: String      // SemesterCourseNo
    let name: String          // SemesterCourseName
    let engName: String       // SemesterCourseENGName
    let choose: String        // Choose  必/選
    let className: String      // StudyClassName 班級
    let department: String    // CourseClassName / 開課系所
    let dayType: String       // DayfgClassTypeName 學制
    let teacher: String       // Teacher
    let time: String          // SemCourseTime 上課時間
    let classroom: String     // ClassRoom
    let credit: String        // Credit
    let language: String      // TeaLanguage
    let enrollLimit: String   // "下限-上限"
    let memo: String          // Memo

    var isRequired: Bool { choose.contains("必") }
}

/// The filter options + CSRF token scraped from the b09120 page.
struct PublicScheduleOptions {
    var years: [NamedOption] = []
    var semesters: [NamedOption] = []
    var classes: [NamedOption] = []
    var defaultYear: String = ""
    var defaultSemester: String = ""
    var token: String = ""
}
