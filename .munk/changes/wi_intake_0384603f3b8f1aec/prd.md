# PurePace 真机自动化取证：断言清单 + 三阶段真机闭环脚本

## 范围

本项按公司定稿（owen `owe_1e41cbe9fea13a45`、`owe_84fe2f091f432a21`、`owe_b252bb65d8b3f99b`）交付**两件、缺一不算完成**：

### (A) 先交「断言清单」→ `docs/device-assertion-matrix.md`

逐项一行，列清四列：**断言项 / 判点（通过条件）/ 证据来源类型与构建身份 / 具体取值路径**。证据来源列必须标死三档之一：

- **Debug 可断言**：只能由 `xcodebuild test` 产出的 Debug UI-test 构建证明；路径写容器跑次 JSON 字段名、`telemetry.announcements[]` 字段名、`.gpx` 解析项（trkpt 数 / 时间跨度 / 折线长）、截图或可及树文件名与判据。
- **Release 候选包可断言**：只能由 zip（sha256 `7258d2e3f7984ef2557278bd1fcdd1eea5db1f34a4d549dc8071d7afcd5b9d8f`）/ commit `8db1a167` 的 Release 候选包证明；路径同上。
- **只能人耳**：只允许出现在最后一批，总数 ≤2 个问题（例：音乐是否被打断 / 播完音量是否恢复 / 播报是否听清），每行写明机器断言不了的原因，随机器证据交回公司负责人一次性问人。

每条真机证据（产物文件名、`report.md` 行、清单行、digest 结论）都必须写明构建身份，二选一且不得混写：**(a) Debug UI-test 构建** 或 **(b) Release 候选包（sha256 `7258…` / commit `8db1a167`）**；同一张结论表出现两种构建必须分行。

**Release 包 km 播报的明确结论**：`-uiTestLocation` 被 `#if DEBUG` 关掉，Release 无法注入确定性源，km 边界只能靠真实移动；无人静止场无法保证跨公里，故「公里播报 + 音乐 duck」在 Release 候选包上**取不到机器证据**。清单中该判点标为「Debug 可断言 + Release 只能人耳」，对外文案只准写「Debug 构建 + 遥测验证」，禁止写「真机已验证公里播报」。把确定性源改为显式 launch-arg 门控进 Release 只在本项写评估结论与影响面，另立项实施，本项不动业务源码。

真机只承载**核心闭环一条**：开跑 → 后台（切走 / 系统自然上锁）连续记录 → 跨公里播报 + 音乐 duck → 结束保存 → 历史 → 导出 GPX。其余语义（Info.plist 声明、单个开关、时间/配速格式化、状态机、四态、阈值）一律落在单测 / 集成 / 模拟器 UI 层，**不得进真机场**；若确实只能真机验证，先写进清单「只能人耳」栏并说明机器断言不了的原因。

### (B) 再交驱动脚本 + 真机跑通

新增 `scripts/verify-ios-device-flow.sh`（一条脚本、三种模式 `--phase=audit|audio|background`）+ 对应 XCUITest（`ios/PurePaceUITests/DeviceFlowUITests.swift`），三模式均**零人工操作**跑通并落盘证据；脚本头注释显式标注「需真机连接」。

- `--phase=audit`（第一产出，待核项，构建身份 **(b) Release 候选包**）：真机首屏截图 + 可及树 dump（`*.ax.json`）+ `report.md` 结论表，核实：①首屏 RunView 五个读数位（`run.distance` / `run.elapsed` / `run.currentPace` / `run.averagePace` / `run.splits`）；②三 Tab（Run / History / Settings）可切换且各有内容；③历史详情页 `runDetail.export` 可用。人反馈「只看到开始/结束」与上述不符，缺项按缺陷列证据记录。若实际只能驱动 Debug 构建，则整体标 **(a)** 并写明候选包未被驱动，不得混标。
- `--phase=audio`（构建身份 **(a) Debug UI-test 构建**）：确定性测试源（DEBUG `-uiTestLocation`）跨一次公里边界 + 系统 Music 在播，机器读回 `telemetry.announcements[]` 的 km 触发 / duck 应用与恢复 / `isOtherAudioPlaying`；实听不在本项。
- `--phase=background`（构建身份 **(b) Release 候选包**）：UI 起跑 → 起音乐 → `XCUIDevice.shared.press(.home)` 切后台 → 等 5–6 分钟（设备按系统设置自然上锁，脚本不驱动锁屏/解锁）→ 仅机器读回容器产物。结论只写「切后台后进程存活 + 持续采样」，不写「锁屏后仍出样本」。

