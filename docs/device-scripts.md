# 真机取证脚本（P0-2）

对应脚本：`scripts/device-run.sh`（**需真机连接**，`--phase=plan` 无需设备）。
既有三模式取证脚本 `scripts/verify-ios-device-flow.sh` 不在本项改动范围；本脚本是可复用底座，
后续正式 run 改用它。

## 定位

把真机取证散落的 `devicectl` / `xcodebuild` / `iproxy` / WDA HTTP 命令收敛为一个幂等入口，
九个 phase 固定顺序：

| # | phase | 职责 |
|---|---|---|
| 1 | `preflight` | 核目标 UDID 在线且为物理机、候选 zip 与解包 `Payload/*.app`、期望 sha256、证据根 |
| 2 | `wda` | 取 `WebDriverAgentRunner.xctestrun`，起 `xcodebuild test-without-building` 与 `iproxy -u <UDID> 8100:8100`（LOCAL:DEVICE），有界轮询 `GET /status` 200 并建 WDA session |
| 3 | `install` | 先查已装状态，已装则先 `devicectl device uninstall app` 再 `devicectl device install app`，记录 bundle id / version / build |
| 4 | `launch` | `devicectl device process launch --terminate-existing`，有界等待首屏就绪（WDA source 可读 或 容器 `Documents/Runs` 出现） |
| 5 | `tcc` | 可插拔授权 `--tcc=auto\|preset\|manual`，只提示 + 有界等待，不点坐标、不识别文案 |
| 6 | `record` | 以 `-autoStartRecording` launch-arg 起记录（App 默认仍关），有界确认进入记录态 |
| 7 | `lock` | WDA `POST /session/<id>/wda/lock`（body `{}`）+ `GET /session/<id>/wda/locked == true` 双证；解锁只做人工提示 + 轮询 |
| 8 | `collect` | `devicectl device copy from --domain-type appDataContainer` 取 `Documents/Runs` / `Documents/Exports` / `Library/Caches/active-run.jsonl`，抽 telemetry，逐文件 sha256 |
| 9 | `evidence` | 写 `summary.json` 与 `manifest-sha256.txt`，跑 EXIT trap 同款清理 |

`--phase=plan`（或 `--dry-run`）只打印计划：9 个 step id、每步将执行的命令模板、计划证据路径，
退出 0；该模式不执行真实 `devicectl` / `xcodebuild` / `iproxy`。

## 用法

```bash
bash scripts/device-run.sh --help                 # 用法
bash scripts/device-run.sh --phase=plan           # 无设备自证（CI/本地）
bash scripts/device-run.sh --phase=all \
  --candidate artifacts/candidates/PurePace-Release-<id>.zip \
  --wda-xctestrun .build/device-run/<candidateKey>/WebDriverAgentRunner.xctestrun \
  --expect-zip-sha256 <hex> --expect-exec-sha256 <hex>
bash scripts/device-run.sh --phase=collect        # 单跑一个 phase（前置 preflight 自动补齐）
bash scripts/device-run.sh --self-check           # bash -n + shellcheck(-S error) + plan 自证
```

选项：

| 选项 | 说明 |
|---|---|
| `--phase=<值>` | `plan\|all\|preflight\|wda\|install\|launch\|tcc\|record\|lock\|collect\|evidence`，缺省 `all` |
| `--dry-run` | 等价 `--phase=plan` |
| `--device=<udid>` | 目标真机，缺省 `00008101-001C701E0A68001E` |
| `--candidate=<zip>` | 候选包；缺省唯一匹配 `artifacts/candidates/PurePace-Release-*.zip` |
| `--expect-zip-sha256=<hex>` | 期望 zip sha256，不匹配 fail-closed |
| `--expect-exec-sha256=<hex>` | 期望 App 可执行文件 sha256，不匹配 fail-closed |
| `--wda-xctestrun=<path>` | WebDriverAgentRunner 的 `.xctestrun` |
| `--tcc=<模式>` | `auto`（缺省）/`preset`/`manual`；非法值退出 2 |
| `--tcc-wait-seconds=<n>` | `manual` / `auto` 回退等待上限，缺省 120 |
| `--self-check` | 对 `scripts/device-*.sh` 逐个 `bash -n`（有 shellcheck 时 `-S error`），并自证 plan 幂等与 step 顺序 |

环境变量（选项优先）：`PUREPACE_DEVICE_UDID`、`PUREPACE_CANDIDATE_ZIP`、
`PUREPACE_EXPECT_ZIP_SHA256`、`PUREPACE_EXPECT_EXEC_SHA256`、`PUREPACE_WDA_XCTESTRUN`、
`PUREPACE_TCC_HELPER`、`PUREPACE_WDA_TIMEOUT_SECONDS`、`PUREPACE_LOCK_WAIT_SECONDS`、
`PUREPACE_UNLOCK_WAIT_SECONDS`、`PUREPACE_FIRST_SCREEN_TIMEOUT_SECONDS`、
`PUREPACE_RECORD_CONFIRM_TIMEOUT_SECONDS`。

## 证据结构

同一候选包路径稳定，重复运行覆盖写同一证据根：

```
artifacts/device-run/<candidateKey>/
  summary.json
  manifest-sha256.txt
  logs/{preflight,wda,install,launch,tcc,record,lock,collect,evidence}.log
  logs/wda.xcodebuild.log      # xcodebuild 完整输出
  logs/iproxy.log
  logs/cleanup.log
  container/runs/              # Documents/Runs
  container/exports/           # Documents/Exports
  container/telemetry/         # 从 run JSON 抽出的 telemetry
  container/diagnostics/active-run.jsonl
  wda/status.json              # GET /status 原文
  wda/lock.json                # POST /wda/lock 原文
  wda/locked.json              # GET /wda/locked 最后一次原文
```

