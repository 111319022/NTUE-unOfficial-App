# PROJECT_GUIDE

NTUE.unofficial 的開發者指南：架構、資料流、後端逆向工程細節與各模組職責。使用者導向的概覽請看 [README.md](README.md)。

---

## 1. 全貌

裝置端 scraper 型 App，**沒有後端**。所有功能都是在裝置上登入校方網站、抓 HTML、解析後以原生 UI 呈現。兩大來源：

- **iNTUE 校務系統** — 課表、成績、請假、缺曠、操行、獎懲、修業進度、在學證明、公開課表。
- **Moodle 教學平台**（`md.ntue.edu.tw`）— 作業、課程公告、學期倒數輔助資料。

兩者皆透過**校園入口網 OpenID Connect**（`protocol.ntue.edu.tw`）登入，OIDC 流程由 `AuthService.performOIDCLogin(clientId:redirectURI:)` 共用。

### 目標（Targets）

pbxproj 為 objectVersion 77（synchronized folders）。

| Target | 資料夾 | 說明 |
| --- | --- | --- |
| `NTUE.unofficial` | `NTUE.unofficial/` | App 主體 |
| `NTUEWidgets` | `NTUEWidgets/` | App 擴充：`@main NTUEWidgetsBundle`，含小工具與 Live Activity UI |
| （共用群組）`Shared/` | `Shared/` | 同步根群組，**同時掛在 App 與 Widget**；純 Foundation，不引入 SwiftSoup／網路 |

- App Group：`group.com.rayhsu63.NTUE-unofficial`（兩個 target 的 entitlements 都有）。
- 各同步群組以 `PBXFileSystemSynchronizedBuildFileExceptionSet` 排除 Info.plist／entitlements，避免「Multiple commands produce」錯誤。
- 手動加入 pbxproj 的物件 UUID 前綴：`AB10000000000000000000xx`。

---

## 2. 導覽結構

四個分頁：

1. **首頁** — 學期倒數 + 下一堂課 + 作業截止 + 今日課表。
2. **課表** — 個人週課表。
3. **作業** — Moodle，依課程分組的作業清單（`AssignmentsView`）。
4. **其他服務** — hub：成績 / 修業進度 / 公開課表 / 請假明細 / 請假申請 / 在學證明 / 缺曠 / 操行 / 獎懲 / 外觀設定。

### 首頁版型（「聚焦現在」）

header（問候 + 日期 + 學期 pill）→ 楓紅 hero 卡（下一堂課倒數 / 「今天上完了」+ 下一上課日 / 「今天沒有課」）→ 三格摘要（今日課程 / 待繳作業 / 學期倒數）→ 作業截止 → 今日課表 → 明日課表。

---

## 3. 網路 / 資料層（`Network/`）

| 檔案 | 職責 |
| --- | --- |
| `NTUEClient.swift` | 共用 HTTP（`postJSON` 供 Moodle AJAX） |
| `AuthService.swift` | OIDC 登入、登入狀態檢查（`isAuthenticated`） |
| `NTUEService.swift` | iNTUE 各功能的抓取進入點（成績、課表、缺曠…、`fetchReportPDF` / `downloadReportPDF`） |
| `NTUEParser.swift` | 解析 HTML JSON island、各資料表、學期選項 |
| `MoodleService.swift` | actor，`ensureSession`→sesskey、AJAX、作業／公告載入 |
| `MoodleParser.swift` | sesskey regex、作業索引表、公告討論串（SwiftSoup） |
| `DataStore.swift` | `@MainActor @Observable` 單例，記憶體快取 + 預取 |
| `Persistence.swift` | 磁碟 SWR 快照（Application Support 的 JSON） |
| `WidgetBridge.swift` | 把快取展開成 `WidgetSnapshot` 寫入 App Group |
| `LiveActivityController.swift` | `@MainActor` 單例，啟動／更新／結束 Live Activity |

### 快取策略

**記憶體（stale-while-revalidate）** — `DataStore` 把每個慢資料集（課表、成績、Moodle 截止、Moodle 作業）快取成它的 in-flight／已完成 `Task`：

- await 已完成的 task 是瞬間的，也去重併發呼叫者。
- `prefetch(studentId:)` 在登入後背景暖機。
- 預設學期經 DataStore；明確切換學期時繞過快取。
- 下拉刷新傳 `forceReload: true`。
- **空結果不快取**（多半是登出重導）並丟棄該 task，下次重試。

**磁碟（瞬間冷啟動）** — `Persistence` 把 `StudentInfo`、`Timetable`、`[MoodleDeadline]` 等寫成 JSON。模型加 `Codable`（如 `TimetableSession`/`Period` 用 CodingKeys 排除 UUID `id`）。`DataStore` 在 init 從磁碟 hydrate 並在每次非空載入時持久化。

