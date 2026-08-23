import SwiftUI

@Observable
@MainActor
final class ScheduleViewModel {
    var timetable = Timetable(periods: [])
    var semesters: [SemesterSelection] = []
    var selected: SemesterSelection?
    /// 畫面上這份課表是「哪一個學期的」。`nil` = 開機時先畫上去的舊快取,
    /// 還不確定屬於哪學期(所以先讓它留著,不要閃 spinner)。
    private(set) var shownID: String?
    var isLoading = false
    var errorMessage: String?

    private let service = NTUEService.shared
    private var cache: [String: Timetable] = [:]   // keyed by semester id
    private var loadTask: Task<Bool, Never>?

    init() {
        if let cached = DataStore.shared.cachedTimetable { timetable = cached }
    }

    /// 載入某學期的課表(`nil` = 本學期,走 DataStore 和首頁/小工具共用)。
    /// 回傳「那個學期真的有課表」,讓呼叫端能決定要不要退回上一個學期。
    @discardableResult
    func load(_ selection: SemesterSelection? = nil, studentId: String, forceReload: Bool = false) async -> Bool {
        // 學校的 session 是有狀態的(先 POST 學期、再 GET 課表),而且一次請求要
        // ~10 秒。兩個學期同時在跑會互相汙染,慢的那個晚回來還會蓋掉新的 ——
        // 所以先取消上一個並等它真的收手,再開始新的。
        loadTask?.cancel()
        _ = await loadTask?.value

        let task = Task { await performLoad(selection, studentId: studentId, forceReload: forceReload) }
        loadTask = task
        return await task.value
    }

    private func performLoad(_ selection: SemesterSelection?,
                             studentId: String,
                             forceReload: Bool) async -> Bool {
        // `nil` 代表本學期 —— DataStore 也是明確要這個學期,兩邊用同一把 key。
        let target = selection ?? NTUETerm.currentSemester()
        let key = target.id

        if !forceReload, let cached = cache[key] {   // memory
            show(cached, for: target)
            return !cached.isEmpty
        }
        // Past semesters never change → read the on-disk snapshot, skip the network.
        if !forceReload, NTUETerm.isPast(target),
           let disk = Persistence.load(Timetable.self, key: "timetable_\(key)"), !disk.isEmpty {
            cache[key] = disk
            show(disk, for: target)
            return true
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            // 本學期和首頁共用 DataStore(已預抓);明確切學期則直接打新的。
            let page: NTUEService.SchedulePage
            if selection == nil {
                page = try await DataStore.shared.timetable(studentId: studentId, forceReload: forceReload)
            } else {
                page = try await service.loadTimetable(for: selection, studentId: studentId)
            }
            if Task.isCancelled { return false }   // 使用者已經切到別的學期了

            if semesters.isEmpty, !page.semesters.isEmpty { semesters = page.semesters }
            selected = page.selected
            if !page.timetable.isEmpty {
                cache[key] = page.timetable
                if NTUETerm.isPast(target) {
                    Persistence.save(page.timetable, key: "timetable_\(key)")
                }
            }
            // 明確切學期 → 一定要換掉畫面,不能掛著上一個學期的課表假裝是這學期的。
            // 本學期載入回空的(學校還沒放課表)→ 先留著開機畫的舊快取,呼叫端
            // 會改看上一個學期。
            if selection != nil || !page.timetable.isEmpty || timetable.isEmpty {
                show(page.timetable, for: target)
            }
            return !page.timetable.isEmpty
        } catch {
            if Task.isCancelled || error.isCancellation { return false }
            errorMessage = error.localizedDescription
            // 切學期失敗同樣要清掉 —— 否則畫面會停在上一個學期,看起來像沒切成功。
            if selection != nil { show(Timetable(periods: []), for: target) }
            return false
        }
    }

    private func show(_ new: Timetable, for selection: SemesterSelection) {
        timetable = new
        shownID = selection.id
    }

    /// 沒有任何學期有課表時,把開機時先畫上去的舊快取收掉 —— 不然畫面會是
    /// 上學期的課表配上本學期的標題。
    func showEmpty(for selection: SemesterSelection) {
        show(Timetable(periods: []), for: selection)
    }

    /// Weekdays (1...7) that actually have sessions; defaults to Mon–Fri.
    var activeWeekdays: [Int] {
        let used = Set(timetable.allSessions.map(\.weekday))
        let weekdays = Array(1...5) + [6, 7].filter { used.contains($0) }
        return weekdays
    }