**硬约束**：不驱动锁屏/解锁，不在 run 内要求人按任何步骤；未自动化到的人手点只写 `pending: 待人现场（needs-you 单点）`；脚本与断言清单未就绪前不得排人、不得约窗口。

## 验收

### (A) 断言清单（第一交付）

- ac-matrix-file: `docs/device-assertion-matrix.md` 存在且非空；每个断言项一行，四列齐备（断言项 / 判点 / 证据来源类型与构建身份 / 具体取值路径）。
- ac-matrix-source-typed: 每行证据来源只取「Debug 可断言」「Release 候选包可断言」「只能人耳」三者之一，无留空；且每行同时写明构建身份（Debug UI-test 构建 / Release 候选包 sha256+commit）。
- ac-matrix-machine-paths: 标为 Debug / Release 可断言的行必须写具体取值路径——JSON 写字段名（如 `activeDuration`、`samples[].timestamp`、`telemetry.announcements[].splitIndex`）、GPX 写解析项（trkpt 数 / 时间跨度 / 折线长）、截图或可及树写文件名与判据；不得只写「检查是否正常」。
- ac-matrix-human-ear-cap: 标为「只能人耳」的行总数 ≤ 2，且只出现在清单最后一批；每行写明机器断言不了的原因。
- ac-matrix-release-km-answer: 清单必须对「Release 候选包上的公里播报 + 音乐 duck 机器证据」给出明确结论行：标为「Debug 可断言 + Release 只能人耳」，写明原因（`-uiTestLocation` 被 `#if DEBUG` 关闭、km 边界需真实移动）；不得出现「Release 候选包机器断言 km 播报」的行；把确定性源加 launch-arg 门控进 Release 只作为评估结论与影响面记录，另立项实施。
- ac-matrix-gate: 清单经 PO 转公司确认后才可跑正式真机场；digest / report 记录确认引用或 `pending: 待公司确认`；未确认时不得产出 `--phase=audio` / `--phase=background` 正式场证据（Coding 可先写清单与做静态检查）。
- ac-matrix-core-loop-only: 清单覆盖「开跑 → 后台连续记录 → 跨公里播报 + 音乐 duck → 结束保存 → 历史 → 导出 GPX」核心闭环；Info.plist 声明、单个开关、时间/配速格式化、状态机、四态、阈值**不出现**在真机断言项中（应指向单测/集成/模拟器层）。
- ac-matrix-audit-items: 清单含候选包真机首屏审计三项（五读数位 / 三 Tab / 详情页 GPX 入口），每项判点与证据文件名规则明确。

### 交付 1：候选包真机 UI 审计（`--phase=audit`）

- ac-audit-output-layout: 每次 audit 运行在 `artifacts/device-audit/<UTC 时间戳>/` 下落盘至少 1 张 `.png`、至少 1 份 `*.ax.json`、1 份 `report.md`；`report.md` 含三项审计逐项 PASS/FAIL 与对应证据文件名，所列文件真实存在且非空。
- ac-audit-runview-five-metrics: 真机首屏可及树证据中同时存在 `run.distance` / `run.elapsed` / `run.currentPace` / `run.averagePace` / `run.splits` 五个标识对应元素；任一缺失即该项 FAIL 并列出缺失标识与截图文件名，不得省略读数位仍判 PASS。
- ac-audit-three-tabs: Run / History / Settings 三 Tab 均可切换，切换后对应页面至少存在一个可及内容元素（Run 读数位 / History 空态或 `history.row` / `settings.announcementToggle`）；三项均有截图 + 可及树证据。
- ac-audit-detail-gpx-entry: 归档至少一条跑次时，可进详情页且 `runDetail.export` 存在、可见、可点击，记 PASS + 证据；若归档为空或无可用跑次，记 FAIL 并写明原因与证据，不得把入口写成「存在」。
- ac-audit-build-identity-honest: `report.md` 记录实际被驱动构建的 bundle id、版本、配置（Debug/Release）、commit，并按 **(a) Debug UI-test 构建** 或 **(b) Release 候选包（sha256 `7258…` / commit `8db1a167`）** 二选一标注；若实际驱动构建与候选 zip 非同一二进制，必须显式标注「实际驱动构建 ≠ 候选包二进制」及差异原因，禁止宣称「候选包已验证」。
- ac-audit-defect-only: 审计缺项/不可用只作为缺陷写进 `report.md`（含证据），不修改 `ios/PurePace/**` 业务 UI。

### 交付 2：脚本契约与门禁边界

