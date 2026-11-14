# 修复 iOS UI 布局断言的采样抖动（稳定采样 + 胶囊去重口径）

## 范围

只修 `testZhHansCopyDatesAndBottomAnchoredPrimaryAction` 依赖的**测量确定性**，不碰产品布局、不放宽阈值：

1. **采样等布局稳定**：`assertRunMetricsBalanced`（`ios/PurePaceUITests/RunFlowUITests.swift` L848-L897）在把帧集合交给 `RunLayoutBalancePolicy.evaluate` 前，对同一状态连续采样，直到帧集合逐位一致（连续 3 轮）才判定；带**有界**轮数与单态总等待上限。未稳定时打印每轮 `frames=` 与 `LARGEST=<值>` 诊断，然后仍用既有断言判红（不跳过、不转绿）。
2. **修正去重口径**：`dedupeFramesInsideHint`（同文件 L899-L904）不再用严格 `hint.contains(frame)` 判内层帧，改为「帧中心点落入胶囊矩形」判据（在注释写清判据与 1.42pt 高差情形下的推导），使比胶囊高 1.42pt 的内层文本帧被去重，不再影响 `largestGap`。
3. **纯判定共用一份实现 + L1 单测**：新增 `ios/Core/Sources/PurePaceCore/RunLayoutSamplingPolicy.swift`（去重谓词 + 稳定判定，仅依赖 Foundation），单测落在 `ios/Core/Tests/PurePaceCoreTests/`；UI 用例与 L1 单测共用同一实现（沿用 `ios/project.yml` 里 UITests target 已把 `PurePace/Design/*.swift` 编入测试 bundle 的既有模式，把该文件加入 sources）。
4. **既有验证矩阵行文本**：只更新 `docs/verification-matrix.md` 第 23 行（「详情导出固定底部 / 指标区居中 / 暂停态 Tab 栏 / 结束态地图 hero（B1）」）的现状/证据/反例文本，不新增行。

## 验收

- ac-settle-three-consecutive-stable: 采样仅在连续 3 轮帧集合（含 `navigationBarBottom`、`primaryActionTop`、内容帧、`run.mapPreview` 帧、`run.backgroundDegraded` 帧）逐位一致后才返回该稳定集合；单测喂「前两轮漂移、第 3 轮起一致」的序列时，返回的必须是第 3 轮之后的稳定集合，而不是首轮采样。
- ac-settle-bounded-and-diagnostic: 稳定前最多 12 轮、单态总等待 ≤6s；未达标时先打印**每轮** `frames=` 与 `LARGEST=<值>`，再用既有 `XCTAssertTrue(evaluation.passes, ...)` 判红；不得新增 `sleep`/`Thread.sleep`（`check-ios-shell.sh` 的 `ac-tests-present` 直接 grep 判红），不得改 `IOS_XCODEBUILD_TIMEOUT=600` 或 UI 分段数量。
- ac-dedupe-center-in-hint: 内层文本帧中心点落入胶囊矩形即被去重（含边界容差），比胶囊高 1.42pt 的内层帧不得出现在送去判定的帧集合里；中心点落在胶囊外的相邻内容块必须保留，不得误删。
- ac-dedupe-largest-neutral: 对同一组「运行中」帧，去重后的 `largestGap` 与「只保留胶囊帧、不含内层文本帧」的计算值相等（差值 0）；内层文本帧的存在不得使 `largestGap` 变大或变小。
- ac-counterexample-downshift-6-red: 以运行中绿样本（`largestGap` 距 80 上限 <1pt）为基准，把胶囊帧整体下移 6pt 后喂同一 `RunLayoutBalancePolicy.evaluate`，必须 `largestGap > 80` 且 `passes == false`（不依赖回退产品代码）。
- ac-counterexample-settle-not-vacuous: 单测喂「每轮都不同」的持续漂移序列，稳定判定必须返回未稳定；若把判据改成恒真（首轮即 stable），该单测必须判红。
- ac-thresholds-and-assertion-strength-unchanged: 80/80/80/16（及 44/24/691/360 等）阈值逐字不变；UI 权威腿枚举（runflow / evidence / screenshot-light / screenshot-dark）与既有断言条数不减少；无 XCTest 重试参数、无 `continue-on-error`、无删断言。
- ac-ios-core-gates-green: `swift build --package-path ios/Core`、`swift test --package-path ios/Core`（含新增去重/稳定判定单测）与 `bash scripts/check-ios-core.sh` 全绿（Sources 仅 `import Foundation`、无平台/业务符号、无版本字面值）。
- ac-shell-selftest-green: `bash scripts/check-ios-shell.sh --self-test` 与全量 `bash scripts/check-ios-shell.sh` 全绿（含阈值锁定与 `ac-tests-present`）。
- ac-matrix-row-updated-no-new-row: `docs/verification-matrix.md` 仍为表头 + 分隔行 + 25 行接缝、6 列、无 `pending` / 缺口；被更新的那一行仍包含「本项实测」与 `wi_intake_1127fd3553df6ea7` 归属（`DocsVerificationMatrixTests` 守护）。
- ac-authoritative-green-same-commit: UI 权威绿只认同 commit 的 `.github/workflows/ios.yml` run；本地连跑该用例 ≥3 次仅作旁证，回执必须写清轮次与结果，并区分「机器已验 / 未验」，不得声称真机已验证。

