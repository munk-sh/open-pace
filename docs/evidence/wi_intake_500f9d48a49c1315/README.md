# 距离恒 0 根因结论 + 三态读数协议 + W1 断言变异红证（证据项，生产代码零改动）

- workItemId: `wi_intake_500f9d48a49c1315`
- 基线 commit: `c381352`（`merge(wi_intake_9681718e12c7b31c): 定位三态可归因 + 诊断快照补字段 + 精度降级不静默`）
- 结论文档（仓内唯一新增文档）: `docs/location-zero-distance-root-cause.md`
- 被测断言（仓库内零改动，均来自 W1 提交）:
  - `ios/PurePaceTests/RunPermissionAndDiagnosticsTests.swift:399` `testSingleImpreciseFixAcceptedAtWindowWithoutAnotherCallback`
  - `ios/PurePaceTests/RunPermissionAndDiagnosticsTests.swift:431` `testLocationSearchStateTimesOutWithAttributableReason`
  - `ios/PurePaceTests/RunPermissionAndDiagnosticsTests.swift:483` `testTimeoutRetryRestartsLocationWithoutResettingSession`
  - `ios/PurePaceTests/RunPermissionAndDiagnosticsTests.swift:525` `testDiagnosticsSnapshotIsSelfConsistentAndSingleSourced`
  - `ios/PurePaceTests/RunPermissionAndDiagnosticsTests.swift:568` `testLastSampleTimeNeverRegresses`
- 变异位置（只在 `/tmp/pp-w1-500f9d48a49c1315/repo/` 副本内改，每次只改一处，跑完即还原）:
  `RunLocationSource.swift`、`RunLocationReadiness.swift`、`RunSessionViewModel.swift`、`RunSessionOrchestrator.swift`。

## 环境与命令

环境：macOS（darwin arm64）、Xcode 26.3 (17C529)、模拟器 iPhone 16 / iOS 18.6
（`id=B3F00298-E08A-41E0-876E-6E8A75C730FD`，已 Booted）、`xcodegen` 3.x。

沙箱准备（仓库只读复制，`.git` / `.munk` / `.build` 不进副本）：

```bash
D=/tmp/pp-w1-500f9d48a49c1315
mkdir -p "$D" && rsync -a --exclude '.build' --exclude '.git' --exclude '.munk' ./ "$D/repo/"
cd "$D/repo" && xcodegen generate --spec ios/project.yml --project ios
```

未变异与每种变异都用同一条命令，只换副本内源码形态或 `-only-testing` 用例：

```bash
xcodebuild test -project ios/PurePace.xcodeproj -scheme PurePace \
  -destination 'platform=iOS Simulator,id=B3F00298-E08A-41E0-876E-6E8A75C730FD' \
  -derivedDataPath "$D/dd" \
  -only-testing:PurePaceTests/RunPermissionAndDiagnosticsTests/<case> \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 300 CODE_SIGNING_ALLOWED=NO
```

复现 1 走 RunCore 包（无需模拟器）：

```bash
swift test --package-path ios/RunCore --filter RunClockDecouplingTests/testElapsedTicksWithClockAndZeroLocationSamples
```

## 未变异（绿）

5 条 W1 用例同批执行：`Executed 5 tests, with 0 failures (0 unexpected)` / `** TEST SUCCEEDED **` / `EXIT:0`
（`logs/green.log`）。

## 变异红证（原文索引）

| 文件 | 含义 | 退出码 | 摘要 |
|---|---|---|---|
| `logs/green.log` | 未变异，5 条用例同批 | 0 | `Executed 5 tests, with 0 failures` / `** TEST SUCCEEDED **` |
| `logs/mutation-1-fallback-silent-drop.log` | 删掉窗口到点的 `accept(pending)`（恢复静默丢弃） | 65 | `Executed 1 test, with 2 failures`，失败于 `:426` / `:427` |
| `logs/mutation-2-search-reason-collapse.log` | `.accuracyFiltered` 分支改返回 `.noCallbacks` | 65 | `Executed 1 test, with 1 failure`，失败于 `:462` |
| `logs/mutation-3-retry-noop.log` | `retryLocation()` 删掉 `locationSource.restart()` | 65 | `Executed 1 test, with 1 failure`，失败于 `:519` |
| `logs/mutation-4-diagnostics-lasterror-dropped.log` | `diagnosticsSnapshot()` 的 `lastError` 写死 `nil` | 65 | `Executed 1 test, with 3 failures`，失败于 `:546` / `:547` / `:548` |
| `logs/mutation-5-no-monotonic-guard.log` | 归档单调守卫 `return sample.timestamp > last` 改 `return true` | 65 | `Executed 1 test, with 1 failure`，失败于 `:585` |

