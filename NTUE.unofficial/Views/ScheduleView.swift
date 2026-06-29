import SwiftUI

@Observable
@MainActor
final class ScheduleViewModel {
    var timetable = Timetable(periods: [])
    var semesters: [SemesterSelection] = []
    var selected: SemesterSelection?
    var isLoading = false
    var errorMessage: String?

    private let service = NTUEService.shared
    private var cache: [String: Timetable] = [:]   // keyed by semester id

    init() {
        if let cached = DataStore.shared.cachedTimetable { timetable = cached }
    }

    func load(_ selection: SemesterSelection? = nil, studentId: String, forceReload: Bool = false) async {
        let key = selection?.id ?? "default"
        if !forceReload, let cached = cache[key] { timetable = cached; return }   // memory
        // Past semesters never change → read the on-disk snapshot, skip the network.
        if !forceReload, let sel = selection, NTUETerm.isPast(sel),
           let disk = Persistence.load(Timetable.self, key: "timetable_\(sel.id)"), !disk.isEmpty {
            cache[key] = disk
            timetable = disk
            return
        }

        isLoading = true
        errorMessage = nil
        do {
            // The default semester is shared with 首頁 via DataStore (prefetched);
            // an explicit semester switch always hits the network fresh.
            let page: NTUEService.SchedulePage
            if selection == nil {
                page = try await DataStore.shared.timetable(studentId: studentId, forceReload: forceReload)
                if !page.timetable.isEmpty || timetable.isEmpty { timetable = page.timetable }
            } else {
                page = try await service.loadTimetable(for: selection, studentId: studentId)
                timetable = page.timetable
            }
            if !page.timetable.isEmpty {
                cache[key] = page.timetable
                if let id = page.selected?.id { cache[id] = page.timetable }
                if let sel = selection, NTUETerm.isPast(sel) {
                    Persistence.save(page.timetable, key: "timetable_\(sel.id)")
                }
            }
            if semesters.isEmpty, !page.semesters.isEmpty { semesters = page.semesters }
            selected = page.selected
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
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

    var body: some View {
        VStack(spacing: 0) {
            if !semesterList.isEmpty && !selectedID.isEmpty {
                SemesterBar(options: semesterList.map(\.option), selectedID: $selectedID)
                    .onChange(of: selectedID) { _, id in
                        guard id != loadedID else { return }
                        Task { await pick(id) }
                    }
            }
            if !vm.timetable.isEmpty {
                Picker("檢視", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            Group {
                if vm.isLoading && vm.timetable.isEmpty {
                    ProgressView("載入課表…").frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = vm.errorMessage, vm.timetable.isEmpty {
                    errorState(error)
                } else if vm.timetable.isEmpty {
                    ContentUnavailableView("此學期沒有課表", systemImage: "calendar.badge.exclamationmark")
                } else {
                    content
                }
            }
        }
        .navigationTitle("我的課表")
        .navigationBarTitleDisplayMode(.inline)
        .background(Theme.background)
        .task { await initialLoad() }
    }

    private func initialLoad() async {
        guard selectedID.isEmpty else { return }   // run once
        await reload()
        // Default to the newest semester (current); if that differs from what the
        // default load returned, the bar's onChange will correct it.
        selectedID = semesterList.last?.id ?? vm.selected?.id ?? ""
        loadedID = vm.selected?.id ?? ""
    }

    private func pick(_ id: String) async {
        loadedID = id
        await reload(semesterList.first { $0.id == id })
    }

    private func reload(_ selection: SemesterSelection? = nil, forceReload: Bool = false) async {
        await vm.load(selection ?? vm.selected, studentId: appState.studentInfo.studentId, forceReload: forceReload)
    }

    @ViewBuilder
    private var content: some View {
        switch mode {
        case .grid: TimetableGridView(periods: vm.visiblePeriods, weekdays: vm.activeWeekdays)
            .refreshable { await reload(forceReload: true) }
        case .list: CourseListView(courses: vm.timetable.courseSummaries)
            .refreshable { await reload(forceReload: true) }
        }
    }

    private func errorState(_ error: String) -> some View {
        ContentUnavailableView {
            Label("載入失敗", systemImage: "wifi.slash")
        } description: { Text(error) } actions: {
            Button("重試") { Task { await reload() } }.buttonStyle(.borderedProminent)
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
