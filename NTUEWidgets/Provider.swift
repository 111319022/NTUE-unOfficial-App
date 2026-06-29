import WidgetKit
import SwiftUI

/// One rendered moment for the widgets. We bake the snapshot in and let SwiftUI's
/// relative/timer text handle the second-by-second countdown; new entries are
/// emitted at each class boundary so "next class" / "current class" flips over
/// at the right time without waking the app.
struct ClassEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct ClassProvider: TimelineProvider {
    func placeholder(in context: Context) -> ClassEntry {
        ClassEntry(date: Date(), snapshot: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (ClassEntry) -> Void) {
        completion(ClassEntry(date: Date(), snapshot: SharedStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ClassEntry>) -> Void) {
        let now = Date()
        let snapshot = SharedStore.load()

        // Re-render at every upcoming class start/end (so the "current/next"
        // selection flips precisely), plus the next few assignment deadlines.
        var moments: Set<Date> = [now]
        let horizon = now.addingTimeInterval(36 * 3600)
        for c in snapshot.classes where c.start <= horizon {
            if c.start > now { moments.insert(c.start) }
            if c.end > now { moments.insert(c.end) }
        }
        for a in snapshot.upcomingAssignments(at: now).prefix(5) where a.due <= horizon {
            moments.insert(a.due)
        }

        let entries = moments.sorted().map { ClassEntry(date: $0, snapshot: snapshot) }
        // Ask the system to rebuild the timeline a bit after our last known
        // boundary so the data (and snapshot) gets refreshed.
        let refreshAt = (moments.max() ?? now).addingTimeInterval(15 * 60)
        completion(Timeline(entries: entries.isEmpty ? [ClassEntry(date: now, snapshot: snapshot)] : entries,
                            policy: .after(refreshAt)))
    }
}
