import Foundation

/// 一個登入 session 內不會變的東西:Laravel 的 CSRF token、各頁面的學期選單、
/// 個人課表的 view id。
///
/// 快取這些純粹是為了砍掉「只為了刮 token / 學期選單」而多打的那一趟頁面 GET。
/// 學校每一趟大約 10 秒,而切學期原本一定要「先 GET 頁面拿 token、再 POST 查詢」
/// —— 省掉前半趟,等於每次切學期都少等一次。Laravel 的 token 是綁 session 而不是
/// 綁頁面,所以整站共用一個就夠;真的過期時伺服器回 419,呼叫端重抓一次即可。
actor NTUESessionCache {
    static let shared = NTUESessionCache()

    /// 某個頁面的學期下拉選單,以及它預設停在哪一個學期。
    struct SemesterMenu {
        var options: [SemesterSelection]
        var selected: SemesterSelection?
    }

    private var csrfToken: String?
    private var menus: [String: SemesterMenu] = [:]        // 頁面網址 → 學期選單
    private var timetableViewIDs: [String: String] = [:]   // 學期 id → 個人課表 view id

    // MARK: - CSRF token

    func token() -> String? { csrfToken }
    func store(token: String) { csrfToken = token }
    func invalidateToken() { csrfToken = nil }

    // MARK: - 學期選單

    func menu(for page: String) -> SemesterMenu? { menus[page] }
    func store(menu: SemesterMenu, for page: String) { menus[page] = menu }

    // MARK: - 個人課表 view id

    func viewID(forSemester id: String) -> String? { timetableViewIDs[id] }
    func store(viewID: String, forSemester id: String) { timetableViewIDs[id] = viewID }

    /// 登入 / 登出時整包丟掉 —— 換帳號後舊 token 與舊 view id 一定失效。
    func clear() {
        csrfToken = nil
        menus.removeAll()
        timetableViewIDs.removeAll()
    }
}
