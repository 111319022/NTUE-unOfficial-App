import SwiftUI

@Observable
@MainActor
final class GradesViewModel {
    var grades: [Grade] = []
    var student = StudentInfo()
    var semesters: [SemesterSelection] = []
    var selected: SemesterSelection?
    var isLoading = false
    var errorMessage: String?

    /// 畫面上這份成績是「哪一個學期的」。`nil` = 還沒確定(開機時先畫的舊快取),
    /// 用來判斷該不該讓位給 spinner。
    private(set) var shownID: String?

    private let service = NTUEService.shared
    private var cache: [String: NTUEService.GradesPage] = [:]   // keyed by semester id
    private let loader = LatestTask()

    func load(_ selection: SemesterSelection? = nil, forceReload: Bool = false) async {
        await loader.run { [self] in await performLoad(selection, forceReload: forceReload) }
    }

    private func performLoad(_ selection: SemesterSelection?, forceReload: Bool) async {
        let key = selection?.id ?? "default"
        if !forceReload, let cached = cache[key] {   // instant re-visit
            errorMessage = nil
            apply(cached, shownID: selection?.id ?? cached.selected?.id)
            return
        }

        // Cold launch: paint the last-known default semester from disk while the
        // network refresh runs, so the screen isn't blank.
        if selection == nil, !forceReload, grades.isEmpty,
           let disk = DataStore.shared.cachedGrades {
            apply(disk, shownID: nil)
        }

        // 明確切學期 → 先把上一個學期的成績收掉。學校要等 ~10 秒,繼續掛著舊
        // 資料會讓人以為根本沒切成功。
        if let selection, shownID != selection.id {
            grades = []
            shownID = nil
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            // Default semester is prefetched/shared via DataStore; a semester
            // switch fetches fresh.
            let page = selection == nil
                ? try await DataStore.shared.grades(forceReload: forceReload)
                : try await service.loadGrades(for: selection)
            if Task.isCancelled { return }   // 使用者已經切到別的學期了
            cache[key] = page
            if let id = page.selected?.id { cache[id] = page }
            apply(page, shownID: selection?.id ?? page.selected?.id)
        } catch {
            if Task.isCancelled || error.isRequestCancellation { return }
            errorMessage = error.localizedDescription
        }
    }

    private func apply(_ page: NTUEService.GradesPage, shownID id: String?) {
        grades = page.grades
        if !page.student.isEmpty { student = page.student }
        if semesters.isEmpty, !page.semesters.isEmpty { semesters = page.semesters }   // never shrink
        selected = page.selected
        shownID = id
    }

    // Summary stats (only courses that actually carry a numeric score).
    var scoredGrades: [Grade] { grades.filter(\.hasScore) }

    var totalCredits: Double {
        grades.filter(\.isPassed).compactMap(\.creditsValue).reduce(0, +)
    }

    var weightedAverage: Double? {
        let items = scoredGrades.compactMap { g -> (Double, Double)? in
            guard let s = g.scoreValue, let c = g.creditsValue, c > 0 else { return nil }
            return (s, c)
        }
        guard !items.isEmpty else { return nil }
        let totalWeight = items.reduce(0) { $0 + $1.1 }
        let weighted = items.reduce(0) { $0 + $1.0 * $1.1 }
        return totalWeight > 0 ? weighted / totalWeight : nil
    }
}

struct GradesView: View {
    @Environment(AppState.self) private var appState
    @State private var vm = GradesViewModel()
    @State private var transcriptVM = TranscriptViewModel()
    @State private var selectedID = ""
    @State private var loadedID: String?

    private static let allID = "all"

    /// The student's enrolled span (by 年級); falls back to the server list.
    private var semesterList: [SemesterSelection] {
        let base = appState.studentInfo.gradeLevel.map { NTUETerm.enrolledSemesters(grade: $0) } ?? vm.semesters
        return NTUETerm.upToCurrent(base)
    }

    private var options: [SemesterOption] {
        [SemesterOption(id: Self.allID, label: "歷年總表")] + semesterList.map(\.option)
    }

