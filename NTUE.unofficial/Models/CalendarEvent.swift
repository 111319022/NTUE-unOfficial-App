import Foundation
import CloudKit

/// A single校園行事曆 entry (活動 / 假期 / 考試 / 典禮…), maintained in the
/// CloudKit Dashboard so new events can be published without an app update.
///
/// CloudKit record type: `CalendarEvent`
///   title    String   — 活動名稱（必填）
///   date     Date/Time — 開始日期（必填）
///   endDate  Date/Time — 結束日期（可空，多日活動才填）
///   category String   — 分類代碼，見 `Category`（可空，預設 general）
///   note     String   — 補充說明（可空）
///   allDay   Int64    — 1 = 整天 / 0 = 有時間（可空，預設 1）
struct CalendarEvent: Identifiable, Codable, Hashable {
    let id: String          // CKRecord.ID.recordName
    let title: String
    let date: Date
    let endDate: Date?
    let category: Category
    let note: String?
    let allDay: Bool

    enum Category: String, Codable, CaseIterable {
        case general    // 一般活動
        case holiday    // 假期 / 放假
        case exam       // 考試
        case ceremony   // 典禮（開學典禮 / 結業式…）
        case deadline   // 截止 / 重要日
        case registration // 選課 / 註冊

        var label: String {
            switch self {
            case .general:      return "活動"
            case .holiday:      return "假期"
            case .exam:         return "考試"
            case .ceremony:     return "典禮"
            case .deadline:     return "重要日"
            case .registration: return "選課註冊"
            }
        }

        var icon: String {
            switch self {
            case .general:      return "star.fill"
            case .holiday:      return "sun.max.fill"
            case .exam:         return "pencil.and.list.clipboard"
            case .ceremony:     return "graduationcap.fill"
            case .deadline:     return "exclamationmark.circle.fill"
            case .registration: return "calendar.badge.plus"
            }
        }
    }

    /// True if `now` falls on/within the event (inclusive of the end day).
    func isOngoing(now: Date = Date(), calendar: Calendar = .current) -> Bool {
        let startDay = calendar.startOfDay(for: date)
        let endDay = calendar.startOfDay(for: endDate ?? date)
        let today = calendar.startOfDay(for: now)
        return today >= startDay && today <= endDay
    }
}

extension CalendarEvent {
    /// Build from a CloudKit record; returns nil if required fields are missing.
    init?(record: CKRecord) {
        guard let title = record["title"] as? String,
              let date = record["date"] as? Date else { return nil }
        self.id = record.recordID.recordName
        self.title = title
        self.date = date
        self.endDate = record["endDate"] as? Date
        let catRaw = (record["category"] as? String) ?? Category.general.rawValue
        self.category = Category(rawValue: catRaw) ?? .general
        self.note = (record["note"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        // allDay stored as Int64 (1/0); default to all-day when absent.
        if let n = record["allDay"] as? Int64 { self.allDay = n != 0 } else { self.allDay = true }
    }

    /// Write into a CloudKit record (used by the DevTools seeder).
    func apply(to record: CKRecord) {
        record["title"] = title
        record["date"] = date
        if let endDate { record["endDate"] = endDate }
        record["category"] = category.rawValue
        if let note { record["note"] = note }
        record["allDay"] = Int64(allDay ? 1 : 0)
    }
}
