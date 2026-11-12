# V1.2 界面返工：设计先行静态稿（浅色主色 / 结束态整屏 / 丢弃确认弹窗）

## Scope

V1.2 被评为不达标，按未完成返工。本轮**只做设计先行静态稿，不改生产代码**，产出可用于下一轮实现的颜色与版式决策证据：

1. **A. 浅色主色 2 套候选**（A1「饱和橙底 + 深字」、A2「深橙底 + 白字」），仅比颜色；覆盖 6 屏（run-not-started / run-running / run-finished / history-list / history-detail / settings）浅色主按钮真实渲染，每套 6 张 = 12 张。
2. **B. 结束态整屏稿 2 版**（B1 地图 hero ≥40% 屏高；B2 上地图中等高度 + 可折叠摘要），浅/深各 1 张 = 4 张；同源真实数据 1.20km / 00:22，含分段明细与无分段替代信息，主操作固定底部安全区上方，给区块实测高度表。
3. **C. 丢弃确认弹窗 2 版**，主次分明、破坏性动作形态明确、sheet 高度自适应内容，浅/深各 1 张 = 4 张。
4. **D. 对照说明** `docs/design-draft-v12/README.md`（一页：结论 / 关键尺寸 / 对比度表 / 反直觉做法说明）。
5. **E. token diff 草案** `docs/design-draft-v12/token-diff.md`（只写建议值，含 onAccent 与 warning/danger 是否需重算，不应用到 `DesignTokens.swift`）。

合计 20 张 PNG（A 12 + B 4 + C 4），均须为 393×852 pt 的模拟器真实渲染，绑 commit 且 `shasum -a 256 -c` 通过。

## Acceptance Criteria

### 交付物与体量

- ac-20-png: `docs/design-draft-v12/` 下恰有 20 张 PNG，且分解为 A=12（6 屏 × 2 套）、B=4（2 版 × 2 外观）、C=4（2 版 × 2 外观）；文件名显式含套/版号与 light/dark 标识（A 组为浅色，可省略 light 但不得含 dark）。
- ac-device-size: 每张 PNG 的像素尺寸满足「逻辑 393×852 pt × 记录倍率」，并在 `docs/design-draft-v12/manifest.md`（或 README 内表格）逐张记录设备型号、逻辑尺寸 393×852、缩放倍率与像素尺寸；倍率与像素尺寸自洽。
- ac-real-render: 20 张全部由 iOS 模拟器真实渲染产生，入口为 debug-only 变体（`#if DEBUG` + 显式启动参数，或独立 design-draft 入口 + 启动参数）；仓库内提供可复跑生成脚本路径与运行日志，禁止手绘、取色近似或设计工具导出。
- ac-sha256: `docs/design-draft-v12/SHA256SUMS` 覆盖 20 张 PNG，`shasum -a 256 -c docs/design-draft-v12/SHA256SUMS` 返回全部 OK。
- ac-commit-bound: 证据绑定 commit，`docs/design-draft-v12/commit.txt`（或 README 内）记录生成时的 head sha，且该 sha 为包含全部交付物的提交。

### A. 浅色主色

- ac-a1-accent-orange: A1 的 accent 色相 H 落在 20–35°（HSL，含端点），饱和度足够（不出现砖红/棕），并在 README 给出 accent 与 onAccent 的 HSL 三元组实测值。
- ac-a2-accent-orange: A2 的 accent 色相 H 落在 20–35°（HSL，含端点），git diff 中该值仍是橙且非压暗砖红，并给出 HSL 三元组。
- ac-contrast-thresholds: 两套均满足 accent vs 浅色页面背景（`background` light token `#FAFAF9`）≥3:1（非文本 UI 组件），onAccent vs accent ≥4.5:1（按钮文字）；README 写明 WCAG 2.x 公式 `(L1+0.05)/(L2+0.05)`、相对亮度分段线性公式、阈值为**先定后测**并写入代码/注释的推导依据。
- ac-a-only-color-diff: A 组 6 屏两张候选之间，除主按钮 accent/onAccent 外其余 token、字号、间距、布局完全一致（同一渲染路径换色），README 说明该对照口径。
- ac-a-six-screens: A 组覆盖 run-not-started / run-running / run-finished / history-list / history-detail / settings 六屏，每屏每套各 1 张。

