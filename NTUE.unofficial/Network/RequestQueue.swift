import Foundation

/// 學校那台伺服器每個請求大約要 10 秒。真正讓人覺得「按了沒反應」的不是單一個
/// 請求慢,而是它排在別人後面 —— 登入後的 `prefetch()` 一次丟五個,使用者當下
/// 點的那一個就得等前面跑完。
///
/// 所以這裡限制同時在跑的數量,並且分兩條線:使用者正在等的請求(`.user`)一律
/// 插隊到背景預抓(`.background`)前面。還在等就被取消的請求(例如又切到別的
/// 學期)會直接從佇列移除,不會白跑一趟。
///
/// 寬度刻意不是 1:歷年成績(`TranscriptViewModel`)會一次抓好幾個學期,那個
/// 平行是有意義的,全部序列化反而更慢。3 只是用來擋住「一次五個把前景擠掉」
/// 的情況 —— 沒有量測過學校端能吃多少並發,所以不假設它會自己排隊。
actor RequestQueue {

    /// iNTUE(nsa.ntue.edu.tw)共用的佇列。
    static let ntue = RequestQueue(width: 3)

    enum Priority: Int, Sendable {
        case background = 0
        case user = 1
    }

    /// 這條執行路徑的優先權。用 task-local 傳遞,呼叫端不必一層層多加參數;
    /// 預設 `.user`,只有 `DataStore.prefetch()` 會降成 `.background`。
    @TaskLocal static var priority: Priority = .user

    private struct Waiter {
        let ticket: Int
        let priority: Priority
        let continuation: CheckedContinuation<Void, Error>
    }

    private let width: Int
    private var running = 0
    private var waiting: [Waiter] = []
    private var nextTicket = 0

    init(width: Int = 1) { self.width = width }

    /// 排隊執行 `body`。同時最多 `width` 個,其餘依「優先權高的先跑、同優先權
    /// 先到先跑」等待。
    nonisolated func run<T>(_ body: () async throws -> T) async throws -> T {
        try await acquire(RequestQueue.priority)
        do {
            let result = try await body()
            await release()
            return result
        } catch {
            await release()
            throw error
        }
    }

    // MARK: - 佇列

    private func acquire(_ priority: Priority) async throws {
        try Task.checkCancellation()
        if running < width {
            running += 1
            return
        }
        let ticket = nextTicket
        nextTicket += 1
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                waiting.append(Waiter(ticket: ticket, priority: priority, continuation: continuation))
            }
        } onCancel: {
            Task { await self.drop(ticket) }
        }
        // 被喚醒 = 前一個把位子直接交棒過來,`running` 不用再加。
    }

    private func release() {
        guard let next = takeNext() else {
            running -= 1
            return
        }
        next.continuation.resume()   // 位子直接交棒,running 維持不變
    }

    /// 優先權最高、同優先權中最早排隊的那一個。`waiting` 本來就是依序 append,
    /// 用嚴格大於比較就會自然保留「先到先跑」。
    private func takeNext() -> Waiter? {
        guard !waiting.isEmpty else { return nil }
        var best = waiting.startIndex
        for i in waiting.indices where waiting[i].priority.rawValue > waiting[best].priority.rawValue {
            best = i
        }
        return waiting.remove(at: best)
    }

    private func drop(_ ticket: Int) {
        guard let i = waiting.firstIndex(where: { $0.ticket == ticket }) else { return }
        waiting.remove(at: i).continuation.resume(throwing: CancellationError())
    }
}
