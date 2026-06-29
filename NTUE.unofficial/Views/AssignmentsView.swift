import SwiftUI

@Observable
@MainActor
final class AssignmentsViewModel {
    var page: MoodleService.AssignmentsPage?
    var isLoading = false
    var errorMessage: String?

    var courses: [MoodleCourseAssignments] { page?.courses ?? [] }
    var semesters: [SemesterSelection] { page?.semesters ?? [] }
    var newestID: String? { page?.semesters.last?.id }

    /// Default (newest) semester — served from the prefetched cache.
    func loadDefault(forceReload: Bool = false) async {
        isLoading = true; errorMessage = nil
        do { page = try await DataStore.shared.moodleAssignments(forceReload: forceReload) }
        catch { errorMessage = error.localizedDescription }
        isLoading = false
    }

    private var cache: [String: MoodleService.AssignmentsPage] = [:]

    /// A specific (older) semester — fetched directly, cached for instant re-visit.
    func load(for selection: SemesterSelection) async {
        if let cached = cache[selection.id] { page = cached; return }
        isLoading = true; errorMessage = nil
        do {
            let result = try await MoodleService.shared.loadCourseAssignments(for: selection)
            cache[selection.id] = result
            page = result
        } catch { errorMessage = error.localizedDescription }
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
    @State private var selectedID = ""
    @State private var loadedID: String?

    private var semesterList: [SemesterSelection] { NTUETerm.upToCurrent(vm.semesters) }

    var body: some View {
        VStack(spacing: 0) {
            if !semesterList.isEmpty {
                SemesterBar(options: semesterList.map(\.option), selectedID: $selectedID)
                    .onChange(of: selectedID) { _, id in
                        guard id != loadedID else { return }
                        Task { await pick(id) }
                    }
            }
            Group {
                if vm.isLoading && vm.courses.isEmpty {
                    loadingView
                } else if let error = vm.errorMessage, vm.courses.isEmpty {
                    errorView(error)
                } else if vm.courses.isEmpty {
                    ContentUnavailableView("沒有作業", systemImage: "checklist", description: Text("這個學期沒有任何作業"))
                } else {
                    list
                }
            }
        }
        .navigationTitle("作業")
        .task { await initialLoad() }
    }

    private func initialLoad() async {
        guard loadedID == nil else { return }
        await vm.loadDefault()
        loadedID = vm.page?.selected?.id ?? ""
        selectedID = loadedID ?? ""
    }

    private func pick(_ id: String) async {
        loadedID = id
        if id == vm.newestID {
            await vm.loadDefault()
        } else if let sel = vm.semesters.first(where: { $0.id == id }) {
            await vm.load(for: sel)
        }
    }

    /// Course-first: a scannable list of courses; tap one to see its assignments.
    private var list: some View {
        List {
            ForEach(vm.courses) { group in
                if group.assignments.isEmpty {
                    CourseRow(group: group)
                } else {
                    NavigationLink {
                        CourseAssignmentsView(group: group)
                    } label: {
                        CourseRow(group: group)
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .refreshable { await refresh() }
    }

    private func refresh() async {
        if selectedID.isEmpty || selectedID == vm.newestID {
            await vm.loadDefault(forceReload: true)
        } else if let sel = vm.semesters.first(where: { $0.id == selectedID }) {
            await vm.load(for: sel)
        }
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("正在從 Moodle 載入作業…")
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
    }

    private func errorView(_ message: String) -> some View {
        ContentUnavailableView {
            Label("無法載入作業", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("重試") { Task { await refresh() } }
                .buttonStyle(.borderedProminent).tint(Theme.accent)
        }
    }
}

/// A course row in the top-level 作業 list.
private struct CourseRow: View {
    let group: MoodleCourseAssignments

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Theme.courseColor(for: group.course.displayName))
                .frame(width: 36, height: 36)
                .overlay(Image(systemName: "book.closed.fill").font(.caption).foregroundStyle(.white))
            VStack(alignment: .leading, spacing: 2) {
                Text(group.course.displayName).font(.subheadline.weight(.medium))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if group.outstandingCount > 0 {
                Text("\(group.outstandingCount)")
                    .font(.caption.weight(.bold)).foregroundStyle(.white)
                    .frame(minWidth: 22, minHeight: 22)
                    .padding(.horizontal, 3)
                    .background(Theme.accentFill, in: Capsule())
            }
        }
        .padding(.vertical, 4)
    }

    private var subtitle: String {
        let total = group.assignments.count
        if total == 0 { return "尚無作業" }
        return group.outstandingCount > 0
            ? "\(group.outstandingCount) 待繳 · 共 \(total) 件"
            : "全部完成 · 共 \(total) 件"
    }
}

/// One course's assignments, split into 待繳 / 已完成.
struct CourseAssignmentsView: View {
    let group: MoodleCourseAssignments
    @State private var sheet: WebDestination?

    private var outstanding: [MoodleAssignment] {
        group.assignments.filter { $0.state == .notSubmitted || $0.state == .draft }
    }
    private var done: [MoodleAssignment] {
        group.assignments.filter { !($0.state == .notSubmitted || $0.state == .draft) }
    }

    var body: some View {
        List {
            if !outstanding.isEmpty {
                Section("待繳") { ForEach(outstanding) { row($0) } }
            }
            if !done.isEmpty {
                Section("已完成") { ForEach(done) { row($0) } }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle(group.course.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $sheet) { d in NTUEWebSheet(url: d.url, title: d.title) }
    }

    private func row(_ a: MoodleAssignment) -> some View {
        Button { sheet = WebDestination(url: a.url, title: a.name) } label: {
            AssignmentRow(assignment: a)
        }
        .buttonStyle(.plain)
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