### B. 结束态整屏

- ac-b1-map-hero: B1 的地图区块实测高度 ≥ 393×852 的 40%（即 ≥340.8pt），且不靠压缩字号实现。
- ac-b2-map-collapsible: B2 地图为中等高度（低于 B1、明显高于现网 96pt 压缩档）且摘要区可折叠，折叠态与展开态至少各有一张证据或 README 说明折叠交互形态。
- ac-b-real-data: B 组浅/深 4 张全部使用同一组真实数据 1.20km / 00:22，来源与现有截图同源 fixture，不得手绘或取色近似。
- ac-b-splits: B 组每版均含分段明细；另需证明无分段时给出明确替代信息（截图或 README 说明），不得只剩空卡。
- ac-b-primary-action: B 组每版主操作固定在底部安全区上方，且截图中不与内容重叠/被裁切。
- ac-b-height-table: README（或 B 专门一节）给出每版各区块实测高度表，合计 ≤ 可用内容高，证明 393×852 放得下且不依赖「压地图到下限」或「压字号」兜底。
- ac-b-no-warning-row: B 组权限提示不再整行占高，改为 inline 小条或收进设置提示；截图中不再出现整行宽权限条挤压地图。

### C. 丢弃确认弹窗

- ac-c-primary-secondary: C 两版均为「主次分明」，禁止两枚等权描边按钮并排；破坏性动作有明确形态（实心 danger 或等价强形态），非破坏性动作为次按钮。
- ac-c-sheet-fit: C 两版 sheet 高度自适应内容，无大段空白（截图中 sheet 顶部到首行内容间距不超过常规内边距，且无固定 medium 高度留白）。
- ac-c-danger-separation: danger 与 accent 不同屏同形状并列：弹窗内不出现 accent 填充按钮与 danger 填充按钮同形状并列。

### D / E 文档

- ac-readme-one-page: `docs/design-draft-v12/README.md` 为一页对照说明，含每套/每版一行结论、关键尺寸与对比度表、以及「为什么不做压暗换对比度 / 压地图换不溢出」的说明。
- ac-token-diff-no-apply: `docs/design-draft-v12/token-diff.md` 只写建议值（accent/onAccent，及 warning/danger 是否需按 H/S/L 分离重算的结论），且 `ios/PurePace/Design/DesignTokens.swift` 零改动。

### 生产代码与门禁边界

- ac-zero-production-diff: 相对基线，改动文件清单只含 `docs/design-draft-v12/**` 与 debug-only 稿件文件（`#if DEBUG` 包裹的新文件或独立 design-draft 入口）；`ios/PurePace/Design/DesignTokens.swift`、任何生产视图、`RunFinishedSummaryLayoutPolicy.swift` 等生产文件零改动，并提供 diff 文件清单证据。
- ac-no-identifier-drift: 不修改既有 identifier 冻结集；新增 debug 入口不读写既有 identifier，且不被加入 UI 测试枚举。
- ac-no-version-signing: 不修改 `VERSION`、`Info.plist`、签名配置；不 push 远端。
- ac-gates-untouched: 不修改 `.munk/code-gates.json`、不提高 `IOS_XCODEBUILD_TIMEOUT`、不加 `continue-on-error`、不删测试腿、不新增权威 UI 测试套件（若确需新增 `ios/PurePaceUITests/*UITests.swift`，同 commit 同步 `scripts/test-ios.sh` 枚举与 `scripts/check-ios-shell.sh` 自检夹具，并在证据中注明）。

### 预算与收口

- ac-budget: 全程 ≤8M token / ≤90 分钟墙钟；到点即停手，交「已做 / 未做 / 未闭合点」回执，不降标准、不手绘兜底、不续命。

## Non-Goals

- 不改生产代码、不落地 token、不发版、不改版本号、不打 tag、不 push 远端。
- 不做真机验收、不做分发、不做动画/转场实现。
- 不重构 `RunFinishedSummaryLayoutPolicy` 的既有压缩逻辑，只出替代版式静态稿。
- 不改 warning/danger 的现网值（仅 token-diff 里给建议）。
- 不新增/调整门禁、超时、`continue-on-error`。
- 不新增 `docs/verification-matrix.md` 行（设计稿不涉及系统接缝）。

