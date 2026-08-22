import Foundation

enum NTUEServiceError: LocalizedError {
    case noToken
    case noTimetableLink
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .noToken: return "無法取得查詢權杖（請重新登入）"
        case .noTimetableLink: return "找不到個人課表資料"
        case .requestFailed(let m): return m
        }
    }
}

extension Error {
    /// 被取消的請求(例如使用者又切到別的學期)不算錯誤,不該跳「載入失敗」,
    /// 也不該觸發重試。
    var isRequestCancellation: Bool {
        self is CancellationError || (self as? URLError)?.code == .cancelled
    }
}

/// Orchestrates the real iNTUE query flows discovered by inspecting the site.
///
/// 每一個對外方法都整段跑在 `RequestQueue.ntue` 上,好讓使用者當下點的那個查詢
/// 能插隊到背景預抓前面(見 `RequestQueue`)。
struct NTUEService {
    static let shared = NTUEService()
    private let client = NTUEClient.shared

    private static let gradesURL = "\(NTUEClient.base)/a05/a052A0"
    private static let scheduleURL = "\(NTUEClient.base)/b04/b04250"
    private static let leaveURL = "\(NTUEClient.base)/f01/f01141"
    private static let enrollmentURL = "\(NTUEClient.base)/a02/a02280"
    private static let publicScheduleURL = "\(NTUEClient.base)/b09/b09120"
    private static let courseSelectionURL = "\(NTUEClient.base)/b04/b04250"
    private static let absenceURL = "\(NTUEClient.base)/b11/b11170"
    private static let conductURL = "\(NTUEClient.base)/f02/f02192"
    private static let rewardURL = "\(NTUEClient.base)/f02/f021b0"
    private static let officerURL = "\(NTUEClient.base)/g01/g01333"

    // MARK: - 共用:頁面抓取與帶 token 的查詢

    /// GET 一個查詢頁,順手把它的 CSRF token 與學期選單記進 session 快取,
    /// 之後同一個 session 裡的查詢就不必再為了刮這兩樣東西多打一趟。
    /// `requireToken` 時抓不到 token 就丟 `.noToken` —— 那通常代表 session 掉了、
    /// 被導回登入頁。
    /// 抓回來的查詢頁,連同「同一份 HTML 只解析一次」就取出的學期選單。
    /// `SwiftSoup.parse` 每呼叫一次就重建一次整個 DOM,呼叫端不該為了拿學期
    /// 選單再解析第二次 —— `semesters` / `defaultSemester` 直接用這裡的。
    private struct LoadedPage {
        let html: String
        let semesters: [SemesterSelection]
        let defaultSemester: SemesterSelection?
    }

    @discardableResult
    private func fetchPage(_ url: String, requireToken: Bool = false) async throws -> LoadedPage {
        let html = try await client.get(url)
        if let token = NTUEParser.csrfToken(from: html) {
            await NTUESessionCache.shared.store(token: token)
        } else if requireToken {
            throw NTUEServiceError.noToken
        }
        let (options, selected) = NTUEParser.semesterOptions(from: html)
        if !options.isEmpty {
            await NTUESessionCache.shared.store(menu: .init(options: options, selected: selected), for: url)
        }
        return LoadedPage(html: html, semesters: options, defaultSemester: selected)
    }

    /// 帶 CSRF token 送出查詢。手上已經有 token 就直接 POST —— 省下的那一趟頁面
    /// GET,正是切學期原本要多等的 ~10 秒。token 真的過期時 Laravel 回 419
    /// (`badServerResponse`),這裡才重抓頁面拿新的再試一次。
    private func post(_ url: String, form: [String: String],
                      referer: String, page: String? = nil) async throws -> String {
        func send(_ token: String) async throws -> String {
            var body = form
            body["_token"] = token
            let response = try await client.post(url, form: body, referer: referer)
            if Self.isLoginRedirect(response) { throw AuthError.sessionExpired }
            return response
        }

        if let token = await NTUESessionCache.shared.token() {
            do {
                return try await send(token)
            } catch {
                if error.isRequestCancellation { throw error }
                await NTUESessionCache.shared.invalidateToken()
            }
        }

        try await fetchPage(page ?? referer, requireToken: true)
        guard let token = await NTUESessionCache.shared.token() else { throw NTUEServiceError.noToken }
        return try await send(token)
    }

