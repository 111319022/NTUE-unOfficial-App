import Foundation

/// A stage of the iNTUE 線上選課 (online course selection). Each stage is a
/// separate tab on the 選課查詢 page (b04250) — see `SelectionStage.pathSuffix`.
enum SelectionStage: String, CaseIterable, Identifiable {
    case result   // 選課結果 (最終，各階段都跑完才有資料)
    case phase1   // 第一階段
    case phase2   // 第二階段
    case phase3   // 第三階段

    var id: String { rawValue }

    var label: String {
        switch self {
        case .result: return "最終結果"
        case .phase1: return "一階"
        case .phase2: return "二階"
        case .phase3: return "三階"
        }
    }

    /// URL suffix appended to `/b04/b04250` (選課結果 has none; stages use /t1…/t3).
    var pathSuffix: String {
        switch self {
        case .result: return ""
        case .phase1: return "/t1"
        case .phase2: return "/t2"
        case .phase3: return "/t3"
        }
    }
}

/// A single meeting slot of a course (one weekday + one 節次), parsed from ClassTime.
struct CourseMeeting: Hashable, Codable {
    let weekday: Int        // 1 = 週一 … 7 = 週日
    let periodName: String  // 節次 (canonical SectionName, e.g. "02", "0M")
}

/// A course the student selected at a given 選課 stage, decoded from the b04250
/// `"data":[…]` JSON island.
struct SelectedCourse: Identifiable, Codable, Hashable {
    let courseNo: String        // SemesterCourseNo 開課號
    let name: String            // SemesterCourseName 科目名稱
    let classType: String       // ClassTypeName 學制
    let studyClass: String      // StudyClassName 班級
    let department: String      // StudyCourseCategoryNames 開課系所
    let teacher: String         // Teacher 任課教師
    let classTimeRaw: String    // ClassTime, e.g. "五(02,03,04)"
    let classroom: String       // location_name 上課教室
    let credit: String          // Credit 學分
    let needPay: String         // NeedPay 是否收費
    let memo: String            // Memo 備註
    let isStop: Bool            // IsStop 停開否 (true = 停開)
    // 志願登記欄位 — only present on the stage tabs (t1/t2/t3); empty on 選課結果.
    var regState: String = ""   // RegState 選中 / 未選中
    var regMemo: String = ""    // RegMemo  抽中第1志願 / 因第1志願已抽中
    var wishOrder: String = ""  // PowerSeq 志願序
    var wishGroup: String = ""  // WishGroupName 志願群組

    var id: String { courseNo.isEmpty ? "\(name)|\(classTimeRaw)" : courseNo }

    var creditValue: Double { Double(credit) ?? 0 }

    /// Whether the student actually got this course. 選課結果 rows carry no
    /// `RegState` (every row is final → enrolled); stage rows are enrolled only
    /// when 選中. Neutral states (登記中 / 待抽籤) count as not-yet-enrolled.
    var isEnrolled: Bool {
        if regState.isEmpty { return true }
        if regState.contains("未") || regState.contains("落") || regState.contains("退") { return false }
        return regState.contains("選中") || regState.contains("選上")
            || regState.contains("已選") || regState.contains("分發")
    }

    /// Parsed meeting slots. Empty when the time is "另訂" / blank (intensive courses).
    var meetings: [CourseMeeting] { SelectedCourse.parseClassTime(classTimeRaw) }

    var hasFixedTime: Bool { !meetings.isEmpty }

    private static let weekdayMap: [Character: Int] =
        ["一": 1, "二": 2, "三": 3, "四": 4, "五": 5, "六": 6, "日": 7, "天": 7]

    /// Parses a ClassTime string into meeting slots. Format: a weekday character
    /// followed by `(節,節,…)`, optionally several blocks ("一(03,04) 三(05)").
    static func parseClassTime(_ raw: String) -> [CourseMeeting] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let regex = try? NSRegularExpression(pattern: #"([一二三四五六日天])\s*[(（]([^)）]*)[)）]"#)
        else { return [] }
        let ns = trimmed as NSString
        var out: [CourseMeeting] = []
        for m in regex.matches(in: trimmed, range: NSRange(location: 0, length: ns.length)) {
            guard let wdChar = ns.substring(with: m.range(at: 1)).first,
                  let wd = weekdayMap[wdChar] else { continue }
            let inner = ns.substring(with: m.range(at: 2))
            for token in inner.split(whereSeparator: { $0 == "," || $0 == "，" || $0 == " " }) {
                let name = NTUEPeriods.normalize(String(token))
                guard !name.isEmpty else { continue }
                out.append(CourseMeeting(weekday: wd, periodName: name))
            }
        }
        return out
    }
}

