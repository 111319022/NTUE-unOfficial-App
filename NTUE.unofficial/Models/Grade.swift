import Foundation

/// One course's grade for a semester, decoded from the iNTUE DataTables JSON island.
struct Grade: Identifiable, Hashable, Codable {
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

    // `id` is a local identity, not part of the persisted payload — exclude it so
    // Codable doesn't warn about the immutable defaulted property.
    private enum CodingKeys: String, CodingKey {
        case courseCode, department, courseName, required, category, credits
        case classGroup, instructor, score, passed, note, withdrawDate
    }
}

/// Basic student profile parsed from the page header (學號 / 姓名 …).
struct StudentInfo: Equatable, Codable {
    var studentId: String = ""
    var name: String = ""
    var department: String = ""
    var className: String = ""
    /// 入學學年 (ROC), the fixed anchor for 年級. Derived from the 在學證明.
    var enrollmentYear: Int?

    var isEmpty: Bool { studentId.isEmpty && name.isEmpty }

    /// Current 年級, auto-incrementing on 8/1 (via `NTUETerm.currentAcademicYear`).
    /// Prefers the 入學學年 anchor; falls back to parsing the class name.
    var gradeLevel: Int? {
        if let enrollmentYear {
            let g = NTUETerm.currentAcademicYear() - enrollmentYear + 1
            return (1...8).contains(g) ? g : nil
        }
        let map: [Character: Int] = ["一": 1, "二": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7]
        for ch in className where map[ch] != nil { return map[ch] }
        return nil
    }

    var gradeLabel: String? {
        guard let g = gradeLevel else { return nil }
        let cn = ["一", "二", "三", "四", "五", "六", "七"]
        return (1...4).contains(g) ? "大\(cn[g - 1])" : "\(g) 年級"
    }

    /// Parses a 年級 string like "二年級" (or "2") → 2.
    static func gradeNumber(_ text: String) -> Int? {
        let map: [Character: Int] = ["一": 1, "二": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7]
        for ch in text where map[ch] != nil { return map[ch] }
        return Int(text.prefix { $0.isNumber })
    }
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

    /// True if the semester has already ended (older than the current one), so
    /// its data is final and can be cached on disk indefinitely.
    static func isPast(_ sel: SemesterSelection, asOf date: Date = Date()) -> Bool {
        return sel < currentSemester(asOf: date)
    }

