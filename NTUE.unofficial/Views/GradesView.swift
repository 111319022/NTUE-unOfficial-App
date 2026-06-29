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

    func load(_ selection: SemesterSelection? = nil, forceReload: Bool = false) async {
        isLoading = true
        errorMessage = nil
        do {
            // Default semester is prefetched/shared via DataStore; a semester
            // switch fetches fresh.
            let page: NTUEService.GradesPage
            if selection == nil {
                page = try await DataStore.shared.grades(forceReload: forceReload)
            } else {
                page = try await service.loadGrades(for: selection)
            }
            grades = page.grades
            if !page.student.isEmpty { student = page.student }
            if !page.semesters.isEmpty { semesters = page.semesters }
            selected = page.selected
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
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
    @State private var vm = GradesViewModel()

    var body: some View {
        Group {
            if vm.isLoading && vm.grades.isEmpty {
                ProgressView("載入成績…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = vm.errorMessage, vm.grades.isEmpty {
                errorState(error)
            } else if vm.grades.isEmpty {
                ContentUnavailableView("此學期沒有成績", systemImage: "doc.text.magnifyingglass")
            } else {
                content
            }
        }
        .navigationTitle("學期成績")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { semesterMenu }
        .background(Color(.systemGroupedBackground))
        .task { if vm.grades.isEmpty { await vm.load() } }
    }

    private var content: some View {
        ScrollView {
            VStack(spacing: 16) {
                summaryCard
                ForEach(vm.grades) { GradeCard(grade: $0) }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
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

    @ToolbarContentBuilder
    private var semesterMenu: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            if !vm.semesters.isEmpty {
                Menu {
                    ForEach(vm.semesters) { sem in
                        Button {
                            Task { await vm.load(sem) }
                        } label: {
                            if sem.id == vm.selected?.id {
                                Label(sem.shortLabel, systemImage: "checkmark")
                            } else {
                                Text(sem.shortLabel)
                            }
                        }
                    }
                } label: {
                    Label(vm.selected?.shortLabel ?? "學期", systemImage: "calendar")
                        .font(.subheadline)
                }
            }
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
