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

/// Orchestrates the real iNTUE query flows discovered by inspecting the site.
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

    // MARK: - Student profile

    /// Fetches the student's basic profile (學號 / 姓名 / 系所 / 班級) from the grades page header.
    func loadStudentInfo() async -> StudentInfo {
        guard let page = try? await client.get(Self.gradesURL) else { return StudentInfo() }
        return NTUEParser.studentInfo(from: page)
    }

    // MARK: - Grades

    struct GradesPage {
        var grades: [Grade]
        var student: StudentInfo
        var semesters: [SemesterSelection]
        var selected: SemesterSelection?
    }

    /// Loads the grades page, then queries the given (or default) semester.
    func loadGrades(for selection: SemesterSelection? = nil) async throws -> GradesPage {
        let page = try await client.get(Self.gradesURL)
        guard let token = NTUEParser.csrfToken(from: page) else { throw NTUEServiceError.noToken }

        let (semesters, defaultSel) = NTUEParser.semesterOptions(from: page)
        let target = selection ?? defaultSel
        let student = NTUEParser.studentInfo(from: page)

        guard let target else {
            // No semester to query — return whatever the landing page held.
            return GradesPage(grades: NTUEParser.grades(from: page),
                              student: student, semesters: semesters, selected: nil)
        }

        let response = try await client.post(Self.gradesURL, form: [
            "_token": token,
            "srh[ACADYear][]": target.year,
            "srh[Semester][]": target.semester,
            "event": "search",
        ], referer: Self.gradesURL)

        let grades = NTUEParser.grades(from: response)
        // Student info sometimes only appears in the POST response.
        let mergedStudent = student.isEmpty ? NTUEParser.studentInfo(from: response) : student

        return GradesPage(grades: grades, student: mergedStudent,
                          semesters: semesters, selected: target)
    }

    // MARK: - Timetable

    struct SchedulePage {
        var timetable: Timetable
        var semesters: [SemesterSelection]
        var selected: SemesterSelection?
    }

    func loadTimetable(for selection: SemesterSelection? = nil, studentId: String) async throws -> SchedulePage {
        let page = try await client.get(Self.scheduleURL)
        guard let token = NTUEParser.csrfToken(from: page) else { throw NTUEServiceError.noToken }

        let (semesters, defaultSel) = NTUEParser.semesterOptions(from: page)
        guard let target = selection ?? defaultSel else {
            return SchedulePage(timetable: Timetable(periods: []), semesters: semesters, selected: nil)
        }

        // Step 1: POST to get the personal-timetable view id.
        let postResponse = try await client.post(Self.scheduleURL, form: [
            "_token": token,
            "srh[ACADYear][]": target.year,
            "srh[Semester][]": target.semester,
            "event": "click",
        ], referer: Self.scheduleURL)

        guard let viewId = NTUEParser.timetableViewId(from: postResponse) else {
            throw NTUEServiceError.noTimetableLink
        }

        // Step 2: GET the grid view and parse the JSON island.
        var comps = URLComponents(string: "\(Self.scheduleURL)/v/\(viewId)")!
        comps.queryItems = [
            URLQueryItem(name: "ACADYear", value: target.year),
            URLQueryItem(name: "Semester", value: target.semester),
            URLQueryItem(name: "StudentNo", value: studentId),
        ]
        let gridHTML = try await client.get(comps.url!.absoluteString, referer: Self.scheduleURL)
        let timetable = NTUEParser.timetable(from: gridHTML)

        return SchedulePage(timetable: timetable, semesters: semesters, selected: target)
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
        let page = try await client.get(Self.courseSelectionURL)
        guard let token = NTUEParser.csrfToken(from: page) else { throw NTUEServiceError.noToken }

        let (semesters, defaultSel) = NTUEParser.semesterOptions(from: page)
        guard let target = selection ?? defaultSel else {
            return CourseSelectionPage(courses: [], semesters: semesters, selected: nil)
        }

        let response = try await client.post(Self.courseSelectionURL + stage.pathSuffix, form: [
            "_token": token,
            "srh[ACADYear][]": target.year,
            "srh[Semester][]": target.semester,
            "event": "search",
        ], referer: Self.courseSelectionURL)

        return CourseSelectionPage(courses: NTUEParser.selectedCourses(from: response),
                                   semesters: semesters, selected: target)
    }

    // MARK: - Leave records (請假明細)

    struct LeavePage {
        var records: [LeaveRecord]
        var semesters: [SemesterSelection]
        var selected: SemesterSelection?
    }

    func loadLeaveRecords(for selection: SemesterSelection? = nil) async throws -> LeavePage {
        // NOTE: f01141 is a heavy page (~10s server-side). Its plain GET already
        // contains the records for the *default* (current) semester, so we avoid
        // an extra ~8s POST unless the user actually switches to another semester.
        let page = try await client.get(Self.leaveURL)
        let (semesters, defaultSel) = NTUEParser.semesterOptions(from: page)
        let target = selection ?? defaultSel

        // Default semester (or no selector): use the records already in the GET.
        if target == nil || target?.id == defaultSel?.id {
            return LeavePage(records: NTUEParser.leaveRecords(from: page),
                             semesters: semesters, selected: target ?? defaultSel)
        }

        guard let token = NTUEParser.csrfToken(from: page), let target else {
            return LeavePage(records: NTUEParser.leaveRecords(from: page),
                             semesters: semesters, selected: defaultSel)
        }

        let response = try await client.post(Self.leaveURL, form: [
            "_token": token,
            "srh[ACADYear][]": target.year,
            "srh[Semester][]": target.semester,
            "srh[SignStatus][]": "",
            "event": "search",
        ], referer: Self.leaveURL)

        return LeavePage(records: NTUEParser.leaveRecords(from: response),
                         semesters: semesters, selected: target)
    }

    // MARK: - 缺曠 / 操行 / 獎懲 (GET serves the current semester inline)

    /// 缺曠 for the given (or current) semester. The GET already holds the current
    /// semester; only a switch to another semester needs the (slow) POST.
    func loadAbsences(for selection: SemesterSelection? = nil) async throws -> [AbsenceRecord] {
        let page = try await client.get(Self.absenceURL)
        let current = NTUEParser.selectedSemester(from: page, yearSelect: "srh[ACADYearSrh][]", semesterSelect: "srh[SemesterSrh][]")

        if selection == nil || selection?.id == current?.id {
            return NTUEParser.absenceRecords(from: page)
        }
        guard let token = NTUEParser.csrfToken(from: page), let target = selection else {
            return NTUEParser.absenceRecords(from: page)
        }
        let response = try await client.post(Self.absenceURL, form: [
            "_token": token,
            "srh[ACADYearSrh][]": target.year,
            "srh[SemesterSrh][]": target.semester,
            "event": "search",
        ], referer: Self.absenceURL)
        return NTUEParser.absenceRecords(from: response)
    }

    func loadConductRecords() async throws -> [ConductRecord] {
        let html = try await client.get(Self.conductURL)
        return NTUEParser.conductRecords(from: html)
    }

    func loadRewardPenalties() async throws -> [RewardPenaltyRecord] {
        let html = try await client.get(Self.rewardURL)
        return NTUEParser.rewardPenaltyRecords(from: html)
    }

    // MARK: - Enrollment certificate (在學證明)

    func loadEnrollmentCertificate() async throws -> EnrollmentCertificate {
        let html = try await client.get(Self.enrollmentURL)
        return NTUEParser.enrollmentCertificate(from: html)
    }

    // MARK: - Public schedule (公開課表查詢)

    func loadPublicScheduleOptions() async throws -> PublicScheduleOptions {
        let html = try await client.get(Self.publicScheduleURL)
        return NTUEParser.publicScheduleOptions(from: html)
    }

    func queryPublicSchedule(token: String, year: String, semester: String, classId: String) async throws -> [PublicCourse] {
        let response = try await client.post(Self.publicScheduleURL, form: [
            "_token": token,
            "srh[ACADYear][]": year,
            "srh[Semester][]": semester,
            "srh[ClassID][]": classId,
            "event": "search",
        ], referer: Self.publicScheduleURL)
        return NTUEParser.publicCourses(from: response)
    }

    /// Generates the official enrollment-certificate PDF and saves it to a temp
    /// file. The page returns `window.open(reportURL)`; that report server URL
    /// generates the PDF (redirecting to a /temp/*.pdf), which we download.
    /// - Parameter english: true for the English certificate (event=pdf_2),
    ///   false for the Chinese one (event=pdf_1).
    func enrollmentCertificatePDF(english: Bool) async throws -> URL {
        try await fetchReportPDF(pageURL: Self.enrollmentURL,
                                 filename: "在學證明\(english ? "_EN" : "").pdf") { _ in
            ["event": english ? "pdf_2" : "pdf_1"]
        }
    }

    // MARK: - Shared report-PDF download

    /// Fetches a school-generated report PDF: GET the page for a fresh CSRF
    /// token, POST the print event, follow the `window.open` report URL, and
    /// download the PDF bytes to a temp file.
    private func fetchReportPDF(pageURL: String, filename: String,
                                buildForm: (String) -> [String: String]) async throws -> URL {
        let page = try await client.get(pageURL)
        guard let token = NTUEParser.csrfToken(from: page) else { throw NTUEServiceError.noToken }

        var form = buildForm(page)
        form["_token"] = token
        let trigger = try await client.post(pageURL, form: form, referer: pageURL)

        guard let reportURL = NTUEParser.reportPopupURL(from: trigger) else {
            throw NTUEServiceError.requestFailed("找不到 PDF 連結")
        }
        let data = try await client.getData(reportURL, referer: pageURL)
        guard data.starts(with: [0x25, 0x50, 0x44, 0x46]) else {  // "%PDF"
            throw NTUEServiceError.requestFailed("PDF 產生失敗，請稍後再試")
        }
        let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try data.write(to: fileURL, options: .atomic)
        return fileURL
    }
}
