import SwiftUI

@Observable
@MainActor
final class PreScheduleViewModel {
    var schedule = PreSchedule([])
    var semesters: [SemesterSelection] = []
    var selected: SemesterSelection?
    var isLoading = false
    var errorMessage: String?

    private let service = NTUEService.shared
    private var cache: [String: [SelectedCourse]] = [:]   // key "<semId>|<stage>"

    func load(stage: SelectionStage, selection: SemesterSelection?, forceReload: Bool = false) async {
        let key = "\(selection?.id ?? "default")|\(stage.rawValue)"
        if !forceReload, let cached = cache[key] {
            schedule = PreSchedule(cached)
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let page = try await service.loadCourseSelection(stage: stage, for: selection)
            cache[key] = page.courses
            if let sel = page.selected {
                cache["\(sel.id)|\(stage.rawValue)"] = page.courses
            }
            schedule = PreSchedule(page.courses)
            if semesters.isEmpty, !page.semesters.isEmpty { semesters = page.semesters }
            selected = page.selected
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct PreScheduleView: View {
    @Environment(AppState.self) private var appState
    @State private var vm = PreScheduleViewModel()
    @State private var stage: SelectionStage = .result
    @State private var selectedID = ""
    @State private var loaded = false

    /// Past + current + the upcoming (選課) term, oldest → newest.
    private var semesterList: [SemesterSelection] {
        let base = appState.studentInfo.gradeLevel.map { NTUETerm.enrolledSemesters(grade: $0) } ?? vm.semesters
        return NTUETerm.upToUpcoming(base)
    }

    private var currentSelection: SemesterSelection? {
        semesterList.first { $0.id == selectedID } ?? vm.selected
    }

    var body: some View {
        VStack(spacing: 0) {
            if !semesterList.isEmpty, !selectedID.isEmpty {
                SemesterBar(options: semesterList.map(\.option), selectedID: $selectedID)
                    .onChange(of: selectedID) { _, _ in Task { await reload() } }
            }

            Picker("階段", selection: $stage) {
                ForEach(SelectionStage.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .onChange(of: stage) { _, _ in Task { await reload() } }

            content
        }
        .navigationTitle("選課結果")
        .navigationBarTitleDisplayMode(.inline)
        .background(Theme.background)
        .task {
            guard !loaded else { return }
            loaded = true
            selectedID = NTUETerm.upcomingSemester().id
            await reload()
        }
    }

    @ViewBuilder
    private var content: some View {
        if vm.isLoading && vm.schedule.courses.isEmpty {
            ProgressView("載入選課資料…").frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = vm.errorMessage, vm.schedule.courses.isEmpty {
            errorState(error)
        } else if vm.schedule.courses.isEmpty {
            emptyState
        } else {
            ScrollView {
                VStack(spacing: 16) {
                    summaryStrip
                    if vm.schedule.hasConflict { notSelectedBanner }
                    if vm.schedule.enrolled.isEmpty {
                        Card {
                            Label("此階段沒有選上的課", systemImage: "tray")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    } else {
                        PreScheduleGridView(schedule: vm.schedule)
                        if !vm.schedule.untimedCourses.isEmpty { untimedSection }
                        courseList
                    }
                    if !vm.schedule.notEnrolled.isEmpty { notEnrolledSection }
                }
                .padding(16)
            }
            .refreshable { await reload(forceReload: true) }
        }
    }

    // MARK: - Sections

    private var summaryStrip: some View {
        HStack(spacing: 10) {
            stat("\(vm.schedule.courseCount)", "選上課程")
            stat(creditText(vm.schedule.totalCredits), "總學分")
            stat("\(vm.schedule.conflictCourses.count)", "未選中")
        }
    }

    private func stat(_ value: String, _ label: String, color: Color = .primary) -> some View {
        VStack(spacing: 3) {
            Text(value).font(.title2.bold()).foregroundStyle(color)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// Overlapping times can't survive selection (conflicts are blocked at
    /// enrolment), so an apparent clash means the course was 未選中, not a 衝堂.
    private var notSelectedBanner: some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                Label("時間重疊,可能未選中", systemImage: "exclamationmark.triangle")
                    .font(.subheadline.bold()).foregroundStyle(.secondary)
                Text(vm.schedule.conflictCourses.map(\.name).joined(separator: "、"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var untimedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("時間另訂 / 密集課程").font(.headline).padding(.leading, 4)
            ForEach(vm.schedule.untimedCourses) { c in courseCard(c, notSelected: false) }
        }
    }

    private var courseList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("已選上課程").font(.headline).padding(.leading, 4)
            ForEach(vm.schedule.enrolled) { c in
                courseCard(c, notSelected: vm.schedule.conflictCourses.contains(c))
            }
        }
    }

    /// 志願 that didn't make it — muted, only on the stage tabs.
    private var notEnrolledSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("未選中志願").font(.subheadline.bold()).foregroundStyle(.secondary).padding(.leading, 4)
            ForEach(vm.schedule.notEnrolled) { c in
                Card {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(c.name).font(.subheadline).foregroundStyle(.secondary)
                            let detail = [c.wishOrder.isEmpty ? "" : "志願\(c.wishOrder)",
                                          c.classTimeRaw, c.regMemo]
                                .filter { !$0.isEmpty }.joined(separator: "・")
                            if !detail.isEmpty {
                                Text(detail).font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                        Spacer()
                        Pill(text: c.regState.isEmpty ? "未選中" : c.regState, color: .secondary)
                    }
                }
                .opacity(0.7)
            }
        }
    }

    private func courseCard(_ c: SelectedCourse, notSelected: Bool) -> some View {
        Card {
            HStack(alignment: .top, spacing: 12) {
                Rectangle()
                    .fill(Theme.courseColor(for: c.name))
                    .frame(width: 4).clipShape(Capsule())
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(c.name).font(.subheadline.bold())
                        if notSelected { Pill(text: "未選中", color: .secondary) }
                    }
                    if !c.teacher.isEmpty {
                        Label(c.teacher, systemImage: "person").font(.caption).foregroundStyle(.secondary)
                    }
                    Label(c.classTimeRaw.isEmpty ? "時間另訂" : c.classTimeRaw, systemImage: "clock")
                        .font(.caption).foregroundStyle(.secondary)
                    if !c.classroom.isEmpty {
                        Label(c.classroom, systemImage: "mappin.and.ellipse").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(creditText(c.creditValue)) 學分").font(.caption2).foregroundStyle(.secondary)
                    if !c.studyClass.isEmpty {
                        Text(c.studyClass).font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("此階段尚無資料", systemImage: "calendar.badge.clock")
        } description: {
            Text("「最終結果」要等所有階段跑完才有資料;選課期間請查看各階段頁籤。")
        }
    }

    private func errorState(_ error: String) -> some View {
        ContentUnavailableView {
            Label("載入失敗", systemImage: "wifi.slash")
        } description: { Text(error) } actions: {
            Button("重試") { Task { await reload(forceReload: true) } }.buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Helpers

    private func reload(forceReload: Bool = false) async {
        await vm.load(stage: stage, selection: currentSelection, forceReload: forceReload)
        if selectedID.isEmpty, let sel = vm.selected { selectedID = sel.id }
    }

    private func creditText(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v)
    }
}

// MARK: - Grid

/// Weekly grid for the 預排, mirroring the real timetable. Overlapping slots
/// (multiple courses in one cell) are shown neutral as 未選中 rather than 衝堂.
struct PreScheduleGridView: View {
    let schedule: PreSchedule

    private let weekdayNames = ["", "一", "二", "三", "四", "五", "六", "日"]
    private let timeColWidth: CGFloat = 44

    private var weekdays: [Int] { schedule.activeWeekdays }
    private var periods: [NTUEPeriods.Period] { schedule.activePeriods }

    var body: some View {
        VStack(spacing: 4) {
            headerRow
            ForEach(periods, id: \.name) { period in gridRow(period) }
        }
    }

    private var headerRow: some View {
        HStack(spacing: 4) {
            Text("節次").font(.caption2.bold()).frame(width: timeColWidth)
            ForEach(weekdays, id: \.self) { wd in
                Text(weekdayNames[wd]).font(.caption.bold()).frame(maxWidth: .infinity)
            }
        }
        .foregroundStyle(.secondary)
    }

    private func gridRow(_ period: NTUEPeriods.Period) -> some View {
        HStack(alignment: .top, spacing: 4) {
            VStack(spacing: 2) {
                Text(period.name).font(.caption2.bold())
                Text(period.time.replacingOccurrences(of: "-", with: "\n"))
                    .font(.system(size: 8)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(width: timeColWidth)
            .padding(.vertical, 4)

            ForEach(weekdays, id: \.self) { wd in
                cell(schedule.courses(weekday: wd, period: period.name))
            }
        }
    }

    @ViewBuilder
    private func cell(_ courses: [SelectedCourse]) -> some View {
        if courses.isEmpty {
            RoundedRectangle(cornerRadius: 8)
                .fill(Theme.cardBackground)
                .frame(maxWidth: .infinity, minHeight: 52)
        } else {
            // Overlapping slots can't be a real 衝堂 (selection blocks them), so
            // they're shown neutral — one of the courses is effectively 未選中.
            let overlap = courses.count > 1
            let color = overlap ? Color.secondary : Theme.courseColor(for: courses[0].name)
            VStack(spacing: 2) {
                ForEach(courses) { c in
                    Text(c.name)
                        .font(.system(size: 10, weight: .semibold))
                        .lineLimit(2).minimumScaleFactor(0.7)
                }
                if overlap {
                    Text("未選中").font(.system(size: 8)).foregroundStyle(.secondary)
                } else if let room = courses.first?.classroom, !room.isEmpty {
                    Text(room).font(.system(size: 8)).foregroundStyle(.secondary)
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
        }
    }
}
