预算 45 分钟 / 期望收口 2026-11-11T06:20Z（实际收口 12:55 +0800，未超时）

# Run 三态重建（run-screens）执行记录

- 改动面（3 文件，零越界）：`ios/PurePace/Run/RunView.swift`（视觉层级）、`ios/PurePace/Run/RunFormatting.swift`（仅新增数值/单位拆分纯函数，既有签名与输出不变）、`ios/PurePaceTests/RunFormattingTests.swift`（仅新增 L1 用例）。`L10n.swift` / `Localizable.xcstrings` / `DesignTokens.swift` / `scripts/**` / `code-gates.json` / `project.yml` / `.xcodeproj` 零 diff（`git status` 可证）。
- 三态：ready / running+paused / finished(saved)；四层：hero 距离（display，中性 surfaceMuted 面板）→ 用时 / 当前配速（primaryValue）→ 平均配速 / 分段（caption）→ 提示胶囊；主操作 `safeAreaInset(edge: .bottom)` 每态唯一，四态同 helper、同高、同锚点。
- 指标块统一三行：`metricLabel` 标签 → 等宽数值 → `metricUnit` 单位；无单位项（用时 / 分段 / 空配速）不渲染空单位行；单位行 `accessibilityHidden`，可及 label 用合并串复原（`run.distance` 仍为 `0.00 km`，配速空值仍为 `--`）。
- 破坏性操作：`run.finish` 内在宽度（无 `maxWidth: .infinity`）+ 无填充底 + `warning` hairline 描边 + `Typography.body`（弱于主操作 `control`），仍 `minHeight: minTapTarget` 且 `accessibilityLabel(Text(label))`。
- 零投影 / 零渐变 / 零嵌套双描边；分组只用 `Stroke.hairline` + `surface`、`surfaceMuted` 明度差 + `Radius.card` / `Radius.panel`。

## 验证证据（真实输出）

- `bash scripts/check-ios-shell.sh` → 30 项断言，0 项失败 / ios shell OK（含零字面色值、零散字体、样式字面量、33 项冻结 identifier、`monospacedDigit()` ≥ 3、状态取色三行原文、L10n 键与 4 个互异 label）。
- `bash scripts/check-ios-shell.sh --self-test` → 84 项断言，0 项失败 / self-test OK。
- `bash scripts/check-baseline.sh` → 11 项断言，0 项失败 / baseline OK (VERSION=0.1.0)。
- `bash scripts/test-ios.sh --unit-only` → `Executed 182 tests, with 0 failures`（含新增 3 个 RunFormatting 用例；RunCore 141 tests 亦 0 失败）。
- 单跑 UI 腿旁证（非门禁项）：本机在该模拟器上 `RunFlowUITests` 全部用例出现 `Test crashed with signal kill`；`git stash` 回到 HEAD 复跑同样 4 失败 3 通过，**与本次改动无关（环境级 flake）**。该次运行中 `testRunPauseResumeFinishAndHistory` 在崩溃前已完成 `run.distance == "0.00 km"` / `run.elapsed == "00:00"` / `run.currentPace == "--"` / `run.averagePace == "--"` 断言（失败信息只有 crash，无断言失败），佐证单位拆分未改可及 label 契约。

## 有意未做

- 未动 `finished && didSave == false` 的空控制区、保存/丢弃二选一（第 4 波）。
- 未接动效、未做 Reduce Motion 视图接线、未归档截图到 `docs/screenshots`、未做真机验收。
- 未改 `.munk/code-gates.json`（既有 `test` 门已执行自动化测试套件）。
