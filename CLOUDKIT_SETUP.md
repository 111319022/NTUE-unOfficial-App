# CloudKit 遠端設定指南

App 現在會從 CloudKit **公開資料庫（Public Database）** 讀三種資料，你在
CloudKit Dashboard 改，所有使用者就會更新，**不必發新版 App**：

| 資料 | Record Type | 用途 |
|------|-------------|------|
| 學期行事曆 | `AcademicTerm` | 開學 / 課程結束(16週) / 學期結束(18週) / 選課開始日，驅動首頁「學期倒數」「假期中」與選課頁預設學期 |
| 校園活動行事曆 | `CalendarEvent` | 開學典禮、結業式、考試週、校慶… 顯示在「其他服務 → 校園行事曆」 |
| 強制更新設定 | `AppConfig` | 低於指定版本時強制跳出更新畫面 |

Container：`iCloud.com.rayhsu63.NTUE-unofficial`

---

## 一次性設定（照順序做）

### 1. 在 Xcode 加上 CloudKit capability
Entitlements 檔已經幫你加好 CloudKit 的 key 了。開 Xcode 後請確認：
- 選 **NTUE.unofficial** target → **Signing & Capabilities**
- 應該會看到 **iCloud** capability，且 **CloudKit** 已勾、container 是
  `iCloud.com.rayhsu63.NTUE-unofficial`（若沒出現，按 **+ Capability** 加 iCloud，
  勾 CloudKit，再勾這個 container；automatic signing 會自動處理 App ID）。
- 裝置 / 模擬器要**登入 iCloud**（設定 → Apple ID）才能讀寫。

### 2. 用 App 內的種子按鈕自動建立 schema（免手打欄位）
1. 用 **Debug** build 跑 App（真機或模擬器，已登入 iCloud）。
2. 進 **其他服務 → 開發者後台 → CloudKit → 「寫入種子資料到 CloudKit」**
   （第一次還看不到「開發者後台」入口是正常的，先看下面〈開發者模式白名單〉解鎖）。
3. 這會把內建學期 + 範例活動 + 一筆 AppConfig 寫進 **Development** 環境，
   CloudKit 會**自動建立對應的 record types 與欄位**。

> 也可以手動在 Dashboard 建 record type，欄位定義見文末。種子按鈕只是幫你省事。

### 3. 把 schema 推到 Production
CloudKit Console → 你的 container → **Schema** → **Deploy Schema Changes…**
把 Development 的 schema 部署到 **Production**。
（注意：Deploy 只搬 **schema**，不搬**資料**。正式資料要在 Production 環境自己建，見下。）

---

## 日常維護（不必發版，也不必進 Console）

有兩種方式，平常用 App 內建的**管理後台**最方便：

### 方式 A：App 內管理後台（推薦）
跑 App → **其他服務 → 開發者後台 → CloudKit → 「管理後台」**，可直接：
- **校園活動**：新增 / 編輯 / 左滑刪除（名稱、日期、多日、分類、備註）。
- **學期行事曆**：新增 / 編輯 / 刪除學期日期。
- **強制更新設定**：設定 `最低版本`（低於此版強制更新，設 `0.0.0` 關閉）與提示文字。

寫入的**環境由 build 決定**（一個 build 一次只連一個環境，執行中無法切換）：
- Xcode Debug build → 連 **Development**（拿來測試 / 種子建 schema）。
- 想改**正式資料**（使用者實際看到的）→ 讓這個 Debug build 連 **Production**：
  在 `NTUE.unofficial.entitlements` 加一行
  ```xml
  <key>com.apple.developer.icloud-container-environment</key>
  <string>Production</string>
  ```
  重新 build 後，管理後台就會寫進正式環境。（前提：schema 已 Deploy 到 Production，見上面步驟 3。）
  管理後台畫面上的「連線」區塊會顯示目前 container,環境依此 entitlement 判定。

### 方式 B：CloudKit Console（備援）
<https://icloud.developer.apple.com/dashboard/> → 選 container → **Data** → 環境選
**Production** → Database 選 **Public Database** → New Record，欄位定義見文末。

---

## 開發者模式白名單（DevAccessPolicy）與資安

「開發者後台」不是靠 `#if DEBUG`，而是靠 CloudKit 上的**白名單**控管：只有 iCloud 帳號的識別碼（`SHA256(userRecordID)`）在 `DevAccessPolicy/main-dev-access-policy` 的 `allowedUserHashes` 內，才會在「其他服務」看到入口。**Release / TestFlight 版也適用**，方便你在正式包上維護資料。

### 第一次解鎖（拿 hash + 加白名單）
隱藏入口：**其他服務 → 關於 → 點「作者」那列 5 下**，跳出「開發者後台解鎖」：
- **Debug 版**：會多一顆「啟用開發者後台（把我加入白名單）」按鈕。按它會在目前環境建立 / 更新 `DevAccessPolicy` 並把這台裝置加進白名單——**寫入時 Development 會自動建 schema，所以你不必手動建 `DevAccessPolicy` record type**。退回「其他服務」就會看到入口。
- **Release 版**：只顯示識別碼供你複製，**沒有**自助啟用按鈕（見下方資安說明）。

