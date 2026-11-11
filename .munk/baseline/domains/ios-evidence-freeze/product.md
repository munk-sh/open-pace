# Domain: ios-evidence-freeze

PurePace iOS 证据冻结域：在已交付的六屏 UI 之上，产出一套可复核、可复算的模拟器证据——12 张浅/深真实 `simctl` 截图（`docs/screenshots/`）、六棵新构建可及树（`docs/evidence/a11y/`）、AX5 最大辅助字号实拍与 frame 实测（`docs/evidence/evidence-freeze/ax5/`），以及只含实测事实、路径、命令、sha256 与退出码的 digest（`docs/evidence/evidence-freeze/digest.md`）。本域只产证据，不改产品面：业务逻辑、文案键值、`DesignTokens` 取值、`.munk/code-gates.json` 门列表均为只读。证据采集入口 `scripts/capture-ios-screenshots.sh --stage all`，取证用例 `ios/PurePaceUITests/EvidenceCaptureUITests.swift`。

## 范围

- `docs/screenshots/`：六屏（`run-not-started` / `run-running` / `run-finished` / `history-list` / `history-detail` / `settings`）× 浅/深 = 12 张 PNG，命名 `<screen>.png` 与 `<screen>-dark.png`，同一台模拟器原生竖屏分辨率；`history-empty.png` 退役（历史列表改真实归档列表），`SHA256SUMS` 为逐文件 sha256 + 最近改动 commit 登记。
- `docs/evidence/a11y/`：恰六棵与六屏一一对应的可及树（`01-run-not-started` / `02-run-running` / `03-run-finished` / `04-history-list` / `05-history-detail` / `06-settings`），由 `XCTAttachment(string: app.debugDescription)` 产出并 `xcrun xcresulttool export attachments` 导出；不对应六屏的旧树（`03-history-empty` / `06-tabs`）不在该目录。
- `docs/evidence/evidence-freeze/ax5/`：`content_size accessibility-extra-extra-extra-large` 档下 4 张关键屏实拍（Run 首屏 / 结束总结 / History 详情 / Settings）与同档实测树。
- `docs/evidence/evidence-freeze/digest.md`：预算回执、环境与构建、逐张生成命令、History 归档来源、六树与「一屏一主操作」清单、AX5 frame 实测、Dynamic Type 既有口径、22 门退出码、commit 绑定、改动范围。
- `scripts/capture-ios-screenshots.sh`：唯一采集入口（`--stage all|shots|trees|ax5`），只用 `xcrun simctl` / `xcodebuild`，不做后处理。
- `ios/PurePaceUITests/EvidenceCaptureUITests.swift`：取证用例（真实记录链路造归档、六树导出、AX5 布局实测、主操作记录）。
- DEBUG-only 截图门控：`ios/PurePace/Run/RunLaunchArguments.swift` 的 `-screenshotRunFinished`（配合 `-autoStartRecording`，真实采样约 30s 后结束到待保存总结态、不落盘、`#if DEBUG` 内）与既有 `-screenshotInitialTab` / `-screenshotOpenRunDetail` / `-autoStartRecording` / `-uiTestLocation` / `-uiTestResetArchive`；`-screenshotHistoryDemo` 本域禁用。
- `README.md`：仅图集数量与描述（「完整 12 张：六屏浅色与深色」），其余章节不动。

## 验收