    /// session 掉了的時候,學校會把查詢 302 到校園入口網的登入頁 —— HTTP 還是
    /// 200,內容卻是登入表單。不攔下來的話,畫面會把它當成「這學期沒有資料」,
    /// 使用者只會覺得切了學期什麼都沒有,而不知道該重新登入。
    private static func isLoginRedirect(_ html: String) -> Bool {
        html.contains("mpassword") && html.contains("oauthServer")
    }

    /// 這個 session 是否已經有可用的 token(有的話就能跳過頁面 GET)。
    private var hasToken: Bool {
        get async { await NTUESessionCache.shared.token() != nil }
    }

    // MARK: - Student profile

    /// Fetches the student's basic profile (學號 / 姓名 / 系所 / 班級) from the grades page header.
    func loadStudentInfo() async -> StudentInfo {
        let page = try? await RequestQueue.ntue.run { try await fetchPage(Self.gradesURL) }
        guard let page else { return StudentInfo() }
        return NTUEParser.studentInfo(from: page.html)
    }

    // MARK: - Grades

    struct GradesPage: Codable {
        var grades: [Grade]
        var student: StudentInfo
        var semesters: [SemesterSelection]
        var selected: SemesterSelection?
    }

    /// Loads the grades page, then queries the given (or default) semester.
    func loadGrades(for selection: SemesterSelection? = nil) async throws -> GradesPage {
        try await RequestQueue.ntue.run {
            // 指定了學期、而且 token 與學期選單都還在快取裡 → 直接查,不必先抓頁面。
            if let target = selection, await hasToken,
               let menu = await NTUESessionCache.shared.menu(for: Self.gradesURL) {
                let response = try await post(Self.gradesURL, form: Self.searchForm(target), referer: Self.gradesURL)
                return GradesPage(grades: NTUEParser.grades(from: response),
                                  student: NTUEParser.studentInfo(from: response),
                                  semesters: menu.options, selected: target)
            }

            let page = try await fetchPage(Self.gradesURL, requireToken: true)
            let semesters = page.semesters
            let defaultSel = page.defaultSemester
            let student = NTUEParser.studentInfo(from: page.html)

            guard let target = selection ?? defaultSel else {
                // No semester to query — return whatever the landing page held.
                return GradesPage(grades: NTUEParser.grades(from: page.html),
                                  student: student, semesters: semesters, selected: nil)
            }

            let response = try await post(Self.gradesURL, form: Self.searchForm(target), referer: Self.gradesURL)
            let grades = NTUEParser.grades(from: response)
            // Student info sometimes only appears in the POST response.
            let mergedStudent = student.isEmpty ? NTUEParser.studentInfo(from: response) : student

            return GradesPage(grades: grades, student: mergedStudent,
                              semesters: semesters, selected: target)
        }
    }

    /// 站上大部分查詢頁共用的送出格式(`_token` 由 `post` 補上)。
    private static func searchForm(_ target: SemesterSelection, event: String = "search") -> [String: String] {
        [
            "srh[ACADYear][]": target.year,
            "srh[Semester][]": target.semester,
            "event": event,
        ]
    }

    // MARK: - Timetable

    struct SchedulePage {
        var timetable: Timetable
        var semesters: [SemesterSelection]
        var selected: SemesterSelection?
    }

    func loadTimetable(for selection: SemesterSelection? = nil, studentId: String) async throws -> SchedulePage {
        try await RequestQueue.ntue.run {
            // 這個學期的 view id 之前已經問到了 → 直接 GET 課表格線,省下「抓頁面
            // 拿 token」和「POST 拿 view id」兩趟(各約 10 秒)。抓回來是空的就當
            // 快取失效,走完整流程重來。
            let menu = await NTUESessionCache.shared.menu(for: Self.scheduleURL)
            if let target = selection ?? menu?.selected,
               let viewID = await NTUESessionCache.shared.viewID(forSemester: target.id) {
                do {
                    let html = try await client.get(Self.gridURL(viewID, target, studentId), referer: Self.scheduleURL)
                    let timetable = NTUEParser.timetable(from: html)
                    if !timetable.isEmpty {
                        return SchedulePage(timetable: timetable, semesters: menu?.options ?? [], selected: target)
                    }
                } catch {
                    if error.isRequestCancellation { throw error }
                    // view id 失效 → 落回完整流程
                }
            }
            return try await loadTimetableViaPage(selection, studentId: studentId)
        }
    }

