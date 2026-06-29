import Foundation

/// Bridges the app's rich network models into the lean `WidgetSnapshot` that the
/// widgets and Live Activity read from the shared App Group container.
enum WidgetBridge {
    /// Rebuild and persist the shared snapshot from the latest cached data.
    /// Cheap and idempotent — safe to call after any data refresh.
    static func update(timetable: Timetable?, deadlines: [MoodleDeadline]?) {
        let classes = expand(timetable: timetable)
        let assignments = (deadlines ?? []).map {
            AssignmentItem(id: $0.id, name: $0.name, courseName: $0.courseName, due: $0.due)
        }
        SharedStore.save(WidgetSnapshot(generatedAt: Date(), classes: classes, assignments: assignments))
    }

    /// Convenience that reads whatever the `DataStore` currently has cached.
    @MainActor static func updateFromCache() {
        update(timetable: DataStore.shared.cachedTimetable,
               deadlines: DataStore.shared.cachedDeadlines)
    }

    /// Expand the recurring weekly timetable onto concrete calendar days for the
    /// next week, so the widget can pick "the next class" even across midnight.
    private static func expand(timetable: Timetable?, daysAhead: Int = 7, now: Date = Date()) -> [ClassSlot] {
        guard let timetable else { return [] }
        let cal = Calendar.current
        var result: [ClassSlot] = []

        for offset in 0...daysAhead {
            guard let day = cal.date(byAdding: .day, value: offset, to: now) else { continue }
            let appWeekday = Self.appWeekday(day, cal: cal)
            for session in timetable.allSessions where session.weekday == appWeekday {
                guard let (start, end) = times(for: session.periodTime, on: day, cal: cal) else { continue }
                // Drop class sessions that have already ended today.
                if end <= now { continue }
                result.append(ClassSlot(
                    courseName: session.courseName,
                    classroom: session.classroom,
                    instructor: session.instructor,
                    start: start,
                    end: end
                ))
            }
        }
        return result.sorted { $0.start < $1.start }
    }

    /// Apple weekday (1=Sun…7=Sat) → app weekday (1=Mon…7=Sun).
    private static func appWeekday(_ date: Date, cal: Calendar) -> Int {
        let apple = cal.component(.weekday, from: date)
        return apple == 1 ? 7 : apple - 1
    }

    /// "07:10-08:00" on a given day → concrete (start, end) Dates.
    private static func times(for periodTime: String, on day: Date, cal: Calendar) -> (Date, Date)? {
        let parts = periodTime.split(separator: "-")
        guard parts.count == 2,
              let start = date(parts[0], on: day, cal: cal),
              let end = date(parts[1], on: day, cal: cal) else { return nil }
        return (start, end)
    }

    private static func date(_ hhmm: Substring, on day: Date, cal: Calendar) -> Date? {
        let c = hhmm.split(separator: ":")
        guard c.count == 2, let h = Int(c[0]), let m = Int(c[1]) else { return nil }
        return cal.date(bySettingHour: h, minute: m, second: 0, of: day)
    }
}
