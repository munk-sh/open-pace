# Domain: design-draft-v12

## 范围

- 承载「设计先行静态稿」类波次：只产**可用于下一轮实现的颜色与版式决策证据**，不改生产视图、不改 token、不发版。
- 产物两簇：
  - `docs/design-draft-v12/**`——20 张 iPhone 16 模拟器真实渲染 PNG（A 组浅色主色 12 = 6 屏 × 2 套；B 组结束态整屏 4 = 2 版 × 浅/深；C 组丢弃确认弹窗 4 = 2 版 × 浅/深）+ `README.md`（一页对照）/ `manifest.md`（逐张设备·倍率·像素）/ `heights.tsv`（运行期实测高度）/ `token-diff.md`（建议值）/ `SHA256SUMS` / `render.log` / `changed-files.txt` / `commit.txt`。
  - debug-only 稿件：`ios/PurePace/DesignDraft/**`（整目录 `#if DEBUG` 包裹）、`ios/PurePace/PurePaceApp.swift` 内唯一 `#if DEBUG` 启动分支（`-designDraftV12 <variant>`）、`scripts/capture-design-draft-v12.sh`（可复跑生成器，支持 `--only a|b|c` / `--skip-build` / `--help`）。
- 与相邻域分工：token 真源与对比度矩阵归 `design-palette-a` / `design-token-gates`；结束态垂直预算与压缩策略的生产落地归 `ios-evidence-freeze` / `ios-ui-design`；丢弃 sheet 的交互与 identifier 归 `ios-run-interaction`。本域只裁决「选哪套颜色 / 哪版版式」，不落生产改动。
- 本域是决策证据域，非长期代码域：下一轮实现条目消费其结论后，改动落在各实现域，本域不再重复记账。

## 验收

