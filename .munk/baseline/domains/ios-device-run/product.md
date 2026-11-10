# Domain: ios-device-run

PurePace iOS 真机取证的**可复用幂等脚本底座**域：`scripts/device-run.sh` 用「单一入口 + 内部 phase」把 devicectl / xcodebuild / iproxy / WDA HTTP / 音源取证命令收敛成 10 步流水（`preflight` → `wda` → `install` → `launch` → `tcc` → `audio` → `record` → `lock` → `collect` → `evidence`），每步固定落日志与起止时刻，证据固定落 `artifacts/device-run/<candidateKey>/` 并被下游直接读取。`audio` step 只委托 `scripts/verify-ios-device-flow.sh --phase=audio`（音频契约本体见 `ios-audio-verification` 域），本域不重写音频命令序列。本域只承载脚本侧契约与文档；TCC 弹窗自动化（P0-1）、pbxproj 入库策略（P1-1）分别是独立子项，本域只留 `PUREPACE_TCC_HELPER` 接缝，不互相实现。真实设备连跑归 Owner 的设备 ops task `task_97c958a247a259ff`，不在 coding 会话内起设备场。

## 范围

- `scripts/device-run.sh`（可拆 `scripts/lib/device-*.sh`）：可执行、`#!/usr/bin/env bash`、`set -euo pipefail`、以 `BASH_SOURCE` 推导仓库根；`--phase=plan|all|preflight|wda|install|launch|tcc|audio|record|lock|collect|evidence`，`--dry-run` 等价 `--phase=plan`；另有 `--self-check`。
- 10 个 phase 职责：`preflight` 核设备/候选包/sha 期望；`wda` 起 `xcodebuild test-without-building` + `iproxy -u <UDID> 8100:8100` 并有界轮询 `GET /status`；`install` 先卸后装；`launch` `--terminate-existing` 后有界等首屏就绪；`tcc` 可插拔授权（`auto|preset|manual`）；`audio` 只调 `scripts/verify-ios-device-flow.sh --phase=audio --configuration=Release` 收 Release 候选包三遍音频证据；`record` 以 `-autoStartRecording` launch-arg 起记录；`lock` WDA 锁 + 双证；`collect` `devicectl device copy from` 取容器并逐文件 sha256；`evidence` 写 `manifest-sha256.txt` 与 `summary.json`。
- 证据结构：`artifacts/device-run/<candidateKey>/` 下 `summary.json`、`manifest-sha256.txt`、`logs/{preflight,wda,install,launch,tcc,audio,record,lock,collect,evidence}.log`、`container/{runs,exports,telemetry,diagnostics}/`、`wda/{status,lock,locked}.json`、`audio/`（`audio-step.json` + `audio-app|audio-runner|audio-none` 证据入口）；`candidateKey=zip-<zipSha256 前 16 位>`；中间解包 / xcresult / xctestrun 只进 `.build/device-run/<candidateKey>/`。
- `docs/device-scripts.md`：用法、全部参数与 env、10 步说明、证据与 `summary.json` 结构、失败语义、幂等口径、`--tcc` 三模式，以及与本域相关的 P0-1 / P1-1 / 设备 ops task 边界。
- `scripts/check-ios-scripts.sh`：把 `device-run.sh` 纳入既有 `bash -n` / `--help` / 未知参数退出 2 断言，并新增 plan 自证块（10 step 顺序、命令模板、两次输出逐字一致、非法 phase 退出 2、`--self-check` 退出 0）与反例自检。

## 验收