    /// 完整流程:(必要時)抓頁面拿 token/學期 → POST 取得個人課表 view id
    /// → GET 格線。
    private func loadTimetableViaPage(_ selection: SemesterSelection?, studentId: String) async throws -> SchedulePage {
        var semesters: [SemesterSelection] = []
        var resolved = selection

        // 指定了學期、而且 token 與學期選單都還在快取裡,那一趟頁面 GET 就純粹是
        // 為了刮 token —— 直接省掉。沒指定學期時才需要它告訴我們預設是哪一學期。
        if resolved != nil, await hasToken,
           let menu = await NTUESessionCache.shared.menu(for: Self.scheduleURL) {
            semesters = menu.options
        } else {
            let page = try await fetchPage(Self.scheduleURL, requireToken: true)
            semesters = page.semesters
            resolved = resolved ?? page.defaultSemester
        }

        guard let target = resolved else {
            return SchedulePage(timetable: Timetable(periods: []), semesters: semesters, selected: nil)
        }

        // Step 1: POST to get the personal-timetable view id.
        let postResponse = try await post(Self.scheduleURL, form: Self.searchForm(target, event: "click"),
                                          referer: Self.scheduleURL)

        guard let viewId = NTUEParser.timetableViewId(from: postResponse) else {
            throw NTUEServiceError.noTimetableLink
        }

        // Step 2: GET the grid view and parse the JSON island.
        let gridHTML = try await client.get(Self.gridURL(viewId, target, studentId), referer: Self.scheduleURL)
        let timetable = NTUEParser.timetable(from: gridHTML)

        // 只有真的抓到課表才記 view id —— 空的可能是學校還沒放課表,下次要重問。
        if !timetable.isEmpty {
            await NTUESessionCache.shared.store(viewID: viewId, forSemester: target.id)
        }

        return SchedulePage(timetable: timetable, semesters: semesters, selected: target)
    }

    private static func gridURL(_ viewID: String, _ target: SemesterSelection, _ studentId: String) -> String {
        var comps = URLComponents(string: "\(scheduleURL)/v/\(viewID)")!
        comps.queryItems = [
            URLQueryItem(name: "ACADYear", value: target.year),
            URLQueryItem(name: "Semester", value: target.semester),
            URLQueryItem(name: "StudentNo", value: studentId),
        ]
        return comps.url!.absoluteString
    }

    // MARK: - Course selection (選課查詢 → 預排)

    struct CourseSelectionPage {
        var courses: [SelectedCourse]
        var semesters: [SemesterSelection]
        var selected: SemesterSelection?
    }

    /// Loads the courses selected at a given 選課 stage for the target (or the
    /// school's default — usually the upcoming) semester. The page GET yields the
    /// CSRF token + semester options; the stage tab is then POSTed with
    /// `event=search`, returning that stage's data island.
    func loadCourseSelection(stage: SelectionStage,
                             for selection: SemesterSelection? = nil) async throws -> CourseSelectionPage {
        try await RequestQueue.ntue.run {
            // 切學期 / 切階段時 token 與學期選單都已在快取 → 直接查。
            if let target = selection, await hasToken,
               let menu = await NTUESessionCache.shared.menu(for: Self.courseSelectionURL) {
                let response = try await post(Self.courseSelectionURL + stage.pathSuffix,
                                              form: Self.searchForm(target),
                                              referer: Self.courseSelectionURL,
                                              page: Self.courseSelectionURL)
                return CourseSelectionPage(courses: NTUEParser.selectedCourses(from: response),
                                           semesters: menu.options, selected: target)
            }

            let page = try await fetchPage(Self.courseSelectionURL, requireToken: true)
            let semesters = page.semesters
            let defaultSel = page.defaultSemester
            guard let target = selection ?? defaultSel else {
                return CourseSelectionPage(courses: [], semesters: semesters, selected: nil)
            }

            let response = try await post(Self.courseSelectionURL + stage.pathSuffix,
                                          form: Self.searchForm(target),
                                          referer: Self.courseSelectionURL,
                                          page: Self.courseSelectionURL)

            return CourseSelectionPage(courses: NTUEParser.selectedCourses(from: response),
                                       semesters: semesters, selected: target)
        }
    }

    // MARK: - Leave records (請假明細)

    struct LeavePage {
        var records: [LeaveRecord]
        var semesters: [SemesterSelection]
        var selected: SemesterSelection?
    }

