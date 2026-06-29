# NTUE.unofficial

非官方的國立臺北教育大學（NTUE）校務 App，用 SwiftUI 打造。把 iNTUE 校務系統與 Moodle 教學平台整合成一個原生 iOS 體驗：課表、成績、作業、請假缺曠、修業進度、在學證明，外加桌面小工具與課程動態（Live Activity）。

> ⚠️ 個人專案，與學校無任何官方關係。所有資料皆在裝置端直接登入校方網站抓取，**沒有任何後端伺服器**，帳密只存在裝置的 Keychain。

## 特色

- **首頁「聚焦現在」**：學期倒數、下一堂課倒數、待繳作業、今日／明日課表，一眼掌握。
- **個人週課表**：可切換學期，過去學期離線快取。
- **作業（Moodle）**：依課程分組，顯示繳交狀態；點開看官方頁面。
- **成績**：單學期成績 + 歷年成績總表（含累積學分與加權 GPA）。
- **其他服務**：修業進度（官方 PDF）、公開課表查詢、請假明細與申請、在學證明（中／英 PDF）、缺曠、操行、獎懲。
- **桌面 / 鎖定畫面小工具**：下一堂課、待繳作業、綜合資訊。
- **課程動態（Live Activity）**：上課中倒數、下一節預覽，靈動島支援。
- **暖調學院視覺**：奶油色基底 + NTUE 楓紅，完整深色模式。

## 技術概覽

| 項目 | 內容 |
| --- | --- |
| 平台 | iOS 26.0+（Widget 擴充 26.5） |
| UI | SwiftUI、`@Observable` |
| 登入 | 校園入口網 OpenID Connect（`protocol.ntue.edu.tw`） |
| 抓取 | 裝置端 `URLSession` + SwiftSoup 解析；多數頁面解析 HTML 內的 JSON island |
| 相依套件 | SwiftSoup（唯一 SPM 相依） |
| 後端 | 無 |

## 專案結構

```
NTUE.unofficial/        App 主體
  Network/              登入、抓取、解析、快取（DataStore / Persistence）
  Models/               資料模型
  Views/                各畫面
Shared/                 App 與 Widget 共用的 DTO + App Group I/O（純 Foundation）
NTUEWidgets/            Widget 擴充 + Live Activity UI
```

詳細架構、後端逆向工程細節、資料流請見 [PROJECT_GUIDE.md](PROJECT_GUIDE.md)。

## 建置

需要 Xcode（命令列只有 CommandLineTools 時請指定 `DEVELOPER_DIR`）。

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcrun xcodebuild -project NTUE.unofficial.xcodeproj \
  -scheme NTUE.unofficial \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' build
```

- SwiftSoup 透過 Swift Package Manager 自動解析。
- App Group `group.com.rayhsu63.NTUE-unofficial`（App 與 Widget 共用）會在首次真機建置時自動註冊。
- 登入與資料抓取無法在模擬器自動測試，需在真機手動驗證。

## 隱私

- 帳號密碼只存在裝置 Keychain，用於重新登入校方網站。
- 抓回的資料快取在 App 的 Application Support 與共用 App Group，登出即清除。
- 沒有第三方分析、沒有伺服器、沒有資料外傳。

## 授權 / 免責

個人學習用途。NTUE 商標與校務內容屬學校所有；本 App 不代表校方立場，使用風險自負。