流程建議：用 Debug 版跑一次 → 解鎖頁按「啟用」→ 再到 Console **Deploy Schema 到 Production**、並確認 Production 的 `DevAccessPolicy` 也有你的 hash。

### 為什麼自助啟用只留在 Debug 版
若 Release 版也能「點五下就把自己加白名單」，任何拿到 App 的人都能取得開發者後台的 **CloudKit 寫入權**（最壞可竄改「強制更新設定」把所有人擋在更新畫面）。所以 `enrollCurrentUser()` 用 `#if DEBUG` 編譯，正式包裡根本不存在這條寫入路徑；要加人只能你手動在 Console 加。

### 後端硬防線：設定 Security Roles（務必做）
CloudKit **公開資料庫預設「任何登入 iCloud 的人都能寫」**，代表高階攻擊者可繞過 App、直接用 CloudKit API 竄改 `DevAccessPolicy` 或行事曆 / 強制更新。App 端的 Debug-gating 只擋「點五下」這個入口，真正的防線要在 Console 收掉公開寫入權：

1. CloudKit Console → 你的 container → **Schema → Security Roles**（或 Record Types 內每個型別的 **Security** 分頁）。
2. 對 `_world`（未登入）與 `_icloud`（任何登入者）兩個角色，把 `DevAccessPolicy`、`AcademicTerm`、`CalendarEvent`、`AppConfig` 的權限設成**只有 READ、拿掉 WRITE / CREATE**。
3. 保留 `_creator`（記錄建立者＝你）可寫；這樣只有你的帳號能改。
4. 設定同樣要 **Deploy 到 Production** 才對正式環境生效。

> 一般使用者只需要「讀」這些資料，拿掉他們的寫入權不影響 App 功能。你自己的維護寫入是以你（record creator / 白名單帳號）的身分進行，不受影響。

---

## Schema 欄位定義（若要手動建）

### `AcademicTerm`
| 欄位 | 型別 | 說明 |
|------|------|------|
| `code` | String | 學期代碼，例 `1151` |
| `name` | String | 顯示名，例 `115 學年度 第 1 學期` |
| `start` | Date/Time | 開學日 |
| `end16` | Date/Time | 課程結束（16 週） |
| `end18` | Date/Time | 學期結束（18 週） |
| `selectionStart` | Date/Time | 選課開始日（可空）。選課頁在這天之後才把預設學期切到這個學期；沒填的底線是上一學期 `end18`（學期結束）前 14 天自動切 |

### `CalendarEvent`
| 欄位 | 型別 | 必填 | 說明 |
|------|------|:---:|------|
| `title` | String | ✅ | 活動名稱 |
| `date` | Date/Time | ✅ | 開始日期（單日活動只填這個） |
| `endDate` | Date/Time | | 結束日期（多日活動才填） |
| `category` | String | | `general`/`holiday`/`exam`/`ceremony`/`deadline`/`registration`，預設 `general` |
| `note` | String | | 補充說明 |
| `allDay` | Int64 | | `1`=整天（預設）/`0`=有時間 |

### `AppConfig`（record name 必須是 `current`）
| 欄位 | 型別 | 說明 |
|------|------|------|
| `minVersion` | String | 最低可用版本，低於此版強制更新（例 `1.5.0`）；設 `0.0.0` 等於關閉 |
| `latestVersion` | String | 最新版本（僅顯示，可空） |
| `updateTitle` | String | 更新畫面標題（可空，有預設） |
| `updateMessage` | String | 更新畫面內文（可空，有預設） |
| `updateURL` | String | App Store 連結（可空） |

### `DevAccessPolicy`（record name 必須是 `main-dev-access-policy`）
控管誰能看到 / 使用「開發者後台」的白名單。Debug 版按解鎖頁的「啟用」會自動建立這型別；手動建時欄位如下：

| 欄位 | 型別 | 說明 |
|------|------|------|
| `enabled` | Int64 | `1`=開啟白名單機制（預設當作開啟）；`0`=整個關閉開發者後台 |
| `allowedUserHashes` | List\<String\> | 允許的帳號識別碼清單（每個為 64 位小寫十六進位；從解鎖頁或被拒訊息取得） |

---

## 離線 / 容錯行為
- 讀不到 CloudKit（沒網路、還沒建 schema）時，學期倒數會用 App 內建的
  `AcademicCalendar.fallbackTerms` 保底，活動列表則顯示上次快取。
- 資料會快取在 App Group，開 App 立即顯示、背景再更新（stale-while-revalidate）。
- 正式環境（Production）預設權限：一般使用者**只能讀**，寫入要靠你在 Dashboard 操作。
