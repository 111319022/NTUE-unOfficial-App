import SwiftUI
import UIKit
import WidgetKit

/// Developer test bench, styled after the sibling TPASS app's developer
/// dashboard. Access is gated at runtime by the CloudKit whitelist
/// (`DeveloperAccessService`) rather than `#if DEBUG`, so the developer can reach
/// it on their own device even in a TestFlight / App Store build.
///
/// The app's widgets and Live Activity have nothing to show outside the
/// semester, because the real `Timetable` is empty in the summer. The 注入 section
/// writes a synthetic `WidgetSnapshot` — anchored to *now* so a class always
/// looks "in progress" — straight into the shared App Group. From there the
/// widgets and Live Activity run their *real* code paths (`contentState(from:)`,
/// `remainingToday`, the timeline provider's boundary entries), so this exercises
/// the actual pipeline, not a mock view.
struct DevToolsView: View {
    @State private var snapshot = SharedStore.load()
    @State private var liveRunning = LiveActivityController.shared.isRunning
    @State private var lastAction: String?
    @State private var seeding = false
    @State private var seedResult: String?
    @State private var importing115 = false
    @State private var import115Result: String?
    @State private var userHash: String?
    @State private var copied = false

    private let liveEnabled = LiveActivityController.shared.systemEnabled