- ac-20-png：`docs/design-draft-v12/` 下恰有 20 张 PNG，分解 A=12（6 屏 × 2 套）、B=4（2 版 × 2 外观）、C=4（2 版 × 2 外观）；文件名显式含套/版号与 light/dark 标识（A 组为浅色可省略 light 但不得含 dark）。
- ac-device-size：每张 PNG 像素尺寸 = 逻辑 393×852 pt × 记录倍率，且 `manifest.md` 逐张记录设备型号、逻辑尺寸、倍率与像素尺寸并自洽。
- ac-real-render：20 张全部由 iOS 模拟器真实渲染产生，入口为 debug-only 变体（`#if DEBUG` + 显式启动参数，或独立 design-draft 入口）；仓库内提供可复跑脚本路径与运行日志；禁止手绘、取色近似、设计工具导出。
- ac-sha256：`SHA256SUMS` 覆盖 20 张 PNG，`shasum -a 256 -c docs/design-draft-v12/SHA256SUMS` 全部 `OK`。
- ac-commit-bound：证据绑定 commit；`commit.txt`（或 README）记录生成时 head sha，且该 sha 为包含全部交付物的提交。
- ac-a1-accent-orange：A1 的 accent 色相 H ∈ [20°, 35°]（HSL，含端点）、饱和度足够（不出现砖红/棕），README 给出 accent 与 onAccent 的 HSL 三元组实测值。
- ac-a2-accent-orange：A2 同上，并证明该值在 diff 中仍是橙而非压暗砖红。
- ac-contrast-thresholds：两套均满足 accent vs 浅色页面背景（light `background` `#FAFAF9`）≥3:1（非文本 UI 组件）、onAccent vs accent ≥4.5:1（按钮文字）；README 写明 WCAG 2.x 公式 `(L1+0.05)/(L2+0.05)`、相对亮度分段线性公式，阈值为**先定后测**并写入代码注释或 README 的推导依据。
- ac-a-only-color-diff：A 组同屏两张候选之间，除主按钮 accent/onAccent 外其余 token、字号、间距、布局完全一致（同一渲染路径换色），README 说明该对照口径。
- ac-a-six-screens：A 组覆盖 run-not-started / run-running / run-finished / history-list / history-detail / settings，每屏每套各 1 张。
- ac-b1-map-hero：B1 地图区块实测高度 ≥ 393×852 × 40%（≥340.8pt），且不靠压缩字号实现。
- ac-b2-map-collapsible：B2 地图为中等高度（低于 B1、明显高于现网 96pt 压缩档），摘要区可折叠，折叠/展开态至少各有一张证据或 README 说明折叠形态。
- ac-b-real-data：B 组浅/深 4 张使用同一组真实数据 1.20 km / 00:22，与现有截图同源 fixture，不得手绘或取色近似。
- ac-b-splits：B 组每版均含分段明细；另需证明无分段时给出明确替代信息（截图或 README 说明），不得只剩空卡。
- ac-b-primary-action：B 组每版主操作固定在底部安全区上方，截图中不与内容重叠/被裁切。
- ac-b-height-table：README（或 B 专门一节）给出每版各区块实测高度表，合计 ≤ 可用内容高，证明 393×852 放得下且不依赖「压地图到下限」或「压字号」兜底。
- ac-b-no-warning-row：B 组权限提示不再整行占高（改 inline 小条或收进设置提示），截图中不出现整行宽权限条挤压地图。
- ac-c-primary-secondary：C 两版均主次分明，禁止两枚等权描边按钮并排；破坏性动作为实心 danger 或等价强形态，非破坏性动作为次按钮。
- ac-c-sheet-fit：C 两版 sheet 高度自适应内容，无大段空白（sheet 顶部到首行内容间距不超过常规内边距，且无固定 medium 高度留白）。
- ac-c-danger-separation：danger 与 accent 不同屏同形状并列——弹窗内不出现 accent 填充按钮与 danger 填充按钮同形状并列。
- ac-readme-one-page：`README.md` 为一页对照说明，含每套/每版一行结论、关键尺寸与对比度表、以及「为什么不做压暗换对比度 / 压地图换不溢出」的说明。
- ac-token-diff-no-apply：`token-diff.md` 只写建议值（accent/onAccent，及 warning/danger 是否需按 H/S/L 分离重算的结论），且 `ios/PurePace/Design/DesignTokens.swift` 零改动。
- ac-zero-production-diff：相对基线，改动清单只含 `docs/design-draft-v12/**` 与 debug-only 稿件文件（`#if DEBUG` 新文件或独立入口）；`DesignTokens.swift`、任何生产视图、`RunFinishedSummaryLayoutPolicy.swift` 零改动，并给 diff 文件清单证据。
- ac-no-identifier-drift：不修改既有 identifier 冻结集；新增 debug 入口不读写既有 identifier，且不被加入 UI 测试枚举。
- ac-no-version-signing：不修改 `VERSION`、`Info.plist`、签名配置；不 push 远端。
- ac-gates-untouched：不修改 `.munk/code-gates.json`、不提高 `IOS_XCODEBUILD_TIMEOUT`、不加 `continue-on-error`、不删测试腿、不新增权威 UI 测试套件（若确需新增 UITest 文件，同 commit 同步 `scripts/test-ios.sh` 枚举与 `scripts/check-ios-shell.sh` 自检夹具并在证据中注明）。
- ac-budget：全程 ≤8M token / ≤90 分钟墙钟；到点停手并交「已做 / 未做 / 未闭合点」回执，不降标准、不手绘兜底、不续命。

## 非目标

- 不改生产代码、不落地 token、不发版、不改版本号、不打 tag、不 push 远端。
- 不做真机验收、不做分发、不做动画/转场实现。
- 不重构 `RunFinishedSummaryLayoutPolicy` 的既有压缩逻辑，只出替代版式静态稿。
- 不改 warning / danger 的现网值（仅 token-diff 给建议）。
- 不新增/调整门禁、超时、`continue-on-error`；不新增 `docs/verification-matrix.md` 行（设计稿不涉及系统接缝）。
- 不新增权威 UI 测试套件、不改既有 identifier 冻结集。

## 实现约束

