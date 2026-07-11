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

    /// Tapping a 上課提醒 opens the app here — start the class Live Activity so the
    /// user gets the on-screen countdown with a single tap (even if 自動顯示 is off).
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        if userInfo["action"] as? String == Self.startLiveActivityAction {
            await MainActor.run { LiveActivityController.shared.start() }
        }
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

    /// 上課提醒 on/off — a local notification before the day's first class.
    var classRemindersEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.classEnabled) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.classEnabled) }
    }

    private enum Keys {
        static let enabled = "notify_assignments"
        static let lead = "notify_assignments_lead"
        static let classEnabled = "notify_class"
    }

    /// Identifier prefixes so we can clear only our own pending requests.
    private static let deadlinePrefix = "deadline-"
    private static let classPrefix = "class-"
    /// Minutes before the day's first class to fire the 上課提醒.
    private static let classLeadMinutes = 30
    /// userInfo marker whose tap starts the class Live Activity.
    static let startLiveActivityAction = "startLiveActivity"

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
        clearPending(prefix: Self.deadlinePrefix, on: center)

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

    // MARK: - Class reminders

    /// Replace all pending 上課提醒 with one per upcoming class day, fired
    /// `classLeadMinutes` before that day's first class. Break days are already
    /// excluded by `WidgetBridge` (學期門檻). No-ops (and clears) when off.
    func rescheduleClassReminders(from timetable: Timetable?) async {
        let center = UNUserNotificationCenter.current()
        clearPending(prefix: Self.classPrefix, on: center)

        guard classRemindersEnabled else { return }
        guard await requestAuthorization() else { return }

        let now = Date()
        let cal = Calendar.current
        // Earliest class of each in-session day for the next ~2 weeks.
        let firstOfDay = Dictionary(grouping: WidgetBridge.upcomingClasses(from: timetable, daysAhead: 14, now: now)) {
            cal.startOfDay(for: $0.start)
        }
        .compactMap { $0.value.min { $0.start < $1.start } }
        .sorted { $0.start < $1.start }

        for slot in firstOfDay {
            let fireDate = slot.start.addingTimeInterval(-Double(Self.classLeadMinutes) * 60)
            guard fireDate > now else { continue }   // lead window already passed
            scheduleClassReminder(slot, at: fireDate, on: center)
        }
    }

    /// Re-run 上課提醒 scheduling from the DataStore's cached timetable.
    func refreshClassRemindersFromCache() async {
        await rescheduleClassReminders(from: DataStore.shared.cachedTimetable)
    }

    /// Remove everything we scheduled (e.g. on logout or when disabled).
    func clearAll() {
        let center = UNUserNotificationCenter.current()
        clearPending(prefix: Self.deadlinePrefix, on: center)
        clearPending(prefix: Self.classPrefix, on: center)
    }

    private func clearPending(prefix: String, on center: UNUserNotificationCenter) {
        center.getPendingNotificationRequests { requests in
            let ids = requests.map(\.identifier).filter { $0.hasPrefix(prefix) }
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
            identifier: "\(Self.deadlinePrefix)\(item.id)-\(Int(offset))",
            content: content,
            trigger: trigger
        )
        center.add(request)
    }

    private func scheduleClassReminder(_ slot: ClassSlot, at fireDate: Date, on center: UNUserNotificationCenter) {
        let content = UNMutableNotificationContent()
        content.title = "上課提醒"
        let place = slot.classroom.isEmpty ? "" : "・\(slot.classroom)"
        content.body = "\(slot.courseName) \(Self.hhmm(slot.start)) 開始\(place)，點一下開啟課程動態"
        content.sound = .default
        content.userInfo = ["action": Self.startLiveActivityAction]

        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(
            identifier: "\(Self.classPrefix)\(Self.dayID(slot.start))",
            content: content,
            trigger: trigger
        )
        center.add(request)
    }

    private static func hhmm(_ date: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    private static func dayID(_ date: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyyMMdd"
        return f.string(from: date)
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