- ac-entry-cli: 脚本可执行；首行 `#!/usr/bin/env bash`；含 `set -euo pipefail`；以 `BASH_SOURCE` 推导仓库根；`--help` 退出 0 且含「用法」与 9 个 phase 名；未知参数退出 2。
- ac-phase-set: 接受 `--phase=plan|all|preflight|wda|install|launch|tcc|audio|record|lock|collect|evidence`，`--dry-run` 等价 `--phase=plan`；非法 phase 退出 2 并打印合法取值。
- ac-device-run-order: 文件头、`--help`、`PHASES`、`VALID_PHASES`、summary step 顺序一致为 `preflight wda install launch tcc audio record lock collect evidence`；`--help` 含「用法」与全部 10 个 phase 名。
- ac-plan-no-device: 无设备、无候选 zip、无 WDA xctestrun 的机器上 `--phase=plan`（或 `--dry-run`）退出 0；stdout 按固定顺序打印 10 个 step id、每步将执行的命令模板（覆盖 `devicectl`、`xcodebuild test-without-building`、`iproxy`、WDA HTTP，`audio` step 含 `step=audio` 与证据模板）与计划证据路径；该模式不执行真实 devicectl / xcodebuild / iproxy。
- ac-plan-path-idempotent: 同一候选包连续两次 `--phase=plan` 打印的 `candidateKey`、证据根、10 个 step id 与产物相对路径完全一致；仅时刻 / 耗时字段允许不同。
- ac-preflight-udid: 默认 UDID `00008101-001C701E0A68001E`，`--device` / `PUREPACE_DEVICE_UDID` 可覆盖；preflight 从 `xcrun devicectl list devices --json-output` 读 `hardwareProperties.udid`、`deviceProperties.name`、`osVersionNumber`、`reality=physical`、`pairingState=paired`；UDID 不在列表、非物理机或未配对时非零退出并在 preflight 日志写明缺失项。
- ac-preflight-candidate: 候选 zip 经 `--candidate` / `PUREPACE_CANDIDATE_ZIP` / `artifacts/candidates/PurePace-Release-*.zip` 唯一定位；解包 `Payload/*.app`，用 `plutil` 读 `CFBundleIdentifier` / `CFBundleShortVersionString` / `CFBundleVersion` / `CFBundleExecutable`；记录 zip sha256、exec sha256、bundle id、version、build、证据根；zip 缺失、多义、解包失败或 app 缺失时非零退出并列出候选路径。
- ac-preflight-expect: `--expect-zip-sha256` / `--expect-exec-sha256`（或同名 env）与实算值逐字比对，不匹配 fail-closed 非零并在 preflight 日志与 summary 打印 expected/actual；未提供时 `identity.pinned=false` 与实际 sha，不得伪装已钉住。
- ac-wda-warmup: `wda` phase 从 `--wda-xctestrun` / `PUREPACE_WDA_XCTESTRUN` 取 WebDriverAgentRunner `.xctestrun`，执行 `xcodebuild test-without-building -xctestrun <path> -destination id=<UDID> ...WebDriverAgentRunner...`（完整输出只进 `logs/wda.xcodebuild.log`），并起 `iproxy -u <UDID> 8100:8100`（LOCAL:DEVICE）；有界轮询 `GET http://127.0.0.1:8100/status` 至 HTTP 200；超时或启动失败非零退出并清理本次启动的进程。
- ac-warmup-timing: `summary.json` 的 `timings.wdaWarmupSeconds` 单独记录预热起止与耗时；`timings.runSeconds` 只覆盖 `record` 开始到 `collect` 结束的场次，不含预热；`logs/wda.log` 首尾分别有 `START wda <UTC>` / `END wda <UTC> status=<status>`。
- ac-install-uninstall-first: `install` 先查已安装状态，已装则 `devicectl device uninstall app --device <UDID> <bundle-id>` 再 `devicectl device install app --device <UDID> <app>`；未装直接安装；记录 `--json-output` 的 bundle id / version；同一候选包连跑两次不得因重复安装失败。
- ac-launch-first-screen: 用 `devicectl device process launch --terminate-existing --device <UDID> <bundle-id>`，有界等首屏就绪（WDA 可及树可读或容器 `Documents/Runs` 出现）；超时非零退出并打印等待判据与最后日志尾部。
- ac-tcc-modes: 接受 `--tcc=auto|preset|manual`（缺省 `auto`；非法值退出 2）；三模式都不用像素坐标、坐标 tap、OCR/截屏文字识别或硬编码「允许/Allow」文案；`auto` 在 `PUREPACE_TCC_HELPER` 可执行时调用它，否则回退到有界 `manual` 等待；`preset` 只校验不等待；`manual` 打印单点提示并在 `--tcc-wait-seconds` 内有界等待。
- ac-tcc-self-report: 授权结论只以 App 自报字段为准（run JSON 的 `telemetry.authorizationStatus.name` 与 `telemetry.accuracyAuthorization.name`）；字段缺失或非预期授权时 `steps[tcc]` 回填 `failed`、整体非零退出；脚本不写入 / 不修改遥测契约，不把 UI 文案或截图当授权证据。
- ac-device-run-audio-single-call: `phase_audio` 只调用 `scripts/verify-ios-device-flow.sh --phase=audio --configuration=Release` 及其 candidate/device 参数，不在 run 内重写 xcodebuild / devicectl / curl 音频命令；失败沿用 `begin_step` / `fail_step` / `end_step` 语义，`steps[]` 的 id 为 `audio`。
- ac-device-run-audio-artifacts: 成功后 `artifacts/device-run/<candidateKey>/audio/` 含语音证据入口（analysis / report / announcements / 曲目元数据 / candidate zip 与 exec sha256）与 `audio-step.json`（证据目录路径 + 必备产物清单）；缺任一必备产物 → 该 step 失败、整体非 0 并在日志写缺失项（fail-closed，不清零通过）。
- ac-device-run-static: `bash scripts/check-ios-scripts.sh` 以 10 step 硬断言 + audio 契约断言退出 0；`bash scripts/device-run.sh --self-check` 退出 0；`bash -n scripts/device-run.sh scripts/verify-ios-device-flow.sh` 与 `scripts/check-shell-expansion.sh` 通过；门数与 id 不变（22 门）。
- ac-record-autostart: `record` 经 `devicectl device process launch --terminate-existing ... -- -autoStartRecording` 传 flag，该 flag 在脚本中只用于此 launch；不传 flag 时 App 默认不自动开跑；脚本不持久化任何自动开跑开关，不传 / 不改 `-releaseDeterministicLocation` 与 `-uiTestLocation` 门控语义；有界确认进入记录态（checkpoint 出现或读数推进）。
- ac-lock-double-proof: 取得 WDA session id 后 `POST /session/<id>/wda/lock` 且 body 为 `{}`，再轮询 `GET /session/<id>/wda/locked` 直到 `true`；两次响应原文分别落 `wda/lock.json` / `wda/locked.json`；只有双证齐全才 `ok`，任一缺失或非 `true` 非零退出。
- ac-unlock-manual: 解锁只打印人工单点提示并轮询 `GET /session/<id>/wda/locked` 直到 `false`（有界）；脚本不发送密码、不调用解锁 API、不驱动坐标或文案；超时记 `pending` 并以非零退出，不得伪造已解锁。
- ac-collect-container: 用 `devicectl device copy from --device <UDID> --domain-type appDataContainer --domain-identifier <bundle-id> --source <remote> --destination <local>` 取 `Documents/Runs`、`Documents/Exports`、`Library/Caches/active-run.jsonl`（诊断）到 `container/runs|exports|diagnostics`；从 run JSON 抽 telemetry 到 `container/telemetry/`；每个落盘文件实算 sha256；四类任一缺失时非零退出并列出缺失路径，不静默跳过。
- ac-evidence-files: 证据根固定 `artifacts/device-run/<candidateKey>/`，`candidateKey=zip-<zipSha256 前 16 位>`；每 phase 写 `logs/<phase>.log`（首行 `START <phase> <UTC>`，末行 `END <phase> <UTC> status=<status>`）；写 `manifest-sha256.txt`（每行 `<64 位 hex>  <相对路径>`，按路径排序，不含自身，含 `summary.json` 与容器文件）与 `summary.json`。
- ac-summary-schema: `summary.json` 顶层固定含 `schemaVersion`、`candidateKey`、`candidate`、`device`、`mode`、`timings`、`steps`、`authorization`、`artifacts`、`pending`；`steps[]` 每项固定含 `id`（10 个固定 id 各一次且顺序固定）、`status`（`ok|skipped|failed|pending|planned`）、`startedAt`、`finishedAt`、`durationSeconds`、`log`、`exitCode`、`error`；`artifacts[]` 每项含 `path`、`sha256`、`bytes`；文件可被 `python3 -m json.tool` 解析。
- ac-idempotent-evidence: 同一候选包连跑两次写同一证据根与同一组相对路径 / 字段；第二次覆盖写不产生带时间戳的兄弟目录，不因已存在文件、已安装 app、残留日志失败；允许 `startedAt` / `finishedAt` / `durationSeconds` / sha 随实际运行变化。
- ac-failure-semantics: 任一步失败立即非零退出；stdout/stderr 摘要打印 `failedStep=<id>`、失败命令与失败日志最后 ≤40 行原文；主流程无 `|| true` / `|| :` 吞错，不在失败路径关闭 `set -e`；`summary.json` 与失败 step 日志仍落盘；成功与失败都经 EXIT trap 释放本次启动的 xcodebuild/iproxy 与 WDA session。
- ac-no-residue: 只 kill 自己启动并记录 PID 的进程；运行结束不残留本脚本启动的 `iproxy` / `xcodebuild`（以证据根或 UDID 过滤 `pgrep -f` 为零），端口 8100 释放；已存在的非本脚本进程不被误杀。
- ac-lint-integration: `bash -n` 通过；`bash scripts/device-run.sh --self-check` 退出 0（对 `scripts/device-*.sh` 逐个 `bash -n`，`shellcheck` 存在时一并执行）；`bash scripts/check-shell-expansion.sh` 退出 0；`scripts/check-ios-scripts.sh` 将 `device-run.sh` 纳入既有断言并整体退出 0；`.munk/code-gates.json` 零 diff，仍为 22 门。
- ac-docs-boundaries: `docs/device-scripts.md` 非空，含用法、全部参数与 env、10 步说明、证据与 `summary.json` 结构、失败语义、幂等口径、`--tcc` 三模式；明确写 P0-1（TCC 弹窗自动化）与 P1-1（pbxproj 入库策略）各自独立、本脚本不实现，并写明 `audio` step 只委托 `verify-ios-device-flow.sh`、音频契约归 `ios-audio-verification` 域；真机连跑归属 `task_97c958a247a259ff`，本项不宣称设备已验证。
- ac-scope-guard: `git diff -- ios/PurePace ios/RunCore ios/Core ios/PurePace.xcodeproj/project.pbxproj ios/project.yml .github/workflows .munk/code-gates.json` 为空；不增删 / 弱化门腿；不引入第三方运行时依赖；脚本只调用 `xcrun devicectl`、`xcodebuild`、`iproxy`、`curl` 与系统 `plutil` / `unzip` / `shasum` / `python3`，不出现 `idb`、`mobilecli`、`osascript`、坐标点击或像素/OCR 逻辑。

