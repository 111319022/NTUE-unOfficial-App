import SwiftUI
import WidgetKit

// Local palette (the widget target can't see the app's Theme).
enum WTheme {
    static let accent = Color(red: 0.62, green: 0.20, blue: 0.20)   // maroon
    static let amber = Color(red: 0.86, green: 0.55, blue: 0.13)
}

extension ClassSlot {
    /// "週一 13:10" style start label.
    var startLabel: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_Hant")
        f.dateFormat = "HH:mm"
        return f.string(from: start)
    }

    var timeRangeLabel: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return "\(f.string(from: start))–\(f.string(from: end))"
    }
}

// MARK: - Next class

struct NextClassView: View {
    var entry: ClassEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryInline:    inline
        case .accessoryCircular:  circular
        case .accessoryRectangular: rectangular
        default: small
        }
    }

    // Resolve what to show at this entry's moment.
    private var state: (label: String, course: ClassSlot, isNow: Bool)? {
        let now = entry.date
        if let cur = entry.snapshot.currentClass(at: now) {
            return ("上課中", cur, true)
        }
        if let next = entry.snapshot.nextClass(after: now) {
            return ("下一節", next, false)
        }
        return nil
    }

    @ViewBuilder private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let s = state {
                HStack(spacing: 4) {
                    Image(systemName: s.isNow ? "book.fill" : "clock.fill")
                    Text(s.label).font(.caption2.weight(.semibold))
                }
                .foregroundStyle(s.isNow ? WTheme.accent : WTheme.amber)

                Text(s.course.courseName)
                    .font(.headline)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)

                if !s.course.classroom.isEmpty {
                    Label(s.course.classroom, systemImage: "mappin.and.ellipse")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                if s.isNow {
                    countdown(to: s.course.end, prefix: "下課")
                } else {
                    countdown(to: s.course.start, prefix: "上課")
                }
            } else {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("今天沒課了").font(.headline)
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func countdown(to date: Date, prefix: String) -> some View {
        HStack(spacing: 3) {
            Text(prefix).font(.caption2).foregroundStyle(.secondary)
            Text(date, style: .timer)
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(WTheme.accent)
        }
    }

    @ViewBuilder private var inline: some View {
        if let s = state {
            Text("\(s.label) \(s.course.courseName) · \(Text(s.isNow ? s.course.end : s.course.start, style: .timer))")
        } else {
            Text("今天沒課了")
        }
    }

    @ViewBuilder private var circular: some View {
        if let s = state {
            Gauge(value: 0) { Text(s.isNow ? "下課" : "上課") }
                currentValueLabel: {
                    Text(s.isNow ? s.course.end : s.course.start, style: .timer)
                        .font(.caption2)
                }
                .gaugeStyle(.accessoryCircularCapacity)
        } else {
            Image(systemName: "checkmark")
        }
    }

    @ViewBuilder private var rectangular: some View {
        if let s = state {
            VStack(alignment: .leading, spacing: 1) {
                Text(s.label).font(.caption2).foregroundStyle(.secondary)
                Text(s.course.courseName).font(.headline).lineLimit(1)
                HStack(spacing: 4) {
                    if !s.course.classroom.isEmpty { Text(s.course.classroom) }
                    Text(s.isNow ? s.course.end : s.course.start, style: .timer)
                        .monospacedDigit()
                }
                .font(.caption2)
            }
        } else {
            Text("今天沒課了")
        }
    }
}

// MARK: - Assignments

struct AssignmentsView: View {
    var entry: ClassEntry
    @Environment(\.widgetFamily) private var family

    private var items: [AssignmentItem] {
        Array(entry.snapshot.upcomingAssignments(at: entry.date).prefix(family == .accessoryRectangular ? 2 : 3))
    }

    var body: some View {
        if family == .accessoryRectangular {
            rectangular
        } else {
            small
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "checklist")
                Text("待繳作業").font(.caption2.weight(.semibold))
                Spacer()
                Text("\(entry.snapshot.upcomingAssignments(at: entry.date).count)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(WTheme.accent)
            }
            .foregroundStyle(WTheme.accent)

            if items.isEmpty {
                Spacer()
                Text("沒有待繳作業").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
            } else {
                ForEach(items) { a in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(a.name).font(.caption.weight(.medium)).lineLimit(1)
                        Text(a.due, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(a.due.timeIntervalSinceNow < 86_400 ? .red : .secondary)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("待繳作業").font(.caption2.weight(.semibold))
            if items.isEmpty {
                Text("沒有待繳").font(.caption2).foregroundStyle(.secondary)
            } else {
                ForEach(items) { a in
                    Text("• \(a.name)").font(.caption2).lineLimit(1)
                }
            }
        }
    }
}

// MARK: - Combined (medium)

struct CombinedView: View {
    var entry: ClassEntry

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            NextClassView(entry: entry)
                .frame(maxWidth: .infinity, alignment: .leading)
            Divider()
            AssignmentsView(entry: entry)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
