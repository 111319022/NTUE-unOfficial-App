import Foundation
import SwiftSoup

/// Parsing helpers for iNTUE pages. The site renders DataTables client-side from
/// a `"data":[ … ]` JSON island embedded in the HTML, so most "scraping" is
/// actually JSON extraction rather than table walking.
enum NTUEParser {

    // MARK: - CSRF token

    /// The Laravel CSRF token, needed for every POST. Prefer the <meta> tag,
    /// fall back to a hidden <input name="_token">.
    static func csrfToken(from html: String) -> String? {
        if let doc = try? SwiftSoup.parse(html) {
            if let meta = try? doc.select("meta[name=csrf-token]").first(),
               let content = try? meta.attr("content"), !content.isEmpty {
                return content
            }
            if let input = try? doc.select("input[name=_token]").first(),
               let value = try? input.attr("value"), !value.isEmpty {
                return value
            }
        }
        return nil
    }

    // MARK: - Semester <select> options

    /// Reads the academic-year and semester options + which one is selected.
    static func semesterOptions(from html: String) -> (options: [SemesterSelection], selected: SemesterSelection?) {
        guard let doc = try? SwiftSoup.parse(html) else { return ([], nil) }

        func optionValues(_ name: String) -> (values: [String], selected: String?) {
            guard let select = try? doc.select("select[name=\"\(name)\"]").first() else { return ([], nil) }
            let options = (try? select.select("option").array()) ?? []
            var values: [String] = []
            var selected: String?
            for opt in options {
                let v = (try? opt.attr("value")) ?? ""
                guard !v.isEmpty else { continue }
                values.append(v)
                if opt.hasAttr("selected") { selected = v }
            }
            return (values, selected)
        }

        let (years, selYear) = optionValues("srh[ACADYear][]")
        let (semesters, selSem) = optionValues("srh[Semester][]")

        var result: [SemesterSelection] = []
        for y in years {
            for s in semesters {
                result.append(SemesterSelection(year: y, semester: s))
            }
        }
        let selected: SemesterSelection?
        if let y = selYear, let s = selSem {
            selected = SemesterSelection(year: y, semester: s)
        } else {
            selected = result.last
        }
        return (result, selected)
    }

    // MARK: - Student info

    /// Parses the `.form-group` header blocks: each has an <h6> label and a
    /// <font> value (學號 / 姓名 …).
    static func studentInfo(from html: String) -> StudentInfo {
        var info = StudentInfo()
        guard let doc = try? SwiftSoup.parse(html) else { return info }

        let groups = (try? doc.select("div.form-group").array()) ?? []
        for group in groups {
            guard let label = try? group.select("h6").first()?.text(),
                  let value = try? group.select("font").first()?.text() else { continue }
            let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
            switch label.trimmingCharacters(in: .whitespacesAndNewlines) {
            case "學號": info.studentId = v
            case "姓名": info.name = v
            case let l where l.contains("系") || l.contains("學系"): info.department = v
            case "班級": info.className = v
            default: break
            }
        }
        return info
    }

    // MARK: - Grades JSON island

    static func grades(from html: String) -> [Grade] {
        guard let rows = jsonDataIsland(in: html) else { return [] }
        return rows.compactMap { row in
            // grade rows always carry a course code
            guard let code = row["SemesterCourseNo"] as? String, !code.isEmpty else { return nil }
            return Grade(
                courseCode:   str(row["SemesterCourseNo"]),
                department:   str(row["StudyCourseCategoryName"]),
                courseName:   str(row["SemesterCourseName"]),
                required:     str(row["Choose"]),
                category:     str(row["CourseClassName"]),
                credits:      str(row["Credit"]),
                classGroup:   str(row["StudyClassName"]),
                instructor:   str(row["Teacher"]),
                score:        str(row["Score"]),
                passed:       str(row["IsPass"]),
                note:         str(row["Memo"]),
                withdrawDate: str(row["StopDate"])
            )
        }
    }

    // MARK: - Timetable

    /// Extracts the `/b04/b04250/v/{id}` personal-timetable link from the POST response.
    static func timetableViewId(from html: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"b04250/v/(\d+)"#) else { return nil }
        let range = NSRange(html.startIndex..., in: html)
        guard let match = regex.firstMatch(in: html, range: range),
              let r = Range(match.range(at: 1), in: html) else { return nil }
        return String(html[r])
    }

