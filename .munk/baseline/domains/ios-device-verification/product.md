# Domain: ios-device-verification

PurePace iOS 真机自动化取证域：用「断言清单 + 一条三模式脚本 + 对应 XCUITest」把核心闭环（开跑 → 后台连续记录 → 跨公里播报 + 音乐 duck → 结束保存 → 历史 → 导出 GPX）与候选包首屏审计从人手走查变成零人工、可重复、带构建身份标注的机器证据。定位与审计不驱动锁屏/解锁，不承载单测/集成/模拟器层语义，不改业务源码。

## 范围

- `docs/device-assertion-matrix.md`（第一交付）：逐项一行、四列（断言项 / 判点 / 证据来源类型与构建身份 / 具体取值路径）；证据来源只取「Debug 可断言」「Release 候选包可断言」「只能人耳」三档。
- `scripts/verify-ios-device-flow.sh`：一条脚本三模式 `--phase=audit|audio|background`，`#!/usr/bin/env bash`、`set -euo pipefail`、以 `BASH_SOURCE` 推导仓库根，头注释写明「需真机连接」与目标 UDID `00008101-001C701E0A68001E`；零人工、不读 stdin、不弹交互。
- `ios/PurePaceUITests/DeviceFlowUITests.swift`：audit / audio / background 三组用例，经 XCTest attachment + `xcresulttool` 导出截图与可及树；后台连续性由 Mac 侧等待 + `devicectl` 只读读容器，不在测试进程内 `sleep` 断言。
- 证据落盘 `artifacts/device-audit/<UTC 时间戳>/`：`report.md`、`*.png`、`*.ax.json`、`run-*.json`、`announcements-*.json`、`*.gpx`、`sha256.txt`；中间产物只进 `.build/device-flow/`。
- `docs/device-flow-usage.md`：脚本用法、三模式、构建配置、证据路径、`pending: 待人现场（needs-you 单点）` 清单。
- 构建身份默认分层：`audit` / `background` 用 Release，`audio` 用 Debug（`-uiTestLocation` 确定性源仅 `#if DEBUG` 可用）。
- `ios/PurePace/Location/ReleaseDeterministicLocationSource.swift`：Release 可用的显式 launch-arg 确定性定位源，实现既有 `RunLocationProviding` 契约，**不得**包在 `#if DEBUG` 内，不 import CoreLocation/AVFoundation、不读写磁盘、不请求授权、不做播报；唯一场景 `km-crossing`（固定基准坐标、经度不变、纬度每 1.0 s 推进 20 m，约 50 个样本跨 1 km）；`sampleSource = .simulated`、`authorization = .authorizedWhenInUse`、`allowsBackgroundLocationUpdates = false`、`pausesLocationUpdatesAutomatically = false`；时钟/生成器 seam 可注入，单测无需 `sleep`。
- `ios/PurePace/Location/RunLocationSourceSelection.swift`：纯参数选择逻辑（Foundation + PurePaceRunCore，无 IO），`@MainActor static func select(arguments:makeReal:makeDeterministic:)`；仅当显式出现 `-releaseDeterministicLocation <scenario>` 时返回确定性源，缺值 / 取值以 `-` 开头 / 场景未知一律 fail-closed 回真实 `RunLocationSource()` 且确定性工厂调用 0 次。
- `ios/PurePace/ContentView.swift`：`#if DEBUG` + `-uiTestLocation` 分支逐字保留；`#else` 分支改为经选择器取源（Debug/Release 均可用，默认落真实源，`telemetryDebugEnabled=false`），正常用户路径无注入入口。
- `ios/PurePaceTests/ReleaseDeterministicLocationSourceTests.swift`：默认路径零注入、flag 路径 1.0 s 严格递增时序、把样本喂既有 `RunSessionOrchestrator` 恰产生 1 条 `splitIndex == 1` / `.kilometerCompleted` 播报、fail-closed 与能力诚实断言。
- `scripts/check-ios-shell.sh`：新增 release-deterministic 断言块（结构断言 + ≥1 条负向自检），不新增 `code-gates` 门（门数保持 22）。
- `docs/device-flow-usage.md` / `docs/device-assertion-matrix.md`：flag 语法、`km-crossing`、默认关、仅设备验证场、`simulated` 不计入真实 CoreLocation 判据；矩阵新增「Release 确定性源门控」行并修正 Release 公里播报结论行。
- 音频 duck 自证（UITests 自带合成音源、`--music-strategy=runner|app|none` 默认 `runner`、runner/none 正负对照、`duckRevoked` / `sessionDeactivated` 只做结构性观测）拆分到子域 `ios-audio-verification`，本域只保留 `--phase=audio` 的形状与证据边界。

