import SwiftUI

@Observable
@MainActor
final class HomeViewModel {
    var timetable = Timetable(periods: [])
    var isLoading = false
    var errorMessage: String?

    func load(studentId: String, forceReload: Bool = false) async {
        isLoading = true
        errorMessage = nil
        do {
            let page = try await DataStore.shared.timetable(studentId: studentId, forceReload: forceReload)
            timetable = page.timetable
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    /// Apple weekday (1=Sun…7=Sat) → app weekday (1=Mon…7=Sun).
    private static func appWeekday(_ date: Date = Date()) -> Int {
        let apple = Calendar.current.component(.weekday, from: date)
        return apple == 1 ? 7 : apple - 1
    }

    private static func minutes(of date: Date = Date()) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    /// "07:10-08:00" → start minutes (430).
    private static func startMinutes(_ time: String) -> Int? {
        guard let first = time.split(separator: "-").first else { return nil }
        let parts = first.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
        return h * 60 + m
    }

    private static func endMinutes(_ time: String) -> Int? {
        let comps = time.split(separator: "-")
        guard comps.count == 2 else { return nil }
        let parts = comps[1].split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
        return h * 60 + m
    }

    var todaySessions: [TimetableSession] {
        let wd = Self.appWeekday()
        return timetable.allSessions
            .filter { $0.weekday == wd }
            .sorted { (Self.startMinutes($0.periodTime) ?? 0) < (Self.startMinutes($1.periodTime) ?? 0) }
    }

    /// The next (or current) class today.
    var nextSession: (session: TimetableSession, inProgress: Bool, minutesUntil: Int)? {
        let now = Self.minutes()
        for s in todaySessions {
            guard let start = Self.startMinutes(s.periodTime) else { continue }
            let end = Self.endMinutes(s.periodTime) ?? (start + 50)
            if now >= start && now <= end {
                return (s, true, 0)
            }
            if start > now {
                return (s, false, start - now)
            }
        }
        return nil
    }

    /// The next day (within the coming week) that has classes, starting tomorrow.
    /// Used to preview "明日課表" once today's classes are over.
    var upcomingDay: (label: String, sessions: [TimetableSession])? {
        let today = Self.appWeekday()
        for offset in 1...7 {
            let wd = (today - 1 + offset) % 7 + 1
            let sessions = timetable.allSessions
                .filter { $0.weekday == wd }
                .sorted { (Self.startMinutes($0.periodTime) ?? 0) < (Self.startMinutes($1.periodTime) ?? 0) }
            guard !sessions.isEmpty else { continue }
            return (offset == 1 ? "明日課表" : "下次上課・\(Self.weekdayName(wd))", sessions)
        }
        return nil
    }

    private static func weekdayName(_ wd: Int) -> String {
        let names = ["一", "二", "三", "四", "五", "六", "日"]
        guard (1...7).contains(wd) else { return "" }
        return "週\(names[wd - 1])"
    }
}

@Observable
@MainActor
final class HomeMoodleViewModel {
    var deadlines: [MoodleDeadline] = []
    var isLoading = false
    var loaded = false

    func load(forceReload: Bool = false) async {
        isLoading = true
        defer { isLoading = false; loaded = true }
        if let result = try? await DataStore.shared.moodleDeadlines(forceReload: forceReload) {
            deadlines = result
        }
    }
}

struct HomeView: View {
    @Environment(AppState.self) private var appState
    @State private var vm = HomeViewModel()
    @State private var moodle = HomeMoodleViewModel()
    @State private var sheet: WebDestination?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                greeting
                semesterCountdownCard
                nextClassCard
                deadlinesSection
                todaySection
                tomorrowSection
                if let error = vm.errorMessage, vm.timetable.isEmpty {
                    Text(error).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("首頁")
        .refreshable {
            await vm.load(studentId: appState.studentInfo.studentId, forceReload: true)
            await moodle.load(forceReload: true)
        }
        .task { if vm.timetable.isEmpty { await vm.load(studentId: appState.studentInfo.studentId) } }
        .task { if !moodle.loaded { await moodle.load() } }
        .sheet(item: $sheet) { d in NTUEWebSheet(url: d.url, title: d.title) }
    }

    // MARK: - Sections

    private var greeting: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(greetingText)
                    .font(.title2.bold())
                Text(dateText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var nextClassCard: some View {
        Card {
            if vm.isLoading && vm.timetable.isEmpty {
                HStack { ProgressView(); Text("載入中…").foregroundStyle(.secondary) }
            } else if let next = vm.nextSession {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label(next.inProgress ? "目前課程" : "下一堂課", systemImage: "books.vertical.fill")
                            .font(.subheadline.bold())
                            .foregroundStyle(Theme.accent)
                        Spacer()
                        if next.inProgress {
                            Pill(text: "進行中", color: .green)
                        } else if next.minutesUntil < 60 {
                            Pill(text: "\(next.minutesUntil) 分鐘後", color: .orange)
                        }
                    }
                    Text(next.session.courseName)
                        .font(.title3.bold())
                    HStack(spacing: 16) {
                        Label(next.session.periodTime, systemImage: "clock")
                        if !next.session.classroom.isEmpty {
                            Label(next.session.classroom, systemImage: "mappin.and.ellipse")
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    if !next.session.instructor.isEmpty {
                        Label(next.session.instructor, systemImage: "person")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Label("今天沒有更多課了", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .foregroundStyle(.green)
                    Text("好好休息一下吧 🎉").font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var semesterCountdownCard: some View {
        switch AcademicCalendar.countdown() {
        case .during(let term, let daysLeft):
            Card {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(term.name).font(.caption).foregroundStyle(.secondary)
                        Text(daysLeft == 0 ? "今天是本學期最後一天" : "本學期還有 \(daysLeft) 天")
                            .font(.headline)
                    }
                    Spacer()
                    Image(systemName: "calendar.badge.clock")
                        .font(.title2).foregroundStyle(Theme.accent)
                }
            }
        case .beforeStart(let term, let days):
            Card {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("距離開學").font(.caption).foregroundStyle(.secondary)
                        Text(days == 0 ? "今天開學！" : "還有 \(days) 天開學")
                            .font(.headline)
                        Text(term.name).font(.caption2).foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Image(systemName: "sun.max.fill")
                        .font(.title2).foregroundStyle(.orange)
                }
            }
        case .unknown:
            EmptyView()
        }
    }

    @ViewBuilder
    private var deadlinesSection: some View {
        if moodle.isLoading && moodle.deadlines.isEmpty {
            Card {
                HStack { ProgressView(); Text("載入作業截止…").foregroundStyle(.secondary) }
            }
        } else if !moodle.deadlines.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("作業截止").font(.headline).padding(.leading, 4)
                ForEach(moodle.deadlines) { d in
                    Button { sheet = WebDestination(url: d.url, title: d.name) } label: {
                        deadlineCard(d)
                    }
                    .buttonStyle(.plain)
                }
            }
        } else if moodle.loaded {
            Card {
                Label("目前沒有待繳作業 🎉", systemImage: "checkmark.seal.fill")
                    .font(.subheadline).foregroundStyle(.green)
            }
        }
    }

    private func deadlineCard(_ d: MoodleDeadline) -> some View {
        Card {
            HStack(spacing: 12) {
                Rectangle()
                    .fill(d.overdue ? Color.red : Theme.courseColor(for: d.courseName))
                    .frame(width: 4).clipShape(Capsule())
                VStack(alignment: .leading, spacing: 3) {
                    Text(d.name).font(.subheadline.bold()).foregroundStyle(.primary)
                    if !d.courseName.isEmpty {
                        Text(d.courseName).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                Pill(text: dueRelative(d.due, overdue: d.overdue),
                     color: d.overdue ? .red : (isDueSoon(d.due) ? .orange : Theme.accent))
            }
        }
    }

    private func isDueSoon(_ due: Date) -> Bool {
        due.timeIntervalSinceNow < 2 * 86_400
    }

    private func dueRelative(_ due: Date, overdue: Bool) -> String {
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: Date()), to: cal.startOfDay(for: due)).day ?? 0
        if overdue || days < 0 { return "已逾期" }
        switch days {
        case 0: return "今天截止"
        case 1: return "明天截止"
        default: return "\(days) 天後"
        }
    }

    @ViewBuilder
    private var todaySection: some View {
        if !vm.todaySessions.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("今日課表").font(.headline).padding(.leading, 4)
                ForEach(vm.todaySessions) { s in
                    Card {
                        HStack(spacing: 12) {
                            Rectangle()
                                .fill(Theme.courseColor(for: s.courseName))
                                .frame(width: 4).clipShape(Capsule())
                            VStack(alignment: .leading, spacing: 2) {
                                Text(s.courseName).font(.subheadline.bold())
                                Text("\(s.periodTime)　\(s.classroom)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("第\(s.periodName)節")
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
    }

    /// Previews the next class day once today's classes are done.
    @ViewBuilder
    private var tomorrowSection: some View {
        if vm.nextSession == nil, let up = vm.upcomingDay {
            VStack(alignment: .leading, spacing: 10) {
                Text(up.label).font(.headline).padding(.leading, 4)
                ForEach(up.sessions) { s in
                    Card {
                        HStack(spacing: 12) {
                            Rectangle()
                                .fill(Theme.courseColor(for: s.courseName).opacity(0.6))
                                .frame(width: 4).clipShape(Capsule())
                            VStack(alignment: .leading, spacing: 2) {
                                Text(s.courseName).font(.subheadline.bold())
                                Text("\(s.periodTime)　\(s.classroom)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("第\(s.periodName)節")
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let name = appState.studentInfo.name.isEmpty ? "同學" : appState.studentInfo.name
        let part = switch hour {
        case 5..<12: "早安"
        case 12..<18: "午安"
        default: "晚安"
        }
        return "\(part)，\(name)"
    }

    private var dateText: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_TW")
        f.dateFormat = "M月d日 EEEE"
        return f.string(from: Date())
    }
}
