# 真机取证流程收敛为可复用幂等脚本（P0-2）

## Scope

- 新增 `scripts/device-run.sh`：单一入口 + 内部 phase，把真机取证的 devicectl / xcodebuild / iproxy / WDA HTTP 命令收敛为幂等脚本，覆盖 9 个步骤：`preflight` → `wda` → `install` → `launch` → `tcc` → `record` → `lock` → `collect` → `evidence`。
- 每步固定落日志与起止时刻；stdout 只输出步骤摘要与证据路径，不打印全量 xcodebuild/设备日志。
- 证据固定落 `artifacts/device-run/<candidateKey>/`，输出 `logs/<phase>.log`、`manifest-sha256.txt`、结构化 `summary.json`，路径与字段可被下游直接读取。
- 新增 `docs/device-scripts.md`：用法、参数、产物结构、失败语义、幂等口径、`--tcc` 三模式，以及与 P0-1 / P1-1 的边界。
- 扩展 `scripts/check-ios-scripts.sh`，把新脚本纳入既有 `lint-ios-scripts` 门的 `bash -n` / `--help` / 未知参数断言；不新增、不删除、不弱化 `.munk/code-gates.json` 门腿。
- 本项只交脚本 + `--phase=plan` 自证 + `bash -n`/既有 lint 门 + 文档；真实设备连跑两次的验收归 Owner 的既有设备 ops task `task_97c958a247a259ff`，不在 coding 会话内起设备场。
- 目标设备默认 `00008101-001C701E0A68001E`；候选包沿用 `artifacts/candidates/PurePace-Release-*.zip` 约定，不复制进仓库。

### 9 个 phase 的职责

1. `preflight`：核目标 UDID 在线且为物理机、候选 zip 路径与解包结果、期望 zip/exec sha256、证据目录；不匹配 fail-closed。
2. `wda`：取 WebDriverAgentRunner 的 `.xctestrun`，起 `xcodebuild test-without-building` 与 `iproxy -u <UDID> 8100:8100`（LOCAL:DEVICE），有界轮询 `GET /status` 200；预热耗时单独记。
3. `install`：先卸旧（若已装）再 `devicectl device install app`，记录 bundle id / version / build。
4. `launch`：`devicectl device process launch --terminate-existing`，有界等待首屏就绪（WDA 可及树可读或 App 容器出现 run 目录）。
5. `tcc`：可插拔授权步骤 `--tcc=auto|preset|manual`，只做授权请求 / 等单点 / 预留 P0-1 helper 接缝；不写死坐标、不测蓝字、不点文案；结果以 App 自报字段校验。
6. `record`：用 `-autoStartRecording` launch-arg 起记录（App 默认仍关；无 flag 不自动开跑），不改定位源门控语义。
7. `lock`：WDA `POST /session/<id>/wda/lock`（body `{}`）+ `GET /session/<id>/wda/locked == true` 双证；解锁只做人工单点轮询，不驱动密码。
8. `collect`：`devicectl device copy from --domain-type appDataContainer` 取记录 JSON、telemetry、诊断文件、导出 GPX，逐文件 sha256。
9. `evidence`：写 `manifest-sha256.txt` 与 `summary.json`，回填每步状态 / 时刻 / 耗时 / 失败原因 / 授权自报校验结果。

## Acceptance Criteria

