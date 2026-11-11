# 证据收口：逐屏浅深截图绑 commit + 可及树 + digest 交人评审

## 范围

本项是 WorkSet 第 5 波唯一子项，只产证据，不改产品面。前序已交付：竞品拆解、设计令牌与静态门、六屏重建、交互闭环、identifier 只增不改契约。本项在现有构建上做一次可复核的证据冻结：

1. **12 张真实模拟器截图**：六屏（Run 首屏 / 跑步中 / 结束总结 / History 列表 / History 详情 / Settings）× 浅色 + 深色，逐张由 `xcrun simctl io <udid> screenshot` 在**同一台**模拟器、**同一 OS 版本**上实取，落入 `docs/screenshots/`，逐张记录完整生成命令、sha256、被测构建 commit SHA。
2. **历史数据必须来自真实归档**：History 列表与详情截图中的跑次，须由 App 真实走一次「开始记录 → 跑步中 → 结束 → 保存」产生并落盘到归档，再以真实归档渲染截图。禁止用 `-screenshotHistoryDemo` 演示注入冒充真实界面；如确有使用，必须在 digest 明写并标为「不入发布路径」，且该图不计入 12 张合格证据。
3. **六棵可及树**：用新构建重出六屏可及树（`docs/evidence/a11y/`），逐屏核对主操作 identifier 与可读 label，并给出「一屏一主操作」清单。
4. **AX5 实拍与如实口径**：把系统字号设为最大辅助档（`accessibility-extra-extra-extra-large`）实拍关键屏，证明不截断、不重叠；同时**如实写明** `Typography` 字号阶梯为固定 `Font.system(size:)`、不随 Dynamic Type 缩放，不得宣称无障碍适配已完成。
5. **code_gates 全量跑并记录退出码**；写一份只含实测事实、路径与 sha256 的 digest，随后交公司转人评审。

## 验收

- ac-screenshot-set-12: `docs/screenshots/` 下存在本项产出的 12 张 PNG，覆盖六屏 × 浅/深无缺项；浅色为 `<screen>.png`、深色为 `<screen>-dark.png`，`screen` ∈ {`run-not-started`, `run-running`, `run-finished`, `history-list`, `history-detail`, `settings`}；每张为同一模拟器原生竖屏分辨率（与实取 simctl 截图尺寸逐张相等，无后处理缩放）。
- ac-same-simulator-os: digest 记录唯一 UDID 与唯一 runtime（版本号 + build），12 张截图与 6 棵可及树的采集命令中出现的 UDID 完全一致；证据命令中不出现第二台设备或第二个 runtime。
- ac-real-simctl-capture: 每张截图由 `xcrun simctl io <udid> screenshot` 实取，digest 逐张贴出完整命令（含 `appearance` 设置命令）；截图未经手绘、改色、裁切或再编码（digest 记录该图 sha256 与 `simctl` 输出文件的 sha256 相等，且不存在中间编辑产物）。
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

- 不改业务逻辑、状态机、归档格式、GPX 导出、History / Settings / Run 的交互行为。
- 不改文案键与文案值（`Localizable.xcstrings` / `L10n`）、不改设计令牌取值、不加动效。
- 不改门禁规则、不改 `.munk/code-gates.json` 门列表与命令、不新增 gate id（identifier 契约已由前序项完成）。
- 不做任何分发动作：不做 ASC / ipa / TestFlight / tag / Release。
- 不排真机验收；真机项（锁屏定位、音频实听、授权弹窗观感）继续 `pending: 待人现场`。
- 不手绘、不改色、不裁切、不重排任何截图；不使用第三方素材。
- 不新增 Tab、屏或二级入口；不为截图新增用户可达的演示/示例入口（demo 入口数必须仍为 0 且门禁绿）。
- 不把 History 空态纳入这 12 张（空态由既有 UI 断言覆盖，非本项证据集要求）。
- 不宣称无障碍适配完成，不写发布就绪结论。

## 实现约束

以下是已核实的环境与契约锚点，不是技术方案；具体机制由 Coding 决定，但不得越过上面的反范围。

