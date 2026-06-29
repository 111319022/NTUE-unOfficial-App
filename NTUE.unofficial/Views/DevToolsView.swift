#if DEBUG
import SwiftUI
import WidgetKit

/// Developer-only test bench (compiled out of Release builds).
///
/// The app's widgets and Live Activity have nothing to show outside the
/// semester, because the real `Timetable` is empty in the summer. This page
/// injects a synthetic `WidgetSnapshot` — anchored to *now* so a class always
/// looks "in progress" — straight into the shared App Group. From there the
/// widgets and Live Activity run their *real* code paths (`contentState(from:)`,
/// `remainingToday`, the timeline provider's boundary entries), so this exercises
/// the actual pipeline, not a mock view.
struct DevToolsView: View {
    @State private var snapshot = SharedStore.load()
    @State private var liveRunning = LiveActivityController.shared.isRunning
    @State private var lastAction: String?

    private let liveEnabled = LiveActivityController.shared.systemEnabled

    var body: some View {
        List {
            statusSection
            injectSection
            liveActivitySection
            restoreSection
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("開發者工具")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { refresh() }
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

    private var injectSection: some View {
        Section {
            ForEach(DebugSnapshot.Scenario.allCases) { scenario in
                Button {
                    DebugSnapshot.inject(scenario)
                    refresh()
                    lastAction = "已注入「\(scenario.title)」並刷新小工具"
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(scenario.title).foregroundStyle(.primary)
                            Text(scenario.detail).font(.caption).foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: scenario.icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 29, height: 29)
                            .background(Theme.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                }
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
                    Label("用目前快照啟動課程動態", systemImage: "play.circle")
                }
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
#endif