`AppState.restoreSession`：若有存的帳密 + 快取 `StudentInfo`，直接進 `.loggedIn` 顯示快取，再背景 `validateAndRefresh()`（`loadStudentInfo` 兼任 auth 檢查；必要時悄悄重登或退到 `.loggedOut`）。只有真正冷啟動才會卡在網路。`logout` / `DataStore.clear()` 會清磁碟快取。

**過去學期** — 比 `NTUETerm.currentSemester` 舊的學期持久化到磁碟（keys `timetable_/leave_/absence_<sem id>`），讀過一次後之後完全離線供應；進行中的學期仍刷新。每個 per-semester VM 也在記憶體依學期 id 快取，切回去瞬間。

---

## 4. iNTUE 後端機制（已用 Chrome 實機驗證）

- **JSON island**：頁面用 DataTables 在 client 端從 HTML 裡的 `"data":[…]` JSON island 渲染。必須 **POST**（不只是 GET）並解析 island，**不要**爬 `<table>` 列。見 `NTUEParser.jsonDataIsland`（字串感知的括號比對）。
- **CSRF**：每次 POST 都要 Laravel `_token`（來自 `<meta name=csrf-token>` 或 hidden input）+ `event=search`（成績／請假／公開）或頁面特定 event。
- **登入檢查陷阱**：`IsServiceWorking.aspx` 即使登出也回 `Working=1`，**不可**用它確認登入。真正檢查 = 抓成績頁確認有學生資訊（`AuthService.isAuthenticated`）。
- **官方 PDF**（在學證明、修業學分檢核表）：POST 頁面帶列印 event → 回應含 `window.open(reportURL)` 指向報表伺服器 `https://intue_report.ntue.edu.tw:82/?reportname=…&format=PDF&…` → GET 該 URL（重導到 `/temp/*.pdf`）→ 下載 bytes → QuickLook。共用 `NTUEService.fetchReportPDF`。
- **請假申請**（f01141/add）是 Vue 寫入表單；決定用 in-app `NTUEWebView`（注入 cookie）承載官方頁面，不重寫寫入 API，避免誤送假單。

### 功能 URL 對照

| 功能 | 代碼 | 備註 |
| --- | --- | --- |
| 成績 | a05 / a052A0 | |
| 個人課表 | b04 / b04250 | POST → `/v/{id}` → grid JSON |
| 請假 | f01 / f01141 | GET 即含預設學期紀錄，頁面約 10s 慢 |
| 在學證明 | a02 / a02280 | 也用來補 `department` / `enrollmentYear` |
| 修業進度 | a04 / a04210 | 列印鈕為 `setSubmit(this,1,0)`，無法猜 `event=`，用離屏 WebView |
| 公開課表 | b09 / b09120 | |
| 缺曠 | b11 / b11170 | 切學期 POST `srh[ACADYearSrh][]` / `srh[SemesterSrh][]` + `event=search` |
| 操行 | f02 / f02192 | |
| 獎懲 | f02 / f021b0 | |

缺曠／操行／獎懲：GET 即供應當學期 JSON island（與成績同機制），模型在 `Models/StudentRecords.swift`。

---

## 5. Moodle 機制

- 懶登入：首次載入資料時用 Keychain 帳密登入；cookie（`MoodleSession`）放共用 cookie store，`NTUEWebView` 也注入。
- **作業**：scrape 每門課的 `/mod/assign/index.php`，依課程分組顯示繳交狀態。
- **課程公告**：每門當學期課程並發 GET `/course/view.php?id=<courseid>` → `MoodleParser.announcementForumId` 取公告 forum 連結（⚠️ `/mod/forum/index.php` 的連結由 JS 渲染，raw HTML 沒有，**必須**用課程頁）→ GET `/mod/forum/view.php?id=<cmid>` → 解析討論串表（標題、作者、日期、discuss 連結），新到舊排序，點開在 `NTUEWebSheet`。
- **首頁作業截止**：用輕量的 `core_calendar_get_action_events_by_timesort`（僅未繳），非完整 per-course scrape。
- **首頁學期倒數**：手動維護的 `Models/AcademicCalendar.swift`（Moodle 的 course enddate 不可靠）。`AcademicTerm` 同時存 `end16`/`end18`，由 `@AppStorage("use18Week")` 切換（預設 16 週），首頁監看此 key 即時重繪。

---

## 6. 學期模型與選擇器

