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
    private var assignmentsTask: Task<MoodleService.AssignmentsPage, Error>?
    private var announcementsTask: Task<MoodleService.AnnouncementsPage, Error>?

    /// Last-known snapshots, hydrated from disk at launch so screens paint
    /// instantly while a fresh fetch runs in the background.
    private(set) var cachedTimetable: Timetable?
    private(set) var cachedDeadlines: [MoodleDeadline]?
    private(set) var cachedGrades: NTUEService.GradesPage?
    private(set) var cachedAssignments: MoodleService.AssignmentsPage?
    private(set) var cachedAnnouncements: MoodleService.AnnouncementsPage?

    private init() {
        cachedTimetable = Persistence.load(Timetable.self, for: .timetable)
        cachedDeadlines = Persistence.load([MoodleDeadline].self, for: .moodleDeadlines)
        cachedGrades = Persistence.load(NTUEService.GradesPage.self, for: .grades)
        cachedAssignments = Persistence.load(MoodleService.AssignmentsPage.self, for: .moodleAssignments)
        cachedAnnouncements = Persistence.load(MoodleService.AnnouncementsPage.self, for: .moodleAnnouncements)
    }

    // MARK: - Accessors (cached, with in-flight de-duplication)

    func timetable(studentId: String, forceReload: Bool = false) async throws -> NTUEService.SchedulePage {
        if forceReload { timetableTask = nil }
        // Use the current academic semester explicitly — in summer the school's
        // own default drifts to the upcoming (empty) term, which used to leave a
        // stale timetable on screen.
        let task = timetableTask ?? Task { try await service.loadTimetable(for: NTUETerm.currentSemester(), studentId: studentId) }
        timetableTask = task
        do {
            let page = try await task.value
            if page.timetable.isEmpty {
                // Likely a logged-out redirect — don't cache; let the next call retry.
                timetableTask = nil
            } else {
                cachedTimetable = page.timetable
                Persistence.save(page.timetable, for: .timetable)
                WidgetBridge.update(timetable: page.timetable, deadlines: cachedDeadlines)
            }
            return page
        } catch {
            timetableTask = nil
            throw error
        }
    }

    func grades(forceReload: Bool = false) async throws -> NTUEService.GradesPage {
        if forceReload { gradesTask = nil }
        let task = gradesTask ?? Task { try await service.loadGrades(for: nil) }
        gradesTask = task
        do {
            let page = try await task.value
            // An empty default semester usually means a logged-out redirect —
            // don't persist it; let the next call retry.
            if page.grades.isEmpty {
                gradesTask = nil
            } else {
                cachedGrades = page
                Persistence.save(page, for: .grades)
            }
            return page
        } catch {
            gradesTask = nil
            throw error
        }
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
                WidgetBridge.update(timetable: cachedTimetable, deadlines: result)
            }
            return result
        } catch {
            deadlinesTask = nil
            throw error
        }
    }

    func moodleAssignments(forceReload: Bool = false) async throws -> MoodleService.AssignmentsPage {
        if forceReload { assignmentsTask = nil }
        let task = assignmentsTask ?? Task { try await MoodleService.shared.loadCourseAssignments() }
        assignmentsTask = task
        do {
            let page = try await task.value
            // No semesters means the enrolled-course list came back empty — a
            // dropped session rather than "no assignments"; don't persist it.
            if page.semesters.isEmpty {
                assignmentsTask = nil
            } else {
                cachedAssignments = page
                Persistence.save(page, for: .moodleAssignments)
            }
            return page
        } catch {
            assignmentsTask = nil
            throw error
        }
    }

    func moodleAnnouncements(forceReload: Bool = false) async throws -> MoodleService.AnnouncementsPage {
        if forceReload { announcementsTask = nil }
        let task = announcementsTask ?? Task { try await MoodleService.shared.loadAnnouncements() }
        announcementsTask = task
        do {
            let page = try await task.value
            // Empty `announcements` is legitimate (nothing posted); guard on the
            // enrolled-course-derived `semesters` to detect a dropped session.
            if page.semesters.isEmpty {
                announcementsTask = nil
            } else {
                cachedAnnouncements = page
                Persistence.save(page, for: .moodleAnnouncements)
            }
            return page
        } catch {
            announcementsTask = nil
            throw error
        }
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
        cachedGrades = nil
        cachedAssignments = nil
        cachedAnnouncements = nil
        Persistence.clearAll()
        WidgetBridge.update(timetable: nil, deadlines: nil)
        LiveActivityController.shared.end()
    }
}
