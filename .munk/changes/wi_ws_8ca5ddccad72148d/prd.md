# 模拟器三条真实链路编排与机器可读报告

## 范围

新增唯一交付物 `scripts/verify-ios-sim-runtime.sh`（本项唯一新增代码文件 + 门禁注册 + 基线文档），把已交付的波 2 运行 Harness（`ios/PurePace/Harness/`，已按 launch arg 契约接线到 `PurePaceApp`）在 **iPhone 16 / iOS 18.6** 模拟器上真实驱动三次，脚本自行复算原始采样并产出机读报告：

1. **direct 链路**：脚本生成 3 km、1 Hz、5:00–7:00/km 的 JSONL 直接流（真实写入 App 容器，不进 `shared/fixtures`），以 `--harness direct` 启动 App，Harness 跑完写 status。
2. **corelocation 链路**：`xcrun simctl location <udid> start --speed=3.0 ...` 注入约 250 m（约 5:00/km）路线，App 以 `--harness corelocation` + `--max-duration` 采集；脚本对 status 的 `rawSamples` 用独立 Haversine 复算并与引擎结果比对。
3. **terminate→relaunch 链路**：direct 跑到 ≥2 个已完成分段并有真实 checkpoint 后，`xcrun simctl terminate` 杀进程，再以 `--harness resume` relaunch，比对恢复快照与杀进程前最后一个 checkpoint。

脚本按硬阈值判定（阈值文案与 Harness `thresholds` 一致，写死不放宽），生成机读报告；`.munk/code-gates.json` append-only 注册 `verify-ios-sim-runtime` 门。

对齐检查点：`cp-metrics-contract` / `cp-persistence-contract`（本项补模拟器侧证据）、`cp-stage2-exit`（本项**不关闭**；真机项仍 `pending: 待人现场`）。

## 验收

