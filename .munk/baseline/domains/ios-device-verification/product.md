# Domain: ios-device-verification

PurePace iOS 真机自动化取证域：用「断言清单 + 一条三模式脚本 + 对应 XCUITest」把核心闭环（开跑 → 后台连续记录 → 跨公里播报 + 音乐 duck → 结束保存 → 历史 → 导出 GPX）与候选包首屏审计从人手走查变成零人工、可重复、带构建身份标注的机器证据。定位与审计不驱动锁屏/解锁，不承载单测/集成/模拟器层语义，不改业务源码。

## 范围

- `docs/device-assertion-matrix.md`（第一交付）：逐项一行、四列（断言项 / 判点 / 证据来源类型与构建身份 / 具体取值路径）；证据来源只取「Debug 可断言」「Release 候选包可断言」「只能人耳」三档。
- `scripts/verify-ios-device-flow.sh`：一条脚本三模式 `--phase=audit|audio|background`，`#!/usr/bin/env bash`、`set -euo pipefail`、以 `BASH_SOURCE` 推导仓库根，头注释写明「需真机连接」与目标 UDID `00008101-001C701E0A68001E`；零人工、不读 stdin、不弹交互。
- `ios/PurePaceUITests/DeviceFlowUITests.swift`：audit / audio / background 三组用例，经 XCTest attachment + `xcresulttool` 导出截图与可及树；后台连续性由 Mac 侧等待 + `devicectl` 只读读容器，不在测试进程内 `sleep` 断言。
- 证据落盘 `artifacts/device-audit/<UTC 时间戳>/`：`report.md`、`*.png`、`*.ax.json`、`run-*.json`、`announcements-*.json`、`*.gpx`、`sha256.txt`；中间产物只进 `.build/device-flow/`。
- `docs/device-flow-usage.md`：脚本用法、三模式、构建配置、证据路径、`pending: 待人现场（needs-you 单点）` 清单。
- 构建身份默认分层：`audit` / `background` 用 Release，`audio` 用 Debug（`-uiTestLocation` 确定性源仅 `#if DEBUG` 可用）。

## 验收

### 断言清单（A，第一交付）

- ac-matrix-file: `docs/device-assertion-matrix.md` 存在且非空；每个断言项一行，四列齐备（断言项 / 判点 / 证据来源类型与构建身份 / 具体取值路径）。
- ac-matrix-source-typed: 每行证据来源只取「Debug 可断言」「Release 候选包可断言」「只能人耳」之一且无留空；每行同时写明构建身份（(a) Debug UI-test 构建 / (b) Release 候选包 sha256 `7258…` + commit `8db1a167`）。
- ac-matrix-machine-paths: Debug/Release 可断言行必须写具体取值路径——JSON 写字段名（`activeDuration`、`samples[].timestamp`、`telemetry.announcements[].splitIndex`）、GPX 写解析项（trkpt 数 / 时间跨度 / 折线长）、截图或可及树写文件名与判据；不得只写「检查是否正常」。
- ac-matrix-human-ear-cap: 「只能人耳」行总数 ≤ 2，且只出现在清单最后一批；每行写明机器断言不了的原因。
- ac-matrix-release-km-answer: 必须给出「Release 候选包上的公里播报 + 音乐 duck 机器证据」明确结论行：标「Debug 可断言 + Release 只能人耳」，写明原因（`-uiTestLocation` 被 `#if DEBUG` 关闭、km 边界需真实移动）；不得出现「Release 候选包机器断言 km 播报」的行；确定性源 launch-arg 门控进 Release 只作评估结论与影响面，另立项实施。
- ac-matrix-gate: 清单经 PO 转公司确认后才可跑正式真机场；digest / report 记录确认引用或 `pending: 待公司确认`；未确认时不得产出 `--phase=audio` / `--phase=background` 正式场证据。
- ac-matrix-core-loop-only: 清单只覆盖核心闭环与首屏审计三项；Info.plist 声明、单个开关、格式化、状态机、四态、阈值不得作为真机断言项（须指向单测/集成/模拟器层）。
- ac-matrix-audit-items: 清单含候选包真机首屏审计三项（五读数位 / 三 Tab / 详情页 GPX 入口），每项判点与证据文件名规则明确。

### 产品标识跟随（矩阵与脚本的构建身份）