- ac-script-cli-contract: `scripts/verify-ios-device-flow.sh` 可执行；首行 `#!/usr/bin/env bash`；含 `set -euo pipefail`；以 `BASH_SOURCE` 推导仓库根；`--help` 输出含「用法」且退出 0；未知参数退出 2；重复执行不依赖上次残留状态。
- ac-script-device-header: 脚本头注释含「需真机连接」并写明目标设备 UDID `00008101-001C701E0A68001E`；不假设模拟器可用。
- ac-script-phases: 脚本只接受 `--phase=audit|audio|background`（缺省或非法值退出非 0 并打印用法）；三模式均不读 stdin、不弹交互提示、不调用任何人手协助接口。
- ac-script-zero-human: 三模式主流程无「请人工…」步骤：不要求人按电源键、输密码、手动开跑/结束/导出；脚本自身驱动启动被测包、开跑、起音乐、切后台、跨边界、保存、导出、读容器。
- ac-script-no-version-literal: 脚本不出现根 `VERSION` 字面值（候选包用通配或 `--candidate` 参数定位，如 `artifacts/candidates/PurePace-Release-*.zip`）；`bash scripts/check-baseline.sh` 通过。
- ac-script-shell-gates: `bash -n scripts/verify-ios-device-flow.sh` 与 `bash scripts/check-shell-expansion.sh` 均退出 0。
- ac-gates-unchanged: `.munk/code-gates.json` 仍为 22 个门且无门引用真机脚本；`git diff -- .github/workflows` 为空；不新增本地阻断门或长耗时门腿。
- ac-signing-commandline-only: 签名参数只在脚本命令行临时传入（`-allowProvisioningUpdates DEVELOPMENT_TEAM=3X4J53U6RY CODE_SIGNING_ALLOWED=YES CODE_SIGN_STYLE=Automatic`）；`ios/project.yml` 主干不出现 `DEVELOPMENT_TEAM` / `CODE_SIGN_STYLE` / 证书配置。
- ac-no-product-source-change: `ios/PurePace/**`、`ios/RunCore/**`、`ios/Core/**` 零改动；`ios/project.yml` 仅在确需登记新测试文件时改；不手改 `ios/PurePace.xcodeproj/project.pbxproj`（由 xcodegen 在脚本运行时生成）。

### `--phase=audio`

- ac-audio-single-run-bounded: 单次 `--phase=audio` 真机无人操作跑完，跑动时长 60–90 秒，跨恰好一次公里边界（确定性测试源 `-uiTestLocation`）；无固定 `sleep` 作成功判据，等待均为有界 `waitForExistence`。
- ac-audio-music-and-announcement: 运行中通过 `XCUIApplication(bundleIdentifier:)` 启动系统 Music 并确认在播；容器跑次 JSON 的 `telemetry.announcements[]` 至少 1 条 km 触发（`trigger` 为公里完成、`splitIndex == 1`），且含音频会话 category/mode/options、duck 应用与恢复、`isOtherAudioPlaying` 取值。
- ac-audio-artifacts: 落盘截图序列（至少覆盖起跑、km 边界、结束）、跑次 JSON、`telemetry.announcements[]` 抽取文件；任一项缺失即 FAIL 并写明证据。

### `--phase=background`

- ac-background-no-lock-driving: 脚本与用例不调用锁屏/解锁/密码输入相关 API（不出现 `press(.lock)`、锁屏按钮号、`lockState` 驱动、`devicectl` 解锁动作）；唯一前后台动作是 `press(.home)`；允许只读查询 `lockState` 作为观测，但不得据此宣称锁屏后连续采样。
- ac-background-continuity: 后台 5–6 分钟后机器读回容器内跑次/检查点 JSON（未解锁拿不到最终 archive 时读 checkpoint / harness status，并在报告标注实际来源）：首条样本早于 `press(.home)`、末条晚于后台窗口结束；相邻样本最大空洞 ≤ 60 秒；`activeDuration` 与墙钟时长相对差 ≤ 5%；样本时间序列单调不减。
- ac-background-telemetry: `telemetry.announcements[]` 含 km 触发记录，含 duck 应用与恢复、`isOtherAudioPlaying` 取值；缺任一项即 FAIL 并列证据。
- ac-background-auth-honest: 报告原样记录 `authorizationStatus` / `accuracyAuthorization` / `allowsBackgroundLocationUpdates` 实测值；若为 WhenInUse，必须写明「后台会被系统掐断」并把结论标为 `pending: 待人现场（needs-you 单点）`，不得用「锁屏」话术包装成结论。
- ac-background-gpx-sha256: 导出的 `.gpx` 真实存在且字节数 > 0，实算 `sha256` 为 64 位十六进制并与写入文件的值一致；`trkpt` 数与样本量级一致（差值 ≤ 1），GPX 时间跨度与记录区间绝对差 ≤ 1 秒。
- ac-background-no-unlock-claim: 若设备自然上锁后需人工解锁才能结束保存，脚本不得尝试解锁或伪造结束动作，只记录已持久化产物与 `pending: 待人现场（needs-you 单点）`，不得把 archive 断言写成通过。

