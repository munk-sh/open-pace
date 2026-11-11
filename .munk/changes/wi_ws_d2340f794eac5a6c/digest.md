# 交付回执：设计令牌真源（token-core）

## 0) 预算与收口时刻

- 开工时刻：2026-11-11 11:21 +0800
- 预算时长：90 分钟（实现 ≤45、测试与反例 ≤30、校验收口 ≤15）
- 期望收口绝对时刻：2026-11-11 12:51 +0800
- 实际收口：2026-11-11 11:27 +0800（预算内，无「超时停手」）

## 1) 结论

唯一输入为 `docs/design/competitor-teardown.md` L253–L274 映射表与「字号层级」「动效节奏」结论；全部新增落在既有两文件：

- `ios/PurePace/Design/DesignTokens.swift`
  - `Colors.purposes`：18 个语义键的机器可读用途注册表（键集与 `palette` 完全相等）；`Colors.purposeProblems(...)` 纯函数对缺键 / 多键 / 空用途 / 复读键名 fail-closed。
  - `Typography.metricLabelSize = 11`、`metricUnitSize = 11`；`sizes` 扩为严格递增 6 档 `[11, 12, 15, 20, 34, 56]`，既有 5 个字号值不变；`roleLadder`（7 角色、按字号非递减、仅 label/unit 同档）与 `numericRoleNames = ["primaryValue", "display"]`，`roleProblems(...)` 校验阶梯与等宽数字标记。
  - `Spacing.metricGroupSpacing = 8`、`metricGroupGap = 16`、`cardPadding = 16`（均落在既有 `{4,8,12,16,24,32}` 档位）；`screenTop/cardGap/sectionGap` 与 `scale` 不变。
  - 新增 `Motion`：`durationShort = 0.2`、`durationState = 0.32`、`reducedMotionDuration = 0`，以及纯函数 `duration(_:reduceMotion:)`（`true` 一律返回 0）。
- `ios/PurePace/Design/ContrastPolicy.swift`
  - 新增阈值分档 `Tier`（body/large/decorative）、`Pair`、唯一成对矩阵 `pairMatrix`（36 对，18 个键全覆盖，只引用 palette 键、零十六进制）、`Scheme`、`component(_:scheme:)` 与 `checks(for:matrix:)` 解析函数；`ratio/ratios/problems/formatted` 语义未改。
- 测试：`DesignTokensTests` 与 `ContrastPolicyTests` 扩展/对齐全部 ac-*，反例均真实调用断言判红。
- 零 hex 改动：矩阵所需 4.5 / 3.0 / 1.10 组合在现有 light/dark 取值下全部达标（最低 light `separator/surfaceMuted` 1.15、dark `separator/surfaceMuted` 1.17；4.5 档最低 light `success/successSoft` 4.81、dark `danger/dangerSoft` 6.86）。

## 2) 证据

`bash scripts/test-ios.sh --unit-only`（exit 0）：

```
Test Suite 'PurePaceTests.xctest' passed
	 Executed 179 tests, with 0 failures (0 unexpected) in 2.564 (2.624) seconds
ac-contrast light success/successSoft 4.81
ac-contrast light danger/dangerSoft 5.66
ac-contrast light onAccent/accent 6.07
ac-contrast dark success/successSoft 7.78
ac-contrast dark danger/dangerSoft 6.86
ac-contrast dark onAccent/accent 9.57
```

light 与 dark 各打印 36 条 `ac-contrast`（`grep -c` 均为 36），整张矩阵 `problems == []`。

`bash scripts/check-ios-shell.sh`（exit 0）：`30 项断言，0 项失败` / `ios shell OK`，`validate_design_tokens` 正例与反例自检仍全绿。

`git diff --name-only` 仅 4 个允许文件：

```
ios/PurePace/Design/ContrastPolicy.swift
ios/PurePace/Design/DesignTokens.swift
ios/PurePaceTests/ContrastPolicyTests.swift
ios/PurePaceTests/DesignTokensTests.swift
```

`ios/PurePace/**` 除 `DesignTokens.swift` 外 `Motion.` 引用为 0；`.animation(` / `withAnimation(` / `isReduceMotionEnabled` 新增为 0。

## 3) 设计取舍

- 矩阵中 `accent` 对三面同时存在 4.5 档与 3.0 档，条目名加 `@large` 后缀保持唯一，便于逐对日志定位。
- 角色阶梯把 label/unit 的 11 只放进 `sizes` 一次，避免破坏「严格递增」；重复档只允许 label/unit 一对，由 `roleProblems` 与单测双重锁定。
- 所有 fail-closed 校验都做成纯函数（`purposeProblems` / `roleProblems` / `checks(for:)`），反例测试直接传入坏数据，不靠注释或手工塞 `nil`。