- ac-device-suite-bundle-id: `scripts/verify-ios-device-flow.sh` 的 usage 说明与 `bundle_id="${PUREPACE_BUNDLE_ID:-sh.munk.purepace}"` 默认值均为 `sh.munk.purepace`（该精确赋值表达式恰 1 处），`PUREPACE_BUNDLE_ID` / `PUREPACE_DEVICE_UDID` / `--device` 的 env 覆盖语义不变；`bash -n` 退出 0。
- ac-device-suite-not-weakened: 脚本 `continue-on-error` 零命中、`set -euo pipefail` 仍在、`--phase` 三值（`audit|audio|background`）与 `pending: 待人现场` 文案仍在；bundle id 迁移只改 usage 与默认值两行，脚本断言、等待、退出码零改动。
- ac-matrix-current-bundle-id: `docs/device-assertion-matrix.md` 的「构建身份与档位」(a) 段与批次 A1 说明写 `sh.munk.purepace` 且全文无旧 bundle id 字面量；三档标签与批次 A1/A2/B 三个标题保留。
- ac-matrix-history-immutable: matrix (b) 段历史候选 `zip sha256 7258…` 与 `commit 8db1a167` 保持原样不改写，`pending: 待人现场` 表述仍在；`docs/evidence/**`、`artifacts/**` 历史证据零改动。
- ac-legacy-bundle-id-grep-exempt-only: `git grep -n 'com\.chaxiu\.purepace' -- ios scripts docs` 命中仅 `docs/evidence/**`；`scripts/` 与 `docs/` 的非 `docs/evidence/` 路径零命中。

### `--phase=audit`（脚本第一产出）

- ac-audit-output-layout: 每次运行在 `artifacts/device-audit/<UTC>/` 下落盘 ≥1 张 `.png`、≥1 份 `*.ax.json`、1 份 `report.md`；`report.md` 含三项审计逐项 PASS/FAIL 与对应证据文件名，所列文件真实存在且非空。
- ac-audit-runview-five-metrics: 首屏可及树同时存在 `run.distance` / `run.elapsed` / `run.currentPace` / `run.averagePace` / `run.splits` 五个标识；任一缺失即该项 FAIL 并列缺失标识与截图文件名。
- ac-audit-three-tabs: Run / History / Settings 三 Tab 均可切换，切换后各有可及内容（`run.distance` / `history.empty` 或 `history.row` / `settings.announcementToggle`）；三项均有截图 + 可及树证据。
- ac-audit-detail-gpx-entry: 有归档时可进详情页且 `runDetail.export` 存在、可见、可点击，记 PASS + 证据；归档为空或无可用跑次记 FAIL 并写明原因与证据，不得写成「存在」。
- ac-audit-build-identity-honest: `report.md` 记录实际被驱动构建的 bundle id、版本、配置、commit，并按 (a)/(b) 二选一标注；实际驱动构建与候选 zip 非同一二进制时必须显式标注「实际驱动构建 ≠ 候选包二进制」及差异原因，禁止宣称「候选包已验证」。
- ac-audit-defect-only: 审计缺项/不可用只作为缺陷写进 `report.md`（含证据），不修改 `ios/PurePace/**` 业务 UI。

### 脚本契约与门禁边界

- ac-script-cli-contract: 脚本可执行；首行 `#!/usr/bin/env bash`；含 `set -euo pipefail`；`BASH_SOURCE` 推导仓库根；`--help` 输出含「用法」且退出 0；未知参数退出 2；重复执行不依赖上次残留状态。
- ac-script-device-header: 头注释含「需真机连接」并写明目标 UDID `00008101-001C701E0A68001E`；不假设模拟器可用。
- ac-script-phases: 只接受 `--phase=audit|audio|background`（缺省或非法值退出非 0 并打印用法）；三模式不读 stdin、不弹交互、不调用人手协助接口。
- ac-script-zero-human: 三模式主流程无「请人工…」步骤；启动被测包、开跑、起音乐、切后台、跨边界、保存、导出、读容器均由脚本/用例驱动。
- ac-script-no-version-literal: 脚本不出现根 `VERSION` 字面值（候选包用 `--candidate` 或通配定位）；`bash scripts/check-baseline.sh` 通过。
- ac-script-shell-gates: `bash -n scripts/verify-ios-device-flow.sh` 与 `bash scripts/check-shell-expansion.sh` 均退出 0。
- ac-gates-unchanged: `.munk/code-gates.json` 仍为 22 门且无门引用真机脚本；`git diff -- .github/workflows` 为空；不新增本地阻断门或长耗时门腿。
- ac-signing-commandline-only: 签名参数只在 `xcodebuild` 命令行临时传入（`-allowProvisioningUpdates DEVELOPMENT_TEAM=3X4J53U6RY CODE_SIGNING_ALLOWED=YES CODE_SIGN_STYLE=Automatic`）；`ios/project.yml` 主干不出现团队/证书配置。
- ac-no-product-source-change: `ios/PurePace/**`、`ios/RunCore/**`、`ios/Core/**` 零改动；`ios/project.yml` 仅在登记新测试文件时改；不手改 `project.pbxproj`。

