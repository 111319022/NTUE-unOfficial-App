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

    static let base = "https://md.ntue.edu.tw"
    private static let clientId = "kunhpdgx"
    private static let redirectURI = "https://md.ntue.edu.tw/auth/ntue/land.php"

    // MARK: - Session

    /// Ensures a live Moodle session and returns its sesskey, logging in with the
    /// saved credentials if needed. Concurrent callers share one establishment.
    private func ensureSession() async throws -> String {
        if let task = sessionTask { return try await task.value }
        let task = Task { try await establishSession() }
        sessionTask = task
        defer { sessionTask = nil }   // clear once done so the next call re-validates
        return try await task.value
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

    private func ajax(_ method: String, args: [String: Any], sesskey: String) async throws -> [String: Any] {
        let url = "\(Self.base)/lib/ajax/service.php?sesskey=\(sesskey)&info=\(method)"
        let payload: [[String: Any]] = [["index": 0, "methodname": method, "args": args]]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let data = try await client.postJSON(url, json: body, referer: "\(Self.base)/my/")
        guard let arr = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let first = arr.first else { throw MoodleError.badResponse }
        if let isError = first["error"] as? Bool, isError {
            let msg = (first["exception"] as? [String: Any])?["message"] as? String
            throw MoodleError.service(msg ?? "Moodle 服務錯誤")
        }
        return first["data"] as? [String: Any] ?? [:]
    }

    // MARK: - 首頁: upcoming deadlines (lightweight, single request)

    /// Outstanding assignment deadlines (submitted ones are auto-excluded by Moodle).
    /// Includes recently-overdue-but-unsubmitted by looking a little into the past.
    func loadUpcomingDeadlines(limit: Int = 20) async throws -> [MoodleDeadline] {
        let sk = try await ensureSession()
        let from = Int(Date().timeIntervalSince1970) - 30 * 86_400
        let data = try await ajax(
            "core_calendar_get_action_events_by_timesort",
            args: ["limitnum": limit, "timesortfrom": from, "limittononsuspendedevents": true],
            sesskey: sk
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

    func loadCourseAssignments(for selection: SemesterSelection? = nil) async throws -> AssignmentsPage {
        let sk = try await ensureSession()
        let allCourses = try await fetchEnrolledCourses(sesskey: sk)
        let semesters = availableSemesters(allCourses)
        let target = selection ?? semesters.last
        let scoped = courses(allCourses, in: target)

        let result = try await withThrowingTaskGroup(of: MoodleCourseAssignments.self) { group in
            for course in scoped {
                group.addTask {
                    let html = (try? await NTUEClient.shared.get("\(Self.base)/mod/assign/index.php?id=\(course.id)")) ?? ""
                    let assignments = MoodleParser.assignments(fromIndex: html)
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
        let sk = try await ensureSession()
        let allCourses = try await fetchEnrolledCourses(sesskey: sk)
        let semesters = availableSemesters(allCourses)
        let target = selection ?? semesters.last
        let scoped = courses(allCourses, in: target)

        let result = try await withThrowingTaskGroup(of: [MoodleAnnouncement].self) { group in
            for course in scoped {
                group.addTask {
                    let courseHTML = (try? await NTUEClient.shared.get("\(Self.base)/course/view.php?id=\(course.id)")) ?? ""
                    guard let forumId = MoodleParser.announcementForumId(fromCoursePage: courseHTML) else { return [] }
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

    private func fetchEnrolledCourses(sesskey: String) async throws -> [MoodleCourse] {
        let data = try await ajax(
            "core_course_get_enrolled_courses_by_timeline_classification",
            args: ["offset": 0, "limit": 0, "classification": "all", "sort": "fullname"],
            sesskey: sesskey
        )
        let courses = data["courses"] as? [[String: Any]] ?? []
        return courses.compactMap { c in
            guard let id = c["id"] as? Int, let full = c["fullname"] as? String else { return nil }
            return MoodleCourse(id: id, fullName: full, shortName: (c["shortname"] as? String) ?? "")
        }
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