    /// Only periods that have at least one session, keeps the grid compact.
    var visiblePeriods: [TimetablePeriod] {
        timetable.periods.filter { !$0.slots.isEmpty }
    }
}

private extension Error {
    /// 被新的學期切換取消掉的請求,不算錯誤,不要跳「載入失敗」。
    var isCancellation: Bool {
        self is CancellationError || (self as? URLError)?.code == .cancelled
    }
}

struct ScheduleView: View {
    @Environment(AppState.self) private var appState
    @State private var vm = ScheduleViewModel()
    @State private var mode: Mode = .grid
    @State private var selectedID = ""
    @State private var loadedID: String?

    enum Mode: String, CaseIterable { case grid = "課表", list = "清單" }

    private var semesterList: [SemesterSelection] {
        let base = appState.studentInfo.gradeLevel.map { NTUETerm.enrolledSemesters(grade: $0) } ?? vm.semesters
        return NTUETerm.upToCurrent(base)
    }

    /// 目前選的學期。找不到就直接從 id 還原,絕不退回 `vm.selected` ——
    /// 那會默默載入「上一個看過的學期」,讓切換看起來沒有反應。
    private var currentSelection: SemesterSelection {
        semesterList.first { $0.id == selectedID }
            ?? SemesterSelection(id: selectedID)
            ?? vm.selected
            ?? NTUETerm.currentSemester()
    }

    /// 畫面上這份課表是不是「現在選的學期」的。開機時先畫的舊快取(`shownID`
    /// 還是 nil)算「還不確定」,先讓它留著。
    private var showsSelectedSemester: Bool {
        vm.shownID == nil || vm.shownID == selectedID
    }

    /// 內容區現在在演哪一齣。換學期(有快取時是同一個 tick 換完的)、或在
    /// 載入/錯誤/空白/課表之間切換,都會換一個值 —— 拿它當 identity 讓畫面
    /// 淡入淡出,而不是硬生生跳過去。切 課表/清單 不影響,那邊維持原本的即時切換。
    private var contentKey: String {
        if isSwitchingSemester { return "loading" }
        if vm.errorMessage != nil, vm.timetable.isEmpty { return "error" }
        if vm.timetable.isEmpty { return "empty" }
        return "content-\(vm.shownID ?? "")"
    }

    /// 換學期時舊的課表要讓位給 spinner —— 學校那邊一次要 ~10 秒,繼續顯示上
    /// 一個學期會讓人以為切換壞掉了。
    private var isSwitchingSemester: Bool {
        vm.isLoading && (vm.timetable.isEmpty || !showsSelectedSemester)
    }