### 证据与诚实性（跨阶段）

- ac-evidence-build-identity: 每条真机证据的产物文件名、`report.md` 结论行、`docs/device-assertion-matrix.md` 行、digest 结论四处均带构建身份标注，二选一：**(a) Debug UI-test 构建** 或 **(b) Release 候选包（sha256 `7258…` / commit `8db1a167`）**；同一张结论表出现两种构建必须分行，禁止混写。
- ac-artifacts-four-kinds: 每次真机运行至少产出四类证据——截图序列、容器跑次 JSON、`telemetry.announcements[]`、导出 `.gpx` 与实算 sha256；全部落盘路径打印到 stdout 并写入 `artifacts/device-audit/<UTC>/report.md`，每条证据文件名带上述 (a)/(b) 身份前缀或后缀。
- ac-real-device-run: 至少一次真实设备运行完成（报告含 UDID、iOS 版本、起止时间、构建身份）；若真机连接或设备侧能力缺失导致无法完成，只可在 `report.md` 与交付摘要如实记录卡点并 report owner，禁止编造截图、可及树、telemetry 或 sha256。
- ac-digest-pointer: 断言清单全文摘要、脚本用法、三模式产物路径、构建身份标注、`pending: 待人现场（needs-you 单点）` 清单写入交付摘要（digest）；`artifacts/device-audit/<UTC>/` 与 `docs/device-assertion-matrix.md` 两个路径明确可见。

## 非目标

- 不驱动锁屏/解锁，不在 run 内要求人按任何步骤；不把「锁屏后仍出样本」写成本项结论；解锁与实听只在真正需要时由 needs-you 单点提出，且不进脚本主流程。
- 真机不承载核心闭环以外的语义（Info.plist 声明、单个开关、格式化、状态机、四态、阈值均在单测/集成/模拟器层证明）。
- 不在本项修复任何业务 UI / 定位 / 音频 / 导出缺陷（缺项按缺陷记录，修复另行立项）。
- 不宣称阶段 2/3「真机已验证」；不改 `code_gates`、`.github/workflows`、CI 触发或发布流程。
- 不写「真机已验证公里播报」：Release 候选包上该判点只能人耳，机器证据仅来自 Debug UI-test 构建；把确定性源改为 launch-arg 门控进 Release 只写评估结论与影响面，本项不实施。
- 不写桌面端自研驱动（CDP / 注入 JS / 自拼截屏）；不装 mobilecli agent，不依赖 `mobile_*`；不引入第三方运行时依赖。
- 不做截图视觉回归、不提交模拟器结论、不改 Android 侧。
- 脚本与断言清单未就绪前不排人、不约窗口。

## 实现约束

