# 修复 device-run.sh 四处真机工具链缺口（launch 就绪 / 容器探针 / tcc 假绿 / 证据保留）

依据：`products/codebase_19e8ad47434ff059/projects/ops_75c530285b695ccb/.munk/runs/trun_1e577604f35dbd01/digest.md`
（2026-11-10 真机工具验证场；本项只读该文件，不读其它历史 digest）。

## Scope

只改 `scripts/device-run.sh` 与 `docs/`（主要 `docs/device-scripts.md`），补齐该场实测暴露的四处缺口：

1. **launch 单 phase 硬依赖 WDA** → 采用**方案 (b)：devicectl 侧就绪断言**。
   理由：单 phase 序列不含 `--phase=wda`，launch 自起 WDA（方案 a）需要 `.xctestrun`、会跨 phase 启停
   `xcodebuild`/`iproxy`，把「就绪判定」变成「进程管理」，且多数场次根本不需要 WDA。
   改为：launch 拉起后按可判定就绪路径轮询——
   - WDA 存在且 `GET /session/<id>/source` 可读 → `readiness=wda`；
   - 否则用 `xcrun devicectl device info processes --device <udid> --json-output <file>` 确认 App 可执行文件
     在设备进程表 → `readiness=devicectl-only`（`wda=absent`）；
   - 两条都不满足 → 非零退出，`summary.launch.reason` 可区分（`devicectl_unready`；无 WDA 时同时 `wda=absent`）。
   「App 真的被拉起并能交互」的断言不删不降：devicectl launch 成功 + 设备进程表里存在该 App 进程（或 WDA UI 树可读）
   才算就绪，二者都无则失败。
2. **`Documents/Runs` 容器探针 error 7000 被当成失败单因** → 容器探针降级为**只记录警告**：
   `summary.launch.containerProbe` 取值 `readable|empty|unreadable(warning)|skipped`；容器不可读**不得**单独导致 launch 失败。
   launch 失败必须给可区分 reason（`devicectl_unready` / `wda_absent`），并把 devicectl 原文留在 `logs/launch.log`。
3. **`tcc=auto` 盲等假绿** → 硬规则：`steps[tcc].status=ok` **当且仅当** App 自报
   `telemetry.authorizationStatus.name == authorizedAlways`（既有 run JSON 遥测路径，`state/authorization.json`）。
   helper 缺失 / helper 成功 / `manual` / `preset` 都不能直接置 ok；未见自报时终态 `pending`（degraded）且退出码非 0，
   `summary.authorization` 保持空值。`collect` 的终审同步收紧为 `authorizedAlways`（原来接受 `authorized*`）。
   `--phase=all` 下 tcc 先记 `pending` 并继续，由 `collect` 以自报字段定终态（ok 仅 authorizedAlways，否则 failed）。
4. **证据根每次 `rm -rf` 重建（现脚本约 706–709 行）** → 取消对 `evidence_dir` 的整根删除；
   按 phase 保留日志（同名 phase 可覆盖写，其它 phase 日志不得清除）。
   为让 `summary.json` / `manifest-sha256.txt` 覆盖**所有已落 phase**，`state_dir` 不再每次调用整体清空
   （仅 `--phase=all` 重置），`summary.steps` 与 manifest 均按证据根/state 中已落地的 phase 生成；
   同一 phase 重跑覆盖自身日志与状态。preflight 改为**每次调用都重跑**（会话内缓存），不得因 state 持久化跳过身份绑定。

## Acceptance Criteria

