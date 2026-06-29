import Foundation
import ActivityKit

/// Starts / updates / ends the class-chain Live Activity.
///
/// Design note (no backend): once started, the countdown ticks on its own via
/// SwiftUI timer text — we don't need to push every second. We re-push a fresh
/// `ContentState` only at class boundaries, which we do whenever the app becomes
/// active. In **auto** mode the app also starts the activity by itself on
/// foreground if a class is happening / coming up today; in **manual** mode the
/// user starts it from Settings. True "pops up on its own while the app is
/// closed" would require ActivityKit push (a server) — out of scope here.
@MainActor
@Observable
final class LiveActivityController {
    static let shared = LiveActivityController()

    /// User preference: auto-start on foreground, or only when tapped.
    var autoStart: Bool {
        get { UserDefaults.standard.bool(forKey: Self.autoKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.autoKey) }
    }
    private static let autoKey = "liveActivity_autoStart"

    /// Whether the system currently allows Live Activities at all.
    var systemEnabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    /// Is one of our activities currently live?
    var isRunning: Bool { !Activity<ClassActivityAttributes>.activities.isEmpty }

    private init() {}

    // MARK: - Public control

    /// Manual start (or restart) from the current snapshot.
    func start() {
        guard systemEnabled else { return }
        let snapshot = SharedStore.load()
        guard let state = Self.contentState(from: snapshot) else { return }
        end()   // ensure a single activity
        let attributes = ClassActivityAttributes(title: "今日課程")
        _ = try? Activity.request(
            attributes: attributes,
            content: ActivityContent(state: state, staleDate: state.pivot.addingTimeInterval(60)),
            pushType: nil
        )
    }

    /// End every running activity.
    func end() {
        for activity in Activity<ClassActivityAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }

    /// Called when the app becomes active: keep a running activity in step with
    /// the current class, and (in auto mode) start one if appropriate.
    func syncOnForeground() {
        let snapshot = SharedStore.load()
        let state = Self.contentState(from: snapshot)

        if isRunning {
            guard let state else { end(); return }   // day's classes are over
            update(to: state)
        } else if autoStart, let state {
            start()
            _ = state
        }
    }

    // MARK: - Private

    private func update(to state: ClassActivityAttributes.ContentState) {
        let content = ActivityContent(state: state, staleDate: state.pivot.addingTimeInterval(60))
        for activity in Activity<ClassActivityAttributes>.activities {
            Task { await activity.update(content) }
        }
    }

    /// Build the content state for "now" from today's remaining class chain.
    /// Returns `nil` when there are no more classes today.
    static func contentState(from snapshot: WidgetSnapshot, now: Date = Date()) -> ClassActivityAttributes.ContentState? {
        let remaining = snapshot.remainingToday(at: now)
        guard !remaining.isEmpty else { return nil }

        if let current = snapshot.currentClass(at: now) {
            let following = remaining.first { $0.start >= current.end }
            return .init(
                phase: .inClass,
                courseName: current.courseName,
                classroom: current.classroom,
                pivot: current.end,
                followingCourseName: following?.courseName,
                followingClassroom: following?.classroom,
                followingStart: following?.start
            )
        }

        // No class in progress → count down to the next one today.
        let next = remaining[0]
        let following = remaining.count > 1 ? remaining[1] : nil
        return .init(
            phase: .beforeNext,
            courseName: next.courseName,
            classroom: next.classroom,
            pivot: next.start,
            followingCourseName: following?.courseName,
            followingClassroom: following?.classroom,
            followingStart: following?.start
        )
    }
}