- ac-screenshot-set-12: `docs/screenshots/` 存在本项产出的 12 张 PNG，覆盖六屏 × 浅/深无缺项；浅色 `<screen>.png`、深色 `<screen>-dark.png`，`screen` ∈ {`run-not-started`, `run-running`, `run-finished`, `history-list`, `history-detail`, `settings`}；每张为同一模拟器原生竖屏分辨率（与实取 `simctl` 截图尺寸逐张相等，无后处理缩放）。
- ac-same-simulator-os: digest 记录唯一 UDID 与唯一 runtime（版本号 + build），12 张截图与 6 棵可及树的采集命令中 UDID 完全一致；证据命令中不出现第二台设备或第二个 runtime。
- ac-real-simctl-capture: 每张截图由 `xcrun simctl io <udid> screenshot` 实取，digest 逐张贴出完整命令（含 `appearance` 设置命令）；截图未经手绘、改色、裁切或再编码（digest 记录该图 sha256 与 `simctl` 输出文件 sha256 相等，且不存在中间编辑产物）。
- ac-history-from-real-archive: History 列表与详情的截图和可及树显示的跑次，来自本机一次真实记录链路产生的归档——digest 给出容器内归档文件路径与 mtime，并给出该归档记录的开始时间/距离，与列表、详情中的可见值逐项相等；证据生成命令中 `-screenshotHistoryDemo` 出现次数为 0（贴出命令原文与 grep 结果）。
- ac-a11y-trees-six: `docs/evidence/a11y/` 下恰有六棵对应六屏的新构建可及树（`01-run-not-started` / `02-run-running` / `03-run-finished` / `04-history-list` / `05-history-detail` / `06-settings`），每棵包含该屏主操作的 identifier 与非空 label；旧集合中不对应六屏的树（`03-history-empty` / `06-tabs`）从该目录移除。
- ac-one-primary-per-screen: digest 的「一屏一主操作」清单恰六行，每屏一行，列该屏主操作的 identifier 与可读 label，两者均非空；identifier 依次为 `run.start`（Run 首屏）/ `run.pause`（跑步中）/ `run.save`（结束总结）/ `history.row`（History 列表首行）/ `runDetail.export`（History 详情）/ `settings.announcementToggle`（Settings）；若新构建实测与此不符，按实测值记录并列明偏差，不得改写期望值或补造标识。
- ac-ax5-capture-and-fit: 最大辅助字号档（`xcrun simctl ui <udid> content_size accessibility-extra-extra-extra-large`）下实拍至少 4 张关键屏（Run 首屏 / 结束总结 / History 详情 / Settings），digest 记录该命令与设置前后 `content_size` 实读值；同档可及树中每个元素 frame 均落在屏内，主操作 frame 与其它内容 frame 无相交，digest 贴出实测 frame 数值与判定结果。
- ac-dynamic-type-limitation-disclosed: digest 明写「`DesignTokens.Typography` 全部为固定 `Font.system(size:)`，字号阶梯不随 Dynamic Type 缩放」这一既有口径，并说明 AX5 证据只能证明固定字号布局在最大系统字号档不截断不重叠；全文不出现「无障碍适配已完成 / 达标」之类结论。
- ac-sha256-manifest: `docs/screenshots/SHA256SUMS` 覆盖目录内全部 PNG（含 12 张新图），`shasum -a 256 -c docs/screenshots/SHA256SUMS` 退出码为 0；digest 中的 sha256 表与该输出逐行一致（无一处冲突或占位值）。
- ac-commit-binding: digest 记录被测构建 commit SHA（`git rev-parse HEAD` 实取，与截图构建对应）与每个证据文件的最近改动 commit 全 SHA（`git log --format=%H -1 -- <file>` 实取）；不得出现猜测值或沿用旧值；若「被测构建 SHA」与「证据入库 SHA」不同，须分列标注成因。
- ac-gates-green: `.munk/code-gates.json` 门列表不变（22 门），digest 逐门记录 id 与真实退出码，全部为 0。
- ac-no-scope-creep: 本项改动路径 ⊆ {`docs/screenshots/**`, `docs/evidence/a11y/**`, `docs/evidence/evidence-freeze/**`, `README.md`（仅图集数量与描述）, `ios/PurePaceUITests/**`, DEBUG-only 截图门控相关视图文件, 新增的截图脚本 `scripts/**`}；不含业务逻辑、`L10n` 键值、`DesignTokens` 取值、`.munk/code-gates.json` 的任何变更。
- ac-claims-discipline: digest 只写实测事实、路径、命令、sha256 与退出码，不含「达标 / 可以给用户用 / 发布就绪」等自判，也不含真机验收与分发动作（ASC / ipa / TestFlight / tag / Release）。
- ac-budget-receipt: 开工首条回执写明预算（预计耗时与门禁轮次上限）与期望收口时刻；超预算即停手并在回执写明已完成的证据与缺口，不靠长会话补绿。

## 非目标

- 不改业务逻辑、状态机、归档格式、GPX 导出、History / Settings / Run 的交互行为；不改门禁规则与 `.munk/code-gates.json` 门列表/命令，不新增 gate id。
- 不改文案键与文案值（`Localizable.xcstrings` / `L10n`）、不改设计令牌取值、不加动效。
- 不做任何分发动作（ASC / ipa / TestFlight / tag / Release）；不排真机验收，真机项（锁屏定位、音频实听、授权弹窗观感）继续 `pending: 待人现场`。
- 不手绘、不改色、不裁切、不重排任何截图；不使用第三方素材。
- 不新增 Tab、屏或二级入口；不为截图新增用户可达的演示/示例入口（demo 入口数仍为 0，Release 不可达）。
- 不把 History 空态纳入这 12 张（空态由既有 UI 断言覆盖）。
- 不宣称无障碍适配完成，不写发布就绪结论。