- ac-launch-wda-path: WDA session 已建且 `GET /session/<id>/source` HTTP 200 且有内容时，launch 就绪判据通过，`summary.launch.readiness="wda"`、`launch.wda="present"`，`steps[launch].status="ok"`。
- ac-launch-devicectl-only: 无 WDA（`wda=absent`）但 `xcrun devicectl device info processes` 输出中存在该 App 可执行文件进程时，launch 就绪通过，`summary.launch.readiness="devicectl-only"`、`launch.reason="wda_absent"`，`steps[launch].status="ok"`。
- ac-launch-container-warning-only: 容器探针 `Documents/Runs` 返回 `CoreDeviceError error 7000`/不可读时，`summary.launch.containerProbe="unreadable(warning)"`，且该探针**单独**不足以使 launch 失败（与 `ac-launch-devicectl-only` 同时成立时 launch 仍 ok）。
- ac-launch-fail-reason-distinct: 无 WDA 且进程表无该 App 进程时，launch 非零退出，`summary.launch.reason="devicectl_unready"`、`launch.wda="absent"`，`logs/launch.log` 保留 devicectl/探针原文。
- ac-launch-no-wda-selfstart: launch phase 不启动 `xcodebuild`/`iproxy`、不创建 WDA session、不新增进程管理；`--phase=launch` 在无 `--wda-xctestrun` 环境下不因缺少 WDA 参数而提前失败。
- ac-tcc-ok-iff-authorized-always: `steps[tcc].status="ok"` 当且仅当 `state/authorization.json` 的 `status == "authorizedAlways"`；`authorizedWhenInUse`、`authorized*` 其他值、空串一律不 ok。
- ac-tcc-helper-missing-no-green: `PUREPACE_TCC_HELPER` 不可执行且 App 未自报 `authorizedAlways` 时，单跑 `--phase=tcc` 终态为 `pending`（不得是 `ok`），退出码非 0，`summary.authorization={status:"",accuracy:"",source:""}`（从未观测到自报时三字段为空）。
- ac-tcc-preset-not-bypass: `--tcc=preset` 不再无条件 ok；同样要求 App 自报 `authorizedAlways`，否则 `pending` 且非零退出。
- ac-tcc-all-mode-deferred: `--phase=all` 下 tcc 未取得自报时记录 `pending` 并继续后续 phase；`collect` 终审只在自报 `authorizedAlways` 时把 tcc 置 `ok`，否则 `failed` 且整体非零退出。
- ac-tcc-no-verbal-evidence: tcc 结论路径不含坐标点击、OCR/截图文字识别、硬编码“允许/Allow”文案、也无“盲等即 ok”分支；`manual wait progress` 只能用于轮询窗口，不能作为通过结论。
- ac-evidence-no-wipe: 单 phase 调用不再 `rm -rf` 证据根；连续两次调用后，第一次已落的其它 phase 日志（如 `logs/launch.log`、`logs/tcc.log`）仍存在；同一 phase 重跑允许覆盖自身日志。
- ac-evidence-coverage: `manifest-sha256.txt` 覆盖证据根内所有已落 phase 日志与非自身文件；`summary.json` 的 `steps[]` 反映所有已落地 phase 的最终状态（非仅本次调用），`python3 -m json.tool` 可解析。
- ac-preflight-per-invocation: 即使上一次调用 preflight 已 ok，新一次调用仍重新执行设备校验与 zip/exec 双 sha 身份绑定并重写 `candidate.json`，不得因 state 持久化跳过。
- ac-self-check-deterministic: `bash scripts/device-run.sh --self-check` 退出 0，且包含且仅依赖确定性夹具（不调用 devicectl/xcodebuild/curl 设备路径、不 sleep 等待、单次 < 30s）：① 既有 5 个布局夹具保留；② wda=absent + 容器探针不可读 + 进程存在 → 分类器输出 `ready=1 readiness=devicectl-only reason=wda_absent containerProbe=unreadable(warning)`，且 wda=absent + 进程缺失 → `ready=0 reason=devicectl_unready`；③ 授权状态空/`authorizedWhenInUse` → 非 ok 且退出非 0，`authorizedAlways` → ok；④ 临时证据根连续两次初始化后第一次 phase 日志仍在，manifest 同时列出两次 phase 日志。
- ac-gates-green: `bash -n scripts/device-run.sh`、`bash scripts/device-run.sh --self-check`、`bash scripts/check-ios-scripts.sh`、`bash scripts/check-shell-expansion.sh` 全部退出 0；`.munk/code-gates.json` 零 diff（仍 22 门）。
- ac-identity-frozen: 不重出候选包、不新增 artifact；`git status --porcelain artifacts/` 为空，证据中的候选 identity 仍为 zip sha256 `a000b0e19c2ee4b5c7f8e067abd9f4c25f95b43569c45b29160c73e38c736897` / exec `d494746936c99043557ae3ba82fe2c94a3bb84c9beb0412e242dda182ef7139d`（脚本不写死、不改期望值语义）。
- ac-scope-guard: `git diff --stat` 仅涉及 `scripts/` 与 `docs/`；对 `ios/`、`.github/workflows/`、`.munk/code-gates.json`、`artifacts/` 零 diff；不新增门腿、不改 CI 预算。
- ac-docs-updated: `docs/device-scripts.md` 同步更新 launch 就绪双路径与 `summary.launch` 字段、tcc「ok 仅 authorizedAlways / 否则 pending 非零」、证据按 phase 保留与跨调用覆盖、`--self-check` 夹具清单；不宣称真机已验证。

