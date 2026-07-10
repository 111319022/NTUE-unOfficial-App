import SwiftUI

/// 校園行事曆 — events maintained remotely in CloudKit. Shows the current
/// semester's countdown plus a dated list of活動 / 假期 / 考試 / 典禮 etc.
struct CalendarView: View {
    @State private var config = RemoteConfigService.shared
    @State private var scope: Scope = .upcoming

    enum Scope: String, CaseIterable, Identifiable {
        case upcoming = "即將到來"
        case all = "全部"
        var id: String { rawValue }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                semesterCard
                Picker("", selection: $scope) {
                    ForEach(Scope.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                if displayedEvents.isEmpty {
                    emptyState
                } else {
                    ForEach(groupedMonths, id: \.key) { month in
                        monthSection(title: month.key, events: month.value)
                    }
                }
            }
            .padding(16)
        }
        .background(Theme.background)
        .navigationTitle("校園行事曆")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await config.refresh() }
        .task { await config.refresh() }
        .overlay(alignment: .bottom) {
            if let err = config.lastError {
                Text(err).font(.caption2).foregroundStyle(.secondary)
                    .padding(8).background(.ultraThinMaterial, in: Capsule())
                    .padding(.bottom, 8)
            }
        }
    }

    // MARK: Semester card

    @ViewBuilder
    private var semesterCard: some View {
        switch AcademicCalendar.countdown() {
        case .during(let term, let daysLeft):
            infoCard(icon: "book.fill", tint: Theme.accent,
                     title: term.name,
                     detail: "本學期剩 \(daysLeft) 天　·　\(dateRange(term.start, AcademicCalendar.end(of: term)))")
        case .beforeStart(let term, let days):
            infoCard(icon: "sun.max.fill", tint: Theme.amber,
                     title: "假期中",
                     detail: days > 0 ? "距 \(term.name) 開學還有 \(days) 天" : "新學期即將開始")
        case .unknown:
            EmptyView()
        }
    }

    private func infoCard(icon: String, tint: Color, title: String, detail: String) -> some View {
        Card {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(tint)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: Month sections

    private func monthSection(title: String, events: [CalendarEvent]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline).padding(.leading, 4)
            ForEach(events) { eventRow($0) }
        }
    }

    private func eventRow(_ e: CalendarEvent) -> some View {
        Card {
            HStack(spacing: 14) {
                VStack(spacing: 1) {
                    Text(dayNumber(e.date)).font(.title3.bold()).foregroundStyle(Theme.accent)
                    Text(weekdayShort(e.date)).font(.caption2).foregroundStyle(.secondary)
                }
                .frame(width: 40)

                Rectangle().fill(Theme.accent.opacity(0.15)).frame(width: 1, height: 34)

                VStack(alignment: .leading, spacing: 3) {
                    Text(e.title).font(.subheadline.bold())
                    HStack(spacing: 6) {
                        Label(e.category.label, systemImage: e.category.icon)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        if e.endDate != nil || !e.allDay {
                            Text(timeRange(e)).font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                    if let note = e.note {
                        Text(note).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                if e.isOngoing() {
                    Pill(text: "進行中", color: Theme.amber)
                }
            }
        }
    }

    private var emptyState: some View {
        Card {
            VStack(spacing: 8) {
                Image(systemName: "calendar")
                    .font(.system(size: 30)).foregroundStyle(.secondary)
                Text(scope == .upcoming ? "目前沒有即將到來的活動" : "尚無行事曆資料")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
    }

    // MARK: Data

    private var displayedEvents: [CalendarEvent] {
        scope == .upcoming ? config.upcomingEvents() : config.events
    }

    /// Events grouped into "yyyy年M月" sections, ordered chronologically.
    private var groupedMonths: [(key: String, value: [CalendarEvent])] {
        let cal = Calendar.current
        let groups = Dictionary(grouping: displayedEvents) { e -> DateComponents in
            cal.dateComponents([.year, .month], from: e.date)
        }
        return groups
            .sorted { ($0.key.year!, $0.key.month!) < ($1.key.year!, $1.key.month!) }
            .map { (monthTitle($0.key), $0.value.sorted { $0.date < $1.date }) }
    }

    // MARK: Formatting

    private func monthTitle(_ c: DateComponents) -> String { "\(c.year ?? 0) 年 \(c.month ?? 0) 月" }

    private func dayNumber(_ d: Date) -> String { "\(Calendar.current.component(.day, from: d))" }

    private func weekdayShort(_ d: Date) -> String {
        let names = ["日", "一", "二", "三", "四", "五", "六"]
        return "週" + names[Calendar.current.component(.weekday, from: d) - 1]
    }

    private func dateRange(_ a: Date, _ b: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_TW"); f.dateFormat = "M/d"
        return "\(f.string(from: a)) – \(f.string(from: b))"
    }

    private func timeRange(_ e: CalendarEvent) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "zh_TW")
        if let end = e.endDate {
            f.dateFormat = "M/d"
            return "\(f.string(from: e.date)) – \(f.string(from: end))"
        }
        f.dateFormat = "HH:mm"
        return f.string(from: e.date)
    }
}
