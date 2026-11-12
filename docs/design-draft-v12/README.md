# V1.2 界面返工 · 设计先行静态稿（一页对照）

证据目录（运行 worktree 绝对路径）：
`/Users/zhutao/Library/Application Support/Munk-AI/munk-auto/worktrees/codebase_19e8ad47434ff059/wi_intake_e3e7d100d6da9247/docs/design-draft-v12/`

- 20 张 PNG 全部来自 iPhone 16 模拟器（iOS 18.6，UDID `B3F00298-E08A-41E0-876E-6E8A75C730FD`）真实渲染：逻辑 393×852 pt、@3x、1179×2556 px。
- 复跑入口：`bash scripts/capture-design-draft-v12.sh`（`--only a|b|c` 局部、`--skip-build` 复用产物、`--help`）；本轮日志 `render.log`；逐张尺寸见 `manifest.md`；校验 `shasum -a 256 -c docs/design-draft-v12/SHA256SUMS`（20/20 OK）。
- 绑定提交：`commit.txt` 记录「证据提交」的 head sha（该提交包含全部交付物与 debug-only 稿件文件；本条 sha 由其后一笔只追加 `commit.txt` 的提交写入，故文件内不含自身）。
- 生产边界：`ios/PurePace/Design/DesignTokens.swift`、生产视图、`RunFinishedSummaryLayoutPolicy.swift`、`ios/PurePaceUITests/**`、`scripts/test-ios.sh`、`.munk/code-gates.json` 零改动；清单见 `changed-files.txt`。唯一生产文件改动是 `ios/PurePace/PurePaceApp.swift` 里 `#if DEBUG` 的 `-designDraftV12` 入口分支（Release 编译期不存在）。

## 一、结论一览（每套/每版一行）

| 编号 | 结论 |
|---|---|
| **A1 饱和橙底 + 深字** `#E85D04` / `#1F1200` | 对比度最宽裕的橙（accent vs 页底 3.35:1、深字 vs accent 5.24:1），6 屏观感最「橙」，推荐作为浅色主色首选。 |
| **A2 深橙底 + 白字** `#BE4E05` / `#FFFFFF` | 颜色更深更稳（4.70:1 / 4.90:1），但白字按钮在浅色页里偏「重」，且与 danger 明度更近（见 token-diff）；作为保守备选。 |
| **B1 地图 hero** | 地图 360pt = 屏高 42.3%（≥ 340.8pt 门槛），内容合计 667.3pt ≤ 可用 691pt，按钮/提示均不裁切。 |
| **B2 中等地图 + 可折叠摘要** | 地图 220pt（现网 96pt 的 2.3 倍），关键指标常显 117.7pt，折叠只收「分段明细」（折叠 60pt / 展开 171pt）；下方留白是三行内容外的呼吸区。 |
| **C1 纵向主次** | danger 实心「确认丢弃」(210pt sheet) + 无描边「取消」，主次最明确。 |
| **C2 图标式 + 底部主操作** | 图标块 + 底部 danger 实心 (143.7pt sheet) + 无填充取消，弹窗最紧凑，适合小屏。 |

## 二、A 组：浅色主色两套候选

### 对比度（先定后测）

阈值先定（写入 `ios/PurePace/DesignDraft/DesignDraftTheme.swift` 头注释，先于取色）：非文本 UI 组件（实心主按钮底 vs 页面底 `#FAFAF9`）≥ **3:1**；按钮文字（`onAccent` vs `accent`）≥ **4.5:1**；浅色 accent 必须仍是橙，HSL **H ∈ [20°, 35°]、S ≥ 60%**。再用与 `ContrastPolicy` 同一 WCAG 2.x 公式实测：

- 相对亮度：`c ≤ 0.04045 → c/12.92`，否则 `((c+0.055)/1.055)^2.4`；`L = 0.2126R + 0.7152G + 0.0722B`（sRGB 线性化）。
- 对比度：`(L1 + 0.05) / (L2 + 0.05)`，`L1 ≥ L2`。

