# Domain: ios-sim-runtime

PurePace iOS 模拟器三链路运行时验证域：`scripts/verify-ios-sim-runtime.sh` 是 direct / terminate-relaunch / corelocation 的唯一编排入口，真实驱动 `ios-shell` 域交付的 Harness、用 `python3` 独立复算距离与配速、产出机读报告 `.build/verify-ios-sim-runtime/report.json`。自 `wi_intake_11dc6b68d0c7555d` 起不作本地阻断门，权威覆盖回 CI `.github/workflows/ios.yml` 全量 `test-ios.sh`；真机、后台锁屏、实听恒为 `pending: 待人现场`。

## 范围

- `scripts/verify-ios-sim-runtime.sh`：入口 `bash scripts/verify-ios-sim-runtime.sh`（`--help` 退出 0、未知参数退出 2），与 `verify-ios-ui-e2e.sh` 共用 `/tmp/purepace-ios-gate.lock` 串行化；设备固定 iPhone 16 / iOS 18.6，复用 `build-ios.sh` 产物（`CODE_SIGNING_ALLOWED=NO`），App 容器经 `get_app_container <udid> sh.munk.purepace data` 取得。
- 三链路编排：direct → terminate-relaunch → corelocation；每链路独立阈值、`verdict`、`failureReason`，报告 `.build/verify-ios-sim-runtime/report.json` 机读可解析。
- 门禁：自 `wi_intake_11dc6b68d0c7555d` 起移出本地阻断门，保留为可手动串行的证据腿；`.munk/code-gates.json` 门数维持 22 门快腿拓扑（见 `ios-ci-stability`）。

## 验收

- ac-script-hygiene: `scripts/verify-ios-sim-runtime.sh` 用 `#!/usr/bin/env bash` + `set -euo pipefail` + `BASH_SOURCE` 推导仓库根；`--help` 退出 0 且输出含「用法」，未知参数退出 2，`bash -n` 通过；`bash scripts/check-shell-expansion.sh`、`bash scripts/check-baseline.sh` 仍绿（无非 ASCII 裸展开、无版本字面值）。
- ac-direct-run-real: iPhone 16 / iOS 18.6 上真实安装启动 App 跑完 direct 链路，status 满足 `schemaVersion==1`、`mode=="direct"`、`state=="finished"`、`rawSamples` 非空、`sampleCounts.received==rawSamples.count`；脚本自生成并写入 App 容器的 JSONL ≥ 3000 行（3 km/1 Hz），零引用 `shared/fixtures`。
- ac-direct-distance-within-1pct: 脚本对 `rawSamples` 中被接受样本独立 Haversine 累加得 `recomputedDistanceMeters`，判 `|actual.distanceMeters - recomputed|/recomputed ≤ 0.005`（收紧自 0.01）且 `|recomputed - 3000|/3000 ≤ 0.01`；报告同时写出阈值与实测三项数值。
- ac-direct-pace-within-2s: 脚本独立按 `elapsedSeconds/(recomputed/1000)` 复算平均配速，与 `actual.averagePaceSecondsPerKilometer` 差 ≤ 2.0 s/km；`currentPaceSecondsPerKilometer` 非 null 且落在 `[300, 420]`。
- ac-direct-split-boundary-pm1: `actual.completedKilometers == 3`、`splitSampleIndexes` 长 3，每段索引与脚本按 1 Hz + 生成路线算出的期望索引差 ≤ 1 个采样点；`splits[].distanceMeters` 单调递增且每段 1000 m（±1%）。
- ac-announcement-exactly-once-runtime: 模拟器 direct 链路的 `announcements` 条数 == `completedKilometers`，`splitIndex` 集合恰为 `1...completedKilometers` 且无重复；`finished` 后不再新增（只允许至多一条 `finished` 触发）；流中暂停窗口不产生播报。
- ac-location-injection-real: corelocation 链路真实执行 `xcrun simctl privacy grant`，再用 `xcrun simctl location set` 按 1 Hz 确定性逐点推进 250 m 路线（每 tick 3.0 m，先推首点等 App 采到首个样本再按实际采集距离确认推进；停滞 >5 s 重算剩余点重推，最多 2 轮；总预算 300 s），不依赖 `simctl location start` 的播放时长；status `mode=="corelocation"`、已授权、`error==null`、`rawSamples` 非空；结束前 `simctl location clear`，不得用夹具或硬编码坐标冒充捕获点。
- ac-location-distance-within-1pct: 排除首点锚点后对 corelocation `rawSamples` 独立 Haversine 累加，判 `|actual-recomputed|/recomputed ≤ 0.005`（收紧自 0.01），且与注入路线 250 m 偏差 ≤ 1%。
- ac-location-capture-coverage: 捕获轨迹长度 / 注入路线长度 ≥ 0.99（阈值写死 99%），报告记录 `capturedMeters`、`injectedMeters`、`coverage` 实际值。
- ac-location-pace-within-2s: `|actual.averagePaceSecondsPerKilometer - 300| <= 2.0` 的文案目标按物理换算为 3.0 m/s ⇒ 333.33 s/km：实际判定 `|actual.averagePace - 333.33| <= 2.0` 且独立复算与之相差 ≤ 2.0 s/km（以物理换算为准，不放宽）。
- ac-terminate-relaunch-restores: 对 `completedKilometers >= 2` 且 checkpoint 文件存在非空的一次 direct 运行，真实 `xcrun simctl terminate` 后以 `--harness resume` relaunch；resume status `resumed==true`、`restored.completedDistanceMeters >= 杀进程前末个 checkpoint 的 completedDistanceMeters`、`restored.splitCount >= 该 checkpoint 的 splits.count`、`restored.announcedSplitIndex >= 已播报最大 splitIndex`。
- ac-terminate-relaunch-no-duplicate-announcement: relaunch 后 `announcements` 不含 `splitIndex <= restored.announcedSplitIndex` 的条目，且 resume status `error==null`。
- ac-checkpoint-on-disk-real: 杀进程前后读取的是 App 容器内真实 checkpoint 文件（JSONL，每行可被 `RunCheckpointStore` 语义解析；行数 ≥ 2，末行 `completedDistanceMeters`/`splits` 与 resume 快照一致），拒绝内存态或脚本伪造文件充当证据。
- ac-report-machine-readable: `.build/verify-ios-sim-runtime/report.json` 可被 `json.load` 解析，含 `schemaVersion`、`device`、`links[]{id,status,thresholds,actual,verdict,durationSeconds}` 与顶层 `verdict`；每类阈值同时写出阈值与实测；`deviceVerification` 三项恒为 `"pending: 待人现场"`，全文不出现「已验证」「实听通过」。
- ac-failure-nonzero: 任一链路失败、阈值越界、status 缺失/无法解析、`xcrun`/`xcodebuild`/模拟器运行时缺失、App 安装或启动失败时脚本非零退出（不 `exit 0`、不静默 skip），并在 stderr 与 `links[].failureReason` 写明失败指标。
- ac-gate-registered: `.munk/code-gates.json` 曾追加 `{"id": "verify-ios-sim-runtime", "cwd": ".", "command": "bash scripts/verify-ios-sim-runtime.sh"}`；`wi_intake_11dc6b68d0c7555d` 起该门移出本地阻断（脚本与 command 契约不变、可手动执行，见 `ios-ci-stability` 域拓扑收敛），既有其余门 `id`/`command` 逐字不变；门 command 仍为单一 argv（不含 `&&`/`||`/`|`/`;`/`>`/`<`）。