## Implementation Constraints

### 根因锚点（已由公司读码定位，非猜测）

- `ios/PurePace/Design/DesignTokens.swift:60` 附近：`accent` light = `#B4400B`（压暗砖红棕），dark = `#FF9A5C`。旧口径「36 hex 逐键照抄、禁止自行微调」**作废**；唯一硬约束：浅色 accent 必须仍是橙（H 20–35°、饱和度足够），以实测对比度达标为前提，允许浅/深用不同 S/L，`onAccent` 一并重配。
- `ios/PurePace/Design/RunFinishedSummaryLayoutPolicy.swift`：`uncompressedFinishedContentHeight = 688`，iPhone 16 可用内容区实测 612.3pt，故标准字号恒走压缩档，地图被压到 `finishedMapFloor = 96pt`（3 × Spacing.xl）；权限提示条整行占高。根因是整屏垂直预算撑不住并用压地图兜底，不是单点文字挤压。
- `ios/PurePace/Run/RunView.swift:607` 起 `discardConfirmationSheet`，`:625` `.presentationDetents([.medium])`：底部贴底固定高度 sheet，上方大段空白，两枚等权描边按钮、无主次。

### 交付目录与命名

- 证据目录固定：`docs/design-draft-v12/`（绝对路径以运行 worktree 为准），PNG 直接放该目录（可按需子目录，但 manifest 必须逐张给出相对路径）。
- 建议命名（最终名以 README 表格为准，但必须能一眼分辨套/版号与外观）：
  - A：`a1-<screen>.png` / `a2-<screen>.png`（screen ∈ run-not-started / run-running / run-finished / history-list / history-detail / settings）
  - B：`b1-finished-light.png` / `b1-finished-dark.png` / `b2-finished-light.png` / `b2-finished-dark.png`
  - C：`c1-discard-light.png` / `c1-discard-dark.png` / `c2-discard-light.png` / `c2-discard-dark.png`
- 必备附属文件：`SHA256SUMS`、`manifest.md`（或 README 表格）、运行日志（如 `render.log`）、生成脚本路径、`commit.txt`。

### 渲染实现约束

- 只允许 debug-only 路径：`#if DEBUG` + 显式启动参数（如 `-designDraftV12`）或独立 design-draft 入口；Release 行为零变化，生产视图文件不改。
- 截图方式任选其一旦需可复跑：`xcrun simctl io <udid> screenshot` 或 XCUITest 截图；能不走测试路径就不新增 UITest 套件，避免扰动权威腿。
- 设备/尺寸：iPhone 16 模拟器、逻辑 393×852 pt；浅/深通过 `simctl ui <udid> appearance light|dark` 切换。
- 真实数据源：复用现有 `-uiTestLocation` 确定性定位与 fixture（1.20km / 00:22 与 `docs/screenshots/run-finished*.png` 同源）；新 debug 入口不得改动既有 identifier。
- 对比度：用与 `ContrastPolicy` 一致的 WCAG 2.x 公式重算并写入 `docs/design-draft-v12`（不要改 `ContrastPolicy.swift` 的 `pairMatrix` 生产值）；阈值先定后测，推导依据写进代码注释或 README。
- 高度表：以模拟器运行时测量值（如 AX frame / accessibility frame 输出）为准，写入 README；不得用设计工具估算冒充实测。

### 证据与提交

- 生成后 `git add` 仅交付物与 debug-only 稿件文件，commit 一次，记录 head sha；不 push。
- `git diff --name-only <base>..HEAD` 的清单作为 ac-zero-production-diff 证据落盘（如 `docs/design-draft-v12/changed-files.txt`）。
- `shasum -a 256 -c docs/design-draft-v12/SHA256SUMS` 必须全 OK。

### 预算

- ≤8M token / ≤90 分钟墙钟。到点停手，回执只写：证据目录绝对路径、20 张文件名清单、对照页与 token diff 路径、commit sha、未做到的点。
