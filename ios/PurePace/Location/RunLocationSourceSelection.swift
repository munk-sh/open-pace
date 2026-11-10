import Foundation
import PurePaceRunCore

/// launch-arg → 定位源选择的纯参数 seam（Foundation + PurePaceRunCore，无 IO、无授权动作）。
///
/// 唯一注入入口：参数里显式出现 `-releaseDeterministicLocation km-crossing` 时才返回确定性源；
/// 缺值、值以 `-` 开头、scenario 未知等任何异常形态一律 fail-closed 回真实 `RunLocationSource()`。
/// 正常用户路径不传该参数，默认即真实 CoreLocation，行为与引入本 seam 前一致。
@MainActor
enum RunLocationSourceSelection {
    /// 选择结果：数据源 + 是否展示调试遥测摘要（仅显式门控时才为 true）。
    struct Selection {
        let source: RunLocationProviding
        let telemetryDebugEnabled: Bool
    }

    static func select(
        arguments: [String],
        makeReal: () -> RunLocationProviding,
        makeDeterministic: (ReleaseDeterministicLocationSource.Scenario) -> RunLocationProviding
    ) -> Selection {
        guard let scenario = deterministicScenario(in: arguments) else {
            return Selection(source: makeReal(), telemetryDebugEnabled: false)
        }
        return Selection(source: makeDeterministic(scenario), telemetryDebugEnabled: true)
    }

    /// 只接受「flag 后紧跟一个合法 scenario 值」这一种形态；其余全部返回 `nil`。
    static func deterministicScenario(
        in arguments: [String]
    ) -> ReleaseDeterministicLocationSource.Scenario? {
        guard let index = arguments.firstIndex(of: ReleaseDeterministicLocationSource.flag) else {
            return nil
        }
        let valueIndex = arguments.index(after: index)
        guard valueIndex < arguments.endIndex else { return nil }
        let value = arguments[valueIndex]
        // 缺少值时会读到下一个 launch arg（以 `-` 开头），必须当作非法而非场景名。
        guard !value.hasPrefix("-") else { return nil }
        return ReleaseDeterministicLocationSource.Scenario(rawValue: value)
    }
}