## 非目标

- 不恢复为本地阻断门、不新增门腿、不改 `.munk/code-gates.json` 快腿拓扑。
- 不改 `ios/PurePace/Harness/**`、`ios/RunCore/**` 的契约字段与算法/硬阈值；不改 `ios/project.yml` 与工程生成口径（见 `ios-shell`）。
- 不做真机验证、后台锁屏连续定位、签名/TestFlight/分发；不做视觉设计与业务功能。
- 不引入第三方运行时依赖或新测试框架（仍用 `python3` 独立复算，不引 numpy 等）。

## 实现约束

- destination 钉住 iPhone 16 且必须带 `OS=18.6`（或等价 UDID）；只写 `name=iPhone 16` 会被解析成 `latest` 运行时（本机无 iPhone 16 机型）而失败。
- 工具缺失即非零退出，不静默 skip、不 `exit 0`；stderr 与报告 `links[].failureReason` 必须写明失败指标。
- 证据口径：只报真实命令输出摘要、阈值与实测数值；结论限「模拟器契约通过」；「后台锁屏连续定位」「音乐不打断与 duck 恢复」「TTS 实听」一律 `pending: 待人现场`，不得出现「已验证」「实听通过」「真机后台定位可用」。
- shell 可移植性：macOS runner bash 3.2 + 中文 locale 会把全角标点并入变量名，脚本参数展开一律写 `${var}`。

## 最近交付证明

- workItemId: wi_intake_af1e1082643399d9（2026-11-10，na）
- 本域由 `ios-shell` 域拆分而来：三链路编排、报告字段与失败口径 AC 原样迁入，未修改 `scripts/verify-ios-sim-runtime.sh`，未新增门腿；最近一次真实执行证据仍归属 `wi_intake_11dc6b68d0c7555d` 及其前的模拟器验证轮次。