- **设备与 OS**：本机可用 runtime 为 iOS 17.5 / 18.6 / 26.3。既有 `docs/evidence/a11y/*.txt` 的树为 `393.0 × 852.0`，与 iPhone 16（iOS 18.6，UDID `B3F00298-E08A-41E0-876E-6E8A75C730FD`）一致；沿用该机可保持与既有证据可比。最终以实取 UDID + `simctl list runtimes` 的版本/build 写入 digest 为准，且全部证据只允许一台机、一个 runtime。
- **已核实的 simctl 能力**：`xcrun simctl ui <udid> appearance light|dark`；`xcrun simctl ui <udid> content_size accessibility-extra-extra-extra-large`（该取值在本机 `simctl ui` 帮助中受支持，实设后可用无参调用读回）；`xcrun simctl io <udid> screenshot <path>`。
- **现有截图与登记**：`docs/screenshots/` 现有 6 张（`run-not-started` / `run-running` / `run-running-dark` / `history-empty` / `history-detail` / `settings`）+ `SHA256SUMS`（含逐文件「最近改动 commit」登记区）。`README.md` 内嵌 `run-not-started.png`、`run-running-dark.png`、`history-detail.png`，并写「完整 6 张」。沿用 `<screen>[-dark].png` 命名可让三处内嵌引用继续有效；`history-empty.png` 因历史列表改为真实归档列表而退役，`README.md` 仅需把图集数量与描述改为 12 张（浅/深各六屏），其余章节不动。
- **既有 DEBUG 截图门控**（仅 DEBUG，Release 编译期不可达）：`-screenshotInitialTab run|history|settings`、`-screenshotOpenRunDetail`、`-screenshotHistoryDemo`（**本项禁用**）、`-autoStartRecording`（越过倒计时自动开跑）、`-uiTestLocation`（确定性测试定位源，可产生真实采样距离）、`-uiTestResetArchive`（清空归档）。**截图启动参数不得包含 `-uiTestResetArchive`**，否则会清掉刚产出的真实归档；若使用 `-uiTestLocation` 或 `-autoStartRecording`，必须在 digest 披露实际启动命令。
- **「结束总结」屏**（`finished` 且未保存，主操作 `run.save`、次操作 `run.discard`，见 `ios/PurePace/Run/RunView.swift`）目前没有直达的启动参数，只能经 UI 交互到达。若为到达该屏确需新增 DEBUG-only 截图门控参数，必须在 `#if DEBUG` 内、Release 不可达，并在 digest 披露参数名与「Release 不可达」依据；不得因此新增用户可达入口（demo 入口数 = 0 与 `check-ios-shell` 必须仍绿）。
- **可及树来源**：既有 `ios/PurePaceUITests/RunFlowUITests.swift` 的 `testZhHansCopyDatesAndBottomAnchoredPrimaryAction` 以 `XCTAttachment(string: app.debugDescription)` 产出六棵树，并由 `xcrun xcresulttool export attachments` 导出；`scripts/verify-ios-ui-e2e.sh` 有同类导出范式可参照。可复用/扩展该用例，但树的归属屏必须与本项六屏一一对应。
- **门禁与 UI 腿**：`.munk/code-gates.json` 22 门中与 iOS 相关的 test 门只跑 `test-ios.sh --unit-only`；UI 驱动腿不在门禁内（权威由 `.github/workflows/ios.yml` 承载）。本机 `RunFlowUITests` 历史上出现过信号级崩溃（前序项已记载为环境 flake，stash 回 HEAD 同复现），不要把该崩溃当作本项回归结论；如遇崩溃，如实记录实测输出与重试次数。
- **字号事实**：`ios/PurePace/Design/DesignTokens.swift` 的 `Typography` 全部为 `Font.system(size:weight:)` 固定点值（`sizes` 阶梯 `[11,12,15,20,34,56]`），不随 Dynamic Type 缩放；这正是 digest 必须如实写明的既有口径。
- **演示注入的既有事实**：`ios/PurePace/History/HistoryDemoRecords.swift` 的演示跑次为固定 5.12 km、固定 `startedAt = 1_760_000_000`，仅在 `-screenshotHistoryDemo` 下可见且不落盘。可用作「真实归档 vs 演示注入」的判据：真实跑次的距离/开始时间不应等于该固定值组合，且必须能在容器内找到对应归档文件。
- **提交绑定**：截图文件的「自身最近改动 commit」只会在截图入库后才存在，允许拆成两次提交（先产证据并记录被测构建 SHA，再回填该文件的最近改动 SHA），但两列都必须实取，不许猜。