- `StudentInfo.gradeLevel` 從 className 讀年級（「數位二甲」→2），優先用固定 `enrollmentYear` 錨點（每 8/1 自動 +1）。
- `NTUETerm.currentAcademicYear`（ROC，8/1 換）+ `NTUETerm.enrolledSemesters(grade:)` 給出 4 年區間。
- 共用上方學期列 `Views/SemesterBar.swift`（`◀ 114 下學期 ▶`：箭頭前後一步、中間是選單），用於成績／課表／請假缺曠／作業／課程公告。
- 未來學期一律經 `NTUETerm.upToCurrent` 隱藏（晚於 `currentSemester` 的丟掉）。
- 成績／課表／請假缺曠的 SemesterBar 由 `enrolledSemesters` 建立（年級未知時 fallback 伺服器清單），列表穩定且有界 —— 修掉了舊 bug：載入舊學期會縮小 `semesterOptions` 導致 114下消失／109出現。
- `AppState.ensureProfileDetails()` 讀一次在學證明（a02280）補 `department` 與 `enrollmentYear` = 學年 −（年級−1）。

### 成績（合併）

`GradesView` 同時承載單學期與歷年：SemesterBar 選項 = [歷年總表] + 各學期。選歷年總表顯示 `TranscriptContent`（聚合），否則顯示單學期。`TranscriptViewModel` 逐學期 `loadGrades(for:)`，累積學分 + 加權 GPA（成績單網頁 a052F2 純 GET 會回首頁，故改用逐學期聚合）。

---

## 7. 視覺設計（暖調學院）

- 調色盤：奶油色畫布 `Theme.background`（#F6F1E9／深色暖炭黑）、近白卡片 `Theme.cardBackground`、NTUE 楓紅 `Theme.accent`、琥珀 `Theme.amber`（快截止）。
- List 畫面加 `.scrollContentBackground(.hidden).background(Theme.background)`。
- 深色模式：暖炭黑底 + 提亮的楓紅／琥珀。`Theme.accent` 在深色為**前景**用（文字／圖示）提亮；白字背後的實心楓紅**填色**用 `Theme.accentFill`（兩種模式都深）。
- ServicesView 分區圖示各一色：`Theme.iconMaroon`（教務）、`Theme.iconAmber`（學生事務）、`Theme.iconBlue`（Moodle）。
- 外觀：`Models/AppTheme.swift`（system/light/dark）以 `@AppStorage("app_theme")` 持久化，WindowGroup 根 `.preferredColorScheme` 套用，picker 在 ServicesView「外觀」區。

---

## 8. 小工具與 Live Activity

**資料流** — `WidgetBridge.update()`（App）把週課表 `Timetable` 展開成未來 7 天具日期的 `ClassSlot`、把 `MoodleDeadline` 映成 `AssignmentItem`，寫成 `WidgetSnapshot` JSON 到 App Group（`SharedStore.save()` 同時呼叫 `WidgetCenter.reloadAllTimelines()`）。掛在 `DataStore` 快取課表／作業之後，登出時清除。Widget `ClassProvider` 讀 `SharedStore.load()`。

**Widgets**（`NTUEWidgets/`）— `NextClassWidget`（systemSmall + accessory）、`AssignmentsWidget`（systemSmall + accessoryRectangular）、`CombinedWidget`（systemMedium）。

**Live Activity** — `LiveActivityController`（App，`@MainActor` 單例）start/update/end `Activity<ClassActivityAttributes>`。倒數用 SwiftUI timer text，App 沒跑也會 tick；controller 只在課堂邊界重推 ContentState（`syncOnForeground()` 在 `scenePhase == .active`）。`liveActivity_autoStart` 設定切自動／手動，皆在 ServicesView「課程動態」區。

> **限制（已告知使用者）**：真正「App 關閉時自己彈出」需 ActivityKit push（伺服器），超出範圍；此處「自動」是前景／背景刷新的 best-effort。

**開發者工具** — `Views/DevToolsView.swift`（`#if DEBUG` 編譯）注入錨定在「現在」的合成 `WidgetSnapshot`，讓暑假（真實課表為空）也能跑小工具與 Live Activity 的真實 code path；含「還原真實資料」(`WidgetBridge.updateFromCache()`)。

---

## 9. 建置 / 驗證

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcrun xcodebuild -project NTUE.unofficial.xcodeproj \
  -scheme NTUE.unofficial \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' build
```

- SwiftSoup 是唯一 SPM 相依。
- 命令列只有 CommandLineTools 時，Widget／簽章相關用：`-destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO`。
- App Group provisioning 無法用 CLI 測（簽章關閉）；首次 Xcode 真機建置會自動註冊群組。
- 無法在模擬器自動測登入（computer-use 無錄影權限）——登入／資料由使用者真機手動驗證。

---

## 10. 設計原則

- **讀取功能預設原生 scraping**；只有有風險的寫入或棘手的官方文件產生才退回 in-app web view。
- 使用者重視畢業／繳交相關的正確性，故修業進度、在學證明等寧可直接呈現官方 PDF，也不自行重組表單。
- `Shared/` 刻意純 Foundation，讓 Widget 不會被拉進 SwiftSoup／網路相依。