## 非目标

- 不做 TCC 弹窗自动化、坐标点击、图标/文案识别（P0-1）；本域只留 `PUREPACE_TCC_HELPER` 接缝与 `--tcc=auto|preset|manual` 三模式。
- 不动 `project.pbxproj` 入库策略、不迁移构建系统（P1-1）。
- 不做日志降噪工具链改造（P1-2）；只做固定路径落盘与摘要输出。
- 不重构 `scripts/verify-ios-device-flow.sh` 的 audit / background 分支；`audio` 分支的音频契约归 `ios-audio-verification` 域，本域只做 step 接线与证据索引。
- 不改 App 源码、`ios/project.yml`、`Info.plist`、遥测 / 存档 / GPX 契约；不改 `.github/workflows/**` 与 CI 预算，不增删 / 弱化 `.munk/code-gates.json` 门腿。
- 不在 coding 会话内连接真机、跑正式验收窗口或宣称「真机已验证」。

## 实现约束

- 允许改动：`scripts/device-run.sh`（可拆 `scripts/lib/device-*.sh`）、`docs/device-scripts.md`、`scripts/check-ios-scripts.sh`、`scripts/verify-ios-device-flow.sh`（仅 audio 分支契约与 `--configuration`）、`docs/device-flow-usage.md`、`docs/device-assertion-matrix.md`；其余路径零 diff，尤其 `ios/**`、`.github/**`、`.munk/code-gates.json`。
- 只用成熟工具链：`xcrun devicectl`（list / install / uninstall / process launch / copy from / info apps）、`xcodebuild test-without-building`、`iproxy`、WDA HTTP（`curl`）；JSON 与 sha 用系统 `plutil` / `unzip` / `shasum` / `python3`，不新增依赖。
- `summary.json` 固定字段：顶层 `schemaVersion=1`、`candidateKey`、`candidate{path,zipSha256,execSha256,bundleId,version,build,pinned,expectedZipSha256,expectedExecSha256}`、`device{udid,name,iosVersion}`、`mode{phase,tcc,status,startedAt,finishedAt}`、`timings{wdaWarmupSeconds,runSeconds,totalSeconds}`、`steps[]`、`authorization{status,accuracy,source}`、`artifacts[]`、`pending[]`。
- 失败语义：main 任一步非零立即 `exit 1`；EXIT trap 统一清理本次启动的 xcodebuild / iproxy / WDA session；失败仍写 `summary.json` 并把 `mode.status=failed`、失败 step 的 `error` 与日志尾部保留；禁止 `|| true` / `|| :` 吞错。
- TCC 与锁屏的人手点只允许「提示 + 轮询」：不解锁、不输密码、不点坐标、不按文案找控件；`-autoStartRecording` 只作为 `record` 步骤的 launch-arg 传入，不写 `UserDefaults`、不改 `RunLaunchArguments`、不改定位源选择逻辑。
- 幂等：同一候选包重复运行允许覆盖写同一证据根；install 前先查已装再卸；WDA / iproxy 只复用或清理自己启动的实例；成功与失败都释放端口 8100 与锁。
- 文档必须写清与 P0-1 / P1-1 的边界；验收只到 `--phase=plan`、`--self-check`、既有 lint 门与文档；真实设备连跑由 Owner 走 `task_97c958a247a259ff`（≤10 分钟只验工具能力），回执写「等待设备验证」。
- `audio` step 必备产物清单（configuration=Release、app/runner/none 三遍、曲目元数据、duck 三字段、候选 zip 与 exec sha256、证据路径）在脚本内集中定义并由 `audio-step.json` 与 summary 双写；缺项 fail-closed，禁止用 `skipped` 掩盖。
- 预算：实施 ≤8M token / ≤90 分钟；超时停手回执，不带病扩范围。