- ac-entry-cli: `scripts/device-run.sh` 可执行；首行 `#!/usr/bin/env bash`；含 `set -euo pipefail`；以 `BASH_SOURCE` 推导仓库根；`--help` 退出 0 且含「用法」与 9 个 phase 名；未知参数退出 2。
- ac-phase-set: 接受 `--phase=plan|all|preflight|wda|install|launch|tcc|record|lock|collect|evidence`，`--dry-run` 等价 `--phase=plan`；非法 phase 退出 2 并打印合法取值。
- ac-plan-no-device: 在无设备、无候选 zip、无 WDA xctestrun 的机器上 `--phase=plan`（或 `--dry-run`）退出 0；stdout 按固定顺序打印 9 个 step id、每步将执行的命令模板（覆盖 `devicectl`、`xcodebuild test-without-building`、`iproxy`、WDA HTTP）与计划证据路径；该模式不执行真实 devicectl / xcodebuild / iproxy。
- ac-plan-path-idempotent: 同一候选包连续两次 `--phase=plan` 打印的 `candidateKey`、证据根、9 个 step id 与产物相对路径完全一致；仅时刻 / 耗时字段允许不同。
- ac-preflight-udid: 默认 UDID 为 `00008101-001C701E0A68001E`，`--device` / `PUREPACE_DEVICE_UDID` 可覆盖；preflight 从 `xcrun devicectl list devices --json-output` 读取 `hardwareProperties.udid`、`deviceProperties.name`、`osVersionNumber`、`reality=physical`、`pairingState=paired`；目标 UDID 不在列表、非物理机或未配对时非零退出并在 preflight 日志写明缺失项。
- ac-preflight-candidate: 候选 zip 经 `--candidate` / `PUREPACE_CANDIDATE_ZIP` / `artifacts/candidates/PurePace-Release-*.zip` 唯一定位；解包 `Payload/*.app`，用 `plutil` 读 `CFBundleIdentifier` / `CFBundleShortVersionString` / `CFBundleVersion` / `CFBundleExecutable`；记录 zip sha256、exec sha256、bundle id、version、build、证据根；zip 缺失、多义、解包失败或 app 缺失时非零退出并列出候选路径。
- ac-preflight-expect: 提供 `--expect-zip-sha256` / `--expect-exec-sha256`（或同名 env）时与实算值逐字比对，不匹配 fail-closed 非零并在 preflight 日志与 summary 打印 expected/actual；未提供时 summary 写 `identity.pinned=false` 与实际 sha，不得伪装已钉住。
- ac-wda-warmup: `wda` phase 从 `--wda-xctestrun` / `PUREPACE_WDA_XCTESTRUN` 取 WebDriverAgentRunner `.xctestrun`，执行 `xcodebuild test-without-building -xctestrun <path> -destination id=<UDID> ...WebDriverAgentRunner...`（完整输出只进 `logs/wda.xcodebuild.log`），并起 `iproxy -u <UDID> 8100:8100`（LOCAL:DEVICE）；有界轮询 `GET http://127.0.0.1:8100/status` 直到 HTTP 200；超时或启动失败非零退出并清理本次启动的进程。
- ac-warmup-timing: `summary.json` 的 `timings.wdaWarmupSeconds` 单独记录预热起止与耗时；`timings.runSeconds` 只覆盖 `record` 开始到 `collect` 结束的场次，不含预热；`logs/wda.log` 首尾分别有 `START wda <UTC>` / `END wda <UTC> status=<status>`。
- ac-install-uninstall-first: `install` phase 先查询已安装状态，已装则 `devicectl device uninstall app --device <UDID> <bundle-id>`，再 `devicectl device install app --device <UDID> <app>`；未装直接安装；记录 devicectl `--json-output` 的 bundle id / version；同一候选包连续运行两次不得因重复安装失败。
- ac-launch-first-screen: `launch` phase 用 `devicectl device process launch --terminate-existing --device <UDID> <bundle-id>`，有界等待首屏就绪：WDA 可及树可读或 App 容器 `Documents/Runs` 出现；超时非零退出并打印等待判据与最后日志尾部。
- ac-tcc-modes: 接受 `--tcc=auto|preset|manual`（缺省 `auto`；非法值退出 2）；三种模式都不使用像素坐标、坐标 tap、OCR/截屏文字识别或硬编码「允许/Allow」文案；`auto` 在 `PUREPACE_TCC_HELPER` 可执行时调用它，否则回退到有界 `manual` 等待（P0-1 未落地前的现有可用路径）；`preset` 只做校验不等待；`manual` 打印单点提示并在 `--tcc-wait-seconds` 内有界等待。
- ac-tcc-self-report: 授权通过与否只以 App 自报字段为准：收集到的 run JSON 中 `telemetry.authorizationStatus.name` 与 `telemetry.accuracyAuthorization.name`；字段缺失或不是预期授权时 `steps[tcc]` 回填 `failed`、整体非零退出；脚本不写入 / 不修改遥测契约，不把 UI 文案或截图当授权证据。
- ac-record-autostart: `record` phase 通过 `devicectl device process launch --terminate-existing ... -- -autoStartRecording` 传 flag，且该 flag 在脚本中只用于此 launch；不传 flag 时 App 默认不自动开跑；脚本不持久化任何自动开跑开关，不传 / 不改 `-releaseDeterministicLocation` 与 `-uiTestLocation` 的门控语义；有界确认进入记录态（checkpoint 出现或读数推进）。
- ac-lock-double-proof: `lock` phase 取得 WDA session id 后 `POST /session/<id>/wda/lock` 且 body 为 `{}`，再轮询 `GET /session/<id>/wda/locked` 直到 `true`；两次响应原文分别落 `wda/lock.json` / `wda/locked.json`；只有双证齐全才 `ok`，任一缺失或非 `true` 非零退出。
- ac-unlock-manual: 解锁只打印人工单点提示并轮询 `GET /session/<id>/wda/locked` 直到 `false`（有界）；脚本不发送密码、不调用解锁 API、不驱动坐标或文案；超时记 `pending` 并以非零退出，不得伪造已解锁。
- ac-collect-container: `collect` phase 用 `devicectl device copy from --device <UDID> --domain-type appDataContainer --domain-identifier <bundle-id> --source <remote> --destination <local>` 取 `Documents/Runs`、`Documents/Exports`、`Library/Caches/active-run.jsonl`（诊断）到固定 `container/runs|exports|diagnostics` 目录；从 run JSON 抽出 telemetry 到 `container/telemetry/`；每个落盘文件实算 sha256；四类任一缺失时非零退出并列出缺失路径，不静默跳过。
- ac-evidence-files: 证据根固定为 `artifacts/device-run/<candidateKey>/`，其中 `candidateKey=zip-<zipSha256 前 16 位>`；每 phase 写 `logs/<phase>.log`（首行 `START <phase> <UTC>`，末行 `END <phase> <UTC> status=<status>`）；写 `manifest-sha256.txt`（每行 `<64 位 hex>  <相对路径>`，按路径排序，不含自身，含 `summary.json` 与容器文件）与 `summary.json`。
- ac-summary-schema: `summary.json` 顶层固定含 `schemaVersion`、`candidateKey`、`candidate`、`device`、`mode`、`timings`、`steps`、`authorization`、`artifacts`、`pending`；`steps[]` 每项固定含 `id`（9 个固定 id 各一次且顺序固定）、`status`（`ok|skipped|failed|pending|planned`）、`startedAt`、`finishedAt`、`durationSeconds`、`log`、`exitCode`、`error`；`artifacts[]` 每项含 `path`、`sha256`、`bytes`；文件可被 `python3 -m json.tool` 解析。
- ac-idempotent-evidence: 同一候选包连续两次完整运行写同一证据根与同一组相对路径 / 字段；第二次覆盖写不产生带时间戳的兄弟目录，不因已存在文件、已安装 app、残留日志而失败；允许 `startedAt` / `finishedAt` / `durationSeconds` / sha 随实际运行变化。
- ac-failure-semantics: 任一步失败立即非零退出；stdout/stderr 摘要打印 `failedStep=<id>`、失败命令与失败日志最后 ≤40 行原文；主流程无 `|| true` / `|| :` 吞错，不在失败路径关闭 `set -e`；`summary.json` 与失败 step 日志仍落盘；成功与失败都经 EXIT trap 释放本次启动的 xcodebuild/iproxy 与 WDA session。
- ac-no-residue: 脚本只 kill 自己启动并记录 PID 的进程；运行结束后不残留本脚本启动的 `iproxy` / `xcodebuild`（以证据根或 UDID 过滤 `pgrep -f` 为零），端口 8100 释放；已存在的非本脚本进程不被误杀。
- ac-lint-integration: 新脚本 `bash -n` 通过；`bash scripts/device-run.sh --self-check` 退出 0（对 `scripts/device-*.sh` 逐个 `bash -n`，`shellcheck` 存在时一并执行）；`bash scripts/check-shell-expansion.sh` 退出 0；`scripts/check-ios-scripts.sh` 将 `device-run.sh` 纳入既有 `bash -n` / `--help` / 未知参数退出 2 断言并整体退出 0；`.munk/code-gates.json` 零 diff，仍为 22 门。
- ac-docs-boundaries: `docs/device-scripts.md` 非空，含用法、全部参数与 env、9 步说明、证据与 `summary.json` 结构、失败语义、幂等口径、`--tcc` 三模式；明确写 P0-1（TCC 弹窗自动化）与 P1-1（pbxproj 入库策略）各自独立、本脚本不实现；真机连跑两次归属 Owner 设备 ops task `task_97c958a247a259ff`，本项不宣称设备已验证。
- ac-scope-guard: `git diff -- ios/PurePace ios/RunCore ios/Core ios/PurePace.xcodeproj/project.pbxproj ios/project.yml .github/workflows .munk/code-gates.json` 为空；不新增 / 删除 / 弱化门腿；不引入第三方运行时依赖；脚本只调用 `xcrun devicectl`、`xcodebuild`、`iproxy`、`curl`（WDA HTTP）与系统 `plutil` / `unzip` / `shasum` / `python3`，不出现 `idb`、`mobilecli`、`osascript`、坐标点击或像素/OCR 逻辑。