| 组合 | hex | HSL（H/S/L） | 实测 | 阈值 | 结论 |
|---|---|---|---|---|---|
| A1 accent vs 页底 `#FAFAF9` | `#E85D04` | 23.4° / 96.6% / 46.3% | **3.35:1** | ≥3:1 | 通过 |
| A1 onAccent vs accent | `#1F1200` | 34.8° / 100% / 6.1% | **5.24:1** | ≥4.5:1 | 通过 |
| A2 accent vs 页底 `#FAFAF9` | `#BE4E05` | 23.7° / 94.9% / 38.2% | **4.70:1** | ≥3:1 | 通过 |
| A2 onAccent vs accent | `#FFFFFF` | — / 0% / 100% | **4.90:1** | ≥4.5:1 | 通过 |
| 现网 accent（对照） | `#B4400B` | **18.8°** / 88.5% / 37.5% | 5.47:1 | ≥3:1 | 色相出界（砖红根因） |

### A 组对照口径

- A1/A2 走**同一份渲染代码**，只换 `DesignDraftPalette.accent` / `onAccent`；其余全部取生产 token（字号、间距、圆角、描边、卡片、tab bar 均为同一路径），因此 6 屏两套之间除主按钮底色/字色外像素级一致。
- 6 屏覆盖：`run-not-started` / `run-running` / `run-finished` / `history-list` / `history-detail` / `settings`，每套每屏 1 张，共 12 张（`a1-*.png` / `a2-*.png`）。
- **已知口径差异（非缺陷）**：地图折线仍在 `TrackMapView` 内取生产 `accent`（`TrackMapView` 无注入参数，本轮不改生产视图），所以 A1/A2 截图里的轨迹线都是现网砖红。本轮 A 组只裁决按钮主色；折线随 token 落地后自动跟随，不需改地图代码。
- A 组 `run-finished` 为**现网结构**（含 96pt 压缩档地图与整行权限提示），只用于比色；版式结论看 B 组。
- A 组 `settings` / `history-list` 的 accent 出现在开关与选中 tab；`history-detail` 出现在导出主按钮与返回/选中态。

## 三、B 组：结束态整屏（实测高度表）

数据同源：`DesignDraftFixture`（37.3349 / -122.0090 起步、22 个 1 Hz 采样点推进 1 200 m，与 `docs/screenshots/run-finished*.png` 同源）→ 距离 1.20 km、用时 00:22、平均配速 0:18 /km、分段 2 段（1.00 km + 0.20 km）。轨迹由生产 `TrackMapView` 画真实折线，不手绘。

可用内容高：393×852 屏去掉状态栏/安全区后根容器 759pt，主操作条固定在底部安全区上方占 68pt → **可用 691pt**。

| 量测点 | B1（地图 hero） | B2（中等地图 + 折叠摘要） |
|---|---|---|
| 地图区块 `finished.map` | **360.0**（852×42.3%，门槛 340.8） | **220.0** |
| 摘要卡 `finished.summary` | —（指标/分段直接成卡） | 折叠 **60.0** / 展开 **171.0** |
| 关键指标卡 `finished.metrics` | 117.7 | 117.7（常显，折叠只隐藏分段） |
| 分段卡 `finished.splits` | 114.0 | 展开时卡内 103.0 |
| 权限提示 `finished.hint`（inline 胶囊） | 23.7 | 23.7 |
| 底部主操作条 `screen.actionBar` | 68.0 | 68.0 |
| 内容合计 `screen.content` | **667.3 ≤ 691** | **652.3 ≤ 691** |

- 两版合计都在 691pt 以内，且**没有压字号**（全部沿用生产 `Typography`），也没有把地图压到 `finishedMapFloor = 96` 兜底。
- 主操作「保存」（accent 实心）+ 「丢弃」（描边次操作）位于底部安全区上方 68pt 条内，截图中不与内容重叠、四个角都完整。
- 权限提示改为 inline 小胶囊（23.7pt，宽度由内容决定），不再整行占高挤压地图。
- **无分段替代信息**：分段为空时同一张卡换成单行文案 `run.finished.splits.empty` =「本轮无分段数据」（生产 `Localizable.xcstrings` 既有 key），标题行右侧不再显示「N 段」；形态仍是同尺寸卡片 + 一条 caption，不出现空卡，也不隐藏整个区块（避免用户以为丢数据）。本轮未单独渲染该变体，替代信息以上述文案与卡壳规则为准。
- **B2 折叠/展开形态**：摘要卡标题「本次跑步」+ 一行 `1.20 km · 00:22 · 0:18 /km`，右侧 chevron；折叠 60pt，展开 171pt（多出分段卡 103pt），关键指标卡始终在卡外常显，展开不产生双描边嵌套（卡内用分隔线）。`b2-finished-expanded` 以量测变体记录（非交付 PNG，见 `heights.tsv`）。
- B/C 组不比较颜色：沿生产 `accent` / `onAccent` token，只考察版式。

