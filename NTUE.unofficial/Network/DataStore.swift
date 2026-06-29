import Foundation

/// Shared cache that lets us **prefetch** the slow school pages in the background
/// (the iNTUE server is ~10s per request) so that by the time the user opens a
/// screen the data is already there — or, if still in flight, they join the same
/// request instead of starting a second one.
///
/// Each dataset is cached as its in-flight/completed `Task`. Awaiting a cached
/// task returns instantly once it has finished; `prefetch()` simply kicks the
/// tasks off right after login.
@MainActor
@Observable
final class DataStore {
    static let shared = DataStore()
    private init() {}

    private let service = NTUEService.shared

    private var timetableTask: Task<NTUEService.SchedulePage, Error>?
    private var gradesTask: Task<NTUEService.GradesPage, Error>?
    private var deadlinesTask: Task<[MoodleDeadline], Error>?
    private var assignmentsTask: Task<[MoodleCourseAssignments], Error>?

    // MARK: - Accessors (cached, with in-flight de-duplication)

    func timetable(studentId: String, forceReload: Bool = false) async throws -> NTUEService.SchedulePage {
        if forceReload { timetableTask = nil }
        if let task = timetableTask { return try await awaiting(task) { self.timetableTask = nil } }
        let task = Task { try await service.loadTimetable(for: nil, studentId: studentId) }
        timetableTask = task
        return try await awaiting(task) { self.timetableTask = nil }
    }

    func grades(forceReload: Bool = false) async throws -> NTUEService.GradesPage {
        if forceReload { gradesTask = nil }
        if let task = gradesTask { return try await awaiting(task) { self.gradesTask = nil } }
        let task = Task { try await service.loadGrades(for: nil) }
        gradesTask = task
        return try await awaiting(task) { self.gradesTask = nil }
    }

    func moodleDeadlines(forceReload: Bool = false) async throws -> [MoodleDeadline] {
        if forceReload { deadlinesTask = nil }
        if let task = deadlinesTask { return try await awaiting(task) { self.deadlinesTask = nil } }
        let task = Task { try await MoodleService.shared.loadUpcomingDeadlines(limit: 12) }
        deadlinesTask = task
        return try await awaiting(task) { self.deadlinesTask = nil }
    }

    func moodleAssignments(forceReload: Bool = false) async throws -> [MoodleCourseAssignments] {
        if forceReload { assignmentsTask = nil }
        if let task = assignmentsTask { return try await awaiting(task) { self.assignmentsTask = nil } }
        let task = Task { try await MoodleService.shared.loadCourseAssignments() }
        assignmentsTask = task
        return try await awaiting(task) { self.assignmentsTask = nil }
    }

    /// Awaits a cached task; on failure drops it so the next caller can retry.
    private func awaiting<T>(_ task: Task<T, Error>, onFailure: @escaping () -> Void) async throws -> T {
        do { return try await task.value }
        catch { onFailure(); throw error }
    }

    // MARK: - Lifecycle

    /// Warm everything in the background right after login. Fire-and-forget;
    /// failures are ignored here (the screens surface their own errors on demand).
    func prefetch(studentId: String) {
        Task { _ = try? await timetable(studentId: studentId) }
        Task { _ = try? await grades() }
        Task { _ = try? await moodleDeadlines() }
        Task { _ = try? await moodleAssignments() }
    }

    func clear() {
        timetableTask?.cancel(); timetableTask = nil
        gradesTask?.cancel(); gradesTask = nil
        deadlinesTask?.cancel(); deadlinesTask = nil
        assignmentsTask?.cancel(); assignmentsTask = nil
    }
}