    /// Extracts the `window.open('…')` report URL from a PDF-trigger response
    /// (e.g. the 在學證明 event=pdf_1 POST).
    static func reportPopupURL(from html: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"window\.open\(\s*['"]([^'"]+)['"]"#) else { return nil }
        let range = NSRange(html.startIndex..., in: html)
        guard let match = regex.firstMatch(in: html, range: range),
              let r = Range(match.range(at: 1), in: html) else { return nil }
        let url = String(html[r])
        return url.hasPrefix("http") ? url : nil
    }

    /// Parses the timetable grid JSON island: rows keyed "1"…"7" (weekdays) plus
    /// SectionName / SectionTime. Each populated cell is `班級<br>課程<br>師<br>教室`.
    static func timetable(from html: String) -> Timetable {
        guard let rows = jsonDataIsland(in: html) else { return Timetable(periods: []) }
        var periods: [TimetablePeriod] = []
        for row in rows {
            let name = str(row["SectionName"])
            let time = normaliseTime(str(row["SectionTime"]))
            var slots: [Int: TimetableSession] = [:]
            for wd in 1...7 {
                let cell = str(row["\(wd)"])
                guard !cell.isEmpty else { continue }
                let parts = cell
                    .replacingOccurrences(of: "<br/>", with: "<br>")
                    .replacingOccurrences(of: "<br />", with: "<br>")
                    .components(separatedBy: "<br>")
                    .map { stripTags($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                guard !parts.isEmpty else { continue }
                slots[wd] = TimetableSession(
                    weekday: wd,
                    periodName: name,
                    periodTime: time,
                    classGroup: parts.count > 0 ? parts[0] : "",
                    courseName: parts.count > 1 ? parts[1] : parts[0],
                    instructor: parts.count > 2 ? parts[2] : "",
                    classroom:  parts.count > 3 ? parts[3] : ""
                )
            }
            periods.append(TimetablePeriod(name: name, time: time, slots: slots))
        }
        return Timetable(periods: periods)
    }

    /// The selected (or first non-empty) option value of a <select>.
    static func optionValue(from html: String, selectName: String) -> String? {
        guard let doc = try? SwiftSoup.parse(html),
              let select = try? doc.select("select[name=\"\(selectName)\"]").first() else { return nil }
        let options = (try? select.select("option").array()) ?? []
        var firstNonEmpty: String?
        for opt in options {
            let v = (try? opt.attr("value")) ?? ""
            guard !v.isEmpty, v != "-" else { continue }
            if firstNonEmpty == nil { firstNonEmpty = v }
            if opt.hasAttr("selected") { return v }
        }
        return firstNonEmpty
    }

    // MARK: - Public schedule (公開課表查詢)

    static func publicScheduleOptions(from html: String) -> PublicScheduleOptions {
        var opts = PublicScheduleOptions()
        opts.token = csrfToken(from: html) ?? ""
        guard let doc = try? SwiftSoup.parse(html) else { return opts }

        func read(_ name: String) -> (options: [NamedOption], selected: String) {
            guard let select = try? doc.select("select[name=\"\(name)\"]").first() else { return ([], "") }
            var list: [NamedOption] = []
            var selected = ""
            for opt in (try? select.select("option").array()) ?? [] {
                let v = (try? opt.attr("value")) ?? ""
                let t = ((try? opt.text()) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !v.isEmpty, v != "-" else { continue }   // skip the "-" placeholder
                list.append(NamedOption(id: v, name: t))
                if opt.hasAttr("selected") { selected = v }
            }
            return (list, selected)
        }

        let (years, selYear) = read("srh[ACADYear][]")
        let (semesters, selSem) = read("srh[Semester][]")
        let (classes, _) = read("srh[ClassID][]")
        opts.years = years
        opts.semesters = semesters
        opts.classes = classes
        opts.defaultYear = selYear.isEmpty ? (years.last?.id ?? "") : selYear
        opts.defaultSemester = selSem.isEmpty ? (semesters.first?.id ?? "") : selSem
        return opts
    }

    static func publicCourses(from html: String) -> [PublicCourse] {
        guard let rows = jsonDataIsland(in: html) else { return [] }
        return rows.compactMap { row in
            let no = str(row["SemesterCourseNo"])
            let name = str(row["SemesterCourseName"])
            guard !no.isEmpty || !name.isEmpty else { return nil }
            let low = str(row["StdAmtLow"]), up = str(row["StdAmtUp"])
            let limit = (low.isEmpty && up.isEmpty) ? "" : "\(low)-\(up)"
            return PublicCourse(
                courseNo: no,
                name: cleanText(name),
                engName: cleanText(str(row["SemesterCourseENGName"])),
                choose: cleanText(str(row["Choose"])),
                className: cleanText(str(row["StudyClassName"])),
                department: cleanText(str(row["CourseClassName"])),
                dayType: cleanText(str(row["DayfgClassTypeName"])),
                teacher: cleanText(str(row["Teacher"])),
                time: cleanText(str(row["SemCourseTime"])),
                classroom: cleanText(str(row["ClassRoom"])),
                credit: cleanText(str(row["Credit"])),
                language: cleanText(str(row["TeaLanguage"])),
                enrollLimit: limit,
                memo: cleanText(str(row["Memo"]))
            )
        }
    }

    // MARK: - Leave records (請假明細)

    static func leaveRecords(from html: String) -> [LeaveRecord] {
        guard let rows = jsonDataIsland(in: html) else { return [] }
        return rows.compactMap { row in
            let id = str(row["StdAbsentID"])
            guard !id.isEmpty else { return nil }
            return LeaveRecord(
                id: id,
                kind: cleanText(str(row["LeaveKindName"])),
                reason: cleanText(str(row["LeaveReason"])),
                dateSection: cleanText(str(row["AbsentSEDate"]), joinBreaksWith: "、"),
                sectionCount: cleanText(str(row["SectionSeqCount"])),
                status: cleanText(str(row["form_status"])),
                applyDate: cleanText(str(row["ApplyDate"])),
                formNumber: str(row["form_number"])
            )
        }
    }

    // MARK: - Enrollment certificate (在學證明)

    /// Parses the a02280 page. Labels (生日 / 科系) repeat across the 中文 and
    /// 英文 sections, so we walk the `.form-group` blocks in order and switch to
    /// English mode once we hit 英文姓名.
    static func enrollmentCertificate(from html: String) -> EnrollmentCertificate {
        var cert = EnrollmentCertificate()
        guard let doc = try? SwiftSoup.parse(html) else { return cert }
        let groups = (try? doc.select("div.form-group").array()) ?? []

        var english = false
        for group in groups {
            guard let label = try? group.select("h6").first()?.text() else { continue }
            let value = ((try? group.select("font").first()?.text()) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let key = label.trimmingCharacters(in: .whitespacesAndNewlines)

            if key == "英文姓名" { english = true; cert.englishName = value; continue }

            switch key {
            case "學號": cert.studentId = value
            case "姓名": cert.name = value
            case "學年": cert.year = value
            case "學期": cert.semester = value
            case "生日" where !english: cert.birthday = value
            case "科系" where !english: cert.department = value
            case "年級": cert.grade = value
            case "處室": cert.office = value
            case "科系" where english: cert.englishDepartment = value
            case "入學年學期": cert.admissionTerm = value
            case "班級類別": cert.classTypeStatement = value
            default: break
            }
        }
        return cert
    }

    // MARK: - JSON island extraction

    /// Finds the first `"data":[ … ]` array in the page and parses it into rows.
    /// Bracket matching is string-aware so brackets inside values don't break it.
    static func jsonDataIsland(in html: String) -> [[String: Any]]? {
        let marker = "\"data\":["
        guard let markerRange = html.range(of: marker) else { return nil }
        let start = html.index(before: markerRange.upperBound) // points at '['

        var depth = 0
        var inString = false
        var escaped = false
        var end: String.Index?
        var i = start
        while i < html.endIndex {
            let c = html[i]
            if inString {
                if escaped { escaped = false }
                else if c == "\\" { escaped = true }
                else if c == "\"" { inString = false }
            } else {
                if c == "\"" { inString = true }
                else if c == "[" { depth += 1 }
                else if c == "]" {
                    depth -= 1
                    if depth == 0 { end = html.index(after: i); break }
                }
            }
            i = html.index(after: i)
        }
        guard let end else { return nil }
        let jsonString = String(html[start..<end])
        guard let data = jsonString.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return nil
        }
        return parsed
    }

    // MARK: - Small helpers

    private static func str(_ any: Any?) -> String {
        if let s = any as? String { return s }
        if let n = any as? NSNumber { return n.stringValue }
        return ""
    }

    private static func stripTags(_ s: String) -> String {
        s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    }

    /// Turns server HTML fragments into plain text: <br> → joiner, strip tags,
    /// decode common entities, collapse whitespace.
    private static func cleanText(_ s: String, joinBreaksWith joiner: String = " ") -> String {
        var t = s
        for br in ["<br>", "<br/>", "<br />", "<BR>", "<BR/>", "<BR />"] {
            t = t.replacingOccurrences(of: br, with: joiner)
        }
        t = stripTags(t)
        let entities = ["&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&apos;": "'"]
        for (k, v) in entities { t = t.replacingOccurrences(of: k, with: v) }
        t = t.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// "07:10<br>08:00" -> "07:10-08:00"
    private static func normaliseTime(_ s: String) -> String {
        stripTags(s.replacingOccurrences(of: "<br>", with: "-")
            .replacingOccurrences(of: "<br/>", with: "-")
            .replacingOccurrences(of: "<br />", with: "-"))
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