    /// The span of semesters a student of `grade` should see, e.g. a 二年級
    /// student in 學年 114 → 113 上 … 116 下 (oldest → newest).
    ///
    /// 至少四學年,但延畢/五年制(grade > 4)會一路長到「現在」這個學年 —— 否則
    /// 大五生的清單會停在入學後第四年,連本學期都選不到。
    static func enrolledSemesters(grade: Int, asOf date: Date = Date()) -> [SemesterSelection] {
        let enrollAY = currentAcademicYear(date) - (grade - 1)
        let lastAY = Swift.max(enrollAY + 3, currentAcademicYear(date))
        var out: [SemesterSelection] = []
        for ay in enrollAY...lastAY {
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

    /// The semester right before `sel` (上 → 前一學年下學期; 下/暑 → 同學年前一個).
    /// Used to fall back when the current term has no grades posted yet.
    static func previousSemester(before sel: SemesterSelection) -> SemesterSelection? {
        switch sel.semester {
        case "1":
            guard let year = Int(sel.year) else { return nil }
            return SemesterSelection(year: "\(year - 1)", semester: "2")
        case "2":
            return SemesterSelection(year: sel.year, semester: "1")
        case "3":
            return SemesterSelection(year: sel.year, semester: "2")
        default:
            return nil
        }
    }

    /// The next semester after the current one — the term 選課/預排 targets.
    /// 上學期 → 下學期 same 學年; 下學期 → next 學年 上學期.
    static func upcomingSemester(asOf date: Date = Date()) -> SemesterSelection {
        let cur = currentSemester(asOf: date)
        if cur.semester == "1" {
            return SemesterSelection(year: cur.year, semester: "2")
        }
        let nextYear = (Int(cur.year) ?? currentAcademicYear(date)) + 1
        return SemesterSelection(year: "\(nextYear)", semester: "1")
    }

    /// Drops semesters newer than the upcoming (選課) term — keeps past + current
    /// + the one term being selected, so 預排 can show the upcoming semester while
    /// still hiding the empty far-future terms the page's <select> also lists.
    static func upToUpcoming(_ list: [SemesterSelection], asOf date: Date = Date()) -> [SemesterSelection] {
        let up = upcomingSemester(asOf: date)
        return list.filter { $0 <= up }
    }

    /// Drops semesters in the future — a term only appears once it has begun.
    static func upToCurrent(_ list: [SemesterSelection], asOf date: Date = Date()) -> [SemesterSelection] {
        let cur = currentSemester(asOf: date)
        return list.filter { $0 <= cur }
    }

    /// 選課頁該預設顯示的學期。
    ///
    /// 選課是「學期末才選下一學期」,而且開學後還有三階/加退選,所以一個學期裡
    /// 大部分時間該看的其實是「現在這個學期」;只有接近期末、選課真的開跑了,
    /// 預設才切到下一學期。判斷順序:
    ///  1. 行事曆上下一學期填了「選課開始日」→ 完全以它為準(最精確,而且在
    ///     CloudKit 改日期就好,不必發新版)。
    ///  2. 沒填 → 底線:本學期「學期結束(18 週)」前 `selectionLeadDays` 天才切。
    ///  3. 行事曆連本學期都沒有 → 用粗估的學期結束日(上學期 1/10、下學期 6/20)
    ///     套同一條規則。
    ///
    /// 不論哪一條,都不會早於目前學期(開學後仍在選課期,看的就是本學期)。
    static func selectionSemester(asOf date: Date = Date(),
                                  terms: [AcademicTerm] = AcademicCalendar.terms) -> SemesterSelection {
        let cur = currentSemester(asOf: date)
        let upcoming = upcomingSemester(asOf: date)

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Taipei") ?? .current

        // 1) 下一學期的行事曆填了選課開始日 → 以它為準(填了就不再推算)。
        if let next = terms.first(where: { $0.code == upcoming.termCode }),
           let selectionStart = next.selectionStart {
            return date >= cal.startOfDay(for: selectionStart) ? upcoming : cur
        }

        // 2) 底線:本學期結束前 selectionLeadDays 天才切。
        if let term = terms.first(where: { $0.code == cur.termCode }) {
            return switched(date, semesterEnd: term.end18, cal: cal) ? upcoming : cur
        }

        // 3) 行事曆沒涵蓋這學期 → 用粗估的學期結束日套同一條規則。
        //    上學期在隔年 1 月、下學期在同一西元年 6 月結束(民國 Y → 西元 Y+1912)。
        var comps = DateComponents()
        comps.year = (Int(cur.year) ?? currentAcademicYear(date)) + 1912
        comps.month = cur.semester == "1" ? 1 : 6
        comps.day = cur.semester == "1" ? 10 : 20
        guard let estimatedEnd = cal.date(from: comps) else { return cur }
        return switched(date, semesterEnd: estimatedEnd, cal: cal) ? upcoming : cur
    }

    /// 學期結束前 `selectionLeadDays` 天(含)之後 → 該切到下一學期了。
    private static func switched(_ date: Date, semesterEnd: Date, cal: Calendar) -> Bool {
        guard let switchDate = cal.date(byAdding: .day, value: -selectionLeadDays, to: semesterEnd) else {
            return date >= cal.startOfDay(for: semesterEnd)
        }
        return date >= cal.startOfDay(for: switchDate)
    }

    /// 選課頁提前幾天切到下一學期(從該學期的「學期結束」往前算)。
    static let selectionLeadDays = 14
}

/// A selectable academic year + semester (scraped from the page's <select> options).
struct SemesterSelection: Identifiable, Hashable, Codable {
    var year: String       // e.g. "114"  (民國年)
    var semester: String   // "1" 上學期 / "2" 下學期 / "3" 暑期

    var id: String { "\(year)-\(semester)" }

    /// 行事曆/Moodle 用的學期代碼,例:114 上 → "1141"。
    var termCode: String { "\(year)\(semester)" }

    /// 由學期代碼還原,例 "1152" → 115 下。
    init(year: String, semester: String) {
        self.year = year
        self.semester = semester
    }

    /// 由 `id` 還原,例 "115-2" → 115 下;格式不符時回 nil。
    init?(id: String) {
        let parts = id.split(separator: "-")
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
        self.year = String(parts[0])
        self.semester = String(parts[1])
    }

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

    /// Ultra-short label for chart axes, e.g. "114上" / "114下" / "114暑".
    var compactLabel: String {
        switch semester {
        case "1": return "\(year)上"
        case "2": return "\(year)下"
        case "3": return "\(year)暑"
        default:  return "\(year)-\(semester)"
        }
    }

    var option: SemesterOption { SemesterOption(id: id, label: shortLabel) }

    /// Keep only 上/下學期 (drop 暑期/暑假) and sort oldest → newest.
    static func ordered(_ list: [SemesterSelection]) -> [SemesterSelection] {
        list.filter { $0.semester == "1" || $0.semester == "2" }.sorted()
    }
}

/// Chronological order. Compares numerically so a 2-digit 學年 ("99") still
/// sorts before a 3-digit one ("114"), unlike a plain string compare.
extension SemesterSelection: Comparable {
    static func < (lhs: Self, rhs: Self) -> Bool {
        let l = (Int(lhs.year) ?? 0, Int(lhs.semester) ?? 0)
        let r = (Int(rhs.year) ?? 0, Int(rhs.semester) ?? 0)
        return l < r
    }
}