    var body: some View {
        List {
            appInfoSection
            identitySection
            statusSection
            cloudKitSection
            injectSection
            liveActivitySection
            restoreSection
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("開發者後台")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { refresh() }
        .task { userHash = await DeveloperAccessService.currentUserHash() }
    }

    // MARK: - App info

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    private var isDebugBuild: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    private var appInfoSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: "graduationcap.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text("NTUE 開發者後台").font(.headline)
                    Text("v\(appVersion)")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(isDebugBuild ? "DEBUG" : "RELEASE")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(isDebugBuild ? .orange : .green)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Capsule().fill((isDebugBuild ? Color.orange : Color.green).opacity(0.12)))
            }
            .padding(.vertical, 4)
            .listRowBackground(Color.clear)
        }
    }

    // MARK: - Developer identity (whitelist enrollment)

    private var identitySection: some View {
        Section {
            Button {
                if let userHash {
                    UIPasteboard.general.string = userHash
                    withAnimation { copied = true }
                }
            } label: {
                devRow("識別碼（點按複製）",
                       subtitle: userHash ?? "讀取中…（需登入 iCloud）",
                       icon: copied ? "checkmark" : "doc.on.doc",
                       color: Theme.iconBlue,
                       mono: true)
            }
            .disabled(userHash == nil)
            .foregroundStyle(.primary)
        } header: {
            Text("開發者身分")
        } footer: {
            Text("把這串識別碼加進 CloudKit 的 DevAccessPolicy/main-dev-access-policy 的 allowedUserHashes,這台裝置的 iCloud 帳號就能看到「開發者後台」(Release 版也適用)。")
        }
    }

    // MARK: - Sections

    private var statusSection: some View {
        Section {
            LabeledContent("Live Activity 系統開關", value: liveEnabled ? "已開啟" : "已關閉")
            LabeledContent("目前是否執行中", value: liveRunning ? "是" : "否")
            LabeledContent("快照產生時間", value: snapshotTime)
            LabeledContent("課程數 / 作業數", value: "\(snapshot.classes.count) / \(snapshot.assignments.count)")
            if let current = snapshot.currentClass() {
                LabeledContent("目前這節", value: current.courseName)
            }
        } header: {
            Text("狀態")
        } footer: {
            if let lastAction {
                Text(lastAction).foregroundStyle(Theme.accent)
            } else {
                Text("注入測試資料後,回主畫面 / 鎖定畫面即可看到小工具與課程動態。")
            }
        }
    }

    private var cloudKitSection: some View {
        Section {
            NavigationLink {
                AdminView()
            } label: {
                devRow("管理後台",
                       subtitle: "新增 / 編輯 行事曆、學期、強制更新設定",
                       icon: "square.grid.2x2.fill",
                       color: Theme.iconMaroon)
            }

            Button {
                seeding = true
                seedResult = nil
                Task {
                    do {
                        let s = try await CloudKitSeeder.seedAll()
                        seedResult = "已寫入 \(s.terms) 學期、\(s.events) 活動、AppConfig。到 CloudKit Console 按 Deploy Schema 推到 Production。"
                        await RemoteConfigService.shared.refresh()
                    } catch {
                        seedResult = "失敗：\(error.localizedDescription)（確認已登入 iCloud 且已加入 CloudKit capability）"
                    }
                    seeding = false
                }
            } label: {
                if seeding {
                    HStack { ProgressView(); Text("寫入中…") }
                } else {
                    devRow("寫入種子資料到 CloudKit",
                           subtitle: "建立 schema + 範例學期 / 活動 / AppConfig",
                           icon: "icloud.and.arrow.up.fill",
                           color: Theme.iconBlue)
                }
            }
            .disabled(seeding)
            .foregroundStyle(.primary)

            Button {
                importing115 = true
                import115Result = nil
                Task {
                    do {
                        let n = try await Calendar115Importer.importAll()
                        import115Result = "已匯入 \(n) 筆 115 學年度校園活動到 CloudKit。可到「管理後台」增刪。"
                        await RemoteConfigService.shared.refresh()
                    } catch {
                        import115Result = "失敗：\(error.localizedDescription)（確認已登入 iCloud、schema 已建立）"
                    }
                    importing115 = false
                }
            } label: {
                if importing115 {
                    HStack { ProgressView(); Text("匯入中…") }
                } else {
                    devRow("匯入 115 學年度行事曆",
                           subtitle: "把官方 115 行事曆的學生相關活動寫進校園行事曆",
                           icon: "calendar.badge.plus",
                           color: Theme.iconMaroon)
                }
            }
            .disabled(importing115)
            .foregroundStyle(.primary)
        } header: {
            Text("CloudKit")
        } footer: {
            Text(import115Result ?? seedResult ?? "把內建的學期行事曆 + 範例活動 + AppConfig 寫進 CloudKit 開發環境,順便自動建立 schema。之後在 Dashboard 維護真實資料即可,不必發新版。")
                .foregroundStyle((import115Result ?? seedResult) == nil ? .secondary : Theme.accent)
        }
    }

    private var injectSection: some View {
        Section {
            ForEach(DebugSnapshot.Scenario.allCases) { scenario in
                Button {
                    DebugSnapshot.inject(scenario)
                    refresh()
                    lastAction = "已注入「\(scenario.title)」並刷新小工具"
                } label: {
                    devRow(scenario.title,
                           subtitle: scenario.detail,
                           icon: scenario.icon,
                           color: Theme.accent)
                }
                .foregroundStyle(.primary)
            }
        } header: {
            Text("注入測試資料")
        } footer: {
            Text("所有時間都錨定在「現在」附近,所以注入後永遠看起來像正在進行;倒數會自己跑。")
        }
    }

    private var liveActivitySection: some View {
        Section {
            if liveRunning {
                Button(role: .destructive) {
                    LiveActivityController.shared.end()
                    liveRunning = false
                    lastAction = "已結束課程動態"
                } label: {
                    Label("結束課程動態", systemImage: "stop.circle")
                }
            } else {
                Button {
                    LiveActivityController.shared.start()
                    liveRunning = LiveActivityController.shared.isRunning
                    lastAction = liveRunning ? "已啟動課程動態" : "啟動失敗:先注入有課的情境,並確認系統已開啟 Live Activity"
                } label: {
                    devRow("用目前快照啟動課程動態",
                           subtitle: "先注入有課的情境再啟動",
                           icon: "play.circle.fill",
                           color: Theme.iconAmber)
                }
                .foregroundStyle(.primary)
                .disabled(!liveEnabled)
            }
        } header: {
            Text("課程動態（Live Activity）")
        } footer: {
            Text(liveEnabled
                 ? "讀取目前快照建立動態;先注入「上課中」或「下課等下一節」再啟動。模擬器可看靈動島(iPhone 15 Pro 以上),鎖定畫面與背景行為以真機為準。"
                 : "系統已關閉 Live Activity,請到 設定 → NTUE → 即時動態 開啟。")
        }
    }

    private var restoreSection: some View {
        Section {
            Button {
                WidgetBridge.updateFromCache()
                refresh()
                lastAction = "已還原為 App 目前快取的真實資料"
            } label: {
                Label("還原真實資料", systemImage: "arrow.counterclockwise")
            }
        } footer: {
            Text("用 App 目前快取的課表 / 作業重建快照,清掉上面注入的測試資料。")
        }
    }

    // MARK: - Row component (TPASS-style colored icon tile)

    private func devRow(_ title: String, subtitle: String, icon: String,
                        color: Color, mono: Bool = false) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(color))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body)
                Text(subtitle)
                    .font(mono ? .system(size: 11, design: .monospaced) : .caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(mono ? 1 : 2)
                    .truncationMode(.middle)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Helpers

    private var snapshotTime: String {
        guard snapshot.generatedAt != .distantPast else { return "—" }
        let f = DateFormatter()
        f.dateFormat = "MM/dd HH:mm:ss"
        return f.string(from: snapshot.generatedAt)
    }

    private func refresh() {
        snapshot = SharedStore.load()
        liveRunning = LiveActivityController.shared.isRunning
    }
}

/// Builds synthetic snapshots for the test bench. Everything is expressed
/// relative to `now`, so injected scenarios stay "live" no matter when you tap.
enum DebugSnapshot {
    enum Scenario: String, CaseIterable, Identifiable {
        case inClass        // a class is happening now
        case beforeNext     // between classes, next one soon
        case doneToday      // today's classes are over (widgets fall back to assignments)
        case fullDay        // several classes — exercises the widget lists

        var id: String { rawValue }

        var title: String {
            switch self {
            case .inClass:    return "上課中(再 20 分下課)"
            case .beforeNext: return "下課等下一節(8 分後上課)"
            case .doneToday:  return "今日課程已結束"
            case .fullDay:    return "一整天多堂課"
            }
        }