## 验收

### 断言清单（A，第一交付）

- ac-matrix-file: `docs/device-assertion-matrix.md` 存在且非空；每个断言项一行，四列齐备（断言项 / 判点 / 证据来源类型与构建身份 / 具体取值路径）。
- ac-matrix-source-typed: 每行证据来源只取「Debug 可断言」「Release 候选包可断言」「只能人耳」之一且无留空；每行同时写明构建身份（(a) Debug UI-test 构建 / (b) Release 候选包 sha256 `7258…` + commit `8db1a167`）。
- ac-matrix-machine-paths: Debug/Release 可断言行必须写具体取值路径——JSON 写字段名（`activeDuration`、`samples[].timestamp`、`telemetry.announcements[].splitIndex`）、GPX 写解析项（trkpt 数 / 时间跨度 / 折线长）、截图或可及树写文件名与判据；不得只写「检查是否正常」。
- ac-matrix-human-ear-cap: 「只能人耳」行总数 ≤ 2，且只出现在清单最后一批；每行写明机器断言不了的原因。
- ac-matrix-release-km-answer: 必须给出「Release 候选包上的公里播报 + 音乐 duck 机器证据」明确结论行：标「Debug 可断言 + Release 机器证据来自显式 launch-arg 确定性源（非真实移动）」，写明真实 CoreLocation 只能人耳及其原因（无人静止场跨不了 1 km）；不得出现「候选包已验证真实定位」类措辞。
- ac-matrix-gate: 清单经 PO 转公司确认后才可跑正式真机场；digest / report 记录确认引用或 `pending: 待公司确认`；未确认时不得产出 `--phase=audio` / `--phase=background` 正式场证据。
- ac-matrix-core-loop-only: 清单只覆盖核心闭环与首屏审计三项；Info.plist 声明、单个开关、格式化、状态机、四态、阈值不得作为真机断言项（须指向单测/集成/模拟器层）。
- ac-matrix-audit-items: 清单含候选包真机首屏审计三项（五读数位 / 三 Tab / 详情页 GPX 入口），每项判点与证据文件名规则明确。

### Release 确定性源（launch-arg 门控，默认关）