- ac-script-hygiene: `scripts/verify-ios-sim-runtime.sh` 以 `#!/usr/bin/env bash` + `set -euo pipefail` + `BASH_SOURCE` 推导仓库根；`bash scripts/verify-ios-sim-runtime.sh --help` 退出 0 且输出含「用法」，未知参数退出 2；`bash -n` 通过；`bash scripts/check-shell-expansion.sh` 与 `bash scripts/check-baseline.sh` 仍绿（脚本内不出现裸 `$var`+非 ASCII，不写版本字面值）。
- ac-direct-run-real: 脚本在 iPhone 16 / iOS 18.6 上真实安装并启动 App 执行 direct 链路，成功读到 `schemaVersion == 1`、`mode == "direct"`、`state == "finished"` 的 status，且 `rawSamples` 非空、`sampleCounts.received == rawSamples.count`；脚本生成并写入 App 容器的 JSONL 行数 ≥ 3000（3 km / 1 Hz），不读取 `shared/fixtures` 任何文件。
- ac-direct-distance-within-1pct: 脚本对 status `rawSamples` 中被接受样本独立做 Haversine 累加得 `recomputedDistanceMeters`，判定 `|actual.distanceMeters - recomputed| / recomputed <= 0.01` 且 `|recomputed - 3000| / 3000 <= 0.01`（期望路线 3 km），报告同时记录阈值、实测三项数值。
- ac-direct-pace-within-2s: 脚本独立按 `elapsedSeconds / (recomputed/1000)` 复算平均配速，判定与 `actual.averagePaceSecondsPerKilometer` 之差 `<= 2.0` s/km；`currentPaceSecondsPerKilometer` 非 null 且落在 `[300, 420]` s/km 区间内（5:00–7:00/km 生成范围的边界校验）。
- ac-direct-split-boundary-pm1: direct 链路 `actual.completedKilometers == 3`，`splitSampleIndexes` 长度 == 3，每个分段的实际采样索引与脚本按 1 Hz 与生成路线独立计算的期望索引之差 `<= 1` 个采样点；`splits[].distanceMeters` 单调递增且每段约 1000 m（±1%）。
- ac-announcement-exactly-once: direct 链路 `announcements` 条数 == `actual.completedKilometers`，`splitIndex` 集合恰为 `1...completedKilometers` 且无重复（同一公里重复 tick 不产生第二条）；`state == "finished"` 后 status 不再新增 announcement；流中插入的暂停窗口不产生任何 announcement。
- ac-location-injection-real: corelocation 链路真实执行 `xcrun simctl privacy grant`（定位授权）与 `xcrun simctl location start --speed=3.0`，status `mode == "corelocation"`、`locationAuthorization` 为已授权取值、`error == null`、`rawSamples` 非空；脚本在结束前执行 `xcrun simctl location clear`，且**不**用夹具或硬编码坐标数组冒充捕获点。
- ac-location-distance-within-1pct: 脚本对 corelocation `rawSamples` 独立 Haversine 累加，判定 `|actual.distanceMeters - recomputed| / recomputed <= 0.01`；且 `recomputed` 与注入路线长度 250 m 的偏差 `<= 1%`（排除首点漂移：被判为锚点的首个接受样本不计入距离）。
- ac-location-capture-coverage: 排除首点后，捕获轨迹长度 / 注入路线长度 `>= 0.99`（覆盖率阈值写死 99%，与 1% 距离误差同一量级），报告记录 `capturedMeters`、`injectedMeters`、`coverage` 实际值。
- ac-location-pace-within-2s: `|actual.averagePaceSecondsPerKilometer - 300| <= 2.0`（3.0 m/s = 5:00/km），且脚本独立复算配速与之相差 `<= 2.0` s/km。
- ac-terminate-relaunch-restores: direct 链路结束后对满足「`actual.completedKilometers >= 2` 且 checkpoint 文件存在且非空」的一次运行，脚本真实执行 `xcrun simctl terminate` 后以 `--harness resume` relaunch；resume status 的 `resumed == true`、`restored.completedDistanceMeters >= 杀进程前最后一个 checkpoint 的 completedDistanceMeters`、`restored.splitCount >= 该 checkpoint 的 splits.count`，且 `restored.announcedSplitIndex >= 已播报的最大 splitIndex`。
- ac-terminate-relaunch-no-duplicate-announcement: relaunch 后 `announcements` 不含任何 `splitIndex <= restored.announcedSplitIndex` 的条目（已播报公里不重复播报）；脚本断言 resume status 的 `error == null`。
- ac-checkpoint-on-disk-real: 杀进程前后脚本读取的是 App 容器内真实 checkpoint 文件（JSONL，每行可被 `RunCheckpointStore` 语义解析；断言行数 >= 2 且最后一行 `completedDistanceMeters`/`splits` 与 resume 快照一致），拒绝以内存态或脚本伪造文件充当证据。
- ac-report-machine-readable: 脚本在固定路径 `.build/verify-ios-sim-runtime/report.json` 写出合法 JSON（`python3 -c 'json.load'` 可解析），含 `schemaVersion`、`device{name,udid,runtime}`、`links[]`（每项含 `id`、`status`、`thresholds`、`actual`、`verdict`、`durationSeconds`）与顶层 `verdict`；每类阈值都以数值同时写出「阈值」与「实际值」；`deviceVerification` 段显式保留 `backgroundLocationContinuous`、`audioNotInterrupted`、`ttsLiveListen` 三项取值 `"pending: 待人现场"`，且报告全文不出现「已验证」「实听通过」。
- ac-failure-nonzero: 任一链路失败、任一阈值越界、status 缺失/无法解析、`xcrun` 或 `xcodebuild` 或模拟器/运行时缺失、App 安装或启动失败时，脚本以非零退出码结束（不得 exit 0、不得静默 skip），并在 stderr 与报告 `links[].failureReason` 写明失败指标。
- ac-gate-registered: `.munk/code-gates.json` 追加 `{"id": "verify-ios-sim-runtime", "cwd": ".", "command": "bash scripts/verify-ios-sim-runtime.sh"}`；既有 21 个门的 `id`/`command` 逐字不变（只增不减）；新门 command 为单一 argv，不含 `&&`/`||`/`|`/`;`/`>`/`<`（`bash scripts/check-ios-run-core.sh` 的门禁断言仍绿）。
- ac-existing-gates-green: `bash scripts/check-ios-shell.sh`、`bash scripts/check-ios-scripts.sh`、`bash scripts/check-ios-run-core.sh`、`bash scripts/check-shared.sh`、`bash scripts/check-gpx-export.sh`、`bash scripts/check-shell-expansion.sh`、`bash scripts/check-baseline.sh` 全部退出 0；本项不修改 `ios/RunCore/**` 与 `ios/PurePace/Harness/**` 的契约字段。

