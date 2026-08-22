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

    /// `cachedTimetable` 是哪個學期的。學期初學校還沒把新學期的課表放上來時,
    /// 這裡拿到的是空的,我們不會用空資料覆寫快取 —— 所以得記著手上這份其實
    /// 是「上學期」的,首頁/小工具/上課提醒才不會把上學期的課當成今天的課。
    /// `nil` = 舊版留下來的快取,不知道是哪學期。
    private(set) var cachedTimetableSemester: String?

    /// 手上的課表是不是本學期的。不知道就當作是 —— 寧可顯示可能過期的課表,
    /// 也不要平白清空一份真的資料(和 `AcademicCalendar.isInSession` 同一套邏輯)。
    var cachedTimetableIsCurrent: Bool {
        cachedTimetableSemester.map { $0 == NTUETerm.currentSemester().id } ?? true
    }

    /// 給小工具、Live Activity、上課提醒用的課表:只有確定是本學期的才算數。
    /// 學期初學校還沒放新課表時回 `nil`,寧可空著也不要排上學期的課。
    var currentSemesterTimetable: Timetable? {
        cachedTimetableIsCurrent ? cachedTimetable : nil
    }

    private init() {
        cachedTimetable = Persistence.load(Timetable.self, for: .timetable)
        cachedTimetableSemester = Persistence.load(String.self, for: .timetableSemester)
        cachedDeadlines = Persistence.load([MoodleDeadline].self, for: .moodleDeadlines).map(Self.currentSemesterOnly)
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
                // 但如果手上那份明明是「上學期」的,就是學校還沒放本學期課表 ——
                // 把小工具和上課提醒裡的舊課清掉(兩者都只吃本學期的課表)。
                // 登出被導回登入頁時快取仍標記為本學期,不會誤清。
                if !cachedTimetableIsCurrent {
                    WidgetBridge.updateFromCache()
                    Task { await NotificationManager.shared.refreshClassRemindersFromCache() }
                }
            } else {
                let semesterID = (page.selected ?? NTUETerm.currentSemester()).id
                cachedTimetable = page.timetable
                cachedTimetableSemester = semesterID
                Persistence.save(page.timetable, for: .timetable)
                Persistence.save(semesterID, for: .timetableSemester)
                WidgetBridge.update(timetable: page.timetable, deadlines: cachedDeadlines)
                // Re-arm 上課提醒 from the freshest timetable (no-op if the feature is off).
                Task { await NotificationManager.shared.rescheduleClassReminders(from: page.timetable) }
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
        let termStart = AcademicCalendar.currentTermStart()
        let task = deadlinesTask ?? Task {
            try await MoodleService.shared.loadUpcomingDeadlines(limit: 12, notBefore: termStart)
        }
        deadlinesTask = task
        do {
            let result = try await task.value
            if result.isEmpty {
                // Empty can mean "no homework" or a dropped session — don't persist; allow retry.
                deadlinesTask = nil
                return result
            }
            // 抓回來的是真資料(session 還在),但裡面可能還混著上學期沒交的作業
            // —— 過濾之後就算變成空的,那也是「本學期沒有待繳」的正確答案,照樣
            // 存起來,免得每次進首頁都為了同一批舊作業重抓一次。
            let current = Self.currentSemesterOnly(result)
            cachedDeadlines = current
            Persistence.save(current, for: .moodleDeadlines)
            WidgetBridge.update(timetable: currentSemesterTimetable, deadlines: current)
            // Re-arm local deadline reminders from the freshest list (no-op if off).
            Task { await NotificationManager.shared.rescheduleDeadlines(current) }
            return current
        } catch {
            deadlinesTask = nil
            throw error
        }
    }

    /// 只留本學期的作業。上學期沒交的作業會一直掛在 Moodle 的行事曆上,首頁、
    /// 小工具和提醒都不該再把它們算成「待繳」—— 那只是一排永遠消不掉的已逾期。
    private static func currentSemesterOnly(_ list: [MoodleDeadline]) -> [MoodleDeadline] {
        let currentTermCode = NTUETerm.currentSemester().termCode
        let termStart = AcademicCalendar.currentTermStart()
        return list.filter { !$0.belongsToPastSemester(currentTermCode: currentTermCode, termStart: termStart) }
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
    ///
    /// 標成 `.background`:學校端一次只跑得動一個請求,預抓一次丟五個會把使用者
    /// 當下按的那一個擠到最後面等好幾十秒。降級之後,使用者一按就插隊到前面
    /// (見 `RequestQueue`),預抓則利用剩下的空檔慢慢跑完。
    func prefetch(studentId: String) {
        RequestQueue.$priority.withValue(.background) {
            Task { _ = try? await timetable(studentId: studentId) }
            Task { _ = try? await grades() }
            Task { _ = try? await moodleDeadlines() }
            Task { _ = try? await moodleAssignments() }
            Task { _ = try? await moodleAnnouncements() }
        }
    }

    func clear() {
        timetableTask?.cancel(); timetableTask = nil
        gradesTask?.cancel(); gradesTask = nil
        deadlinesTask?.cancel(); deadlinesTask = nil
        assignmentsTask?.cancel(); assignmentsTask = nil
        announcementsTask?.cancel(); announcementsTask = nil
        cachedTimetable = nil
        cachedTimetableSemester = nil
        cachedDeadlines = nil
        cachedGrades = nil
        cachedAssignments = nil
        cachedAnnouncements = nil
        Persistence.clearAll()
        WidgetBridge.update(timetable: nil, deadlines: nil)
        LiveActivityController.shared.end()
        NotificationManager.shared.clearAll()
    }
}
