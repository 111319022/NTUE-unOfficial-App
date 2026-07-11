import Foundation

/// One-tap importer for the **115 學年度（2026-2027）校園行事曆**, curated from the
/// 教務處 official calendar PDF down to student-facing entries: 放假 / 連假、
/// 考試週、選課 / 註冊、開學 / 校慶 / 畢業典禮、停修 / 休退學 / 延畢等重要截止日、
/// 缺曠預警、獎助學金、宿舍開封宿、以及全部八次社團幹部會議。
///
/// Internal admin items (行政會議、各委員會、教師成績繳交…) are intentionally
/// excluded so 校園行事曆 stays useful to students.
///
/// Record ids are stable (`event-115-NNN`), so re-running the import **overwrites**
/// the same records (savePolicy `.allKeys`) instead of creating duplicates.
/// Run it once from a device signed into iCloud; it writes to whichever CloudKit
/// environment the build targets (Debug → Development, entitlement-flipped → Production).
enum Calendar115Importer {

    /// Writes all curated events to CloudKit and returns how many were saved.
    static func importAll() async throws -> Int {
        let events = allEvents
        try await CloudKitAdmin.save(events: events)
        return events.count
    }

    /// The curated 115 學年度 event list, built into stable `CalendarEvent`s.
    static var allEvents: [CalendarEvent] {
        raw.enumerated().map { (i, r) in
            let (title, cat, start, end, note) = r
            return CalendarEvent(id: String(format: "event-115-%03d", i + 1),
                                 title: title,
                                 date: date(start),
                                 endDate: end.map(date),
                                 category: cat,
                                 note: note,
                                 allDay: true)
        }
    }

    // MARK: - Curated data  (title, 分類, 開始, 結束?, 備註?)

    private typealias Row = (String, CalendarEvent.Category, String, String?, String?)

