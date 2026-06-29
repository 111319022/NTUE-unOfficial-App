import SwiftUI

@Observable
@MainActor
final class AnnouncementsViewModel {
    var announcements: [MoodleAnnouncement] = []
    var isLoading = false
    var errorMessage: String?

    func load(forceReload: Bool = false) async {
        isLoading = true
        errorMessage = nil
        do {
            announcements = try await DataStore.shared.moodleAnnouncements(forceReload: forceReload)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

/// 課程公告 — each course's 公告 forum, aggregated newest-first.
struct AnnouncementsView: View {
    @State private var vm = AnnouncementsViewModel()
    @State private var sheet: WebDestination?

    var body: some View {
        Group {
            if vm.isLoading && vm.announcements.isEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("正在彙整各課公告…").font(.subheadline).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = vm.errorMessage, vm.announcements.isEmpty {
                ContentUnavailableView {
                    Label("無法載入公告", systemImage: "exclamationmark.triangle")
                } description: { Text(error) } actions: {
                    Button("重試") { Task { await vm.load() } }.buttonStyle(.borderedProminent).tint(Theme.accent)
                }
            } else if vm.announcements.isEmpty {
                ContentUnavailableView("目前沒有課程公告", systemImage: "megaphone")
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(vm.announcements) { a in
                            Button { sheet = WebDestination(url: a.url, title: a.subject) } label: {
                                AnnouncementCard(announcement: a)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(16)
                }
                .refreshable { await vm.load(forceReload: true) }
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("課程公告")
        .navigationBarTitleDisplayMode(.inline)
        .task { if vm.announcements.isEmpty { await vm.load() } }
        .sheet(item: $sheet) { d in NTUEWebSheet(url: d.url, title: d.title) }
    }
}

private struct AnnouncementCard: View {
    let announcement: MoodleAnnouncement

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Pill(text: announcement.courseName, color: Theme.courseColor(for: announcement.courseName))
                    Spacer()
                    if !announcement.dateText.isEmpty {
                        Text(announcement.dateText).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Text(announcement.subject)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                if !announcement.author.isEmpty {
                    Label(announcement.author, systemImage: "person")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
