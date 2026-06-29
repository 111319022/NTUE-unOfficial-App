import SwiftUI

@Observable
@MainActor
final class ConductViewModel {
    var conduct: [ConductRecord] = []
    var rewards: [RewardPenaltyRecord] = []
    var isLoading = false
    var errorMessage: String?

    private let service = NTUEService.shared

    func load() async {
        isLoading = true
        errorMessage = nil
        async let c = service.loadConductRecords()
        async let r = service.loadRewardPenalties()
        do {
            conduct = try await c
            rewards = try await r
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

/// 操行成績 + 獎懲紀錄 in one screen.
struct ConductView: View {
    @State private var vm = ConductViewModel()

    var body: some View {
        Group {
            if vm.isLoading && vm.conduct.isEmpty && vm.rewards.isEmpty {
                ProgressView("載入操行 / 獎懲…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = vm.errorMessage, vm.conduct.isEmpty && vm.rewards.isEmpty {
                ContentUnavailableView {
                    Label("載入失敗", systemImage: "wifi.slash")
                } description: { Text(error) } actions: {
                    Button("重試") { Task { await vm.load() } }.buttonStyle(.borderedProminent).tint(Theme.accent)
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        conductSection
                        rewardSection
                    }
                    .padding(16)
                }
                .refreshable { await vm.load() }
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("操行 / 獎懲")
        .navigationBarTitleDisplayMode(.inline)
        .task { if vm.conduct.isEmpty && vm.rewards.isEmpty { await vm.load() } }
    }

    @ViewBuilder
    private var conductSection: some View {
        Text("操行成績").font(.headline).padding(.leading, 4)
        if vm.conduct.isEmpty {
            Card { Text("目前沒有操行成績").font(.subheadline).foregroundStyle(.secondary) }
        } else {
            ForEach(vm.conduct) { ConductCard(record: $0) }
        }
    }

    @ViewBuilder
    private var rewardSection: some View {
        Text("獎懲紀錄").font(.headline).padding(.leading, 4).padding(.top, 4)
        if vm.rewards.isEmpty {
            Card {
                Label("沒有獎懲紀錄", systemImage: "checkmark.seal.fill")
                    .font(.subheadline).foregroundStyle(.green)
            }
        } else {
            ForEach(vm.rewards) { RewardPenaltyCard(record: $0) }
        }
    }
}

private struct ConductCard: View {
    let record: ConductRecord

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(record.termLabel).font(.subheadline.bold())
                    Spacer()
                    if record.hasScore {
                        Text(record.score)
                            .font(.title3.bold())
                            .foregroundStyle(Theme.scoreColor(Double(record.score)))
                    } else {
                        Pill(text: "未公布", color: .gray)
                    }
                }
                if !record.nonZeroCounts.isEmpty {
                    FlowChips(items: record.nonZeroCounts.map { "\($0.0) \($0.1)" })
                }
            }
        }
    }
}

private struct RewardPenaltyCard: View {
    let record: RewardPenaltyRecord

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Pill(text: record.type, color: record.isPenalty ? .red : .green)
                    Spacer()
                    Text(record.termLabel).font(.caption).foregroundStyle(.secondary)
                }
                if !record.reason.isEmpty {
                    Text(record.reason).font(.subheadline)
                }
                if !record.article.isEmpty {
                    Text(record.article).font(.caption).foregroundStyle(.secondary)
                }
                if !record.eliminateStatus.isEmpty {
                    Label(record.eliminateStatus, systemImage: "arrow.uturn.backward.circle")
                        .font(.caption).foregroundStyle(.blue)
                }
            }
        }
    }
}

/// Simple wrapping row of small chips.
private struct FlowChips: View {
    let items: [String]
    var body: some View {
        HStack(spacing: 6) {
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Theme.accentSoft)
                    .foregroundStyle(Theme.accent)
                    .clipShape(Capsule())
            }
            Spacer(minLength: 0)
        }
    }
}