## 非目标

- 不写任何 UI 页面；不接 TTS 实际发声；不改占位首屏；不动 `ios/RunCore` 的算法与硬阈值。
- 不改 Harness launch arg 契约、status schema 字段名与阈值取值（`--harness/--status/--stream/--checkpoint/--max-duration` 按现网锁定）。
- 不把 `shared/fixtures` 当坐标流；不用硬编码期望轨迹冒充捕获点；不用夹具替代 `simctl` 注入。
- 不声称真机结论：后台锁屏连续定位、音乐不打断与 duck 恢复、TTS 实听一律 `pending: 待人现场`；不关闭 `cp-stage2-exit`。
- 不改 `.github/workflows/*`（新增门只进 `code-gates.json`，不要求 CI 跑模拟器链路）；不写 Android 业务；不引入第三方依赖。
- 不新增第二个验证脚本、不改 `build-ios.sh` / `test-ios.sh` 的入口语义。

## 实现约束

- 现有可复用接缝（已交付，直接驱动，不重写）：
  - App bundle id `com.chaxiu.purepace`；`ios/project.yml` target `PurePace` 已含 `Harness/` 源目录、`UIBackgroundModes: location` 与定位用途说明。
  - Harness 已在 `ios/PurePace/PurePaceApp.swift` 按 `--harness` 接线：无该 flag 走占位首屏，有则渲染空 Harness root。
  - launch arg 契约（不得改名）：`--harness direct|corelocation|resume`；`--status` 三模式必填；`--stream` 仅 direct 必填；`--checkpoint` 三模式必填；`--max-duration <秒>` 可选。Harness 自建 status/checkpoint 父目录。
  - status 唯一可观测面：`schemaVersion=1`，含 `mode/state/startedAt/updatedAt/finishedAt/resumed/restored/rawSamples/sampleCounts/actual{distanceMeters,elapsedSeconds,averagePaceSecondsPerKilometer,currentPaceSecondsPerKilometer,completedKilometers,splitCount,splitSampleIndexes}/thresholds/splits/announcements/error`；corelocation 额外含 `locationAuthorization`。原子写，路径由 `--status` 指定。
  - `scripts/build-ios.sh` 已把派生数据写到 `.build/ios` 并打印真实 `.app` 路径；destination 固定 `platform=iOS Simulator,name=iPhone 16,OS=18.6`。脚本可复用其构建产物或自行 `xcodebuild build`，但不得伪造成功行（`check-ios-scripts.sh` 有反例断言）。
  - 本机已存在 iPhone 16 设备（`xcrun simctl list devices available`）与 iOS 18.6 runtime（`xcrun simctl list runtimes`），`xcrun simctl location` 可用。容器路径取 `xcrun simctl get_app_container <udid> com.chaxiu.purepace data`。
- 时间预算：direct 3 km 走流回放（按样本时间戳推进，秒级完成）；corelocation 注入 250 m / 3.0 m/s 约 83 s 真实时间，需用 `--max-duration` 兜底并轮询 status 到 `finished`/超时；脚本整体必须能在本机数分钟内完成，超时不得删减断言（超时即失败）。
- 复算独立：脚本用 `python3`（缺失即 fail，不得 skip）对 `rawSamples` 做 Haversine 与配速复算；不得信任 `actual` 自证。
- 报告与临时产物只落 `.build/verify-ios-sim-runtime/`（已在 `.gitignore`）；`shared/fixtures` 零引用。
- 脚本卫生：新脚本会被 `check-shell-expansion.sh` 扫描（`scripts/**/*.sh` 非注释行），变量展开一律 `${var}`；`check-baseline.sh` 断言 `scripts/*.sh` 无版本字面值，故不得写死版本号。
- 门禁注册只做 append，`verify-ios-sim-runtime` 的 command 必须是单一 argv。
- 基线文档：落 `ios-shell` 域（新增模拟器验证编排口径）与必要时 `repo-baseline` 门禁记录；不重写既有域全文。
