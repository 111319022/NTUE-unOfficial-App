import SwiftUI

@Observable
@MainActor
final class AssignmentsViewModel {
    var courses: [MoodleCourseAssignments] = []
    var isLoading = false
    var errorMessage: String?

    func load(forceReload: Bool = false) async {
        isLoading = true
        errorMessage = nil
        do {
            courses = try await DataStore.shared.moodleAssignments(forceReload: forceReload)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

/// Identifiable wrapper so a Moodle page can drive a `.sheet(item:)`.
struct WebDestination: Identifiable {
    let url: URL
    let title: String
    var id: String { url.absoluteString }
}

/// 作業 tab — every assignment of the current semester, grouped by course, with
/// submission status. Tapping one opens the official Moodle page in-app.
struct AssignmentsView: View {
    @State private var vm = AssignmentsViewModel()
    @State private var sheet: WebDestination?

    var body: some View {
        Group {
            if vm.isLoading && vm.courses.isEmpty {
                loadingView
            } else if let error = vm.errorMessage, vm.courses.isEmpty {
                errorView(error)
            } else if vm.courses.isEmpty {
                ContentUnavailableView("沒有作業", systemImage: "checklist", description: Text("本學期目前沒有任何作業"))
            } else {
                list
            }
        }
        .navigationTitle("作業")
        .task { if vm.courses.isEmpty { await vm.load() } }
        .refreshable { await vm.load(forceReload: true) }
        .sheet(item: $sheet) { d in NTUEWebSheet(url: d.url, title: d.title) }
    }

    private var list: some View {
        List {
            ForEach(vm.courses) { group in
                Section {
                    if group.assignments.isEmpty {
                        Text("目前沒有作業")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                    } else {
                        ForEach(group.assignments) { a in
                            Button { sheet = WebDestination(url: a.url, title: a.name) } label: {
                                AssignmentRow(assignment: a)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } header: {
                    HStack {
                        Text(group.course.displayName)
                        Spacer()
                        if group.outstandingCount > 0 {
                            Text("\(group.outstandingCount) 待繳")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Theme.accent)
                        }
                    }
                }
            }
        }
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("正在從 Moodle 載入作業…")
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }

    private func errorView(_ message: String) -> some View {
        ContentUnavailableView {
            Label("無法載入作業", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("重試") { Task { await vm.load() } }
                .buttonStyle(.borderedProminent).tint(Theme.accent)
        }
    }
}

private struct AssignmentRow: View {
    let assignment: MoodleAssignment

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(assignment.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                    Text(dueLabel)
                }
                .font(.caption)
                .foregroundStyle(assignment.isOverdue ? Color.red : .secondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                Pill(text: statusLabel, color: assignment.state.color)
                if assignment.isGraded {
                    Text("成績 \(assignment.gradeText)")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private var statusLabel: String {
        switch assignment.state {
        case .submitted: return "已繳交"
        case .draft: return "草稿"
        case .notSubmitted: return assignment.isOverdue ? "逾期未繳" : "未繳交"
        case .none: return assignment.statusText.isEmpty ? "—" : assignment.statusText
        }
    }

    private var dueLabel: String {
        guard let due = assignment.dueDate else {
            return assignment.dueText.isEmpty ? "無截止日" : assignment.dueText
        }
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_TW")
        f.dateFormat = "M/d (EEE) HH:mm"
        return f.string(from: due)
    }
}
