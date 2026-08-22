import Foundation

/// 只保留「最後一次」的載入工作。
///
/// 學校那邊一次請求要 ~10 秒,而切學期的按鈕按一下就發一次。沒有這層的話,
/// 連按三下就是三個流程同時在跑,而且**最後回來的**才會蓋到畫面上 —— 使用者
/// 明明停在 113 上,畫面卻可能落在 114 下。取消掉舊的,畫面就一定跟著最後
/// 選到的那個學期走。
///
/// `RequestQueue` 會把「還在排隊就被取消」的請求直接丟掉,所以連按也不會真的
/// 送出那麼多次。
@MainActor
final class LatestTask {
    private var task: Task<Void, Never>?

    /// 取消上一個並等它真的收手,再開始新的。等待是必要的 —— 學校的 session
    /// 是有狀態的,兩個學期的流程重疊會互相汙染。
    func run(_ operation: @escaping () async -> Void) async {
        task?.cancel()
        _ = await task?.value
        let started = Task { await operation() }
        task = started
        await started.value
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}