- `candidateKey=zip-<候选 zip sha256 前 16 位>`；无候选包时（`--phase=plan` 自证）为
  `zip-<sha256("no-candidate") 前 16 位>`，同样稳定。
- 中间产物（解包、probe、devicectl `--json-output`、session 描述）只进
  `.build/device-run/<candidateKey>/`。
- `manifest-sha256.txt`：每行 `<64 位 hex>  <相对证据根路径>`，按路径排序，不含自身，
  含 `summary.json`、`logs/**`、`container/**`、`wda/*.json`。
- `logs/<phase>.log` 首行 `START <phase> <UTC>`，末行 `END <phase> <UTC> status=<status>`。

## summary.json

顶层字段固定：`schemaVersion`、`candidateKey`、`candidate`、`device`、`mode`、`timings`、
`steps`、`authorization`、`artifacts`、`pending`。

- `candidate`：`path`、`zipSha256`、`execSha256`、`bundleId`、`version`、`build`、`pinned`、
  `expectedZipSha256`、`expectedExecSha256`。未提供期望 sha 时 `pinned=false` 且 expected 为 `null`，
  不伪装已钉住。
- `device`：`udid`、`name`、`iosVersion`（来自 `devicectl list devices`）。
- `mode`：`phase`、`tcc`、`status`（`ok|failed`）、`startedAt`、`finishedAt`。
- `timings`：`wdaWarmupSeconds`（wda 起跑到 `/status` 200）、`runSeconds`（record 开始到 collect 结束，
  不含预热）、`totalSeconds`。
- `steps[]`：9 个固定 id 各一次且顺序固定，每项含 `id`、`status`（`ok|skipped|failed|pending|planned`）、
  `startedAt`、`finishedAt`、`durationSeconds`、`log`、`exitCode`、`error`。
- `authorization`：`status` / `accuracy` / `source`，只来自 run JSON 的
  `telemetry.authorizationStatus.name` 与 `telemetry.accuracyAuthorization.name`。
- `artifacts[]`：`path`、`sha256`、`bytes`（不含 `summary.json` 与 manifest 自身）。
- `pending[]`：需人现场确认的条目（如人工解锁超时）。

可用 `python3 -m json.tool` 解析。

## 失败语义

- 任一步失败立即非零退出（`fail-closed`）；主流程不用 `|| true` / `|| :` 吞错。
- stdout/stderr 摘要打印 `failedStep=<id>`、失败原因与该 step 日志最后 ≤ 40 行原文。
- 失败路径同样落盘 `summary.json`（`mode.status=failed`，失败 step `error` 非空）与 manifest。
- 成功与失败都经 EXIT trap 释放本次启动的 `xcodebuild` / `iproxy`、删除 WDA session、
  释放端口 8100；只 kill 自己记录过 PID 的进程，不误杀既有实例，`logs/cleanup.log` 记录残留检查。

## 幂等口径

- 同一候选包重复运行写同一证据根、同一组相对路径与字段，不产生带时间戳的兄弟目录。
- `install` 先查已装、已装则先卸，连续两次运行不因重复安装失败。
- `wda` / `iproxy` 只复用或清理本脚本自己启动的实例；上次残留日志与新证据同路径覆盖写。
- 允许每次变化：`startedAt` / `finishedAt` / `durationSeconds` / sha（内容随运行变化）。

## TCC 三模式

| 模式 | 行为 |
|---|---|
| `auto`（缺省） | `PUREPACE_TCC_HELPER` 可执行时调用它；否则回退到有界 `manual` 等待 |
| `preset` | 假定已授权，只做校验不等待 |
| `manual` | 打印单点提示，在 `--tcc-wait-seconds` 内有界等待 |

三种模式都不使用像素坐标、坐标点击、OCR/截屏文字识别或「允许/Allow」文案匹配。
授权结论只读 App 自报字段：收集中 run JSON 的 `telemetry.authorizationStatus.name`（期望
`authorized*`）与 `telemetry.accuracyAuthorization.name`（期望 `fullAccuracy|reducedAccuracy`）；
字段缺失或不是预期授权时 `steps[tcc]` 回填 `failed`，整体非零退出。脚本不写入、不修改遥测契约，
不把 UI 文案或截图当授权证据。

## 与 P0-1 / P1-1 的边界

- **P0-1（TCC 弹窗自动化）**：独立立项，负责弹窗自动化工具改造。本脚本只保留
  `PUREPACE_TCC_HELPER` 接缝与 `auto|preset|manual` 三模式，不实现弹窗自动点击。
- **P1-1（pbxproj 入库策略）**：独立立项，负责 `project.pbxproj` 入库与构建系统策略。
  本脚本不生成、不改写、不迁移 `ios/project.yml` / `project.pbxproj`。
- 本脚本只调用 `xcrun devicectl`、`xcodebuild`、`iproxy`、`curl`（WDA HTTP）与系统
  `plutil` / `unzip` / `shasum` / `python3`，不引入第三方运行时依赖，不改 App 源码、遥测 / 存档 /
  GPX 契约、`.munk/code-gates.json`、`.github/workflows/**`。

## 真机验证归属

本项只交脚本、`--phase=plan` 自证、`bash -n` / 既有 `lint-ios-scripts` 门与本文档；
**本项不宣称真机已验证**。真机连跑两次的验收归 Owner 的设备 ops task `task_97c958a247a259ff`，
由 Product Ops 在设备场执行；在该任务回执前，本脚本的真机结论一律为「等待设备验证」。