### `--phase=audio`

- ac-audio-single-run-bounded: 单次真机无人操作跑完，跑动 60–90 秒，跨恰好一次公里边界；无固定 `sleep` 作成功判据，等待均为有界 `waitForExistence`。
- ac-audio-music-and-announcement: 运行中启动系统 Music 并确认在播；`telemetry.announcements[]` 至少 1 条 km 触发（`trigger` 为公里完成、`splitIndex == 1`），含音频会话 category/mode/options、duck 应用与恢复、`isOtherAudioPlaying` 取值。
- ac-audio-artifacts: 截图序列（起跑 / km 边界 / 结束）、跑次 JSON、`announcements-*.json` 抽取均落盘；任一项缺失即 FAIL 并列证据。

### `--phase=background`

- ac-background-no-lock-driving: 不调用锁屏/解锁/密码输入相关 API（不出现 `press(.lock)`、锁屏按钮号、`lockState` 驱动、解锁动作）；唯一前后台动作是 `press(.home)`；只读查询 `lockState` 仅作观测，不得据此宣称锁屏后连续采样。
- ac-background-continuity: 首条样本早于 `press(.home)`、末条晚于后台窗口结束；相邻样本最大空洞 ≤ 60 秒；`activeDuration` 与墙钟相对差 ≤ 5%；时间序列单调不减。未解锁读不到最终 archive 时改读 checkpoint 并在报告标注来源。
- ac-background-telemetry: `telemetry.announcements[]` 含 km 触发记录、duck 应用与恢复、`isOtherAudioPlaying` 取值；缺任一项即 FAIL 并列证据。
- ac-background-auth-honest: 报告原样记录 `authorizationStatus` / `accuracyAuthorization` / `allowsBackgroundLocationUpdates` 实测值；WhenInUse 时必须写「后台会被系统掐断」并标 `pending: 待人现场（needs-you 单点）`，不得用「锁屏」话术包装结论。
- ac-background-gpx-sha256: 导出 `.gpx` 存在且字节数 > 0，实算 `sha256` 为 64 位十六进制并与写入文件一致；`trkpt` 数与样本量级一致（差 ≤ 1）；GPX 时间跨度与记录区间绝对差 ≤ 1 秒。
- ac-background-no-unlock-claim: 自然上锁后需人工解锁才能结束保存时，脚本不得解锁或伪造结束动作，只记录已持久化产物与 `pending: 待人现场（needs-you 单点）`，不得把 archive 断言写成通过。

### 证据与诚实性（跨阶段）

- ac-evidence-build-identity: 每份证据的产物文件名、`report.md` 结论行、清单行、digest 结论四处均带构建身份标注（(a)/(b) 二选一）；同一结论表两种构建必须分行，禁止混写。
- ac-artifacts-four-kinds: 每次真机运行至少产出四类证据——截图序列、容器跑次 JSON、`telemetry.announcements[]`、导出 `.gpx` 与实算 sha256；路径打印 stdout 并写入 `report.md`，文件名带 (a)/(b) 身份前缀或后缀。
- ac-real-device-run: 至少一次真实设备运行完成（报告含 UDID、iOS 版本、起止时间、构建身份）；连接或设备侧能力缺失时如实记录卡点并 report owner，禁止编造截图、可及树、telemetry 或 sha256。
- ac-digest-pointer: 断言清单摘要、脚本用法、三模式产物路径、构建身份标注、`pending: 待人现场（needs-you 单点）` 清单写入交付摘要；`artifacts/device-audit/<UTC>/` 与 `docs/device-assertion-matrix.md` 两个路径明确可见。

## 非目标

