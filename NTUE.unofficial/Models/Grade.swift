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

    /// 年級 read from the class name, e.g. "數位二甲" → 2.
    var gradeLevel: Int? {
        let map: [Character: Int] = ["一": 1, "二": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7]
        for ch in className where map[ch] != nil { return map[ch] }
        return nil
    }

    var gradeLabel: String? { gradeLevel.map { "\($0) 年級" } }
}

/// Academic-year / semester maths for NTUE (民國年; the year rolls on 8/1).
enum NTUETerm {
    /// Current 學年 (ROC year). The academic year starts 8/1.
    static func currentAcademicYear(_ date: Date = Date()) -> Int {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Taipei") ?? .current
        let c = cal.dateComponents([.year, .month], from: date)
        let gregorian = (c.month ?? 1) >= 8 ? (c.year ?? 0) : (c.year ?? 0) - 1
        return gregorian - 1911
    }

    /// The 4-year span of semesters a student of `grade` should see, e.g. a
    /// 二年級 student in 學年 114 → 113 上 … 116 下 (oldest → newest).
    static func enrolledSemesters(grade: Int, asOf date: Date = Date()) -> [SemesterSelection] {
        let enrollAY = currentAcademicYear(date) - (grade - 1)
        var out: [SemesterSelection] = []
        for ay in enrollAY...(enrollAY + 3) {
            out.append(SemesterSelection(year: "\(ay)", semester: "1"))
            out.append(SemesterSelection(year: "\(ay)", semester: "2"))
        }
        return out
    }

    /// The semester happening right now. 上學期 = Aug–Jan, 下學期 = Feb–Jul.
    static func currentSemester(asOf date: Date = Date()) -> SemesterSelection {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Taipei") ?? .current
        let m = cal.component(.month, from: date)
        let sem = (m >= 8 || m == 1) ? "1" : "2"
        return SemesterSelection(year: "\(currentAcademicYear(date))", semester: sem)
    }

    /// Drops semesters in the future — a term only appears once it has begun.
    static func upToCurrent(_ list: [SemesterSelection], asOf date: Date = Date()) -> [SemesterSelection] {
        let cur = currentSemester(asOf: date)
        return list.filter { ($0.year, $0.semester) <= (cur.year, cur.semester) }
    }
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

    var option: SemesterOption { SemesterOption(id: id, label: shortLabel) }

    /// Keep only 上/下學期 (drop 暑期/暑假) and sort oldest → newest.
    static func ordered(_ list: [SemesterSelection]) -> [SemesterSelection] {
        list.filter { $0.semester == "1" || $0.semester == "2" }
            .sorted { ($0.year, $0.semester) < ($1.year, $1.semester) }
    }
}
