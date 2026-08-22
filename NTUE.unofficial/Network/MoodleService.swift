import Foundation

enum MoodleError: LocalizedError {
    case notLoggedIn
    case sessionExpired
    case badResponse
    case service(String)

    var errorDescription: String? {
        switch self {
        case .notLoggedIn: return "尚未登入，請重新登入"
        case .sessionExpired: return "Moodle 登入已過期"
        case .badResponse: return "Moodle 回應格式異常"
        case .service(let m): return m
        }
    }
}

/// Talks to md.ntue.edu.tw (Moodle). Login reuses the校園入口網 OIDC flow with
/// Moodle's own client; data comes from Moodle's AJAX web service (clean JSON)
/// and the per-course assignment index page (HTML).
actor MoodleService {
    static let shared = MoodleService()
    private let client = NTUEClient.shared

    /// In-flight session establishment, shared so concurrent callers (e.g. the
    /// 作業/截止/公告 prefetch firing at once) don't each kick off their own
    /// OIDC login — concurrent logins race on cookies and the portal rejects
    /// duplicate logins with a 4xx (→ NSURLError -1011).
    private var sessionTask: Task<String, Error>?

    /// 這次登入的 sesskey。它在整個登入期間都不變,但原本每一次操作(首頁截止、
    /// 作業、公告)都為了拿它重抓一次 `/my/` 整頁 —— 快取起來就少掉那一趟。
    /// 真的過期時由 `ajax` 收到 Moodle 的 invalidsesskey 後清掉重建。
    private var cachedSesskey: String?

    /// 修課清單。作業和公告要的是同一份,原本各抓各的,預抓時等於白跑一趟。
    /// 加退選期間可能會變,所以給一個短 TTL 而不是一路快取到關 App。
    private var cachedCourses: [MoodleCourse]?
    private var coursesFetchedAt: Date?
    private static let coursesTTL: TimeInterval = 600

    /// 課程 id → 公告討論區 id。forum id 是課程本身的固定屬性,跟登入無關,
    /// 查過就一直有效 —— 公告頁原本每門課都得先抓一次課程頁才知道它。
    private enum ForumLookup { case id(Int), missing }
    private var announcementForums: [Int: ForumLookup] = [:]

    static let base = "https://md.ntue.edu.tw"
    private static let clientId = "kunhpdgx"
    private static let redirectURI = "https://md.ntue.edu.tw/auth/ntue/land.php"

    // MARK: - Session

    /// Ensures a live Moodle session and returns its sesskey, logging in with the
    /// saved credentials if needed. Concurrent callers share one establishment.
    private func ensureSession() async throws -> String {
        if let cachedSesskey { return cachedSesskey }              // 免掉一次 /my/ 整頁
        if let task = sessionTask { return try await task.value }  // 併發的呼叫共用同一次建立
        let task = Task { try await establishSession() }
        sessionTask = task
        defer { sessionTask = nil }
        let sesskey = try await task.value
        cachedSesskey = sesskey
        return sesskey
    }

    /// sesskey 失效時整組丟掉,下一次 `ensureSession()` 會重新登入。
    /// forum id 不用清 —— 那是課程的固定屬性,跟這次登入無關。
    private func invalidateSession() {
        cachedSesskey = nil
        cachedCourses = nil
        coursesFetchedAt = nil
    }

    private func establishSession() async throws -> String {
        if let sk = try? await fetchSesskey() { return sk }
        // Session missing/expired → re-login with the credentials saved at iNTUE login.
        guard let user = KeychainHelper.load(key: "ntue_username"),
              let pass = KeychainHelper.load(key: "ntue_password") else {
            throw MoodleError.notLoggedIn
        }
        try await AuthService.performOIDCLogin(
            client: client, username: user, password: pass,
            clientId: Self.clientId, redirectURI: Self.redirectURI
        )
        guard let sk = try? await fetchSesskey() else { throw MoodleError.sessionExpired }
        return sk
    }

    private func fetchSesskey() async throws -> String {
        let html = try await client.get("\(Self.base)/my/")
        guard MoodleParser.isLoggedIn(html), let sk = MoodleParser.sesskey(from: html) else {
            throw MoodleError.sessionExpired
        }
        return sk
    }

    // MARK: - AJAX

    /// 送一次 AJAX。sesskey 是快取下來的,所以這裡要負責在它失效時重新登入再試
    /// 一次 —— 少了這層,快取一旦過期就會一直失敗到重開 App。
    /// 三個對外入口(截止日 / 作業 / 公告)都會先經過 AJAX 才去抓 HTML 頁,
    /// 所以這一層等於幫後面的頁面請求也驗好了 session。
    private func ajax(_ method: String, args: [String: Any]) async throws -> [String: Any] {
        do {
            return try await ajaxOnce(method, args: args, sesskey: try await ensureSession())
        } catch MoodleError.sessionExpired {
            invalidateSession()
            return try await ajaxOnce(method, args: args, sesskey: try await ensureSession())
        }
    }

    private func ajaxOnce(_ method: String, args: [String: Any], sesskey: String) async throws -> [String: Any] {
        let url = "\(Self.base)/lib/ajax/service.php?sesskey=\(sesskey)&info=\(method)"
        let payload: [[String: Any]] = [["index": 0, "methodname": method, "args": args]]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let data = try await client.postJSON(url, json: body, referer: "\(Self.base)/my/")

        // 回的不是 JSON 陣列,通常代表被導回登入頁 → 當成 session 過期讓上層重試。
        guard let arr = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]],
              let first = arr.first else { throw MoodleError.sessionExpired }

        if let isError = first["error"] as? Bool, isError {
            let exception = first["exception"] as? [String: Any]
            let code = (exception?["errorcode"] as? String) ?? ""
            // 只有這幾個錯誤碼值得重登;其他是真的服務錯誤,重試也沒用。
            if ["invalidsesskey", "servicerequireslogin", "requireloginerror"].contains(code) {
                throw MoodleError.sessionExpired
            }
            throw MoodleError.service((exception?["message"] as? String) ?? "Moodle 服務錯誤")
        }
        return first["data"] as? [String: Any] ?? [:]
    }

    // MARK: - 首頁: upcoming deadlines (lightweight, single request)

    /// Outstanding assignment deadlines (submitted ones are auto-excluded by Moodle).
    /// Includes recently-overdue-but-unsubmitted by looking a little into the past.
    func loadUpcomingDeadlines(limit: Int = 20) async throws -> [MoodleDeadline] {
        let from = Int(Date().timeIntervalSince1970) - 30 * 86_400
        let data = try await ajax(
            "core_calendar_get_action_events_by_timesort",
            args: ["limitnum": limit, "timesortfrom": from, "limittononsuspendedevents": true]
        )
        let events = data["events"] as? [[String: Any]] ?? []
        return events.compactMap { e in
            guard let id = e["id"] as? Int,
                  let timesort = e["timesort"] as? Int,
                  let urlStr = e["url"] as? String, let url = URL(string: urlStr) else { return nil }
            let name = (e["activityname"] as? String) ?? (e["name"] as? String) ?? "作業"
            let courseName = courseDisplayName((e["course"] as? [String: Any])?["fullname"] as? String)
            return MoodleDeadline(
                id: id,
                name: cleanDeadlineName(name),
                courseName: courseName,
                due: Date(timeIntervalSince1970: TimeInterval(timesort)),
                overdue: (e["overdue"] as? Bool) ?? false,
                url: url
            )
        }
        .sorted { $0.due < $1.due }
    }

    // MARK: - 作業 tab: every assignment per course, by semester

    struct AssignmentsPage: Sendable, Codable {
        var courses: [MoodleCourseAssignments]
        var semesters: [SemesterSelection]
        var selected: SemesterSelection?
    }

    /// 修課清單在 TTL 內是走快取的,那時候 `ajax` 不會跑,也就沒人幫忙驗
    /// session —— 底下抓課程頁時才會發現登入掉了。所以這裡再包一層:碰到
    /// session 過期就清掉快取、重登,整個流程再跑一次。
    func loadCourseAssignments(for selection: SemesterSelection? = nil) async throws -> AssignmentsPage {
        do {
            return try await assignmentsPage(for: selection)
        } catch MoodleError.sessionExpired {
            invalidateSession()
            return try await assignmentsPage(for: selection)
        }
    }

    private func assignmentsPage(for selection: SemesterSelection?) async throws -> AssignmentsPage {
        let allCourses = try await fetchEnrolledCourses()
        let semesters = availableSemesters(allCourses)
        let target = selection ?? semesters.last
        let scoped = courses(allCourses, in: target)

        let result = try await withThrowingTaskGroup(of: MoodleCourseAssignments.self) { group in
            for course in scoped {
                group.addTask {
                    let html = (try? await NTUEClient.shared.get("\(Self.base)/mod/assign/index.php?id=\(course.id)")) ?? ""
                    // 登入掉了會拿回登入頁,解析出來剛好是「沒有作業」—— 那是最糟的
                    // 失敗方式(看起來像正常結果)。明確認出來,交給上層重登重試。
                    if !html.isEmpty, !MoodleParser.isLoggedIn(html) { throw MoodleError.sessionExpired }
                    var seen = Set<Int>()
                    let assignments = MoodleParser.assignments(fromIndex: html)
                        .filter { seen.insert($0.id).inserted }   // unique module ids → safe List diff
                        .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
                    return MoodleCourseAssignments(course: course, assignments: assignments)
                }
            }
            var out: [MoodleCourseAssignments] = []
            for try await item in group { out.append(item) }
            return out.sorted {
                if $0.outstandingCount != $1.outstandingCount { return $0.outstandingCount > $1.outstandingCount }
                return $0.course.displayName < $1.course.displayName
            }
        }
        return AssignmentsPage(courses: result, semesters: semesters, selected: target)
    }

    // MARK: - 課程公告

    struct AnnouncementsPage: Sendable, Codable {
        var announcements: [MoodleAnnouncement]
        var semesters: [SemesterSelection]
        var selected: SemesterSelection?
    }

    func loadAnnouncements(for selection: SemesterSelection? = nil) async throws -> AnnouncementsPage {
        do {
            return try await announcementsPage(for: selection)
        } catch MoodleError.sessionExpired {
            invalidateSession()
            return try await announcementsPage(for: selection)
        }
    }

    private func announcementsPage(for selection: SemesterSelection?) async throws -> AnnouncementsPage {
        let allCourses = try await fetchEnrolledCourses()
        let semesters = availableSemesters(allCourses)
        let target = selection ?? semesters.last
        let scoped = courses(allCourses, in: target)

        let result = try await withThrowingTaskGroup(of: [MoodleAnnouncement].self) { group in
            for course in scoped {
                group.addTask {
                    guard let forumId = try await self.announcementForumID(for: course) else { return [] }
                    let forumHTML = (try? await NTUEClient.shared.get("\(Self.base)/mod/forum/view.php?id=\(forumId)")) ?? ""
                    return MoodleParser.announcements(courseName: course.displayName, fromForum: forumHTML)
                }
            }
            var out: [MoodleAnnouncement] = []
            for try await items in group { out.append(contentsOf: items) }
            return out.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        }
        return AnnouncementsPage(announcements: result, semesters: semesters, selected: target)
    }

    /// 課程的公告討論區 id。查過就記著 —— 這個 id 不會變,但原本每次開公告頁
    /// 都要為了它把每一門課的課程頁重抓一遍(每門課多一趟)。
    private func announcementForumID(for course: MoodleCourse) async throws -> Int? {
        switch announcementForums[course.id] {
        case .id(let id): return id
        case .missing: return nil
        case nil: break
        }
        let html = (try? await NTUEClient.shared.get("\(Self.base)/course/view.php?id=\(course.id)")) ?? ""
        // 登入頁也「沒有公告區」—— 不認出來就會把它記成 .missing,之後就算重登
        // 也永遠不再查這門課了。
        if !html.isEmpty, !MoodleParser.isLoggedIn(html) { throw MoodleError.sessionExpired }
        guard let id = MoodleParser.announcementForumId(fromCoursePage: html) else {
            // 抓到頁面但沒有公告區 → 記成「沒有」;抓失敗(空字串)不記,下次重試。
            if !html.isEmpty { announcementForums[course.id] = .missing }
            return nil
        }
        announcementForums[course.id] = .id(id)
        return id
    }

    /// 修課清單。作業和公告共用同一份,TTL 內不重抓。
    private func fetchEnrolledCourses() async throws -> [MoodleCourse] {
        if let cachedCourses, let at = coursesFetchedAt,
           Date().timeIntervalSince(at) < Self.coursesTTL {
            return cachedCourses
        }
        let data = try await ajax(
            "core_course_get_enrolled_courses_by_timeline_classification",
            args: ["offset": 0, "limit": 0, "classification": "all", "sort": "fullname"]
        )
        let courses = data["courses"] as? [[String: Any]] ?? []
        let parsed = courses.compactMap { c -> MoodleCourse? in
            guard let id = c["id"] as? Int, let full = c["fullname"] as? String else { return nil }
            return MoodleCourse(id: id, fullName: full, shortName: (c["shortname"] as? String) ?? "")
        }
        // De-dup by course id: Moodle can return the same course twice when the
        // user has multiple enrolment instances / meta-linked roles. Duplicate
        // ids would crash the 作業 List's animated diff (UICollectionView assertion).
        var seen = Set<Int>()
        let unique = parsed.filter { seen.insert($0.id).inserted }
        cachedCourses = unique
        coursesFetchedAt = Date()
        return unique
    }

    /// The 上/下學期 present among the enrolled courses (course prefix `1142` →
    /// 114 學年 第 2 學期), ordered oldest → newest.
    private func availableSemesters(_ courses: [MoodleCourse]) -> [SemesterSelection] {
        let codes = Set(courses.map(\.semesterCode)).filter { $0.count == 4 }
        let sels = codes.map { SemesterSelection(year: String($0.prefix(3)), semester: String($0.suffix(1))) }
        return SemesterSelection.ordered(sels)
    }

    /// Courses belonging to the given semester (defaults to all if unknown).
    private func courses(_ courses: [MoodleCourse], in selection: SemesterSelection?) -> [MoodleCourse] {
        guard let selection else { return courses }
        let code = selection.year + selection.semester
        return courses.filter { $0.semesterCode == code }
    }

    // MARK: - Name helpers

    private func courseDisplayName(_ fullName: String?) -> String {
        guard let fullName else { return "" }
        return MoodleCourse(id: 0, fullName: fullName, shortName: "").displayName
    }

    /// Strips the Moodle "：到期" / ":due" suffix the calendar appends.
    private func cleanDeadlineName(_ name: String) -> String {
        var n = name
        for suffix in ["：到期", ":到期", "：開始", ":開始"] {
            if n.hasSuffix(suffix) { n = String(n.dropLast(suffix.count)) }
        }
        return n.trimmingCharacters(in: .whitespaces)
    }
}