- 根因锚点（已读码定位）：`DesignTokens.swift` 的 light `accent = #B4400B` 为压暗砖红（H 18.8°），旧「36 hex 逐键照抄、禁止微调」口径作废，唯一硬约束是「浅色 accent 仍是橙（H 20–35°、S 足够）且实测对比度达标」，允许浅/深用不同 S/L，onAccent 一并重配；`RunFinishedSummaryLayoutPolicy.uncompressedFinishedContentHeight = 688` 超出 iPhone 16 可用 612.3pt，导致标准字号恒走压缩档并把地图压到 96pt 兜底；`RunView.discardConfirmationSheet` 用 `.presentationDetents([.medium])` 固定高度 + 两枚等权描边按钮。
- 证据目录固定 `docs/design-draft-v12/`，PNG 直接落该目录；命名约定 A：`a1|a2-<screen>.png`，B：`b<1|2>-finished-<light|dark>.png`，C：`c<1|2>-discard-<light|dark>.png`。
- 只有 debug-only 路径允许进入生产工程：`#if DEBUG` + 显式启动参数；Release 行为零变化；能不走测试路径就不新增 UITest 套件，避免扰动权威腿。
- 渲染口径：iPhone 16 模拟器、逻辑 393×852 pt、@3x；浅/深用 `simctl ui <udid> appearance light|dark` 切换；截图用 `xcrun simctl io screenshot`，不复用 UI 测试截图通道。
- 真实数据：复用既有 `-uiTestLocation` 确定性定位与 fixture（1.20 km / 00:22，与 `docs/screenshots/run-finished*.png` 同源），新 debug 入口不得读写既有 identifier。
- 对比度：用与 `ContrastPolicy` 一致的 WCAG 2.x 公式重算并落盘，阈值先定后测、推导写进代码注释或 README；不得改 `ContrastPolicy.swift` 的 `pairMatrix` 生产值。
- 高度表以模拟器运行期实测（AX frame / 探针输出）为准，禁止用设计工具估算冒充实测。
- 提交纪律：`git add` 仅交付物与 debug-only 稿件文件，commit 一次并记录 head sha；`git diff --name-only <base>..HEAD` 清单作为 ac-zero-production-diff 证据落盘。本轮 hardening 后另注：后续轮次如需修文档/脚本，须在 `commit.txt` 里显式声明「哪些提交只改文档、不影响 20 张图与 SHA256SUMS 绑定」。

## 最近交付证明

- workItemId: wi_intake_e3e7d100d6da9247（2026-11-12，pass）
- 交付：`docs/design-draft-v12/` 20 张 PNG（A=12 / B=4 / C=4，393×852 pt @3x = 1179×2556 px）+ README 一页对照 + `manifest.md` / `heights.tsv` / `token-diff.md` / `SHA256SUMS` / `render.log` / `changed-files.txt` / `commit.txt`；debug-only 稿件 `ios/PurePace/DesignDraft/**` 5 文件（整目录 `#if DEBUG`）、`PurePaceApp.swift` 单一 `#if DEBUG` 入口分支、`scripts/capture-design-draft-v12.sh`。
- 结论（供下一轮实现）：A 组首选 A1（accent `#E85D04` / onAccent `#1F1200`，3.35:1 与 5.24:1，H 23.4°），A2（`#BE4E05` / `#FFFFFF`，4.70:1 / 4.90:1）为保守备选；现网 `#B4400B` 实测 H 18.8° 即砖红根因。B 组推荐先落 B1（地图 360pt = 42.3% 屏高，内容合计 667.3 ≤ 可用 691pt，权限提示改 inline 23.7pt 胶囊，主操作固定底部 68pt 条），B2（地图 220pt、折叠摘要 60/171pt、合计 652.3pt）作小屏备选；两版均不压字号、不动 96pt 兜底。C 组 C1（210pt sheet、danger 实心 + 无描边次操作）主次最强，C2（143.7pt 图标式）最紧凑。
- token diff 草案要点：`warning` 不必重算（与两套候选 ΔH ≥ 26.5°）；`danger` 选 A1 可保持 `#660D09`，选 A2 建议压到 `#4E0A07` 拉开明度；dark accent 本轮未实测，建议保持不动。落地时须同步 `DesignTokens.swift` 的 danger 语义注释或补 `onDanger` 对比度对。
- 偏离与有意未做：①A 组截图中地图折线仍取生产 `accent`（`TrackMapView` 无注入参数，本轮不改生产视图），已在 README 标注为已知口径差异，非缺陷；②无分段替代信息未单独渲染 PNG，以 README 的文案 key（`run.finished.splits.empty`）与卡壳规则说明为准；③B2 展开态以 `heights.tsv` 量测变体记录，不作交付 PNG；④dark accent 与 `onDanger` 只给建议值，未实测。
- 验证：`code_gates` 22 门 attempt 001 全绿；`shasum -a 256 -c docs/design-draft-v12/SHA256SUMS` 20/20 `OK`；`git diff --name-only main..HEAD` 35 文件全部落在 `docs/design-draft-v12/**`、`ios/PurePace/DesignDraft/**`、`PurePaceApp.swift`（仅 `#if DEBUG` 分支）与 `scripts/capture-design-draft-v12.sh`，`DesignTokens.swift` / `RunFinishedSummaryLayoutPolicy.swift` / `ios/PurePaceUITests/**` / `scripts/test-ios.sh` / `.munk/code-gates.json` 零改动。
