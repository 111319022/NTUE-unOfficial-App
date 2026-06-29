import Foundation

/// A submitted leave request (請假明細), decoded from the f01141 JSON island.
struct LeaveRecord: Identifiable, Hashable, Codable {
    let id: String          // StdAbsentID
    let kind: String        // LeaveKindName  事假/病假…
    let reason: String      // LeaveReason
    let dateSection: String // AbsentSEDate   日期/節次
    let sectionCount: String // SectionSeqCount 節數
    let status: String      // form_status    簽核狀態（核准/簽核中…）
    let applyDate: String   // ApplyDate
    let formNumber: String  // form_number

    enum Status {
        case approved, pending, rejected, other
    }

    var statusKind: Status {
        if status.contains("核准") || status.contains("通過") { return .approved }
        if status.contains("退") || status.contains("不") { return .rejected }
        if status.contains("簽核") || status.contains("待") { return .pending }
        return .other
    }
}
