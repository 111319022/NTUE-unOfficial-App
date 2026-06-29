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

    private let service = NTUEService.shared

    private var timetableTask: Task<NTUEService.SchedulePage, Error>?
    private var gradesTask: Task<NTUEService.GradesPage, Error>?
    private var deadlinesTask: Task<[MoodleDeadline], Error>?
    private var assignmentsTask: Task<[MoodleCourseAssignments], Error>?
    private var announcementsTask: Task<[MoodleAnnouncement], Error>?

    /// Last-known snapshots, hydrated from disk at launch so screens paint
    /// instantly while a fresh fetch runs in the background.
    private(set) var cachedTimetable: Timetable?
    private(set) var cachedDeadlines: [MoodleDeadline]?

    private init() {
        cachedTimetable = Persistence.load(Timetable.self, for: .timetable)
        cachedDeadlines = Persistence.load([MoodleDeadline].self, for: .moodleDeadlines)
    }

    // MARK: - Accessors (cached, with in-flight de-duplication)

    func timetable(studentId: String, forceReload: Bool = false) async throws -> NTUEService.SchedulePage {
        if forceReload { timetableTask = nil }
        let task = timetableTask ?? Task { try await service.loadTimetable(for: nil, studentId: studentId) }
        timetableTask = task
        do {
            let page = try await task.value
            if page.timetable.isEmpty {
                // Likely a logged-out redirect — don't cache; let the next call retry.
                timetableTask = nil
            } else {
                cachedTimetable = page.timetable
                Persistence.save(page.timetable, for: .timetable)
            }
            return page
        } catch {
            timetableTask = nil
            throw error
        }
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
        let task = deadlinesTask ?? Task { try await MoodleService.shared.loadUpcomingDeadlines(limit: 12) }
        deadlinesTask = task
        do {
            let result = try await task.value
            if result.isEmpty {
                // Empty can mean "no homework" or a dropped session — don't persist; allow retry.
                deadlinesTask = nil
            } else {
                cachedDeadlines = result
                Persistence.save(result, for: .moodleDeadlines)
            }
            return result
        } catch {
            deadlinesTask = nil
            throw error
        }
    }

    func moodleAssignments(forceReload: Bool = false) async throws -> [MoodleCourseAssignments] {
        if forceReload { assignmentsTask = nil }
        if let task = assignmentsTask { return try await awaiting(task) { self.assignmentsTask = nil } }
        let task = Task { try await MoodleService.shared.loadCourseAssignments() }
        assignmentsTask = task
        return try await awaiting(task) { self.assignmentsTask = nil }
    }

    func moodleAnnouncements(forceReload: Bool = false) async throws -> [MoodleAnnouncement] {
        if forceReload { announcementsTask = nil }
        let task = announcementsTask ?? Task { try await MoodleService.shared.loadAnnouncements() }
        announcementsTask = task
        return try await awaiting(task) { self.announcementsTask = nil }
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
        Task { _ = try? await moodleAnnouncements() }
    }

    func clear() {
        timetableTask?.cancel(); timetableTask = nil
        gradesTask?.cancel(); gradesTask = nil
        deadlinesTask?.cancel(); deadlinesTask = nil
        assignmentsTask?.cancel(); assignmentsTask = nil
        announcementsTask?.cancel(); announcementsTask = nil
        cachedTimetable = nil
        cachedDeadlines = nil
        Persistence.clearAll()
    }
}