## 最近交付证明

- workItemId: wi_intake_a22d527eed9de808（2026-11-10，pass）
- 交付：`scripts/device-run.sh` 新增 `audio` phase（`tcc` 之后、`record` 之前，10 step 全链路同步：文件头、`PHASES` / `VALID_PHASES`、`--help`、`--phase=plan`、summary step 顺序、`run_real_phase`）；`phase_audio` 只调 `scripts/verify-ios-device-flow.sh --phase=audio --configuration=Release`，把证据收进 `artifacts/device-run/<candidateKey>/audio/`（三遍子目录 + `music-source.json` + `audio-step.json` 必备产物清单），缺项 `fail_step` 非 0；`scripts/check-ios-scripts.sh` 硬断言升 10 step 并新增 audio 契约块（Release 默认 / launch-arg / 三遍 / 非法 configuration 退出 2 / 缺候选包 fail-closed）；`docs/device-scripts.md`、`docs/device-flow-usage.md`、`docs/device-assertion-matrix.md` 同步。
- 实测：`code_gates` 22 门全绿；`--phase=plan` 无设备退出 0 且两次输出逐字一致、含 `step=audio` 与证据模板；`.munk/code-gates.json`、`ios/**`、`.github/**` 零 diff。
- 边界：真机 `--phase=audio` 实跑未执行（无设备场、无候选包），仍为 `pending: 等待设备验证`（Owner 设备 ops task `task_97c958a247a259ff`）；音频契约语义与 `duckRevoked` / `sessionDeactivated` 定性归 `ios-audio-verification` 域与 `pending-classification: wi_intake_f76b858c0c2376f5`。
