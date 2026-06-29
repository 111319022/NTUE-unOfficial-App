import SwiftUI

@Observable
@MainActor
final class LeaveDetailViewModel {
    var records: [LeaveRecord] = []
    var semesters: [SemesterSelection] = []
    var selected: SemesterSelection?
    var isLoading = false
    var errorMessage: String?

    private let service = NTUEService.shared
    private var cache: [String: NTUEService.LeavePage] = [:]

    func load(_ selection: SemesterSelection? = nil, forceReload: Bool = false) async {
        let key = selection?.id ?? "default"
        if !forceReload, let cached = cache[key] { apply(cached); return }
        records = []          // show the loading state while the slow fetch runs
        isLoading = true
        errorMessage = nil
        do {
            let page = try await service.loadLeaveRecords(for: selection)
            cache[key] = page
            if let id = page.selected?.id { cache[id] = page }
            apply(page)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func apply(_ page: NTUEService.LeavePage) {
        records = page.records
        if semesters.isEmpty, !page.semesters.isEmpty { semesters = page.semesters }
        selected = page.selected
    }
}

@Observable
@MainActor
final class AbsenceViewModel {
    var records: [AbsenceRecord] = []
    var isLoading = false
    var errorMessage: String?

    private let service = NTUEService.shared
    private var cache: [String: [AbsenceRecord]] = [:]

    func load(for selection: SemesterSelection? = nil, forceReload: Bool = false) async {
        let key = selection?.id ?? "default"
        if !forceReload, let cached = cache[key] { records = cached; return }
        records = []
        isLoading = true
        errorMessage = nil
        do {
            let result = try await service.loadAbsences(for: selection)
            cache[key] = result
            records = result
        } catch { errorMessage = error.localizedDescription }
        isLoading = false
    }
}

/// Combined 請假 / 缺曠 view — the two attendance-related records in one place.
struct AttendanceView: View {
    @Environment(AppState.self) private var appState
    @State private var leaveVM = LeaveDetailViewModel()
    @State private var absenceVM = AbsenceViewModel()
    @State private var mode: Mode = .leave
    @State private var selectedID = ""
    @State private var leaveLoadedID: String?
    @State private var absenceLoadedID: String?

    enum Mode: String, CaseIterable { case leave = "請假紀錄", absence = "缺曠紀錄" }

    private var semesterList: [SemesterSelection] {
        let base = appState.studentInfo.gradeLevel.map { NTUETerm.enrolledSemesters(grade: $0) } ?? leaveVM.semesters
        return NTUETerm.upToCurrent(base)
    }
    private var options: [SemesterOption] { semesterList.map(\.option) }
    private var currentSemester: SemesterSelection? { semesterList.first { $0.id == selectedID } }

    var body: some View {
        VStack(spacing: 0) {
            if !options.isEmpty && !selectedID.isEmpty {
                SemesterBar(options: options, selectedID: $selectedID)
                    .onChange(of: selectedID) { _, _ in Task { await ensureLoaded() } }
            }
            Picker("", selection: $mode) {
                ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .onChange(of: mode) { _, _ in Task { await ensureLoaded() } }

            switch mode {
            case .leave: leaveContent
            case .absence: absenceContent
            }
        }
        .background(Theme.background)
        .navigationTitle("請假 / 缺曠")
        .navigationBarTitleDisplayMode(.inline)
        .task { await initialLoad() }
    }

    private func initialLoad() async {
        guard selectedID.isEmpty else { return }
        await leaveVM.load()                       // default 請假 (the opening tab)
        selectedID = leaveVM.selected?.id ?? ""
        leaveLoadedID = selectedID
        // 缺曠 loads lazily the first time the user opens that tab.
    }

    /// Loads only the visible tab for the selected semester (lazy + cached),
    /// so switching waits on one ~8s fetch instead of two.
    private func ensureLoaded() async {
        guard !selectedID.isEmpty else { return }
        switch mode {
        case .leave:
            if leaveLoadedID != selectedID {
                leaveLoadedID = selectedID
                await leaveVM.load(currentSemester)
            }
        case .absence:
            if absenceLoadedID != selectedID {
                absenceLoadedID = selectedID
                await absenceVM.load(for: currentSemester)
            }
        }
    }

    // MARK: 請假

    @ViewBuilder
    private var leaveContent: some View {
        Group {
            if leaveVM.isLoading && leaveVM.records.isEmpty {
                loading("載入請假紀錄…")
            } else if let error = leaveVM.errorMessage, leaveVM.records.isEmpty {
                retry(error) { await leaveVM.load(leaveVM.selected) }
            } else if leaveVM.records.isEmpty {
                ContentUnavailableView("此學期沒有請假紀錄", systemImage: "calendar.badge.checkmark")
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(leaveVM.records) { record in
                            NavigationLink {
                                LeaveRecordDetailView(record: record)
                            } label: {
                                LeaveRecordCard(record: record)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(16)
                }
                .refreshable { await leaveVM.load(currentSemester, forceReload: true) }
            }
        }
    }

    // MARK: 缺曠

    @ViewBuilder
    private var absenceContent: some View {
        Group {
            if absenceVM.isLoading && absenceVM.records.isEmpty {
                loading("載入缺曠紀錄…")
            } else if let error = absenceVM.errorMessage, absenceVM.records.isEmpty {
                retry(error) { await absenceVM.load(for: currentSemester) }
            } else if absenceVM.records.isEmpty {
                ContentUnavailableView("目前沒有缺曠紀錄", systemImage: "checkmark.seal.fill", description: Text("本學期全勤，繼續保持 🎉"))
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(absenceVM.records) { AbsenceCard(record: $0) }
                    }
                    .padding(16)
                }
                .refreshable { await absenceVM.load(for: currentSemester, forceReload: true) }
            }
        }
    }

    // MARK: helpers

    private func loading(_ text: String) -> some View {
        ProgressView(text).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func retry(_ message: String, action: @escaping () async -> Void) -> some View {
        ContentUnavailableView {
            Label("載入失敗", systemImage: "wifi.slash")
        } description: { Text(message) } actions: {
            Button("重試") { Task { await action() } }.buttonStyle(.borderedProminent)
        }
    }
}

struct AbsenceCard: View {
    let record: AbsenceRecord

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(record.courseName).font(.subheadline.bold())
                    Spacer()
                    Pill(text: "缺曠 \(record.absentOverTotal)", color: pillColor)
                }
                HStack(spacing: 16) {
                    if !record.teacher.isEmpty { Label(record.teacher, systemImage: "person") }
                    if !record.classGroup.isEmpty { Label(record.classGroup, systemImage: "person.3") }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if record.reachedFailThreshold {
                    Label("已達零分標準，請注意", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private var pillColor: Color {
        if record.reachedFailThreshold { return .red }
        return record.hasAbsence ? .orange : .green
    }
}

struct LeaveRecordCard: View {
    let record: LeaveRecord

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Pill(text: record.kind, color: Theme.accent)
                    Spacer()
                    statusPill
                }
                if !record.reason.isEmpty {
                    Text(record.reason)
                        .font(.subheadline)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Divider()
                HStack(spacing: 16) {
                    Label(record.dateSection, systemImage: "calendar")
                        .lineLimit(1)
                    if !record.sectionCount.isEmpty {
                        Label("\(record.sectionCount) 節", systemImage: "clock")
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var statusPill: some View {
        let (text, color): (String, Color) = switch record.statusKind {
        case .approved: (record.status.isEmpty ? "核准" : record.status, .green)
        case .pending: (record.status.isEmpty ? "簽核中" : record.status, .orange)
        case .rejected: (record.status.isEmpty ? "未通過" : record.status, .red)
        case .other: (record.status, .gray)
        }
        return Pill(text: text, color: color)
    }
}

// MARK: - Detail

struct LeaveRecordDetailView: View {
    let record: LeaveRecord

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Card {
                    HStack {
                        Pill(text: record.kind, color: Theme.accent)
                        Spacer()
                        statusPill
                    }
                }

                section(title: "假由") {
                    Text(record.reason.isEmpty ? "（無）" : record.reason)
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                section(title: "請假資訊") {
                    detailRow("請假日期 / 節次", record.dateSection)
                    Divider().padding(.vertical, 8)
                    detailRow("節數", record.sectionCount.isEmpty ? "—" : "\(record.sectionCount) 節")
                    if !record.applyDate.isEmpty {
                        Divider().padding(.vertical, 8)
                        detailRow("申請日期", record.applyDate)
                    }
                    if !record.formNumber.isEmpty {
                        Divider().padding(.vertical, 8)
                        detailRow("表單編號", record.formNumber)
                    }
                }
            }
            .padding(16)
        }
        .background(Theme.background)
        .navigationTitle("請假內容")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var statusPill: some View {
        let (text, color): (String, Color) = switch record.statusKind {
        case .approved: (record.status.isEmpty ? "核准" : record.status, .green)
        case .pending: (record.status.isEmpty ? "簽核中" : record.status, .orange)
        case .rejected: (record.status.isEmpty ? "未通過" : record.status, .red)
        case .other: (record.status, .gray)
        }
        return Pill(text: text, color: color)
    }

    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.subheadline.bold()).foregroundStyle(.secondary)
                content()
            }
        }
    }

    private func detailRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 130, alignment: .leading)
            Text(value.isEmpty ? "—" : value)
                .font(.subheadline.weight(.medium))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