## 四、C 组：丢弃确认弹窗

| 版本 | sheet 高度 | 主操作 | 次操作 | 结论 |
|---|---|---|---|---|
| C1 纵向主次 | **210.0** | danger 实心「确认丢弃」44pt 高、满宽 | 无边框文字「取消」 | 主次最明确，破坏性动作最强形态 |
| C2 图标式 + 底部主操作 | **143.7** | danger 实心「确认丢弃」44pt | 无填充「取消」 | 最紧凑；图标块 + 标题在同一行 |

- 两版都是「一个实心破坏性主操作 + 一个无描边/无填充次操作」，**没有**两枚等权描边按钮并排；sheet 高度由内容自适应（无固定 `.medium` 留白，sheet 顶部到标题的间距就是常规内边距）。
- 弹窗内不出现 accent 实心按钮与 danger 实心按钮同形状并列：sheet 为不透明面板，覆盖在 B2 结束态之上，底层「保存」（accent 实心）被遮住（截图可见 sheet 顶边之上只有地图/摘要/提示）。
- 破坏性动作与 accent 分离：H 2.6° 红 vs accent H 23.4°/23.7° 橙，色相相隔 ≥20°，且形态不同屏并列（见 token-diff §danger）。

## 五、为什么不做「压暗换对比度 / 压地图换不溢出」

- **不压暗换对比度**：达到 3:1 有两条路——压暗 accent 或提亮/去饱和。压暗会立刻把 H 推到 20° 以下、S 也掉进砖红区间（现网 `#B4400B` 正是 H 18.8°），返工等于回到原点；本轮的解法是**把色相与饱和度先钉在橙区间（H 23~24°、S ≥95%）**，再用「亮底深字（A1）/ 深底白字（A2）」把文字对比度做上来（3.35 / 4.70，文字 5.24 / 4.90）。代价只是按钮文字颜色变化，不动色相。
- **不压地图换不溢出**：现网把地图压到 96pt 仍溢出，根因是整屏垂直预算（`uncompressedFinishedContentHeight = 688`）撑不住，压地图只是把溢出点往后挪。B1 直接把地图做成 360pt hero、B2 做 220pt，再**删掉整行权限条（改 inline 23.7pt）并把指标行收成 117.7pt 两列**，让 667.3 / 652.3 落在 691pt 预算内——不需要压字号，也不需要继续压地图。
- 因此下一轮实现建议顺序：先落 B1（主路径），B2 作为小屏/摘要偏好备选；token 侧按 `token-diff.md` 落 A1（首选）。

## 六、文件清单

| 组 | 文件 |
|---|---|
| A1（6） | `a1-run-not-started` `a1-run-running` `a1-run-finished` `a1-history-list` `a1-history-detail` `a1-settings` |
| A2（6） | `a2-run-not-started` `a2-run-running` `a2-run-finished` `a2-history-list` `a2-history-detail` `a2-settings` |
| B（4） | `b1-finished-light` `b1-finished-dark` `b2-finished-light` `b2-finished-dark` |
| C（4） | `c1-discard-light` `c1-discard-dark` `c2-discard-light` `c2-discard-dark` |

附属：`manifest.md`（逐张设备/倍率/像素尺寸）、`heights.tsv` + `manifest.md` 高度表（运行期探针实测）、`render.log`、`SHA256SUMS`、`changed-files.txt`、`commit.txt`、`token-diff.md`。

## 七、debug-only 实现口径

- 新增 `ios/PurePace/DesignDraft/`（4 个视图文件 + theme），整目录 `#if DEBUG` 包裹，Release 不参与编译。
- `PurePaceApp.swift` 只有一个 `#if DEBUG` 分支：启动参数 `-designDraftV12 <variant>` 存在时用 `DesignDraftRootView` 作为根视图。
- 探针标识统一前缀 `designDraft.*`（`designDraft.screen` / `designDraft.height` / `designDraft.ready`），不读写任何既有 identifier，未新增 UI 测试套件，`scripts/test-ios.sh` 枚举与 `scripts/check-ios-shell.sh` 扫描目录均未受影响。
