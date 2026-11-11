import Foundation
import PurePaceRunCore

/// 归档读取结果：读取成功（0 条也是成功）与读取失败是两个可判等区分的状态。
enum HistoryLoadOutcome: Equatable {
    case loaded([RunRecord])
    case failed
}

/// History 的视图状态：归档读取结果 + 由记录 id 组成的单一导航路径。
/// 不依赖 SwiftUI，供 `HistoryView` 绑定，并由单元测试用可抛错 loader 钉住转移。
struct HistoryViewState: Equatable {
    /// `nil` 表示还没有读取过；`loaded` / `failed` 均视为已读。
    private(set) var outcome: HistoryLoadOutcome?
    /// 详情路径只存记录 id，详情视图按 id 在当前结果中就地查找构造。
    var path: [UUID] = []
    /// 已读取过的刷新令牌；同一 token 不重复读取。
    private(set) var loadedToken: Int?
    private var didAutoOpenDetail = false

    /// 读取成功时的记录集合；失败或未读时为空数组。
    var records: [RunRecord] {
        guard case .loaded(let records) = outcome else { return [] }
        return records
    }

    /// 读取失败态（与「成功且 0 条」互相独立）。
    var didFail: Bool {
        outcome == .failed
    }

    /// 成功读取且确实 0 条时才进入空态。
    var isEmpty: Bool {
        guard case .loaded(let records) = outcome else { return false }
        return records.isEmpty
    }

    /// 是否应在当前 token 下再次读取；`force` 供失败态重试使用。
    func shouldLoad(token: Int, force: Bool = false) -> Bool {
        force || loadedToken != token || outcome == nil
    }

    /// 执行一次读取；返回是否真的调用了 loader（同一 token 的非强制重复调用为 `false`）。
    @discardableResult
    mutating func load(
        token: Int,
        force: Bool = false,
        using loader: () throws -> [RunRecord]
    ) -> Bool {
        guard shouldLoad(token: token, force: force) else { return false }
        loadedToken = token
        do {
            outcome = .loaded(try loader())
        } catch {
            outcome = .failed
        }
        reconcilePath()
        return true
    }

    /// 列表行下钻：路径只保留当前详情 id（单一真源，不做多级栈）。
    mutating func open(recordID: UUID) {
        path = [recordID]
    }

    mutating func popToRoot() {
        path = []
    }

    /// 截图取证门控：首次读取后直接进入首条记录详情，只执行一次。
    mutating func openFirstDetailIfNeeded(autoOpen: Bool) {
        guard autoOpen, !didAutoOpenDetail, let first = records.first else { return }
        didAutoOpenDetail = true
        path = [first.id]
    }

    /// 刷新后路径指向的记录已不存在时清栈回列表根；失败态同样回根。
    private mutating func reconcilePath() {
        guard let current = path.first else { return }
        guard records.contains(where: { $0.id == current }) else {
            path = []
            return
        }
        path = [current]
    }
}