- ac-default-selects-real: 无 `-releaseDeterministicLocation` 时 `RunLocationSourceSelection.select` 返回注入的真实源实例（`source === makeReal()`），`telemetryDebugEnabled == false`。
- ac-default-no-injection: 无 flag 时确定性源工厂调用次数为 0，确定性源未构造、未 `start()`、注入桩收到 0 个样本；计数在单测中直接可读。
- ac-flag-selects-release-source: 参数含 `-releaseDeterministicLocation km-crossing` 时返回 `ReleaseDeterministicLocationSource` 且 `sampleSource == .simulated`；选择逻辑不依赖 `#if DEBUG`，Debug 与 Release 配置均编译可用。
- ac-flag-sample-timing: 注入递增时钟后样本时间戳严格递增、相邻差 == 1.0 s，纬度单调推进、经度固定；单测不出现 `sleep` / `Thread.sleep`。
- ac-flag-km-boundary: 样本按序喂既有 `RunSessionOrchestrator`（先 `start(at:)`），累计距离跨过 1000 m 时恰好 1 条 `AnnouncementCommand`（`splitIndex == 1`、`trigger == .kilometerCompleted`）；跨过前 0 条，跨过后 `metrics.completedKilometers == 1`。
- ac-flag-fail-closed: flag 无值、值以 `-` 开头、或 scenario 未知（如 `bogus`）时确定性源工厂调用次数 0，返回真实源。
- ac-flag-honest-capabilities: `allowsBackgroundLocationUpdates == false`、`pausesLocationUpdatesAutomatically == false`、`authorization == .authorizedWhenInUse`；源码不 import CoreLocation，不调用任何授权 / `startUpdatingLocation` API。
- ac-production-source-untouched: `RunLocationSource.swift`、`RunSessionViewModel.swift`、`ios/RunCore/Sources`、`ios/PurePace/Audio`、`History`、`Settings`、`Info.plist`、`ios/project.yml` 零 diff；采样阈值、状态机、播报调度零改动。
- ac-ui-tests-untouched: `ios/PurePaceUITests/**` 零 diff，现有 Debug 用例仍以 `-uiTestLocation`（及 `-uiTestLocationFast`）启动，其中 `-releaseDeterministicLocation` 零命中。
- ac-static-gate-default-path: `scripts/check-ios-shell.sh` 的 release-deterministic 块在默认分支被改为直接注入确定性源、或选择器默认分支不再构造真实源时退出非 0；正常仓库上 `bash scripts/check-ios-shell.sh` 退出 0。
- ac-static-gate-permissions-unchanged: 该静态块断言 `ios/project.yml` 的 `NS*UsageDescription` 键恰为既有两条（WhenInUse / AlwaysAndWhenInUse），`UIBackgroundModes` 含 `location` 与 `audio` 且无第三项；`ios/PurePace/Info.plist` 零 diff。
- ac-static-gate-negative-selftest: 该静态块至少 1 条负向自检（临时副本去掉/加上被禁止结构必须报错），自检不恒真且不影响正常仓库通过。
- ac-gate-topology-unchanged: `.munk/code-gates.json` 仍为 22 门、id/command 语义不变；`check-ios-scripts.sh` / `check-ios-release.sh` 的门数断言不改；不新增 timeout、无 `continue-on-error`、不删腿；`.github/workflows/**` 零 diff。
- ac-docs-flag-documented: `docs/device-flow-usage.md` 含 `-releaseDeterministicLocation`、`km-crossing`、默认关、仅设备验证场、`simulated`、不计入真实 CoreLocation 判据的明确表述；不写「真机已验证」。
- ac-matrix-row-added: `docs/device-assertion-matrix.md` 的 Release 公里播报结论表新增一行「Release 确定性源门控」，同时含「默认关」「仅设备验证场」「不计入真实 CoreLocation 判据」三要素。
- ac-matrix-conclusion-honest: 该表现有结论行不再把「Release 上取不到机器证据 / 只能人耳」当绝对结论，改为「真实 CoreLocation 只能人耳；Release 机器证据来自显式 launch-arg 确定性源（非真实移动）」，且无「候选包已验证真实定位」类措辞。

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
- ac-audio-music-and-announcement: 运行中由 **runner 自播音源**（`--music-strategy=runner`，默认）提供他路音频并确认在播（系统 Music 不再作为默认路径，详见子域 `ios-audio-verification`）；`--phase=audio` 须同时跑 `--music-strategy=none` 负对照；`telemetry.announcements[]` 至少 1 条 km 触发（`trigger` 为公里完成、`splitIndex == 1`），含音频会话 category/mode/options、duck 应用与恢复、`isOtherAudioPlaying` 取值。
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
- 不写「真机已验证公里播报」：确定性源只提供「仅设备验证场」的机器证据，样本 `simulated` 不计入真实 CoreLocation 判据；真实移动结论仍只能人耳。
- 不写桌面端自研驱动（CDP / 注入 JS / 自拼截屏）；不装 mobilecli agent，不依赖 `mobile_*`；不引入第三方运行时依赖。
- 不做截图视觉回归、不提交模拟器结论、不改 Android 侧；脚本与清单未就绪前不排人、不约窗口。

## 实现约束

- **交付顺序与流程门**：先出清单交 PO 转公司确认；未确认前只做清单与静态检查，不跑正式真机场（audio / background）；确认后再跑真机，audit 仍是脚本第一产出。
- **构建身份（硬要求）**：所有真机证据一律二选一标注，不得混写——(a) Debug UI-test 构建（`xcodebuild test` 产出）或 (b) Release 候选包（zip sha256 `7258d2e3f7984ef2557278bd1fcdd1eea5db1f34a4d549dc8071d7afcd5b9d8f` / commit `8db1a167`）；产物文件名、`report.md`、清单行、digest 四处都要带。
- **可写文件集合**（超出会被回滚）：`docs/device-assertion-matrix.md`、`scripts/verify-ios-device-flow.sh`、`ios/PurePaceUITests/`（新增/修改用例）、`ios/project.yml`（仅登记新测试文件时）、`docs/` 其它简短说明、`artifacts/device-audit/`。禁止改 `ios/PurePace/**`、`ios/RunCore/**`、`ios/Core/**`、`.munk/code-gates.json`、`.github/workflows/**`、既有 `scripts/check-*`。
  - 例外（`Release 确定性源` 项）：允许 `ios/PurePace/ContentView.swift`（仅 `#else` 分支接线）、`ios/PurePace/Location/ReleaseDeterministicLocationSource.swift`、`ios/PurePace/Location/RunLocationSourceSelection.swift`、`ios/PurePaceTests/ReleaseDeterministicLocationSourceTests.swift`、`ios/PurePace.xcodeproj/project.pbxproj`（仅生成器产物）、`scripts/check-ios-shell.sh`、`docs/device-flow-usage.md`；其余 `ios/PurePace/**` 与业务契约仍禁改。
