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

    private let service = NTUEService.shared
    private var cache: [String: NTUEService.GradesPage] = [:]   // keyed by semester id

    func load(_ selection: SemesterSelection? = nil, forceReload: Bool = false) async {
        let key = selection?.id ?? "default"
        if !forceReload, let cached = cache[key] { apply(cached); return }   // instant re-visit

        // Cold launch: paint the last-known default semester from disk while the
        // network refresh runs, so the screen isn't blank.
        if selection == nil, !forceReload, grades.isEmpty,
           let disk = DataStore.shared.cachedGrades {
            apply(disk)
        }

        isLoading = true
        errorMessage = nil
        do {
            // Default semester is prefetched/shared via DataStore; a semester
            // switch fetches fresh.
            let page = selection == nil
                ? try await DataStore.shared.grades(forceReload: forceReload)
                : try await service.loadGrades(for: selection)
            cache[key] = page
            if let id = page.selected?.id { cache[id] = page }
            apply(page)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func apply(_ page: NTUEService.GradesPage) {
        grades = page.grades
        if !page.student.isEmpty { student = page.student }
        if semesters.isEmpty, !page.semesters.isEmpty { semesters = page.semesters }   // never shrink
        selected = page.selected
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
                SemesterBar(options: options, selectedID: $selectedID)
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
        .task { await initialLoad() }
    }

    private func initialLoad() async {
        guard loadedID == nil else { return }
        await vm.load()
        loadedID = vm.selected?.id ?? ""
        selectedID = loadedID ?? ""
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
