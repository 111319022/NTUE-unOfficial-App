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

    func load(_ selection: SemesterSelection? = nil) async {
        isLoading = true
        errorMessage = nil
        do {
            let page = try await service.loadLeaveRecords(for: selection)
            records = page.records
            if !page.semesters.isEmpty { semesters = page.semesters }
            selected = page.selected
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

struct LeaveDetailView: View {
    @State private var vm = LeaveDetailViewModel()

    var body: some View {
        Group {
            if vm.isLoading && vm.records.isEmpty {
                ProgressView("載入請假紀錄…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = vm.errorMessage, vm.records.isEmpty {
                ContentUnavailableView {
                    Label("載入失敗", systemImage: "wifi.slash")
                } description: { Text(error) } actions: {
                    Button("重試") { Task { await vm.load(vm.selected) } }.buttonStyle(.borderedProminent)
                }
            } else if vm.records.isEmpty {
                ContentUnavailableView("此學期沒有請假紀錄", systemImage: "calendar.badge.checkmark")
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(vm.records) { record in
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
                .background(Color(.systemGroupedBackground))
                .refreshable { await vm.load(vm.selected) }
            }
        }
        .navigationTitle("請假明細")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !vm.semesters.isEmpty {
                    Menu {
                        ForEach(vm.semesters) { sem in
                            Button {
                                Task { await vm.load(sem) }
                            } label: {
                                if sem.id == vm.selected?.id {
                                    Label(sem.shortLabel, systemImage: "checkmark")
                                } else { Text(sem.shortLabel) }
                            }
                        }
                    } label: { Label(vm.selected?.shortLabel ?? "學期", systemImage: "calendar") }
                }
            }
        }
        .task { if vm.records.isEmpty { await vm.load() } }
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
        .background(Color(.systemGroupedBackground))
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