## Non-Goals

- 不做 TCC 弹窗自动化、坐标点击、图标/文案识别（P0-1）；本脚本只保留 `PUREPACE_TCC_HELPER` 接缝与 `--tcc=auto|preset|manual` 三种模式。
- 不动 `project.pbxproj` 入库策略、不迁移构建系统（P1-1 / 构建系统另行立项）。
- 不做日志降噪工具链改造（P1-2）；本脚本只做固定路径落盘与摘要输出。
- 不重构或删除既有 `scripts/verify-ios-device-flow.sh`；新脚本是可复用底座，后续 run 改用它，旧三模式脚本不在本项改。
- 不修改 App 源码、`ios/project.yml`、`Info.plist`、遥测 / 存档 / GPX 契约。
- 不新增 / 删除 / 弱化 `.munk/code-gates.json` 门腿，不改 `.github/workflows/**` 与 CI 预算。
- 不在 coding 会话内连接真机、跑正式验收窗口或宣称「真机已验证」；真机连跑两次只由 Owner 的设备 ops task 执行。

## Implementation Constraints

- 允许改动：新增 `scripts/device-run.sh`（可拆 `scripts/lib/device-*.sh`）、新增 `docs/device-scripts.md`、扩展 `scripts/check-ios-scripts.sh`。其余路径零 diff，尤其 `ios/**`、`.github/**`、`.munk/code-gates.json`。
- `scripts/device-run.sh` 只用成熟工具链：`xcrun devicectl`（list / install / uninstall / process launch / copy from / info apps）、`xcodebuild test-without-building`、`iproxy`、WDA HTTP（`curl`）。JSON 与 sha 可用系统 `plutil` / `unzip` / `shasum` / `python3`，不新增依赖。
- 证据固定结构（可被下游直接读）：
  - `artifacts/device-run/<candidateKey>/summary.json`
  - `artifacts/device-run/<candidateKey>/manifest-sha256.txt`
  - `artifacts/device-run/<candidateKey>/logs/{preflight,wda,install,launch,tcc,record,lock,collect,evidence}.log`
  - `artifacts/device-run/<candidateKey>/container/{runs,exports,telemetry,diagnostics}/`
  - `artifacts/device-run/<candidateKey>/wda/{status.json,lock.json,locked.json}`
  - `candidateKey=zip-<zipSha256 前 16 位>`，同一候选包路径稳定；中间解包 / xcresult / xctestrun 只进 `.build/device-run/<candidateKey>/`。