日志为对应 `xcodebuild` 原始输出的裁剪版（保留 `Test Case` / `error:` / `Executed` / `** TEST … **` / `EXIT`，
头部写明被测用例、变异内容、执行位置与命令）；断言原文逐字未改，裁剪只删编译与环境噪声行。

## 复现日志（机器侧可复现 / pending）

| 文件 | 项 | 输入 | 实测读数 | 标记 |
|---|---|---|---|---|
| `logs/repro-1-zero-callbacks.log` | 零回调 → 计时在走、距离 0 | 注入时钟 +5.0s，零条定位采样 | `REPRO-1 callbacks=0 elapsed=5.0 distance=0.0` | 机器侧可复现 |
| `logs/repro-2-zero-distance-branches.log` | 65m fix 窗口内 0、到点接受 | acc=65m，t=0 / t=15s | `REPRO-2A raw=1 filtered=1 samples=0`；`REPRO-2B samples=1 lastAccepted=Optional(65.0)` | 机器侧可复现 |
| 同上 | 250m fix 超降级上限永不结算 | acc=250m，t=15s | `REPRO-2C raw=1 filtered=1 samples=0 lastAccepted=nil` | 机器侧可复现 |
| 同上 | 30s 搜索态可归因 | `denied` / `services=off` / `raw=3 filtered=3` | `.unauthorized` / `.servicesDisabled` / `.accuracyFiltered` | 机器侧可复现 |
| `docs/location-zero-distance-root-cause.md` §4.5 | 真机三态 × ≥30s 读数（原始回调 / 丢弃 / 采样 / 授权 / 精度授权 / 后台标志） | W1 WiFi 有网、W2 WiFi 关+蜂窝、W3 飞行模式 | 未采集 | `pending: 待人现场` |

复现 2 的读数来自 `/tmp` 副本内临时新增的 `testReproZeroDistanceBranches` 打印（只为读真实数字，
不入仓）；复现 1 同样只在副本测试内加 1 行 `print`。仓内测试文件零改动。

## 发现（如实记账，本项不修）

1. `RunLocationSource.flushPendingFallbackIfDue()`（`ios/PurePace/Location/RunLocationSource.swift:385-386`）
   在 pending `> 200m` 时 `return`：既不清空 pending 也不重挂定时器；后续无回调则永不结算，
   距离恒 0（复现 2C 实测 `samples=0`）。
2. 降级窗口原点是 `beginUpdating()` 的 `updatingStartedAt`（`:322`），不是「第一条低精度回调」；
   到点判据是 `uptime() - startedAt >= 15s`（`:381`）。
3. `ios/PurePace` 全目录无 `NWPathMonitor` / `Network` / `Reachability` 命中：三态网络形态不参与任何
   定位分支判定，网络只影响首 fix 延迟与精度；距离恒 0 的归属只能靠 `原始回调` / `精度过滤丢弃` 两列判别。
4. 授权/服务判定顺序两层不一致：`RunLocationReadiness.resolve`（`RunLocationReadiness.swift:78-85`）服务优先，
   `RunLocationSearchState.resolve`（`:125-130`）授权优先。
5. 三态真机读数未采集（无设备），保持 `pending: 待人现场`。

## 仓库零改动证明

- 本项 `git status` 只新增 `docs/location-zero-distance-root-cause.md`、`docs/evidence/wi_intake_500f9d48a49c1315/`
  与 `.munk/changes/wi_intake_500f9d48a49c1315/`；`ios/**`、`scripts/**`、`shared/**`、`VERSION`、
  `.munk/code-gates.json`、`docs/verification-matrix.md` 零 diff。
- 全部变异与复现探针只在 `/tmp/pp-w1-500f9d48a49c1315/repo` 副本内存在，跑完已从备份还原（逐字 diff 校验一致）。