    var body: some View {
        VStack(spacing: 0) {
            if !options.isEmpty && !selectedID.isEmpty {
                SemesterBar(options: options, selectedID: $selectedID,
                            isLoading: selectedID == Self.allID ? transcriptVM.isLoading : vm.isLoading)
                    .onChange(of: selectedID) { _, id in
                        guard id != loadedID else { return }
                        Task { await select(id) }
                    }
            }
            content
        }
        .navigationTitle("成績")
        .navigationBarTitleDisplayMode(.inline)
        .background(Theme.background)
        .toolbar {
            if selectedID == Self.allID {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        GradeAnalysisView(vm: transcriptVM)
                    } label: {
                        Label("成績分析", systemImage: "chart.xyaxis.line")
                    }
                }
            }
        }
        .task { await initialLoad() }
    }

    private func initialLoad() async {
        guard loadedID == nil else { return }
        await vm.load()
        await fallBackToPreviousIfEmpty()
        loadedID = vm.selected?.id ?? ""
        selectedID = loadedID ?? ""
    }

    /// 學期初本學期還沒登任何成績時,自動改看上一個學期。
    /// 上一學期同樣沒有成績(例如大一新生)就維持原本的學期。
    private func fallBackToPreviousIfEmpty() async {
        guard vm.grades.isEmpty, vm.errorMessage == nil,
              let current = vm.selected,
              let previous = NTUETerm.previousSemester(before: current),
              semesterList.contains(previous) else { return }

        await vm.load(previous)
        if vm.grades.isEmpty { await vm.load(current) }   // 兩個都空 → 回到原本學期(走快取)
    }

    private func select(_ id: String) async {
        loadedID = id
        if id == Self.allID {
            await transcriptVM.load()   // loads every semester once
        } else if let sem = semesterList.first(where: { $0.id == id }) {
            await vm.load(sem)
        }
    }

    @ViewBuilder
    private var content: some View {
        if selectedID == Self.allID {
            TranscriptContent(vm: transcriptVM)
        } else if vm.isLoading && vm.grades.isEmpty {
            ProgressView("載入成績…").frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = vm.errorMessage, vm.grades.isEmpty {
            errorState(error)
        } else if vm.grades.isEmpty {
            ContentUnavailableView("此學期沒有成績", systemImage: "doc.text.magnifyingglass")
        } else {
            semesterContent
        }
    }

    private var semesterContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                summaryCard
                ForEach(vm.grades) { GradeCard(grade: $0) }
            }
            .padding(16)
        }
        .background(Theme.background)
        .refreshable { await vm.load(vm.selected, forceReload: true) }
        .overlay(alignment: .top) {
            if vm.isLoading { ProgressView().padding(8) }
        }
    }

    private var summaryCard: some View {
        Card {
            VStack(spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(vm.selected?.displayLabel ?? "本學期")
                            .font(.headline)
                        if !vm.student.name.isEmpty {
                            Text("\(vm.student.name)　\(vm.student.className)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
                Divider()
                HStack {
                    stat("平均", vm.weightedAverage.map { String(format: "%.1f", $0) } ?? "—")
                    Divider().frame(height: 36)
                    stat("取得學分", String(format: "%.0f", vm.totalCredits))
                    Divider().frame(height: 36)
                    stat("修課數", "\(vm.grades.count)")
                }
            }
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.title2.bold()).foregroundStyle(Theme.accent)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func errorState(_ error: String) -> some View {
        ContentUnavailableView {
            Label("載入失敗", systemImage: "wifi.slash")
        } description: {
            Text(error)
        } actions: {
            Button("重試") { Task { await vm.load(vm.selected) } }
                .buttonStyle(.borderedProminent)
        }
    }

}

struct GradeCard: View {
    let grade: Grade

    var body: some View {
        Card {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(grade.courseName)
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 6) {
                        if !grade.instructor.isEmpty {
                            Text(grade.instructor)
                        }
                        Text(grade.courseCode)
                            .foregroundStyle(.tertiary)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    HStack(spacing: 6) {
                        Pill(text: grade.isRequired ? "必修" : "選修",
                             color: grade.isRequired ? Theme.accent : .blue)
                        Pill(text: "\(grade.credits) 學分", color: .gray)
                        if !grade.note.isEmpty {
                            Pill(text: grade.note, color: .orange)
                        }
                    }
                }
                Spacer(minLength: 8)
                scoreBadge
            }
        }
    }

    private var scoreBadge: some View {
        VStack(spacing: 2) {
            Text(grade.score.isEmpty ? "—" : grade.score)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.scoreColor(grade.scoreValue))
            if !grade.passed.isEmpty {
                Text(grade.isPassed ? "及格" : "不及格")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(grade.isPassed ? .green : .red)
            }
        }
        .frame(minWidth: 56)
    }
}
