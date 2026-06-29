import SwiftUI

@Observable
@MainActor
final class TranscriptViewModel {
    struct SemesterGrades: Identifiable {
        let selection: SemesterSelection
        let grades: [Grade]
        var id: String { selection.id }
    }

    var semesters: [SemesterGrades] = []
    var progress: (done: Int, total: Int)?
    var isLoading = false
    var errorMessage: String?

    private let service = NTUEService.shared

    func load() async {
        guard semesters.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        do {
            // First call returns the default semester + the full semester list.
            let first = try await service.loadGrades(for: nil)
            let all = first.semesters
            if let sel = first.selected {
                append(SemesterGrades(selection: sel, grades: first.grades))
            }
            progress = (semesters.count, max(all.count, 1))

            for sem in all where sem.id != first.selected?.id {
                if let page = try? await service.loadGrades(for: sem) {
                    append(SemesterGrades(selection: sem, grades: page.grades))
                }
                progress = (semesters.count, all.count)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        progress = nil
        isLoading = false
    }

    private func append(_ item: SemesterGrades) {
        semesters.append(item)
        // Newest semester first.
        semesters.sort { ($0.selection.year, $0.selection.semester) > ($1.selection.year, $1.selection.semester) }
    }

    // MARK: - Aggregates

    private var allGrades: [Grade] { semesters.flatMap(\.grades) }

    var totalCredits: Double {
        allGrades.filter(\.isPassed).compactMap(\.creditsValue).reduce(0, +)
    }

    var cumulativeGPA: Double? { Self.weightedAverage(allGrades) }

    static func weightedAverage(_ grades: [Grade]) -> Double? {
        let items = grades.compactMap { g -> (Double, Double)? in
            guard let s = g.scoreValue, let c = g.creditsValue, c > 0 else { return nil }
            return (s, c)
        }
        guard !items.isEmpty else { return nil }
        let weight = items.reduce(0) { $0 + $1.1 }
        guard weight > 0 else { return nil }
        return items.reduce(0) { $0 + $1.0 * $1.1 } / weight
    }

    static func credits(_ grades: [Grade]) -> Double {
        grades.filter(\.isPassed).compactMap(\.creditsValue).reduce(0, +)
    }
}

/// 歷年成績總表 — every semester's grades aggregated natively, with cumulative GPA.
/// The 歷年成績 aggregate, embeddable inside the 成績 page (no nav chrome).
struct TranscriptContent: View {
    var vm: TranscriptViewModel

    var body: some View {
        Group {
            if vm.isLoading && vm.semesters.isEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("正在彙整歷年成績…").font(.subheadline).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = vm.errorMessage, vm.semesters.isEmpty {
                ContentUnavailableView {
                    Label("載入失敗", systemImage: "wifi.slash")
                } description: { Text(error) } actions: {
                    Button("重試") { Task { await vm.load() } }.buttonStyle(.borderedProminent).tint(Theme.accent)
                }
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        summaryCard
                        if let p = vm.progress, p.done < p.total {
                            Label("載入中 \(p.done)/\(p.total) 學期…", systemImage: "arrow.triangle.2.circlepath")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        ForEach(vm.semesters) { semesterSection($0) }
                    }
                    .padding(16)
                }
            }
        }
    }

    private var summaryCard: some View {
        Card {
            HStack {
                stat("累計學分", String(format: "%g", vm.totalCredits))
                Divider().frame(height: 36)
                stat("累計加權平均", vm.cumulativeGPA.map { String(format: "%.2f", $0) } ?? "—",
                     color: Theme.scoreColor(vm.cumulativeGPA))
            }
        }
    }

    private func stat(_ title: String, _ value: String, color: Color = .primary) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.title2.bold()).foregroundStyle(color)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func semesterSection(_ sem: TranscriptViewModel.SemesterGrades) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(sem.selection.displayLabel).font(.subheadline.bold())
                    Spacer()
                    let avg = TranscriptViewModel.weightedAverage(sem.grades)
                    Text("均 \(avg.map { String(format: "%.1f", $0) } ?? "—")　\(String(format: "%g", TranscriptViewModel.credits(sem.grades))) 學分")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Divider()
                ForEach(sem.grades) { g in
                    HStack(spacing: 10) {
                        Text(g.courseName).font(.caption).lineLimit(1)
                        Spacer(minLength: 8)
                        if !g.credits.isEmpty {
                            Text("\(g.credits)學分").font(.caption2).foregroundStyle(.tertiary)
                        }
                        Text(g.score.isEmpty ? "—" : g.score)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.scoreColor(g.scoreValue))
                            .frame(width: 38, alignment: .trailing)
                    }
                }
                if sem.grades.isEmpty {
                    Text("此學期無成績").font(.caption).foregroundStyle(.tertiary)
                }
            }
        }
    }
}