## 非目标

- 不改产品视觉、布局、受管视图与任何 `accessibilityIdentifier`；不改 `RunView`/`TrackMapView`/token。
- 不放宽任何阈值（80/16 等）、不加 XCTest 重试、不改超时（`IOS_XCODEBUILD_TIMEOUT` 仍 600）、不删/弱化断言、不引入 `continue-on-error`。
- 不把 settle 等待实现成固定长 sleep；不引入墙钟累计量作为判据。
- 不新增验证矩阵行、不动其它行；不改 UI 腿枚举与 `scripts/test-ios.sh` 分段结构。
- 不动 Audio/TTS、定位、遥测、GPX 逻辑；不改 `VERSION`、project 版本号或 `README`。
- 不做真机/现场验收（真机项仍 `pending: 待人现场`）。

## 实现约束

- 文件锚点：`ios/PurePaceUITests/RunFlowUITests.swift`（`assertRunMetricsBalanced` L848-L897、`dedupeFramesInsideHint` L899-L904、`waitUntil` L1538-L1547、`assertRunMetricsBalanced` 的 5 个调用点 L129 / L644 / L664 / L692 / L763）；`ios/Core/Sources/PurePaceCore/RunLayoutSamplingPolicy.swift` 与 `ios/Core/Tests/PurePaceCoreTests/RunLayoutSamplingPolicyTests.swift` 为新增文件；`ios/project.yml` 的 `PurePaceUITests.sources` 增加该 Core 源文件路径；`docs/verification-matrix.md` 第 23 行。
- 一份实现两处编译：UI 用例不得复制去重/稳定判定逻辑，必须与 L1 单测共用 `RunLayoutSamplingPolicy`；该文件在 `ios/Core` 内只 `import Foundation`，不得出现 `check-ios-core.sh` 禁止的平台/业务符号（含注释里的关键字），也不得出现根 `VERSION` 字面值。
- 去重判据（择一，本项选中心点法）：判据为「帧中心点落入胶囊矩形（边界内缩 0.5pt 容差）」，注释需写清推导——稳定布局下内层文本帧比胶囊高 1.42pt 时上下各外扩 0.71pt，中心点仍在胶囊内，故中心点判据能覆盖严格 `contains` 漏掉的 1.42pt 情形；中心点在胶囊外的相邻块不会被误删。
- 稳定采样必须复用现有 `waitUntil`（0.2s 轮询）/ `AXSnapshotBatch` 口径，不新增固定 sleep；上限写死为「连续 3 轮一致 + 最多 12 轮 + 单态 ≤6s」，最坏情况 5 个调用点合计 ≤30s，不逼近 runflow 段的 600s 预算。
- 判红诊断格式固定：每轮打印 `round=<n> frames=<...>` 与 `LARGEST=<value>`；未稳定时的最终判红仍走 `RunLayoutBalancePolicy.evaluate` 的原断言，不改错误语义。
- 反例只喂合成/实测帧，不依赖产品代码回退：a) 胶囊下移 6pt 必须 largest>80；b) 内层文本帧加入后 largest 与「仅胶囊」相等；c) 恒真 settle 判据必须被持续漂移序列打成红。
- 验证口径：本地 `swift build`/`swift test --package-path ios/Core` + `bash scripts/check-ios-core.sh` + `bash scripts/check-ios-shell.sh --self-test` + 全量 `bash scripts/check-ios-shell.sh` 必绿；UI 权威绿只认同 commit 的 `ios.yml` run；本地连跑目标用例 ≥3 次仅作旁证并写清轮次与结果；回执区分「机器已验 / 未验」，不声称真机已验证。预算 ≤8M token / ≤90 分钟。