    func loadLeaveRecords(for selection: SemesterSelection? = nil) async throws -> LeavePage {
        try await RequestQueue.ntue.run {
            // 切到「非預設學期」而且 token/選單都在快取 → 直接 POST,省掉重頁面的 GET。
            if let target = selection, await hasToken,
               let menu = await NTUESessionCache.shared.menu(for: Self.leaveURL),
               let defaultSel = menu.selected, defaultSel.id != target.id {
                let response = try await post(Self.leaveURL, form: Self.leaveForm(target), referer: Self.leaveURL)
                return LeavePage(records: NTUEParser.leaveRecords(from: response),
                                 semesters: menu.options, selected: target)
            }

            // NOTE: f01141 is a heavy page (~10s server-side). Its plain GET already
            // contains the records for the *default* (current) semester, so we avoid
            // an extra ~8s POST unless the user actually switches to another semester.
            let page = try await fetchPage(Self.leaveURL)
            let semesters = page.semesters
            let defaultSel = page.defaultSemester
            let target = selection ?? defaultSel

            // Default semester (or no selector): use the records already in the GET.
            if target == nil || target?.id == defaultSel?.id {
                return LeavePage(records: NTUEParser.leaveRecords(from: page.html),
                                 semesters: semesters, selected: target ?? defaultSel)
            }

            guard await hasToken, let target else {
                return LeavePage(records: NTUEParser.leaveRecords(from: page.html),
                                 semesters: semesters, selected: defaultSel)
            }

            let response = try await post(Self.leaveURL, form: Self.leaveForm(target), referer: Self.leaveURL)
            return LeavePage(records: NTUEParser.leaveRecords(from: response),
                             semesters: semesters, selected: target)
        }
    }

    private static func leaveForm(_ target: SemesterSelection) -> [String: String] {
        var form = searchForm(target)
        form["srh[SignStatus][]"] = ""
        return form
    }

    // MARK: - 缺曠 / 操行 / 獎懲 (GET serves the current semester inline)

    /// 缺曠 for the given (or current) semester. The GET already holds the current
    /// semester; only a switch to another semester needs the (slow) POST.
    func loadAbsences(for selection: SemesterSelection? = nil) async throws -> [AbsenceRecord] {
        try await RequestQueue.ntue.run {
            // 已經知道本學期是哪一個,而且要看的不是它 → 直接 POST。
            if let target = selection, await hasToken,
               let menu = await NTUESessionCache.shared.menu(for: Self.absenceURL),
               let current = menu.selected, current.id != target.id {
                let response = try await post(Self.absenceURL, form: Self.absenceForm(target), referer: Self.absenceURL)
                return NTUEParser.absenceRecords(from: response)
            }

            let page = try await fetchPage(Self.absenceURL)
            let current = NTUEParser.selectedSemester(from: page.html,
                                                      yearSelect: "srh[ACADYearSrh][]",
                                                      semesterSelect: "srh[SemesterSrh][]")
            // 這一頁的下拉欄位名稱和其他頁不同,`fetchPage` 記不到,這裡補記。
            if let current {
                await NTUESessionCache.shared.store(menu: .init(options: [], selected: current), for: Self.absenceURL)
            }

            if selection == nil || selection?.id == current?.id {
                return NTUEParser.absenceRecords(from: page.html)
            }
            guard await hasToken, let target = selection else {
                return NTUEParser.absenceRecords(from: page.html)
            }
            let response = try await post(Self.absenceURL, form: Self.absenceForm(target), referer: Self.absenceURL)
            return NTUEParser.absenceRecords(from: response)
        }
    }

    private static func absenceForm(_ target: SemesterSelection) -> [String: String] {
        [
            "srh[ACADYearSrh][]": target.year,
            "srh[SemesterSrh][]": target.semester,
            "event": "search",
        ]
    }

    /// 操行成績 — all semesters. The GET only serves the current term; a 全選
    /// (empty 學年/學期) search returns the full history, newest first.
    /// 手上已有 token 時連那一趟 GET 都省下來。
    func loadConductRecords() async throws -> [ConductRecord] {
        try await RequestQueue.ntue.run {
            if await hasToken == false {
                let page = try await fetchPage(Self.conductURL)
                guard await hasToken else {
                    return NTUEParser.conductRecords(from: page.html).sorted { $0.sortKey > $1.sortKey }
                }
            }
            let response = try await post(Self.conductURL, form: Self.allSemestersForm, referer: Self.conductURL)
            return NTUEParser.conductRecords(from: response).sorted { $0.sortKey > $1.sortKey }
        }
    }

