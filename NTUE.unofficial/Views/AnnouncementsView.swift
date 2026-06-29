import SwiftUI

@Observable
@MainActor
final class AnnouncementsViewModel {
    var page: MoodleService.AnnouncementsPage?
    var isLoading = false
    var errorMessage: String?

    var announcements: [MoodleAnnouncement] { page?.announcements ?? [] }
    var semesters: [SemesterSelection] { page?.semesters ?? [] }
    var newestID: String? { page?.semesters.last?.id }

    func loadDefault(forceReload: Bool = false) async {
        // Cold launch: paint the last-known page from disk while refreshing.
        if page == nil, !forceReload, let disk = DataStore.shared.cachedAnnouncements {
            page = disk
        }
        isLoading = true; errorMessage = nil
        do { page = try await DataStore.shared.moodleAnnouncements(forceReload: forceReload) }
        catch { errorMessage = error.localizedDescription }
        isLoading = false
    }

    private var cache: [String: MoodleService.AnnouncementsPage] = [:]

    func load(for selection: SemesterSelection) async {
        if let cached = cache[selection.id] { page = cached; return }
        isLoading = true; errorMessage = nil
        do {
            let result = try await MoodleService.shared.loadAnnouncements(for: selection)
            cache[selection.id] = result
            page = result
        } catch { errorMessage = error.localizedDescription }
        isLoading = false
    }
}

/// 課程公告 — each course's 公告 forum, aggregated newest-first.
struct AnnouncementsView: View {
    @State private var vm = AnnouncementsViewModel()
    @State private var sheet: WebDestination?

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
            content
        }
        .background(Theme.background)
        .navigationTitle("課程公告")
        .navigationBarTitleDisplayMode(.inline)
        .task { await initialLoad() }
        .sheet(item: $sheet) { d in NTUEWebSheet(url: d.url, title: d.title) }
    }

    @ViewBuilder
    private var content: some View {
        if vm.isLoading && vm.announcements.isEmpty {
            VStack(spacing: 12) {
                ProgressView()
                Text("正在彙整各課公告…").font(.subheadline).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = vm.errorMessage, vm.announcements.isEmpty {
            ContentUnavailableView {
                Label("無法載入公告", systemImage: "exclamationmark.triangle")
            } description: { Text(error) } actions: {
                Button("重試") { Task { await refresh() } }.buttonStyle(.borderedProminent).tint(Theme.accent)
            }
        } else if vm.announcements.isEmpty {
            ContentUnavailableView("這個學期沒有課程公告", systemImage: "megaphone")
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
            .refreshable { await refresh() }
        }
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

    private func refresh() async {
        if selectedID.isEmpty || selectedID == vm.newestID {
            await vm.loadDefault(forceReload: true)
        } else if let sel = vm.semesters.first(where: { $0.id == selectedID }) {
            await vm.load(for: sel)
        }
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
