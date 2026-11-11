# identifier 契约放开只增不改 + 主操作补齐 + demo 入口 = 0 门禁

## 范围

只修第 4 波留下的三处契约缺口，不动视觉与产品面：

1. **identifier 契约由「33 项完全等值」改为「只增不改」**（`scripts/check-ios-shell.sh` 的 `validate_design_tokens`）：
   - 既有 33 项构成冻结清单，逐项必须存在；任一项改名或删除即判红。
   - 允许新增：新增项必须非空、唯一（同一新 id 在源码中只出现一次）、其控件带非空可读 label，且整体计数单调不减（输出真实计数，低于上界即红）。
2. **补齐第 4 波新增主操作的 identifier**（`ios/PurePace/Run/RunView.swift`）：
   - 倒计时取消 → `run.cancelCountdown`
   - 结束总结保存 → `run.save`
   - 结束总结丢弃 → `run.discard`
   - 既有 33 项 identifier 一个不改（不改名、不删除、不改语义）。
3. **demo / 示例入口 = 0 回归断言**：把现有「5 个文件关键词 grep」升级为可计数断言——发布路径 `ios/PurePace/**/*.swift` 中用户可达的 demo / 示例数据入口数必须为 0；DEBUG-only 注入不得经 UI 触达（DEBUG 块内的示例按钮同样判红）。
4. **`--self-test` 三类反例/正例齐全**并跑出真实红/绿：改名判红、删除判红、新增放行且计数递增；另加「新增但 label 为空」「新增但 id 重复」两条判红反例，以及 demo 入口判红反例。

## 验收

- ac-frozen-rename-red: 把既有 33 项中任一 identifier 改名后执行 `bash scripts/check-ios-shell.sh`，退出码非 0，且失败原因包含冻结 identifier 语义（不是被其他规则顺带命中的偶然红）。
- ac-frozen-delete-red: 删除既有 33 项中任一 identifier 后门禁退出码非 0，失败原因指向该 identifier 缺失。
- ac-addition-allowed: 在 `RunView.swift` 追加一个带非空 `L10n` 可读 label 且全局唯一的新 identifier（如 `run.extra`）后，门禁退出码为 0（放行）。
- ac-count-monotonic: 门禁在通过路径输出实际 identifier 计数；上述新增使计数由冻结基线 33 递增为 34，计数低于基线（回归删除）时判红。
- ac-addition-empty-red: 新增 identifier 为空串，或该控件无可读 `accessibilityLabel`，门禁判红。
- ac-addition-duplicate-red: 同一个新增 id 在源码中出现两次，门禁判红。
- ac-new-main-action-ids: `RunView.swift` 中倒计时取消、保存、丢弃三个主操作分别带 `run.cancelCountdown` / `run.save` / `run.discard`，且各自 `accessibilityLabel` 为非空 L10n 键；仓库 identifier 总数为 36，既有 33 项字面逐个未变。
- ac-demo-entry-zero: 发布路径 `ios/PurePace/**/*.swift` 中用户可达 demo / 示例数据入口计数等于 0；向任一视图文件（含 `#if DEBUG` 块内）追加 `Button("示例跑次")` 或等价 `L10n` 示例入口后，门禁判红。
- ac-selftest-coverage: `bash scripts/check-ios-shell.sh --self-test` 同时覆盖「改名判红」「删除判红」「新增放行并计数」三类，输出 `self-test OK`；把任一反例改回正例或把新增反例当正例断言时自检自身判红。
- ac-gates-green: `.munk/code-gates.json` 门列表不变（22 门）且全部通过。

## 非目标

- 不新增 gate id、不改 `.munk/code-gates.json` 门列表与命令。
- 不改 `DesignTokens`、`RunInteractionPlan`、`RunSessionViewModel`、状态机、GPX 导出、归档文件格式。
- 不改任何 `L10n` 键与其文案值（新增 identifier 复用既有 `runCancelCountdownLabel` / `runSaveLabel` / `runDiscardLabel`）。
- 不重做任何屏的视觉、不新增动效、不调整布局与令牌。
- 不改既有 identifier 名称；不改 History / Settings / 详情页行为。
- 不新增 UI 用例、不跑模拟器观感与真机验收（真机项继续 `pending: 待人现场`）。
- 不做 demo 数据的删除式重构：只要「用户不可达 + 断言为 0」，已存在的 launch-arg 门控注入保持原样。

## 实现约束

- 可改文件仅限：`scripts/check-ios-shell.sh`、`ios/PurePace/Run/RunView.swift`，以及为对齐新 identifier 必须同步的既有测试文件（仅在现有断言会因此失败时才改）。其余路径一律不动。
- identifier 冻结清单继续作为单一真源常量置于脚本内，新增项以「必需新增 + 计数下限」表达，避免下次再退回完全等值。
- 现有扫描用 `sort -u` 后比对，天然掩盖重复；新增项的「唯一性」判定必须基于去重前的原始出现次数（既有 `tab.run` 在 `ContentView.swift` 与 `RunView.swift` 各出现一次，是既有既定事实，不因此判红）。
- 计数需在通过路径可见（`pass` 行打印 `identifier: 36（冻结 33 + 新增 3）` 之类真实计数），否则「计数单调」不可验证。
- demo 入口断言用可计数形式（先计数再与 0 比较并输出真实计数），覆盖 `ios/PurePace/**/*.swift` 全量文件而非固定 5 个文件；注释行不算命中（沿用脚本既有的整行注释跳过口径）。
- 自检沿用现有 `design_root` 复制 + 单点破坏模式；新增/改动反例都用 `check_ok` / `check_fail` / `check_fail_reason` 表达。
- 开工首条回执写明预算（预计门禁轮次与时长上限）与期望收口时刻；超预算即停手回执，不靠长会话补绿。
- 收口必须贴真实输出：`check-ios-shell.sh` 正常跑、`--self-test` 跑，以及 22 门全绿的原始摘要行。
