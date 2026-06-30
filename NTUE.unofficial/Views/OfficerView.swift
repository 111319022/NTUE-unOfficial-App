import SwiftUI

@Observable
@MainActor
final class OfficerViewModel {
    var records: [OfficerRecord] = []
    var isLoading = false
    var errorMessage: String?

    private let service = NTUEService.shared

    func load() async {
        isLoading = true
        errorMessage = nil
        do {
            records = try await service.loadOfficerRecords()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

/// 擔任幹部紀錄 — the student's officer / representative-team appointments.
struct OfficerView: View {
    @State private var vm = OfficerViewModel()

    var body: some View {
        Group {
            if vm.isLoading && vm.records.isEmpty {
                ProgressView("載入幹部紀錄…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = vm.errorMessage, vm.records.isEmpty {
                ContentUnavailableView {
                    Label("載入失敗", systemImage: "wifi.slash")
                } description: { Text(error) } actions: {
                    Button("重試") { Task { await vm.load() } }
                        .buttonStyle(.borderedProminent).tint(Theme.accent)
                }
            } else if vm.records.isEmpty {
                ContentUnavailableView {
                    Label("沒有幹部紀錄", systemImage: "person.text.rectangle")
                } description: {
                    Text("目前查無擔任幹部 / 代表隊紀錄")
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(vm.records) { OfficerCard(record: $0) }
                    }
                    .padding(16)
                }
                .refreshable { await vm.load() }
            }
        }
        .background(Theme.background)
        .navigationTitle("幹部紀錄")
        .navigationBarTitleDisplayMode(.inline)
        .task { if vm.records.isEmpty { await vm.load() } }
    }
}

private struct OfficerCard: View {
    let record: OfficerRecord

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(record.team).font(.subheadline.bold())
                    Spacer()
                    if !record.jobTitle.isEmpty {
                        Pill(text: record.jobTitle, color: Theme.accent)
                    }
                }
                if !record.periodLabel.isEmpty {
                    Label(record.periodLabel, systemImage: "calendar")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