- `summary.json` 固定字段：
  ```json
  {
    "schemaVersion": 1,
    "candidateKey": "zip-<16hex>",
    "candidate": {
      "path": "", "zipSha256": "", "execSha256": "",
      "bundleId": "", "version": "", "build": "",
      "pinned": false, "expectedZipSha256": null, "expectedExecSha256": null
    },
    "device": { "udid": "", "name": "", "iosVersion": "" },
    "mode": { "phase": "", "tcc": "auto", "status": "", "startedAt": "", "finishedAt": "" },
    "timings": { "wdaWarmupSeconds": 0, "runSeconds": 0, "totalSeconds": 0 },
    "steps": [
      {
        "id": "preflight", "status": "ok", "startedAt": "", "finishedAt": "",
        "durationSeconds": 0, "log": "logs/preflight.log", "exitCode": 0, "error": ""
      }
    ],
    "authorization": { "status": "", "accuracy": "", "source": "" },
    "artifacts": [ { "path": "", "sha256": "", "bytes": 0 } ],
    "pending": []
  }
  ```
- 失败语义：main 流程任一步非零立即 `exit 1`；EXIT trap 统一清理本次启动的 xcodebuild / iproxy / WDA session；失败时仍写 `summary.json` 并把 `mode.status=failed`、失败 step 的 `error` 与日志尾部保留；禁止用 `|| true` / `|| :` 吞命令错误。
- TCC 语义：`auto` 优先 `PUREPACE_TCC_HELPER`（P0-1 落地后的接缝），否则按 `manual` 有界等待；`preset` 假定已授权只校验；`manual` 打印单点提示并等待。最终授权结论只读 App 自报 `telemetry.authorizationStatus.name` / `telemetry.accuracyAuthorization.name`，缺字段即失败。
- 授权 / 锁屏的人手点只允许「提示 + 轮询」：不解锁、不输密码、不点坐标、不按文案找控件。
- `-autoStartRecording` 只作为 `record` 步骤的 launch-arg 传入；App 默认关的语义不变；脚本不写 `UserDefaults`、不改 `RunLaunchArguments`、不改定位源选择逻辑。
- 幂等：同一候选包重复运行允许覆盖写同一证据根；install 前先查已装再卸；WDA / iproxy 只复用或清理本脚本自己启动的实例；失败与成功都释放端口 8100 与锁。
- 文档必须写清与 P0-1 / P1-1 的边界：P0-1 负责 TCC 弹窗自动化工具改造，P1-1 负责 pbxproj 入库策略；本项只提供脚本侧接缝，不互相实现。
- 真机归属：本项验收只到 `--phase=plan`、`--self-check`、既有 lint 门与文档；真实设备连跑两次由 Owner 走 `task_97c958a247a259ff`（≤10 分钟只验工具能力），回执写「等待设备验证」。
- 预算：实施 ≤8M token / ≤90 分钟；超时立即停手并回执，不带病扩范围。
