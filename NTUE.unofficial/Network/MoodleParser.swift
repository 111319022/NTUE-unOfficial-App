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

    // MARK: - Helpers

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
