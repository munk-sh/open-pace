# 主题：跑步定位三态读数与「距离恒 0」归因（ios-run-resilience / three-state-readings）

`ios-run-resilience` 的主题子档：距离恒 0 的四条代码分支归因、WiFi / 蜂窝 / 飞行模式三态读数签名、真机读屏自采集协议，以及 W1 新增断言的 `/tmp` 变异红证。**全篇是文档与证据面契约，不改生产代码。**

## Scope

- `docs/location-zero-distance-root-cause.md`（本域唯一新增结论文档）：四条零距离分支的根因链条（每条对仓内真实文件与符号）、三态读数签名、读屏协议、证据索引。
- `docs/evidence/{workItemId}/`：`README.md` 路径索引 + `logs/` 下复现日志与变异日志。
- 被测对象只读：`RunPermissionAndDiagnosticsTests` 五条 W1 断言 + `RunClockDecouplingTests/testElapsedTicksWithClockAndZeroLocationSamples`。

## Acceptance

- ac-rootcause: 结论文档给出四条零距离分支（零回调 / 精度过滤丢弃 / 降级窗口吞掉 / 静置同坐标）的根因链条——代码路径 + 触发条件 + 与三态网络形态对应的读数签名，每条对上仓内真实符号：`RunLocationSource.start()`、`RunLocationSource.deliver(_:)`、`RunLocationSource.flushPendingFallbackIfDue()`、`RunMetricsEngine.ingest(_:)`、`RunLocationSearchState.resolve`。
- ac-repro: `docs/evidence/{workItemId}/logs/` 内的复现日志来自真实执行并带时间 / 输入 / 读数（`repro-1-zero-callbacks.log`、`repro-2-zero-distance-branches.log`），逐项标「机器侧可复现」或 `pending: 待人现场`，README 给逐条路径索引。
- ac-mutation-w1: W1 五条断言（`testSingleImpreciseFixAcceptedAtWindowWithoutAnotherCallback` / `testLocationSearchStateTimesOutWithAttributableReason` / `testTimeoutRetryRestartsLocationWithoutResettingSession` / `testDiagnosticsSnapshotIsSelfConsistentAndSingleSourced` / `testLastSampleTimeNeverRegresses`）在 `/tmp` 副本上各有一条「构造错误输入 → 实际测得红」日志（`mutation-1..5`，退出码 65，失败行 `:426` / `:462` / `:519` / `:546` / `:585`），未变异对照 `green.log` 为 `Executed 5 tests, with 0 failures`；日志写进文档路径索引。
- ac-protocol: 读屏协议覆盖三态 × ≥30s 的 `原始回调` / `精度过滤丢弃` / `采样点数` / 授权状态 / 精度授权 / 后台标志，逐项写「点哪里、看诊断区哪几行、什么算异常」，人可按步执行且不含任何命令行。
- ac-scope: 本项 diff 只新增 `docs/`（结论文档 + 证据）与 `.munk/`（change pack / baseline fold）；`ios/**`、`scripts/**`、`shared/**`、`VERSION`、`.munk/code-gates.json`、`docs/verification-matrix.md` 零 diff。

## Non-Goals

- 不修根因、不调阈值（50m 接受 / 15s 降级窗口 / 200m 降级上限）、不新增或删除断言、不改生产代码。
- 不跑真机、不代填三态真机读数（一律 `pending: 待人现场`）。
- 不碰相邻项文件（`SettingsView` / `HistoryView` / `RunDetailView` / `RunInteractionPlan` / `DesignTokens`）。
- 不新建第二套文档体系、不改 `docs/verification-matrix.md` 的全局行数。

## Implementation Constraints

- 变异与复现探针只在仓库外 `/tmp` 副本内做，跑完从备份还原；日志必须来自实际执行，不得事后编写。
- 每个数字标口径（测试类 / 用例 / 注入输入 / 窗口秒数），结论中的符号名与代码位置取自仓内真实代码，禁编造。
- 反馈环优先：只单跑单个测试类（≤60 秒），禁跑全量门；整文件写入，禁逐点微编辑。
- 已如实记账的发现（本项不修）：`flushPendingFallbackIfDue()` 在 pending `> 200m` 时 `return` 既不清 pending 也不重挂定时器（后续无回调则永不结算）；`RunLocationReadiness.resolve` 先判服务、`RunLocationSearchState.resolve` 先判授权，两层顺序不一致。

## Latest Delivery Proof

- `wi_intake_500f9d48a49c1315`（docs-only）：`docs/location-zero-distance-root-cause.md` + `docs/evidence/wi_intake_500f9d48a49c1315/`（README + 2 条复现日志 + `green.log` + `mutation-1..5`）；五条变异均实测退出码 65，未变异同批 `Executed 5 tests, with 0 failures`。
- 前置同域：`wi_intake_9681718e12c7b31c` 定位搜索三态可归因（服务/错误进诊断、30s 窗口 + 四类原因、`run.retryLocation` 出口、>50m fix 走 15s 降级窗口不静默丢弃）。
- 未闭合：真机三态 × ≥30s 读数未采集（`pending: 待人现场`）；`denied + 服务关闭` 在 readiness 层仍丢 `permissionDenied`。