    var body: some View {
        VStack(spacing: 0) {
            if !semesterList.isEmpty && !selectedID.isEmpty {
                SemesterBar(options: semesterList.map(\.option), selectedID: $selectedID,
                            isLoading: vm.isLoading)
                    .onChange(of: selectedID) { _, id in
                        guard id != loadedID else { return }
                        Task { await pick(id) }
                    }
            }
            VStack(spacing: 0) {
                if !vm.timetable.isEmpty && showsSelectedSemester {
                    Picker("檢視", selection: $mode) {
                        ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .transition(.opacity)
                }
                ZStack {   // 讓進場/退場的兩份重疊著交叉淡出,而不是先空一格再補上
                    stateContent
                        .id(contentKey)
                        .transition(.opacity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .animation(.easeInOut(duration: 0.22), value: contentKey)
        }
        .navigationTitle("我的課表")
        .navigationBarTitleDisplayMode(.inline)
        .background(Theme.background)
        .task { await initialLoad() }
    }

    @ViewBuilder
    private var stateContent: some View {
        if isSwitchingSemester {
            ProgressView("載入課表…").frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = vm.errorMessage, vm.timetable.isEmpty {
            errorState(error)
        } else if vm.timetable.isEmpty {
            ContentUnavailableView("此學期沒有課表", systemImage: "calendar.badge.exclamationmark")
        } else {
            content
        }
    }

    private func initialLoad() async {
        guard loadedID == nil else { return }   // run once
        let current = NTUETerm.currentSemester()
        var shown = current
        // 本學期(和首頁共用的那份)。學校在學期初還沒放課表時會是空的。
        if await reload(current) == false, vm.errorMessage == nil {
            if let fallback = await newestSemesterWithTimetable(before: current) {
                shown = fallback
            } else if vm.errorMessage == nil {
                vm.showEmpty(for: current)
            }
        }
        loadedID = shown.id
        selectedID = shown.id
    }

    /// 學期初學校還沒放本學期課表時,往前找最近一個有課表的學期來顯示 ——
    /// 標題寫著本學期、內容卻是上學期的,比直接顯示上學期還糟。
    private func newestSemesterWithTimetable(before current: SemesterSelection) async -> SemesterSelection? {
        var candidate = current
        for _ in 0..<2 {   // 最多往前兩個學期(上學期 / 再上一個)
            guard let previous = NTUETerm.previousSemester(before: candidate),
                  semesterList.contains(previous) else { return nil }
            if await reload(previous) { return previous }
            if vm.errorMessage != nil { return nil }   // 連不上就別再往前試了
            candidate = previous
        }
        return nil
    }

    private func pick(_ id: String) async {
        loadedID = id
        await reload(currentSelection)
    }

    @discardableResult
    private func reload(_ selection: SemesterSelection, forceReload: Bool = false) async -> Bool {
        // 本學期走 DataStore(首頁、小工具、上課提醒共用同一份);其他學期直接打。
        let target = selection == NTUETerm.currentSemester() ? nil : selection
        return await vm.load(target, studentId: appState.studentInfo.studentId, forceReload: forceReload)
    }

    @ViewBuilder
    private var content: some View {
        switch mode {
        case .grid: TimetableGridView(periods: vm.visiblePeriods, weekdays: vm.activeWeekdays)
            .refreshable { await reload(currentSelection, forceReload: true) }
        case .list: CourseListView(courses: vm.timetable.courseSummaries)
            .refreshable { await reload(currentSelection, forceReload: true) }
        }
    }

    private func errorState(_ error: String) -> some View {
        ContentUnavailableView {
            Label("載入失敗", systemImage: "wifi.slash")
        } description: { Text(error) } actions: {
            Button("重試") { Task { await reload(currentSelection, forceReload: true) } }
                .buttonStyle(.borderedProminent)
        }
    }

}

// MARK: - Grid

struct TimetableGridView: View {
    let periods: [TimetablePeriod]
    let weekdays: [Int]

    private let weekdayNames = ["", "一", "二", "三", "四", "五", "六", "日"]
    private let timeColWidth: CGFloat = 44

    var body: some View {
        ScrollView([.vertical]) {
            VStack(spacing: 4) {
                headerRow
                ForEach(periods) { period in
                    gridRow(period)
                }
            }
            .padding(12)
        }
    }

    private var headerRow: some View {
        HStack(spacing: 4) {
            Text("節次")
                .font(.caption2.bold())
                .frame(width: timeColWidth)
            ForEach(weekdays, id: \.self) { wd in
                Text(weekdayNames[wd])
                    .font(.caption.bold())
                    .frame(maxWidth: .infinity)
            }
        }
        .foregroundStyle(.secondary)
    }

    private func gridRow(_ period: TimetablePeriod) -> some View {
        HStack(alignment: .top, spacing: 4) {
            VStack(spacing: 2) {
                Text(period.name).font(.caption2.bold())
                Text(period.time.replacingOccurrences(of: "-", with: "\n"))
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(width: timeColWidth)
            .padding(.vertical, 4)

            ForEach(weekdays, id: \.self) { wd in
                cell(period.slots[wd])
            }
        }
    }

    private func cell(_ session: TimetableSession?) -> some View {
        Group {
            if let s = session {
                let color = Theme.courseColor(for: s.courseName)
                VStack(spacing: 2) {
                    Text(s.courseName)
                        .font(.system(size: 10, weight: .semibold))
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                    if !s.classroom.isEmpty {
                        Text(s.classroom)
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(4)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(color.opacity(0.18))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(color.opacity(0.5), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Theme.cardBackground)
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
        }
    }
}

// MARK: - List

struct CourseListView: View {
    let courses: [CourseSummary]

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(courses) { course in
                    Card {
                        HStack(alignment: .top) {
                            Rectangle()
                                .fill(Theme.courseColor(for: course.courseName))
                                .frame(width: 4)
                                .clipShape(Capsule())
                            VStack(alignment: .leading, spacing: 6) {
                                Text(course.courseName).font(.headline)
                                if !course.instructor.isEmpty {
                                    Label(course.instructor, systemImage: "person")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Label(course.scheduleText, systemImage: "clock")
                                    .font(.caption).foregroundStyle(.secondary)
                                if !course.classrooms.isEmpty {
                                    Label(course.classrooms, systemImage: "mappin.and.ellipse")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
    }
}