/// NTUE's fixed 節次 schedule. Names match the b04250 SectionName / ClassTime
/// tokens (zero-padded); times verified live from the personal-timetable grid.
enum NTUEPeriods {
    struct Period: Hashable { let name: String; let time: String }

    static let all: [Period] = [
        .init(name: "0M", time: "07:10-08:00"),
        .init(name: "01", time: "08:10-09:00"),
        .init(name: "02", time: "09:10-10:00"),
        .init(name: "03", time: "10:10-11:00"),
        .init(name: "04", time: "11:10-12:00"),
        .init(name: "0N", time: "12:10-13:20"),
        .init(name: "05", time: "13:30-14:20"),
        .init(name: "06", time: "14:30-15:20"),
        .init(name: "07", time: "15:30-16:20"),
        .init(name: "08", time: "16:30-17:20"),
        .init(name: "0E", time: "17:30-18:20"),
        .init(name: "09", time: "18:30-19:15"),
        .init(name: "10", time: "19:15-20:00"),
        .init(name: "11", time: "20:10-20:55"),
        .init(name: "12", time: "20:55-21:40"),
    ]

    private static let timeByName: [String: String] =
        Dictionary(uniqueKeysWithValues: all.map { ($0.name, $0.time) })
    private static let indexByName: [String: Int] =
        Dictionary(uniqueKeysWithValues: all.enumerated().map { ($1.name, $0) })

    /// Canonicalises a ClassTime token to a SectionName: "2"→"02", "M"→"0M",
    /// "N"→"0N", "E"→"0E"; already-canonical names pass through.
    static func normalize(_ token: String) -> String {
        let t = token.trimmingCharacters(in: .whitespaces).uppercased()
        guard !t.isEmpty else { return "" }
        if timeByName[t] != nil { return t }
        if let n = Int(t) { return String(format: "%02d", n) }
        switch t {
        case "M": return "0M"
        case "N": return "0N"
        case "E": return "0E"
        default:  return t
        }
    }

    static func time(_ name: String) -> String { timeByName[name] ?? "" }
    static func order(_ name: String) -> Int { indexByName[name] ?? Int.max }
}

/// Lays a set of selected courses onto the weekly grid and reports conflicts.
/// This is the model behind the 預排 visual timetable.
struct PreSchedule {
    /// Every row returned for the stage (used for the raw count / not-選中 list).
    let courses: [SelectedCourse]
    /// The courses the student actually got (選中 / 選課結果) — what the grid shows.
    let enrolled: [SelectedCourse]
    /// 志願 that didn't make it (only on stage tabs) — shown muted below the grid.
    let notEnrolled: [SelectedCourse]

    /// slot key "weekday-period" → enrolled courses occupying it (>1 = real 衝堂).
    let slots: [String: [SelectedCourse]]

    init(_ courses: [SelectedCourse]) {
        self.courses = courses
        let active = courses.filter { !$0.isStop }
        self.enrolled = active.filter(\.isEnrolled)
        self.notEnrolled = active.filter { !$0.isEnrolled }
        var map: [String: [SelectedCourse]] = [:]
        for course in enrolled {
            for m in course.meetings {
                map["\(m.weekday)-\(m.periodName)", default: []].append(course)
            }
        }
        self.slots = map
    }

    func courses(weekday: Int, period: String) -> [SelectedCourse] {
        slots["\(weekday)-\(period)"] ?? []
    }

    /// Weekdays that actually have a class (always shows Mon–Fri; adds 六/日 if used).
    var activeWeekdays: [Int] {
        let used = Set(enrolled.flatMap { $0.meetings.map(\.weekday) })
        return (Array(1...5) + [6, 7].filter(used.contains))
    }

    /// 節次 rows that have at least one class, in schedule order.
    var activePeriods: [NTUEPeriods.Period] {
        let used = Set(enrolled.flatMap { $0.meetings.map(\.periodName) })
        return NTUEPeriods.all.filter { used.contains($0.name) }
    }

    /// Enrolled courses with no parseable time (時間另訂 / 密集課程).
    var untimedCourses: [SelectedCourse] {
        enrolled.filter { !$0.hasFixedTime }
    }

    /// Distinct (weekday,period) slots holding more than one course.
    var hasConflict: Bool { slots.values.contains { $0.count > 1 } }

    /// Conflicting course pairs, de-duplicated, for the warning banner.
    var conflictCourses: [SelectedCourse] {
        var seen = Set<String>()
        var out: [SelectedCourse] = []
        for group in slots.values where group.count > 1 {
            for c in group where !seen.contains(c.id) { seen.insert(c.id); out.append(c) }
        }
        return out.sorted { $0.name < $1.name }
    }

    var totalCredits: Double { enrolled.reduce(0) { $0 + $1.creditValue } }
    var courseCount: Int { enrolled.count }
}