- **确定性源口径**：`Timer` 只允许出现在 `Location/`，不进 `Run/`；选择器 seam 除 `CommandLine.arguments` 外不读全局状态；未知/缺值 scenario 不抛异常、不弹 UI、不向用户可见位置写日志；`ios/project.yml` 的 `sources: - path: PurePace` 自动纳入新文件，须 `xcodegen generate --spec project.yml` 后提交生成的 pbxproj。
- **驱动方式**：只用成熟工具链——`xcrun devicectl` 装/启 + 设备端 `xcodebuild test`（`-destination id=<UDID>`、`-only-testing`、`-resultBundlePath`），截图/可及树经 XCTest attachment + `xcresulttool export attachments` 导出；禁止自写桌面驱动。
- **候选包定位**：不在 worktree 内，位于 products 侧 `artifacts/candidates/PurePace-Release-*.zip`；脚本用 `--candidate` 或通配定位，不复制进仓库，不写死版本号（`check-baseline` 扫 `scripts/*.sh`）。
- **配置分层**：audit / background 用生产定位源（Release / 不传 `-uiTestLocation`）；audio 才用 DEBUG 确定性源；每模式报告写清构建配置，禁止用 Debug 结果冒充 Release 行为。
- **后台两段式**：阶段一设备端开跑并 `press(.home)` 后立即结束；等待放 Mac 侧（宿主等待 + `devicectl` 只读读容器）；阶段二 `activate()` 回前台完成结束保存与导出；不在测试进程内 `sleep` 断言后台连续性。
- **证据目录**：`artifacts/device-audit/<UTC>/` 存 `report.md`、`*.png`、`*.ax.json`、`run-*.json`、`announcements-*.json`、`*.gpx`、`sha256.txt`；resultBundle 等中间产物留 `.build/`（gitignore）。
- **门禁口径**：`check-baseline`、`check-shell-expansion`、`check-ios-scripts`、`check-ios-shell`、`check-ios-release` 保持绿；新增脚本不进既有 `targets`，但须自满足 `--help`/未知参数契约与 shell 展开检查；报告与脚本不含 git 推送、tag、Release 动作，不写「真机已验证」。

## 最近交付证明

- workItemId: wi_intake_abacaa757ba3bd09（2026-11-10，pass）
- 交付：Release 可用的显式 launch-arg 确定性定位源（默认关）——`ReleaseDeterministicLocationSource`（`km-crossing`：1.0 s/20 m 推进，约 50 样本跨 1 km，`simulated` + WhenInUse + 后台开关 false）与纯参数选择器 `RunLocationSourceSelection`（缺值 / 以 `-` 开头 / 未知场景 fail-closed 回真实源、构造次数 0）；`ContentView` 的 `#if DEBUG` + `-uiTestLocation` 分支逐字保留，`#else` 分支改经选择器。`scripts/check-ios-shell.sh` 增 release-deterministic 断言块（含负向自检），门数仍 22；`docs/device-flow-usage.md` 增「Release 确定性源（仅设备验证场）」小节，矩阵新增「Release 确定性源门控」行并把 Release 公里播报结论改为「真实 CoreLocation 只能人耳；机器证据来自显式确定性源」。
- 实测：默认路径单测零构造零注入；flag 路径时序严格 1.0 s 递增，喂 `RunSessionOrchestrator` 恰 1 条 `splitIndex == 1` / `.kilometerCompleted`；候选包从提交 `1e7e653` 出（zip `43be04f3…`，413660 B；exec `2378b720…`，1507136 B；`UIBackgroundModes=["location","audio"]`、`sh.munk.purepace`、0.1.0(1)、MinimumOSVersion 17.0 均从解压 `.app/Info.plist` 读回）。
- 边界：`ios/PurePaceUITests/**`、`ios/RunCore/**`、`ios/Core/**`、`ios/project.yml`、`ios/PurePace/Info.plist`、`.github/workflows/**`、`.munk/code-gates.json` 零 diff；候选 `iosCI` 为 `pending: 待同 commit ios.yml run 判定`，真机三档仍为 `pending: 待人现场`；`simulated` 样本不构成真实定位结论。