## Non-Goals

- 不改 App 源码、遥测/存档/GPX 契约、`ios/project.yml`、`ios/PurePace.xcodeproj`、`Info.plist`。
- 不改 `.github/workflows/*`，不新增/删除/弱化门腿，不延长超时掩盖失败，不引入 `continue-on-error`/skip。
- 不重出候选包、不 push tag、不上传、不跑真机场、不在本项内做真机验收；真机复核归 Owner 设备场。
- 不做 TCC 弹窗自动化（P0-1）、不做 WDA 自启动编排（方案 a）、不重构 `verify-ios-device-flow.sh`。
- 不把容器探针升级成新的登录/首屏证据来源；它只保留为 warning 级辅助信息。

## Implementation Constraints

- 改动文件锚点（当前脚本行号，供 Coding 定位，落地以函数名为准）：
  - `run_self_check()`（约 550–683 行）追加 ②③④ 夹具；既有 layout[1..5] 夹具原样保留。
  - 证据初始化（约 706–709 行）删除 `rm -rf "$evidence_dir"`；`state_dir` 仅在 `--phase=all` 时清空；新增 `init_evidence_root`/会话级 preflight 缓存变量。
  - `write_summary()`（约 793 起）新增 `launch` 对象；`write_manifest()` 抽成可按任意根调用的函数供 self-check 复用；`steps` 的 `status` 枚举保持 `ok|skipped|failed|pending|planned`。
  - `first_screen_ready()`/`phase_launch()`（约 1320–1503 行）：拆出纯函数 `classify_launch_readiness <wda_present> <wda_source_ok> <process_ok> <container_state>`，phase 只负责取探针与写 `state/launch-readiness.json`。
  - `tcc_manual_wait()`/`phase_tcc()`（约 1505–1538 行）：新增 `tcc_outcome_check <auth_status>`（ok 仅 `authorizedAlways`）与 `read_authorization_status`；回退/等待期间用 `copy_from_container`+`extract_telemetry` 轮询自报，不得以等待结束置 ok。
  - `enforce_authorization()`（约 1892 起）：期望值由 `authorized*` 收紧为 `authorizedAlways`，tcc 状态为 `ok|pending` 时都执行终审，成功时把 tcc 置 `ok` 并清空 error。
  - `ensure_preflight()`（约 1233 行）：改为按本次调用缓存（变量），不再读持久化 step 状态决定是否跳过。
- 设备命令只用既有工具：`xcrun devicectl device info processes ... --json-output <file>`（Xcode 26.3 已确认存在），JSON 解析用 `python3`；仍不引入 idb/mobilecli/osascript。
- 新 summary 字段（写入 `docs/device-scripts.md`）：`launch.readiness ∈ {wda, devicectl-only}`、`launch.wda ∈ {present, absent}`、`launch.containerProbe ∈ {readable, empty, unreadable(warning), skipped}`、`launch.reason ∈ {"", wda_absent, devicectl_unready}`。
- 所有新变量展开写 `${var}` 形式（`check-shell-expansion` 字节级门）；新增函数保持 `set -euo pipefail` 下不依赖未定义变量。
- 候选 identity 只作为常量出现在验收/文档中，脚本不得写死 zip/exec sha；不得改 `--expect-*` 语义与 pinned 判定。
- `.munk/baseline/domains/ios-device-run/*` 不在本项编辑范围（Intake 只能写 `.munk/changes/**`）；其中 `ac-tcc-modes` 旧措辞由 Delivery 归档时同步，不阻塞本项。
