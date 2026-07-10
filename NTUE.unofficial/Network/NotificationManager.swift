import Foundation
import UserNotifications

/// Schedules **local** notifications for upcoming Moodle assignment deadlines.
///
/// These fire even when the app is closed, because iOS holds the pre-scheduled
/// notifications — no push server needed. We only ever know about *future* work
/// while the app is open, so the strategy is: whenever fresh deadlines load
/// (`DataStore`), wipe our pending requests and re-schedule from the latest list.
///
/// Detecting *new* server data (new grades / announcements) while closed would
/// need a background refresh or a push server, which is out of scope — hence only
/// deadline reminders live here.
@MainActor
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()
    private override init() { super.init() }

    /// Route our reminders through this object so they also show as a banner while
    /// the app is in the foreground. Call once at launch.
    func registerAsDelegate() {
        UNUserNotificationCenter.current().delegate = self
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    /// Master on/off, mirrored by the settings toggle.
    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.enabled) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.enabled) }
    }

    /// How early (before the due time) to remind. Persisted as the raw value.
    var lead: LeadTime {
        get { LeadTime(rawValue: UserDefaults.standard.string(forKey: Keys.lead) ?? "") ?? .dayAndHours }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: Keys.lead) }
    }

    private enum Keys {
        static let enabled = "notify_assignments"
        static let lead = "notify_assignments_lead"
    }

    /// All identifiers we manage share this prefix so we can clear only ours.
    private static let idPrefix = "deadline-"

    // MARK: - Authorization

    /// Ask for permission. Returns whether we're authorized afterwards.
    @discardableResult
    func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        default:
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            return granted
        }
    }

    /// Current system authorization status (so settings can show "去設定開啟").
    func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    // MARK: - Scheduling

    /// Replace all pending deadline reminders with ones derived from `deadlines`.
    /// No-ops (and clears) when the feature is off.
    func rescheduleDeadlines(_ deadlines: [MoodleDeadline]) async {
        let center = UNUserNotificationCenter.current()
        clearPending(center)

        guard isEnabled else { return }
        guard await requestAuthorization() else { return }

        let now = Date()
        // Keep it well under the 64 pending-notification cap: a handful of
        // upcoming, not-yet-due assignments × up to 2 lead times each.
        let upcoming = deadlines
            .filter { !$0.overdue && $0.due > now }
            .sorted { $0.due < $1.due }
            .prefix(20)

        for item in upcoming {
            for offset in lead.offsets {
                let fireDate = item.due.addingTimeInterval(-offset)
                guard fireDate > now else { continue }   // lead window already passed
                schedule(item, at: fireDate, offset: offset, on: center)
            }
        }
    }

    /// Re-run scheduling from whatever the DataStore currently has cached
    /// (used when the user flips the toggle or changes the lead time).
    func refreshFromCache() async {
        await rescheduleDeadlines(DataStore.shared.cachedDeadlines ?? [])
    }

    /// Remove everything we scheduled (e.g. on logout or when disabled).
    func clearAll() {
        clearPending(UNUserNotificationCenter.current())
    }

    private func clearPending(_ center: UNUserNotificationCenter) {
        center.getPendingNotificationRequests { requests in
            let ids = requests.map(\.identifier).filter { $0.hasPrefix(Self.idPrefix) }
            center.removePendingNotificationRequests(withIdentifiers: ids)
        }
    }

    private func schedule(_ item: MoodleDeadline, at fireDate: Date, offset: TimeInterval, on center: UNUserNotificationCenter) {
        let content = UNMutableNotificationContent()
        content.title = item.name
        content.body = "\(item.courseName)　\(Self.remaining(from: offset))截止"
        content.sound = .default
        content.userInfo = ["url": item.url.absoluteString]

        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(
            identifier: "\(Self.idPrefix)\(item.id)-\(Int(offset))",
            content: content,
            trigger: trigger
        )
        center.add(request)
    }

    /// "還有 1 天" / "還有 3 小時" / "即將" — describes the lead offset.
    private static func remaining(from offset: TimeInterval) -> String {
        if offset <= 0 { return "即將" }
        let hours = Int(offset / 3600)
        if hours % 24 == 0, hours > 0 { return "還有 \(hours / 24) 天" }
        if hours >= 1 { return "還有 \(hours) 小時" }
        return "即將"
    }
}

/// Preset reminder lead times shown in settings.
enum LeadTime: String, CaseIterable, Identifiable {
    case dayAndHours   // 1 天前 + 3 小時前
    case oneDay        // 1 天前
    case threeHours    // 3 小時前
    case oneHour       // 1 小時前

    var id: String { rawValue }

    var label: String {
        switch self {
        case .dayAndHours: return "1 天前 + 3 小時前"
        case .oneDay: return "1 天前"
        case .threeHours: return "3 小時前"
        case .oneHour: return "1 小時前"
        }
    }

    /// Seconds-before-due for each reminder this preset fires.
    var offsets: [TimeInterval] {
        switch self {
        case .dayAndHours: return [86_400, 10_800]
        case .oneDay: return [86_400]
        case .threeHours: return [10_800]
        case .oneHour: return [3_600]
        }
    }
}