- 不驱动锁屏/解锁，不在 run 内要求人按任何步骤；不把「锁屏后仍出样本」写成本项结论。
- 真机不承载核心闭环以外的语义（Info.plist 声明、单个开关、格式化、状态机、四态、阈值均在单测/集成/模拟器层证明）。
- 不在本项修复任何业务 UI / 定位 / 音频 / 导出缺陷（缺项按缺陷记录，修复另行立项）。
- 不宣称阶段 2/3「真机已验证」；不改 `code_gates`、`.github/workflows`、CI 触发或发布流程。
- 不写「真机已验证公里播报」：Release 候选包上该判点只能人耳，机器证据仅来自 Debug UI-test 构建；launch-arg 门控进 Release 只写评估结论与影响面，本项不实施。
- 不写桌面端自研驱动（CDP / 注入 JS / 自拼截屏）；不装 mobilecli agent，不依赖 `mobile_*`；不引入第三方运行时依赖。
- 不做截图视觉回归、不提交模拟器结论、不改 Android 侧；脚本与清单未就绪前不排人、不约窗口。

## 实现约束

- **交付顺序与流程门**：先出清单交 PO 转公司确认；未确认前只做清单与静态检查，不跑正式真机场（audio / background）；确认后再跑真机，audit 仍是脚本第一产出。
- **构建身份（硬要求）**：所有真机证据一律二选一标注，不得混写——(a) Debug UI-test 构建（`xcodebuild test` 产出）或 (b) Release 候选包（zip sha256 `7258d2e3f7984ef2557278bd1fcdd1eea5db1f34a4d549dc8071d7afcd5b9d8f` / commit `8db1a167`）；产物文件名、`report.md`、清单行、digest 四处都要带。
- **可写文件集合**（超出会被回滚）：`docs/device-assertion-matrix.md`、`scripts/verify-ios-device-flow.sh`、`ios/PurePaceUITests/`（新增/修改用例）、`ios/project.yml`（仅登记新测试文件时）、`docs/` 其它简短说明、`artifacts/device-audit/`。禁止改 `ios/PurePace/**`、`ios/RunCore/**`、`ios/Core/**`、`.munk/code-gates.json`、`.github/workflows/**`、既有 `scripts/check-*`。
- **驱动方式**：只用成熟工具链——`xcrun devicectl` 装/启 + 设备端 `xcodebuild test`（`-destination id=<UDID>`、`-only-testing`、`-resultBundlePath`），截图/可及树经 XCTest attachment + `xcresulttool export attachments` 导出；禁止自写桌面驱动。
- **候选包定位**：不在 worktree 内，位于 products 侧 `artifacts/candidates/PurePace-Release-*.zip`；脚本用 `--candidate` 或通配定位，不复制进仓库，不写死版本号（`check-baseline` 扫 `scripts/*.sh`）。
- **配置分层**：audit / background 用生产定位源（Release / 不传 `-uiTestLocation`）；audio 才用 DEBUG 确定性源；每模式报告写清构建配置，禁止用 Debug 结果冒充 Release 行为。
- **后台两段式**：阶段一设备端开跑并 `press(.home)` 后立即结束；等待放 Mac 侧（宿主等待 + `devicectl` 只读读容器）；阶段二 `activate()` 回前台完成结束保存与导出；不在测试进程内 `sleep` 断言后台连续性。
- **证据目录**：`artifacts/device-audit/<UTC>/` 存 `report.md`、`*.png`、`*.ax.json`、`run-*.json`、`announcements-*.json`、`*.gpx`、`sha256.txt`；resultBundle 等中间产物留 `.build/`（gitignore）。
- **门禁口径**：`check-baseline`、`check-shell-expansion`、`check-ios-scripts`、`check-ios-shell`、`check-ios-release` 保持绿；新增脚本不进既有 `targets`，但须自满足 `--help`/未知参数契约与 shell 展开检查；报告与脚本不含 git 推送、tag、Release 动作，不写「真机已验证」。

## 最近交付证明

- workItemId: wi_intake_e97db968c68e4562（2026-11-10，pass）
- 交付：设备取证套件跟随 `sh.munk.purepace`——`scripts/verify-ios-device-flow.sh` 只改 usage 说明与 `PUREPACE_BUNDLE_ID` 默认值两行（env 覆盖保留）；`docs/device-assertion-matrix.md` 的 (a) 段与批次 A1 说明换新 id，(b) 段历史候选 `7258…` / commit `8db1a167` 与 `pending: 待人现场` 原样保留。旧 id 全局命中收敛到 `docs/evidence/stage3-e2e/report.json` 2 条历史证据。
- 边界：`docs/evidence/**`、`artifacts/**`、`ios/PurePaceUITests/**`、`ios/project.yml`、`.github/workflows/**` 零改动；三模式断言、等待与退出码未弱化。真机三档补测仍为 `pending: 待人现场`。