    /// 獎懲紀錄 — all semesters via the same 全選 search.
    func loadRewardPenalties() async throws -> [RewardPenaltyRecord] {
        try await RequestQueue.ntue.run {
            if await hasToken == false {
                let page = try await fetchPage(Self.rewardURL)
                guard await hasToken else {
                    return NTUEParser.rewardPenaltyRecords(from: page.html).sorted { $0.sortKey > $1.sortKey }
                }
            }
            let response = try await post(Self.rewardURL, form: Self.allSemestersForm, referer: Self.rewardURL)
            return NTUEParser.rewardPenaltyRecords(from: response).sorted { $0.sortKey > $1.sortKey }
        }
    }

    /// 學年/學期留空 = 全選,拿到完整歷年紀錄。
    private static let allSemestersForm: [String: String] = [
        "srh[ACADYear][]": "",
        "srh[Semester][]": "",
        "event": "search",
    ]

    /// 擔任幹部紀錄 (g01333). The GET already lists every appointment.
    func loadOfficerRecords() async throws -> [OfficerRecord] {
        try await RequestQueue.ntue.run {
            let page = try await fetchPage(Self.officerURL)
            return NTUEParser.officerRecords(from: page.html)
        }
    }

    // MARK: - Enrollment certificate (在學證明)

    func loadEnrollmentCertificate() async throws -> EnrollmentCertificate {
        try await RequestQueue.ntue.run {
            let page = try await fetchPage(Self.enrollmentURL)
            return NTUEParser.enrollmentCertificate(from: page.html)
        }
    }

    // MARK: - Public schedule (公開課表查詢)

    func loadPublicScheduleOptions() async throws -> PublicScheduleOptions {
        try await RequestQueue.ntue.run {
            let page = try await fetchPage(Self.publicScheduleURL)
            return NTUEParser.publicScheduleOptions(from: page.html)
        }
    }

    func queryPublicSchedule(token: String, year: String, semester: String, classId: String) async throws -> [PublicCourse] {
        try await RequestQueue.ntue.run {
            let response = try await client.post(Self.publicScheduleURL, form: [
                "_token": token,
                "srh[ACADYear][]": year,
                "srh[Semester][]": semester,
                "srh[ClassID][]": classId,
                "event": "search",
            ], referer: Self.publicScheduleURL)
            return NTUEParser.publicCourses(from: response)
        }
    }

    /// Generates the official enrollment-certificate PDF and saves it to a temp
    /// file. The page returns `window.open(reportURL)`; that report server URL
    /// generates the PDF (redirecting to a /temp/*.pdf), which we download.
    /// - Parameter english: true for the English certificate (event=pdf_2),
    ///   false for the Chinese one (event=pdf_1).
    func enrollmentCertificatePDF(english: Bool) async throws -> URL {
        try await RequestQueue.ntue.run {
            try await fetchReportPDF(pageURL: Self.enrollmentURL,
                                     filename: "在學證明\(english ? "_EN" : "").pdf",
                                     form: ["event": english ? "pdf_2" : "pdf_1"])
        }
    }

    /// Downloads an already-resolved report-server PDF URL — e.g. the
    /// `window.open` target captured from a page's own print button — using the
    /// logged-in session, and saves the bytes to a temp file. Used by the
    /// 修業進度管制 headless flow, where the print button's `setSubmit(this,1,0)`
    /// can't be replicated as a plain `event=` POST.
    func downloadReportPDF(from reportURL: String, referer: String, filename: String) async throws -> URL {
        try await RequestQueue.ntue.run {
            let data = try await client.getData(reportURL, referer: referer)
            return try Self.writePDF(data, to: filename)
        }
    }

    // MARK: - Shared report-PDF download

    /// Fetches a school-generated report PDF: POST the print event (re-using the
    /// session's CSRF token when we already have one), follow the `window.open`
    /// report URL, and download the PDF bytes to a temp file.
    private func fetchReportPDF(pageURL: String, filename: String, form: [String: String]) async throws -> URL {
        let trigger = try await post(pageURL, form: form, referer: pageURL)

        guard let reportURL = NTUEParser.reportPopupURL(from: trigger) else {
            throw NTUEServiceError.requestFailed("找不到 PDF 連結")
        }
        let data = try await client.getData(reportURL, referer: pageURL)
        return try Self.writePDF(data, to: filename)
    }

    private static func writePDF(_ data: Data, to filename: String) throws -> URL {
        guard data.starts(with: [0x25, 0x50, 0x44, 0x46]) else {  // "%PDF"
            throw NTUEServiceError.requestFailed("PDF 產生失敗，請稍後再試")
        }
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try data.write(to: fileURL, options: .atomic)
        return fileURL
    }
}