    private static let raw: [Row] = [
        // ── 115 學年度 第 1 學期（2026 秋）──────────────────────────────
        ("第一學期開始", .general, "2026-08-01", nil, nil),
        ("開放學生機車位線上申請", .registration, "2026-08-01", "2026-09-17", "線上申請至 9/17 截止"),
        ("進修學制新生註冊日暨學雜費繳費截止", .registration, "2026-08-13", nil, nil),
        ("就學貸款申請（大學部 / 研究所 / 碩專班）", .registration, "2026-08-17", "2026-09-24", nil),
        ("學生宿舍暑宿封宿", .general, "2026-08-22", nil, nil),
        ("日間學制碩博士班新生註冊日", .registration, "2026-08-24", nil, nil),
        ("學生宿舍新生開宿", .general, "2026-08-29", nil, nil),
        ("新生始業輔導活動", .ceremony, "2026-09-03", "2026-09-04", nil),
        ("社團博覽會", .general, "2026-09-04", nil, nil),
        ("學生宿舍舊生開宿", .general, "2026-09-05", nil, nil),
        ("開學正式上課", .ceremony, "2026-09-07", nil, "日間學制舊生註冊日"),
        ("日間學制第三階段選課", .registration, "2026-09-07", "2026-09-21", "詳閱本學期選課須知"),
        ("進修學制第三階段加退選、校際選課", .registration, "2026-09-07", "2026-09-21", nil),
        ("日間學制校際選課申請", .registration, "2026-09-07", "2026-09-18", nil),
        ("大一英文免修或抵免申請", .deadline, "2026-09-07", "2026-09-18", nil),
        ("個別心理諮商開始", .general, "2026-09-07", nil, nil),
        ("周餘龍教授獎助學金、王天生老師獎學金申請", .deadline, "2026-09-07", "2026-10-02", nil),
        ("第一次社團幹部會議", .general, "2026-09-08", nil, nil),
        ("大一新生健康檢查", .general, "2026-09-09", nil, nil),
        ("全校性選舉", .general, "2026-09-10", nil, nil),
        ("日間學制新生及轉學生抵免學分申請截止", .deadline, "2026-09-11", nil, nil),
        ("進修學制新生抵免學分申請截止", .deadline, "2026-09-14", nil, nil),
        ("中秋節，放假一日", .holiday, "2026-09-25", nil, nil),
        ("教師節，放假一日", .holiday, "2026-09-28", nil, nil),
        ("新生盃球類競賽", .general, "2026-09-29", "2026-10-16", nil),
        ("教育部弱勢助學計畫學生助學金申請", .deadline, "2026-10-01", "2026-10-20", nil),
        ("葉故校長霞翟女士獎學金申請", .deadline, "2026-10-01", "2026-10-15", nil),
        ("學士班缺曠課時數第 1 次預警通知", .deadline, "2026-10-05", "2026-10-16", nil),
        ("日間學制學士班畢業生輔系、雙主修學分審核或放棄申請", .deadline, "2026-10-05", "2026-10-16", nil),
        ("國慶日補假一日", .holiday, "2026-10-09", nil, "國慶日適逢週六"),
        ("日間學制學士班畢業初審", .deadline, "2026-10-12", "2026-11-06", nil),
        ("第二次社團幹部會議", .general, "2026-10-13", nil, nil),
        ("傑出表現獎學金、大一清寒助學金申請", .deadline, "2026-10-15", "2026-11-02", nil),
        ("學生修讀雙主修申請", .registration, "2026-10-19", "2026-10-30", nil),
        ("大學部第一次學生幹部座談會", .general, "2026-10-20", nil, nil),
        ("光復節補假一日", .holiday, "2026-10-26", nil, "光復節適逢週日"),
        ("日間學制研究所及進修學制學生畢業初審", .deadline, "2026-10-27", "2026-11-20", nil),
        ("期中考週", .exam, "2026-10-27", "2026-10-30", nil),
        ("進修學制期中考週", .exam, "2026-10-27", "2026-11-01", nil),
        ("學士班缺曠課時數第 2 次預警通知", .deadline, "2026-10-27", "2026-11-06", nil),
        ("二月制教育實習申請", .deadline, "2026-11-01", "2026-11-30", nil),
        ("常依福智獎學金申請", .deadline, "2026-11-02", "2026-11-16", nil),
        ("日間學制學士班提前畢業生名單收件截止", .deadline, "2026-11-06", nil, nil),
        ("第三次社團幹部會議", .general, "2026-11-10", nil, nil),
        ("校運會會前賽", .general, "2026-11-10", nil, nil),
        ("校慶運動會（校運會）", .general, "2026-11-11", "2026-11-12", nil),
        ("學士班學生修讀輔系申請", .registration, "2026-11-16", "2026-11-30", nil),
        ("學士班缺曠課時數第 3 次預警通知", .deadline, "2026-11-23", "2026-12-04", nil),
        ("學生次一學期教育部學雜費減免申請", .deadline, "2026-11-23", "2026-12-11", nil),
        ("心理健康促進主題週", .general, "2026-11-23", "2026-11-27", nil),
        ("地方公職人員選舉投票日", .general, "2026-11-28", nil, nil),
        ("日間學制受理停修課程", .deadline, "2026-11-30", "2026-12-11", nil),
        ("進修學制受理學生期中停修申請", .deadline, "2026-11-30", "2026-12-14", nil),
        ("全校研究生代表座談會暨大學部第二次學生幹部座談會", .general, "2026-12-01", nil, nil),
        ("體育系 116 級體育表演會", .general, "2026-12-03", "2026-12-05", nil),
        ("131 週年校慶慶祝大會暨校慶園遊會", .ceremony, "2026-12-05", nil, nil),
        ("第四次社團幹部會議", .general, "2026-12-08", nil, nil),
        ("日間學制學士班延畢申請、研究所延長修業年限申請截止", .deadline, "2026-12-11", nil, nil),
        ("學生本學期休、退學申請截止", .deadline, "2026-12-11", nil, nil),
        ("術科期末考週", .exam, "2026-12-14", "2026-12-18", nil),
        ("學科期末考週", .exam, "2026-12-21", "2026-12-24", nil),
        ("進修學制期末考週", .exam, "2026-12-21", "2026-12-27", nil),
        ("行憲紀念日，放假一日", .holiday, "2026-12-25", nil, nil),
        ("第 17 週教師彈性補充教學", .general, "2026-12-28", "2026-12-31", nil),
        ("調整放假一日", .holiday, "2026-12-31", nil, "於 12/5 校慶園遊會補行上班"),
        ("開國紀念日，放假一日", .holiday, "2027-01-01", nil, nil),
        ("學生缺曠登錄截止", .deadline, "2027-01-02", nil, "統計學士班缺曠課致成績零分名單"),
        ("第 18 週教師彈性補充教學", .general, "2027-01-04", "2027-01-08", nil),
        ("學士班缺曠課致學期成績零分通知", .deadline, "2027-01-04", "2027-01-08", nil),
        ("個別心理諮商結束", .general, "2027-01-08", nil, nil),
        ("學生宿舍期末封宿", .general, "2027-01-10", nil, nil),
        ("寒假開始", .holiday, "2027-01-11", nil, nil),
        ("115-2 碩專班就學貸款申請", .registration, "2027-01-18", "2027-02-26", nil),
        ("115-2 就學貸款申請（大學部 / 研究所）", .registration, "2027-01-20", "2027-02-26", nil),

        // ── 115 學年度 第 2 學期（2027 春）──────────────────────────────
        ("第二學期開始", .general, "2027-02-01", nil, nil),
        ("八月制教育實習申請", .deadline, "2027-02-01", "2027-04-30", nil),
        ("轉學生大一英文免修或抵免申請", .deadline, "2027-02-01", "2027-02-26", nil),
        ("春節連假（小年夜至初三），放假五日", .holiday, "2027-02-04", "2027-02-10", "尚未正式公告"),
        ("寒假結束", .general, "2027-02-12", nil, nil),
        ("學生宿舍開宿", .general, "2027-02-13", nil, nil),
        ("開學正式上課（註冊日）", .ceremony, "2027-02-15", nil, nil),
        ("日間學制校際選課申請", .registration, "2027-02-15", "2027-02-26", nil),
        ("日間學制第三階段選課", .registration, "2027-02-15", "2027-03-02", "詳閱本學期選課須知"),
        ("進修學制第三階段加退選、校際選課", .registration, "2027-02-15", "2027-03-02", nil),
        ("個別心理諮商開始", .general, "2027-02-15", nil, nil),
        ("第五次社團幹部會議", .general, "2027-02-16", nil, nil),
        ("第二學期日間學制新生抵免學分申請截止", .deadline, "2027-02-19", nil, nil),
        ("和平紀念日補假一日", .holiday, "2027-03-01", nil, "和平紀念日適逢週日"),
        ("學士班應屆畢業生專業表現優異學生甄選申請", .deadline, "2027-03-02", "2027-03-31", nil),
        ("日間學制學生轉系（組）申請", .registration, "2027-03-05", "2027-03-12", nil),
        ("資訊科基本能力分級鑑定", .general, "2027-03-06", nil, nil),
        ("第六次社團幹部會議", .general, "2027-03-09", nil, nil),
        ("學士班缺曠課時數第 1 次預警通知", .deadline, "2027-03-15", "2027-03-26", nil),
        ("日間學制學士班畢業生輔系、雙主修學分審核或放棄申請", .deadline, "2027-03-15", "2027-03-26", nil),
        ("日間學制學士班畢業初審", .deadline, "2027-03-22", "2027-04-16", nil),
        ("大學部第一次學生幹部座談會", .general, "2027-03-23", nil, nil),
        ("民族掃墓節，放假一日", .holiday, "2027-04-05", nil, nil),
        ("兒童節補假一日", .holiday, "2027-04-06", nil, "兒童節適逢週日，尚未正式公告"),
        ("碩士在職專班學生畢業初審", .deadline, "2027-04-07", "2027-04-30", nil),
        ("學士班缺曠課時數第 2 次預警通知", .deadline, "2027-04-07", "2027-04-16", nil),
        ("期中考週", .exam, "2027-04-12", "2027-04-16", nil),
        ("進修學制期中考週", .exam, "2027-04-12", "2027-04-18", nil),
        ("日間學制學士班提前畢業生名單收件截止", .deadline, "2027-04-16", nil, nil),
        ("學生修讀雙主修申請", .registration, "2027-04-19", "2027-04-29", nil),
        ("校長盃球類競賽", .general, "2027-04-19", "2027-05-21", nil),
        ("第七次社團幹部會議", .general, "2027-04-20", nil, nil),
        ("數學科教學基本知能分級鑑定", .general, "2027-04-20", nil, nil),
        ("勞動節補假一日", .holiday, "2027-04-30", nil, "勞動節適逢週六"),
        ("心理健康促進主題週", .general, "2027-05-03", "2027-05-07", nil),
        ("日間學制受理停修課程", .deadline, "2027-05-10", "2027-05-21", nil),
        ("學士班缺曠課時數第 3 次預警通知", .deadline, "2027-05-10", "2027-05-21", nil),
        ("進修學制受理學生期中停修申請", .deadline, "2027-05-10", "2027-05-24", nil),
        ("學生次一學期教育部學雜費減免申請", .deadline, "2027-05-10", "2027-05-28", nil),
        ("水上運動會", .general, "2027-05-11", nil, nil),
        ("全校研究生代表座談會暨大學部第二次學生幹部座談會", .general, "2027-05-11", nil, nil),
        ("學士班學生修讀輔系申請", .registration, "2027-05-17", "2027-05-31", nil),
        ("第八次社團幹部會議暨社團幹部交接", .general, "2027-05-18", nil, nil),
        ("日間學制學士班延畢申請、研究所延長修業年限申請截止", .deadline, "2027-05-21", nil, nil),
        ("學生本學期休、退學申請截止", .deadline, "2027-05-21", nil, nil),
        ("術科期末考週", .exam, "2027-05-24", "2027-05-28", nil),
        ("學科期末考週", .exam, "2027-05-31", "2027-06-04", nil),
        ("進修學制期末考週", .exam, "2027-05-31", "2027-06-06", nil),
        ("第 17 週教師彈性補充教學", .general, "2027-06-07", "2027-06-11", nil),
        ("端午節，放假一日", .holiday, "2027-06-09", nil, nil),
        ("學生曠課登錄截止", .deadline, "2027-06-12", nil, "統計學士班缺曠課致成績零分通知"),
        ("第 18 週教師彈性補充教學", .general, "2027-06-14", "2027-06-18", nil),
        ("學士班缺曠課致學期成績零分通知", .deadline, "2027-06-14", "2027-06-18", nil),
        ("個別心理諮商結束", .general, "2027-06-18", nil, nil),
        ("畢業典禮（暫定）", .ceremony, "2027-06-19", nil, "於 116/10/8 調整放假"),
        ("學生宿舍期末封宿", .general, "2027-06-20", nil, nil),
        ("暑假開始", .holiday, "2027-06-21", nil, nil),
        ("第 2 學期結束", .general, "2027-07-31", nil, nil),
    ]

    private static func date(_ s: String) -> Date {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Asia/Taipei")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: s) ?? Date()
    }
}