        var detail: String {
            switch self {
            case .inClass:    return "phase = inClass,並帶下一節預覽"
            case .beforeNext: return "phase = beforeNext"
            case .doneToday:  return "無剩餘課程 → 動態應自動結束"
            case .fullDay:    return "測小工具的課程列表與 timeline 翻頁"
            }
        }

        var icon: String {
            switch self {
            case .inClass:    return "book.fill"
            case .beforeNext: return "clock.fill"
            case .doneToday:  return "moon.zzz.fill"
            case .fullDay:    return "calendar"
            }
        }
    }

    static func inject(_ scenario: Scenario, now: Date = Date()) {
        let classes: [ClassSlot]
        switch scenario {
        case .inClass:
            classes = [
                slot("資料結構", "B201", "王老師", from: -25, to: 20, now: now),
                slot("演算法", "B305", "李老師", from: 50, to: 110, now: now),
            ]
        case .beforeNext:
            classes = [
                slot("線性代數", "A103", "陳老師", from: 8, to: 58, now: now),
                slot("計算機概論", "A210", "林老師", from: 88, to: 138, now: now),
            ]
        case .doneToday:
            classes = []
        case .fullDay:
            classes = [
                slot("微積分", "C101", "張老師", from: -180, to: -120, now: now),
                slot("普通物理", "C205", "黃老師", from: -25, to: 20, now: now),
                slot("英文", "D102", "Smith", from: 50, to: 110, now: now),
                slot("體育", "體育館", "吳老師", from: 140, to: 200, now: now),
            ]
        }
        let assignments = [
            AssignmentItem(id: -1, name: "Lab 3 報告", courseName: "資料結構",
                           due: now.addingTimeInterval(20 * 3600)),
            AssignmentItem(id: -2, name: "習題 5", courseName: "演算法",
                           due: now.addingTimeInterval(3 * 24 * 3600)),
        ]
        SharedStore.save(WidgetSnapshot(generatedAt: now, classes: classes, assignments: assignments))
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// A class slot whose start/end are `from`/`to` minutes relative to `now`.
    private static func slot(_ name: String, _ room: String, _ teacher: String,
                             from: Double, to: Double, now: Date) -> ClassSlot {
        ClassSlot(courseName: name, classroom: room, instructor: teacher,
                  start: now.addingTimeInterval(from * 60),
                  end: now.addingTimeInterval(to * 60))
    }
}

/// First-time unlock sheet reached from 關於 → 作者 (tap 5×). Shows this device's
/// whitelist hash (copyable) and a one-tap bootstrap that creates/updates the
/// `DevAccessPolicy` record and enrolls this iCloud account — so the developer
/// tools appear without ever touching the CloudKit Console.
struct DevUnlockSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var hash: String?
    @State private var copied = false
#if DEBUG
    @State private var working = false
    @State private var enrolled = false
    @State private var message: String?
#endif

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        if let hash {
                            UIPasteboard.general.string = hash
                            withAnimation { copied = true }
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 32, height: 32)
                                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.iconBlue))
                            Text(hash ?? "讀取中…（需登入 iCloud）")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                                .truncationMode(.middle)
                        }
                        .padding(.vertical, 2)
                    }
                    .disabled(hash == nil)
                } header: {
                    Text("你的識別碼")
                } footer: {
                    Text("這是這台裝置 iCloud 帳號的識別碼。點按可複製,手動貼到 CloudKit 白名單也行;或直接用下面的按鈕一鍵啟用。")
                }

#if DEBUG
                Section {
                    Button {
                        enroll()
                    } label: {
                        if working {
                            HStack { ProgressView(); Text("啟用中…") }
                        } else {
                            Label("啟用開發者後台（把我加入白名單）", systemImage: "key.fill")
                                .foregroundStyle(Theme.accent)
                        }
                    }
                    .disabled(working || hash == nil)
                } header: {
                    Text("自助啟用（僅 Debug 版）")
                } footer: {
                    Text(message ?? "會在目前 CloudKit 環境建立 / 更新 DevAccessPolicy,並把這台裝置加入白名單。Debug 版會自動建立 schema;要上 Release 需再到 CloudKit Console 按 Deploy to Production。")
                        .foregroundStyle(message == nil ? .secondary : (enrolled ? Theme.accent : .red))
                }

                if enrolled {
                    Section {
                        Label("已啟用,回上一頁就會看到「開發者後台」。", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                    }
                }
#else
                Section {
                    Label("複製上面的識別碼傳給開發者,由開發者手動加入白名單後即可解鎖。", systemImage: "envelope")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } footer: {
                    Text("正式版不提供自助啟用,以免任何人都能把自己加入白名單。")
                }
#endif
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("開發者後台解鎖")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .task { hash = await DeveloperAccessService.currentUserHash() }
        }
    }

#if DEBUG
    private func enroll() {
        working = true
        message = nil
        Task {
            do {
                try await DeveloperAccessService.enrollCurrentUser()
                enrolled = true
                message = "已把這台裝置加入白名單。"
            } catch {
                message = "失敗：\(error.localizedDescription)"
            }
            working = false
        }
    }
#endif
}
