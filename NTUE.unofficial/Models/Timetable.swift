import Foundation

/// A single class session in the weekly timetable.
struct TimetableSession: Identifiable, Hashable, Codable {
    let id = UUID()
    let weekday: Int          // 1 = Monday … 7 = Sunday
    let periodName: String    // 節次, e.g. "0M", "1", "2"
    let periodTime: String    // e.g. "07:10-08:00"
    let classGroup: String    // 班級
    let courseName: String    // 課程名稱
    let instructor: String    // 教師
    let classroom: String     // 教室

    // `id` is a fresh local identifier, not part of the persisted payload.
    private enum CodingKeys: String, CodingKey {
        case weekday, periodName, periodTime, classGroup, courseName, instructor, classroom
    }
}

/// One row (period) of the timetable grid.
struct TimetablePeriod: Identifiable, Codable {
    let id = UUID()
    let name: String          // SectionName 節次
    let time: String          // SectionTime, normalised to "07:10-08:00"
    /// weekday(1...7) -> session in that slot (if any)
    let slots: [Int: TimetableSession]

    private enum CodingKeys: String, CodingKey { case name, time, slots }
}

/// The whole weekly timetable.
struct Timetable: Codable {
    let periods: [TimetablePeriod]

    var allSessions: [TimetableSession] {
        periods.flatMap { $0.slots.values }
    }

    /// Distinct courses (deduplicated by name+teacher) for a simple list view.
    var courseSummaries: [CourseSummary] {
        var seen: [String: CourseSummary] = [:]
        for s in allSessions {
            let key = s.courseName + s.instructor
            if var existing = seen[key] {
                existing.sessions.append(s)
                seen[key] = existing
            } else {
                seen[key] = CourseSummary(
                    courseName: s.courseName,
                    instructor: s.instructor,
                    classGroup: s.classGroup,
                    sessions: [s]
                )
            }
        }
        return seen.values.sorted { $0.courseName < $1.courseName }
    }

    var isEmpty: Bool { allSessions.isEmpty }
}

struct CourseSummary: Identifiable {
    let id = UUID()
    let courseName: String
    let instructor: String
    let classGroup: String
    var sessions: [TimetableSession]

    var classrooms: String {
        Array(Set(sessions.map(\.classroom))).filter { !$0.isEmpty }.sorted().joined(separator: ", ")
    }

    /// e.g. "週一 1-2、週三 5"
    var scheduleText: String {
        let names = ["", "週一", "週二", "週三", "週四", "週五", "週六", "週日"]
        let grouped = Dictionary(grouping: sessions, by: \.weekday)
        return grouped.keys.sorted().map { wd in
            let periods = grouped[wd]!.map(\.periodName).joined(separator: ",")
            return "\(names[safe: wd] ?? "")\(periods)"
        }.joined(separator: "、")
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