- **交付顺序与流程门**：先做 `docs/device-assertion-matrix.md`（A，三档标注 + 构建身份），交 PO 转公司确认；**清单未确认前只做清单与静态检查，不跑正式真机场（audio / background）**；确认后再实现脚本与真机跑通（B）；audit 仍是脚本第一产出。digest 记录确认引用或 `pending: 待公司确认`。
- **构建身份（硬要求）**：所有真机证据一律二选一标注，不得混写——**(a) Debug UI-test 构建**（`xcodebuild test` 产出，`-uiTestLocation` 仅 Debug 可用）或 **(b) Release 候选包**（zip sha256 `7258d2e3f7984ef2557278bd1fcdd1eea5db1f34a4d549dc8071d7afcd5b9d8f` / commit `8db1a167`）。产物文件名、`report.md`、清单行、digest 四处都要带；同一结论表混两种构建必须分行。默认分层：audit/background 为 (b)，audio 为 (a)。
- **Release km 播报结论**：`#if DEBUG` 关闭 `-uiTestLocation`，Release 无确定性源，km 边界需真实移动，故 Release 候选包上「公里播报 + 音乐 duck」机器证据取不到；清单标「Debug 可断言 + Release 只能人耳」，对外只写「Debug 构建 + 遥测验证」。把确定性源改为显式 launch-arg 门控进 Release 只写影响面（编译进 Release、包体与误触风险、需产品决策），另立项实施。
- **可写文件集合（超出会被 Delivery 回滚）**：`docs/device-assertion-matrix.md`、`scripts/verify-ios-device-flow.sh`、`ios/PurePaceUITests/`（新增/修改用例）、`ios/project.yml`（仅在需登记新测试文件时）、`docs/` 其它简短说明、`artifacts/device-audit/`。禁止改 `ios/PurePace/**` 业务源码、`ios/RunCore/**`、`ios/Core/**`、`.munk/code-gates.json`、`.github/workflows/**`、既有 `scripts/check-*`。
- **设备与工具链（已核实）**：`xcrun devicectl list devices` 可见 `iPhone 12 Pro Max (iPhone13,4)`，Identifier `40383DE2-0E21-511A-BD19-A6FE5F80A148`，state `available (paired)`；公司给定 UDID `00008101-001C701E0A68001E`，脚本优先 `-destination id=<UDID>` 并允许环境变量覆盖。Xcode 26.3（17C529），`xcodegen` 在 `/opt/homebrew/bin/xcodegen`。
- **候选包位置**：不在本 worktree 内，实际位于 `/Users/zhutao/Library/Application Support/Munk-AI/munk-auto/products/codebase_19e8ad47434ff059/artifacts/candidates/PurePace-Release-0.1.0-20261109T084100Z.zip`（commit `8db1a167`，sha256 见上，407275 B）。脚本用 `--candidate <path>` 或 `artifacts/candidates/PurePace-Release-*.zip` 通配定位；不要把 zip 复制进仓库；不要写死 `0.1.0`（`check-baseline` 的 `ac-no-hardcoded-version` 扫 `scripts/*.sh`）。
- **驱动方式**：只用成熟工具链——`xcrun devicectl` 装/启 + 设备端 `xcodebuild test`（`-destination id=<UDID>`、`-only-testing:PurePaceUITests/DeviceFlowUITests/<case>`、`-resultBundlePath .build/...`），截图/可及树经 XCTest attachment + `xcrun xcresulttool export attachments` 导出；禁止自写桌面驱动。
- **审计对象诚实性**：若 `xcodebuild test` 只能驱动同 commit 的 Release 构建而无法直接驱动 zip 内 `.app`，必须在 `report.md` 写明实际构建与候选 zip 的差异，不得混称；可考虑 `-configuration Release` 复现候选构建配置。
- **配置分层**：`--phase=audit` 与 `--phase=background` 用生产定位源（Release / 不传 `-uiTestLocation`）；`--phase=audio` 才用 DEBUG 确定性源（`-uiTestLocation`，可按需 `-uiTestLocationFast`）。每个模式报告写清构建配置，禁止用 Debug 结果冒充 Release 行为。
- **音乐 App**：系统 Music bundle id 建议 `com.apple.MobileMusic`，以运行期能启动为准；启动失败按 FAIL 记录，不伪造「音乐在播」。
- **容器读回**：用 `xcrun devicectl device copy from` / `device info files` 一类只读能力读取 App 数据容器；若设备已锁读不到最终 archive，按 `ac-background-continuity` 读 checkpoint 并标注来源。
- **工程生成**：新增测试文件后由脚本 `xcodegen generate --spec ios/project.yml --project ios` 生成工程再跑；不手改 `project.pbxproj`，不提交 `.xcodeproj` 变更（不在可写集合）。`ios/project.yml` 的 `CODE_SIGNING_ALLOWED: NO` 基线不动，签名只在 `xcodebuild` 命令行覆盖。
- **证据目录**：`artifacts/device-audit/<UTC 时间戳>/` 存 `report.md`、`*.png`、`*.ax.json`、`run-*.json`、`announcements-*.json`、`*.gpx`、`sha256.txt`；`resultBundle` 等中间产物留 `.build/`（gitignore），只把导出后的证据复制进上述目录。`docs/` 下另加简短说明，列脚本用法、三模式、证据路径与 `pending: 待人现场（needs-you 单点）` 清单。
- **门禁口径**：`check-baseline`、`check-shell-expansion`、`check-ios-scripts`、`check-ios-shell`、`check-ios-release` 保持绿；新增脚本不加入既有 `targets` 列表也可，但须自满足 `--help`/未知参数契约与 shell 展开检查。
- **口径**：报告与脚本不含 git 推送、tag、Release 动作；不写「真机已验证」。