## 实现约束

- 设备与 OS：一律沿用 iPhone 16 / iOS 18.6（UDID `B3F00298-E08A-41E0-876E-6E8A75C730FD`，runtime `18.6` build `22G86`）以与既有 `393.0 × 852.0` 可及树可比；全部证据只允许一台机、一个 runtime，最终以实取 UDID 与 `simctl list runtimes` 写入 digest 为准。
- 采集能力只用系统 `simctl`：`xcrun simctl ui <udid> appearance light|dark`、`xcrun simctl ui <udid> content_size <档位>`、`xcrun simctl io <udid> screenshot <path>`；构建产物来自 `xcodebuild build-for-testing ... -derivedDataPath .build/ios`，采集日志与 xcresult 落 `.build/evidence/`（不入库）。
- 截图启动参数不得包含 `-uiTestResetArchive`（会清掉真实归档）；使用 `-autoStartRecording` / `-uiTestLocation` / `-screenshotRunFinished` 必须在 digest 披露实际启动命令。新增截图门控只能在 `#if DEBUG` 内且 Release 不可达。
- 真实归档优先：History 列表/详情必须由 App 真实「开始记录 → 跑步中 → 结束 → 保存」产生并落盘，再以真实归档渲染；`-screenshotHistoryDemo`（固定 5.12 km / `startedAt = 1_760_000_000`、不落盘）禁用，其固定值组合是「演示注入 vs 真实归档」判据。
- 可及树来源：复用 `ios/PurePaceUITests/RunFlowUITests.swift` 的 `XCTAttachment(string: app.debugDescription)` + `xcrun xcresulttool export attachments` 范式（`scripts/verify-ios-ui-e2e.sh` 同类），树的归属屏必须与六屏一一对应。
- 门禁与 UI 腿：`.munk/code-gates.json` 22 门保持不变，iOS 相关 test 门只跑 `test-ios.sh --unit-only`；UI 驱动腿权威在 `.github/workflows/ios.yml`。`RunFlowUITests` 历史 signal-kill 崩溃属环境 flake（stash 回 HEAD 同复现），不得当作回归结论，遇崩溃如实记录实测输出与重试次数。
- 字号事实：`DesignTokens.Typography` 全部为固定 `Font.system(size:weight:)`，`sizes = [11, 12, 15, 20, 34, 56]`，不随 Dynamic Type 缩放——digest 必须如实写明，AX5 只证明固定字号布局不截断不重叠。
- 提交绑定可拆两次提交（先产证据记被测构建 SHA，再回填证据文件最近改动 SHA），但两列都必须实取，不许猜；文件无法内嵌承载自身 commit SHA，digest 自身以其最近改动 commit 单独列出。

## 最近交付证明

- workItemId: wi_ws_40dd046fe0d3b1ec（2026-11-11，pass）
- 交付：证据冻结收口。`docs/screenshots/` 12 张 1179×2556 逐张由 `xcrun simctl io` 实取（六屏 × 浅/深，`history-empty.png` 退役，`SHA256SUMS` 逐文件 sha256 + 最近改动 commit 重建）；`docs/evidence/a11y/` 恰六棵并与六屏一一对应，主操作实测 `run.start` / `run.pause` / `run.save` / `history.row` / `runDetail.export` / `settings.announcementToggle` 与期望一致、无偏差；AX5 档 4 张实拍 + frame 实测 `outOfBounds=0 overlaps=0`，同档树 4 棵入库；`docs/evidence/evidence-freeze/digest.md` 记录唯一 UDID/runtime、逐张命令、真实归档路径与 mtime、22 门退出码、commit 绑定；`README.md` 仅改图集数量为 12 张；新增 `scripts/capture-ios-screenshots.sh` 与 DEBUG-only `-screenshotRunFinished`（Release 不可达，digest 披露）。
- 判定与证据：22 门 attempt 001 全绿；`shasum -a 256 -c docs/screenshots/SHA256SUMS` 退出码 0；被测构建 SHA `e4f2fc1` 与证据入库 SHA `067b4ff` 分列（截图来自前者构建、证据文件在其后入库）；History 跑次来自真实归档（非 5.12 km / `1_760_000_000` 演示组合），`-screenshotHistoryDemo` 出现次数 0。
- 偏离与边界：首轮 `check-shell-expansion` 因脚本裸变量紧跟中文退出码 1，已修复并复跑全绿（门禁 2 轮，未超预算）；未做真机验收（`pending: 待人现场`）、未做任何分发动作；digest 不含「无障碍达标 / 发布就绪」结论。
