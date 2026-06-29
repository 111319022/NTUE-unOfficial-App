import Foundation

/// 缺曠紀錄 — one row per course (b11170).
struct AbsenceRecord: Identifiable, Hashable, Codable {
    let id = UUID()
    let courseName: String     // SemesterCourseName
    let teacher: String        // Teacher
    let classGroup: String     // StudyClassName
    let absentOverTotal: String // SessionTotalHour, e.g. "3/54" (缺曠時數/課程總時數)
    let totalHours: String     // TotalTeacherHour
    let failFlag: String       // Standard 已達零分標準註記

    private enum CodingKeys: String, CodingKey {
        case courseName, teacher, classGroup, absentOverTotal, totalHours, failFlag
    }

    /// Absent hours parsed from "3/54".
    var absentHours: Int? { Int(absentOverTotal.split(separator: "/").first.map(String.init) ?? "") }
    var hasAbsence: Bool { (absentHours ?? 0) > 0 }
    /// True when the school flagged this course as having reached the fail threshold.
    var reachedFailThreshold: Bool { !failFlag.trimmingCharacters(in: .whitespaces).isEmpty }
}

/// 操行成績 — one row per semester (f02192).
struct ConductRecord: Identifiable, Hashable {
    let id = UUID()
    let year: String        // ACADYear
    let semester: String    // Semester (e.g. "下學期")
    let score: String       // EndScore 最終成績
    let merit: String       // RP4 嘉獎
    let minorMerit: String  // RP5 小功
    let majorMerit: String  // RP6 大功
    let warning: String     // NoEliminateRP1 申誡
    let minorDemerit: String // NoEliminateRP2 小過
    let majorDemerit: String // NoEliminateRP3 大過

    var termLabel: String { "\(year) \(semester)" }
    var hasScore: Bool { !score.trimmingCharacters(in: .whitespaces).isEmpty }

    /// (label, count) for each reward/penalty kind with a non-zero count.
    var nonZeroCounts: [(String, String)] {
        [("嘉獎", merit), ("小功", minorMerit), ("大功", majorMerit),
         ("申誡", warning), ("小過", minorDemerit), ("大過", majorDemerit)]
            .filter { Int($0.1) ?? 0 > 0 }
    }
}

/// 獎懲紀錄 — one row per reward/penalty (f021b0).
struct RewardPenaltyRecord: Identifiable, Hashable {
    let id = UUID()
    let year: String          // ACADYear 獎懲發生學年度
    let semester: String      // Semester 獎懲學期
    let type: String          // TotleBonusPenalty 獎懲支數 (e.g. "嘉獎一次")
    let article: String       // ReasonContent 獎懲條文
    let reason: String        // Memo 獎懲事由
    let eliminateStatus: String // EliminateStatus 銷過狀態

    var termLabel: String { "\(year) \(semester)" }
    /// Penalties (過/誡) are red; rewards (獎/功) are green.
    var isPenalty: Bool { type.contains("過") || type.contains("誡") }
}
