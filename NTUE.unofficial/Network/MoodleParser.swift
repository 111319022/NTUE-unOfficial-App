import Foundation
import SwiftSoup

/// Parsing helpers for md.ntue.edu.tw (Moodle). Two kinds of input:
/// 1. The `M.cfg.sesskey` token embedded in every logged-in page.
/// 2. The HTML table on `/mod/assign/index.php?id=<course>` (one row per assignment).
enum MoodleParser {

    /// Extracts the AJAX session key from a logged-in Moodle page.
    static func sesskey(from html: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #""sesskey":"(\w+)""#) else { return nil }
        let range = NSRange(html.startIndex..., in: html)
        guard let m = regex.firstMatch(in: html, range: range),
              let r = Range(m.range(at: 1), in: html) else { return nil }
        return String(html[r])
    }

    /// True if a fetched Moodle page belongs to a logged-in session.
    static func isLoggedIn(_ html: String) -> Bool {
        !html.contains("notloggedin") && sesskey(from: html) != nil
    }

    /// Parses the assignment index table for one course.
    static func assignments(fromIndex html: String) -> [MoodleAssignment] {
        guard let doc = try? SwiftSoup.parse(html),
              let table = try? doc.select("table.generaltable").first() else { return [] }
        var result: [MoodleAssignment] = []
        let rows = (try? table.select("tbody tr")) ?? Elements()
        for row in rows.array() {
            // The assignment name + link lives in column c1; rows without it are
            // section dividers and are skipped.
            guard let link = try? row.select("td.c1 a[href*=view.php]").first(),
                  let href = try? link.attr("href"),
                  let id = moduleId(from: href),
                  let name = try? link.text(), !name.isEmpty else { continue }
            let dueText = cellText(row, "td.c2")
            let status = cellText(row, "td.c3")
            let grade = cellText(row, "td.c4")
            result.append(MoodleAssignment(
                id: id,
                name: name,
                dueDate: parseDue(dueText),
                dueText: dueText,
                statusText: status,
                gradeText: grade
            ))
        }
        return result
    }

    /// Finds the 公告 (news) forum's module id from a course page
    /// (`/course/view.php?id=`). The forum index page renders its links via JS,
    /// so we read the course page instead, where the link is in the raw HTML.
    static func announcementForumId(fromCoursePage html: String) -> Int? {
        guard let doc = try? SwiftSoup.parse(html) else { return nil }
        let links = (try? doc.select("a[href*=forum/view.php]").array()) ?? []
        // Prefer the forum named 公告 / Announcements; fall back to the first forum.
        let preferred = links.first {
            let t = (try? $0.text()) ?? ""
            return t.contains("公告") || t.lowercased().contains("announce")
        } ?? links.first
        guard let preferred, let href = try? preferred.attr("href") else { return nil }
        return queryInt(href, "id")
    }

    /// Parses the discussion list on a `/mod/forum/view.php` page into announcements.
    static func announcements(courseName: String, fromForum html: String) -> [MoodleAnnouncement] {
        guard let doc = try? SwiftSoup.parse(html),
              let table = try? doc.select("table").first() else { return [] }
        let rows = (try? table.select("tbody tr")) ?? Elements()
        var result: [MoodleAnnouncement] = []
        for row in rows.array() {
            guard let link = try? row.select("a[href*=discuss.php]").first(),
                  let href = try? link.attr("href"),
                  let id = queryInt(href, "d"),
                  let subjectRaw = try? link.text(), !subjectRaw.isEmpty else { continue }
            let subject = subjectRaw.replacingOccurrences(of: " Locked", with: "")
                .trimmingCharacters(in: .whitespaces)
            let rowText = (try? row.text()) ?? ""
            let (date, dateText) = parseForumDate(rowText)
            result.append(MoodleAnnouncement(
                id: id,
                courseName: courseName,
                subject: subject,
                author: extractAuthor(rowText, dateText: dateText),
                date: date,
                dateText: dateText
            ))
        }
        return result
    }

    // MARK: - Helpers

    private static func queryInt(_ href: String, _ key: String) -> Int? {
        let full = href.hasPrefix("http") ? href : "https://md.ntue.edu.tw" + href
        return URLComponents(string: full)?.queryItems?.first(where: { $0.name == key })?.value.flatMap(Int.init)
    }

    /// Extracts a Moodle date like "29 5月 2026" → Date + the matched text.
    private static func parseForumDate(_ text: String) -> (Date?, String) {
        guard let regex = try? NSRegularExpression(pattern: #"(\d{1,2})\s*(\d{1,2})月\s*(\d{4})"#) else { return (nil, "") }
        let range = NSRange(text.startIndex..., in: text)
        guard let m = regex.firstMatch(in: text, range: range),
              let mr = Range(m.range, in: text) else { return (nil, "") }
        func num(_ i: Int) -> Int? { Range(m.range(at: i), in: text).flatMap { Int(text[$0]) } }
        let dateText = String(text[mr])
        guard let d = num(1), let mo = num(2), let y = num(3) else { return (nil, dateText) }
        var comps = DateComponents(); comps.year = y; comps.month = mo; comps.day = d
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Taipei") ?? .current
        return (cal.date(from: comps), dateText)
    }

    /// From a row like "200001950 蕭雅真 29 5月 2026" pull the author name.
    private static func extractAuthor(_ rowText: String, dateText: String) -> String {
        var t = rowText
        if !dateText.isEmpty, let r = t.range(of: dateText) { t = String(t[..<r.lowerBound]) }
        // Drop leading student-id digits, keep the (Chinese) name token.
        let tokens = t.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" })
            .map(String.init).filter { !$0.isEmpty && Int($0) == nil }
        return tokens.last ?? ""
    }

    private static func cellText(_ row: Element, _ selector: String) -> String {
        guard let cell = try? row.select(selector).first(), let t = try? cell.text() else { return "" }
        return t
    }

    private static func moduleId(from href: String) -> Int? {
        guard let comps = URLComponents(string: href.hasPrefix("http") ? href : "https://md.ntue.edu.tw" + href) else { return nil }
        return comps.queryItems?.first(where: { $0.name == "id" })?.value.flatMap(Int.init)
    }

    /// "2026年 05月 22日(週五) 08:55" → Date (Asia/Taipei).
    static func parseDue(_ text: String) -> Date? {
        guard let regex = try? NSRegularExpression(pattern: #"(\d{4})\D+?(\d{1,2})\D+?(\d{1,2})\D+?(\d{1,2}):(\d{2})"#) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let m = regex.firstMatch(in: text, range: range) else { return nil }
        func num(_ i: Int) -> Int? { Range(m.range(at: i), in: text).flatMap { Int(text[$0]) } }
        guard let y = num(1), let mo = num(2), let d = num(3), let h = num(4), let mi = num(5) else { return nil }
        var comps = DateComponents()
        comps.year = y; comps.month = mo; comps.day = d; comps.hour = h; comps.minute = mi
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Taipei") ?? .current
        return cal.date(from: comps)
    }
}
