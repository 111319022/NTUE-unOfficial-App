import Foundation

/// Lean, dependency-free data shared between the main app and the widget /
/// Live Activity extension. Deliberately decoupled from the app's network
/// models (Timetable, MoodleDeadline, …) so the widget target never has to
/// pull in SwiftSoup or the networking layer — the app converts its rich
/// models into these flat DTOs when it writes the snapshot.

/// One concrete, dated class session (the weekly timetable expanded onto a
/// real calendar day).
struct ClassSlot: Codable, Hashable, Identifiable {
    let courseName: String
    let classroom: String
    let instructor: String
    let start: Date
    let end: Date

    var id: String { "\(courseName)|\(start.timeIntervalSince1970)" }
}

/// One upcoming assignment deadline.
struct AssignmentItem: Codable, Hashable, Identifiable {
    let id: Int
    let name: String
    let courseName: String
    let due: Date
}

/// Everything the widgets / Live Activity need, written by the app into the
/// shared App Group container.
struct WidgetSnapshot: Codable {
    /// When the app last wrote this snapshot.
    let generatedAt: Date
    /// Upcoming class sessions (today + the next several days), sorted by start.
    let classes: [ClassSlot]
    /// Upcoming assignments, sorted by due date.
    let assignments: [AssignmentItem]

    static let empty = WidgetSnapshot(generatedAt: .distantPast, classes: [], assignments: [])
}

// MARK: - Derived queries (pure, usable from either target)

extension WidgetSnapshot {
    /// The class in progress right now, if any.
    func currentClass(at now: Date = Date()) -> ClassSlot? {
        classes.first { $0.start <= now && now < $0.end }
    }

    /// The next class that hasn't started yet.
    func nextClass(after now: Date = Date()) -> ClassSlot? {
        classes
            .filter { $0.start > now }
            .min { $0.start < $1.start }
    }

    /// Today's classes that haven't finished yet (includes the current one),
    /// in chronological order — the chain a Live Activity counts through.
    func remainingToday(at now: Date = Date(), calendar: Calendar = .current) -> [ClassSlot] {
        classes
            .filter { calendar.isDate($0.start, inSameDayAs: now) && $0.end > now }
            .sorted { $0.start < $1.start }
    }

    /// Assignments still due in the future, soonest first.
    func upcomingAssignments(at now: Date = Date()) -> [AssignmentItem] {
        assignments
            .filter { $0.due > now }
            .sorted { $0.due < $1.due }
    }
}
