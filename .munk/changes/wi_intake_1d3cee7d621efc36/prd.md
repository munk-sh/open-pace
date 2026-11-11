# V1.2 二审判定重做：石墨+竞速橙（方向 A）+ 详情/结束态轨迹地图与总结感

V1.2 唯一目标（`goal.md` + 公司裁决 `owe_31679eee431d416d` + `owe_7e84f7f059177094`）。可观测终态：一轮跑完能看到本轮距离/时长/配速 + 自己的路线地图 + 分段明细，历史详情页能回看同一条轨迹；整屏为石墨中性骨架 + 烤橙单点强调，**不再有青绿黑与青绿 brand**。除地图叠加与结束态总结感外，功能面不扩。

## 范围

1. **色板整体替换（方向 A）**：`ios/PurePace/Design/DesignTokens.swift` 内 18 键 × 浅/深 = 36 个 hex 按 digest §3 方向 A 表逐键替换；`purposes` 用途注册表与 18 键**不增不减不改语义**；视图层仍零裸色值（`DesignTokens.swift` 为唯一豁免文件）。
2. **色值记录落仓**：新增 `docs/design/palette-a.md`（18×2 hex 表 + 来源路径 + 37 对实测值 + 与「早期 Android 绿」禁区对照）与 `docs/evidence/palette-a-contrast.txt`（37 对 ×2 侧逐对实测数字）。
3. **层级与形状档位**：hero 主数据卡改 `surface`、次卡改 `surfaceMuted`（纠正倒置）；圆角 3 档数值改 `control 10 / card 14 / panel 20`；字号仍 6 档、数值改 `11 / 13 / 15 / 20 / 36 / 64`（label 与 unit 同为 11）；`display` `.bold` + 等宽、`primaryValue` `.semibold`、`metricLabel` 由 `.medium` 升 `.semibold`；字重集合仍 `[.regular, .semibold, .bold]`；间距仍 6 档 `4/8/12/16/24/32`。
4. **轨迹地图（新）**：新增收口到一处的 `TrackMapView` 壳（坐标进 / 地图出），只出现在**详情页与结束态**；MapKit 单 SDK（`MapPolyline`，必要时退 `MKPolyline`，不子类化 renderer）；accent 4pt 轨迹 + accentSoft 光晕；相机按包围盒一次定位、padding 8–12%；空轨迹/定位失败给明确 zh-Hans 空态文案与图标（不留空白地图）。
5. **结束态总结感**：结束态含 到/时/配速 + 轨迹预览卡 + 分段明细；无分段数据给显式文案；保存主、丢弃次。承接窄项 `wi_intake_c1a670784196dbd8` 的「记录态/结束待保存态收 TabBar、权限横幅移出主视区」（该项当前**尚未在 main**，本项须自带该行为且不回退）。
6. **存储与渲染分离**：轨迹只存 WGS-84；RDP 抽稀 ε=3m **只用于渲染**（原始 `samples` 与 GPX 导出语义不变）；采样间隔 >60s 断线分段；`RunArchiveStore.list()` 加轻量索引使列表页不再全量解码 samples；**不迁 SwiftData、不改数据格式、不升 formatVersion**。
7. **复评素材**：全绿后按既有 `scripts/capture-ios-screenshots.sh` 管线重出 6 屏 × 浅/深 = 12 张到 `docs/screenshots/`（同名覆盖），重算 `SHA256SUMS` 并 `shasum -c` 全 OK；另附 6 棵可及树 + AX5 最大字号实拍；截图绑定 commit 全 sha 并给出「截图构建与 main 无 App target 差异」的比对结论。产品不自判达标，只出证据交公司转人复评。

## 验收（每条可独立判红；新增断言须同 commit 附反例，反例不得依赖改生产代码才红）

### 色板
- ac-palette-hex-exact: `DesignTokens.Colors.palette` 的 18 键 × 浅/深 共 36 个 hex 与方向 A 表**逐键逐侧完全相等**；表驱动断言（期望表写在测试里，取值为字面 UInt32），把任一键改回旧值或改任一分量即红。
- ac-palette-keys-frozen: 调色板仍恰为 18 键、键集与冻结清单相等、无重复；每键 light/dark 成对且**逐键两侧不等**；`purposes` 键集等于 palette 键集且用途文本语义不变；`DesignTokensTests` 与 `check-ios-shell.sh` 的 18 键冻结门仍绿。
- ac-palette-neutral-purity: 深色中性三键 `background #0B0C0D` / `surface #16181A` / `surfaceMuted #1E2124` 的 **HSV 饱和度 ≤ 20%**（纯函数断言 + 门断言双落，见「实现约束 · 裁决 A」：实测 15.38% / 15.38% / 16.67%）；回归到旧值 `#0A1211`(44.44%) / `#141F1D`(35.48%) / `#1A2724`(33.33%) 必须判红；浅色三键 `#FAFAF9` / `#FFFFFF` / `#F2F2F1` 实测饱和度（0.40% / 0.00% / 0.41%）一并记录并断言 ≤4%。
- ac-palette-no-green: 18 键全部落在 digest §3.4 禁区外——不得出现 H 72–85°(S≥90%)、H 120–150°(S≥45%)、H 165–180°(S≥55%)、泛绿中性（中性三键 S >4% 或 H 落在 60–200°）任一命中；对 36 个 hex 做纯函数扫描，把 accent 改回 `#0B6F60` 即红。
- ac-palette-doc: `docs/design/palette-a.md` 存在且含 18×2 hex 表、来源（公司调研 digest 路径）、37 对实测值（含最薄 pair 与 accent/background 实测）、与禁区的对照说明；文件内 hex 与代码逐键一致（脚本比对，改任一侧即红）。

### 对比度
- ac-contrast-matrix-pass: `ContrastPolicy.pairMatrix` 为 **37 对**（既有 36 对不删不改，新增恰 1 对，新增对须是装饰 1.10 档的地图光晕可辨识 pair——建议 `accentSoft/surface`），`checks(for:)` 对 light 与 dark 各 37 对全部 PASS（body 4.5 / large 3.0 / decorative 1.10）；删任一对或改任一 hex 使任一对跌破阈值即红。
- ac-contrast-evidence: `docs/evidence/palette-a-contrast.txt` 存在，逐行给出 `pair 名 / 前景 hex / 背景 hex / 实测比值（4 位小数）/ 阈值`，覆盖 37 对 ×2 侧 = 74 行，且与 `ContrastPolicy.ratio` 现场重算值在 1e-4 内一致（脚本逐行核对，篡改数字即红）；文件内记录最薄 pair 与 `accent/background` 实测值。

### 令牌与语法纪律
- ac-zero-literal-color: 除 `DesignTokens.swift` 外，视图/组件文件命中 `Color(`、`Color.`、`UIColor`、`#colorLiteral`、`.foregroundStyle(.` 等裸色值判定为红——现门保持绿（改色不引入新豁免文件）。
- ac-type-scale-6: 字号档恰 6 档 `[11, 13, 15, 20, 36, 64]`（`metricLabel` 与 `metricUnit` 同为 11），`roleLadder` 仍 7 角色且按字号非递减；把 caption 改回 12 或新增第 7 档即红。
- ac-weights-3-and-roles: 字重集合精确等于 `[.regular, .semibold, .bold]`，代码与源文件内零 `.heavy`；`display` = bold + 等宽、`primaryValue` = semibold + 等宽、`metricLabel` = semibold（把 metricLabel 改回 `.medium` 即红）。
- ac-radius-3: 圆角恰 3 档且为 `control 10 / card 14 / panel 20`（改回 12/16/20 即红）。
- ac-spacing-6: 间距恰 6 档 `4/8/12/16/24/32`，语义间距项仍精确落在这 6 档内。
- ac-monospaced-digits: `monospacedDigit()` 出现次数 RunView ≥3、HistoryView ≥1、RunDetailView ≥1（删任一即红）。
- ac-card-hierarchy: 跑步页 hero 主数据卡用 `surface`、次级指标卡用 `surfaceMuted`（静态门断言两处引用，回退成 hero 用弱底即红）。
- ac-primary-action-distinct: 一屏一个主操作；主操作与卡片形状可区分（主操作用 `Radius.control`=10 且非卡片描述，卡片用 `Radius.card`=14）；A 色板下 warning/danger 与 accent 色相 41° 内，三态区分只能靠位置/形状/文案——静态门断言「结束/丢弃/开始」三者各自带可读文案与不同位置/形状，不得只靠颜色。

### 契约与状态
- ac-identifier-freeze: 33 项冻结 identifier（`history.* / run.* / runDetail.* / settings.* / tab.*`）**零删除、零改名**（与冻结清单 diff = 0），只允许新增；新增项须非空、唯一、带可读 label 且总计数单调不减。
- ac-tab-count-zero: 记录态与结束待保存态**可见 TabBar 项数 = 0**（承接窄项结论）；权限横幅不得占据主视区（移出主视区或收进次级位置）。回退任一条件即红（可判红用例：记录中/结束时断言 `tab.*` 不可命中）。
- ac-store-index-no-sample-decode: `RunArchiveStore.list()` 不再为每行全量解码 `samples`（轻量索引：id / 起止时间 / 距离 / 时长 / 是否有轨迹），历史列表页路径不解码轨迹；反例用例=让某条记录 samples 超大/畸形时列表仍能成行且耗时断言不随 samples 线性增长；`list()` 先前的「坏文件跳过、排序 startedAt 降序 + id 升序」语义必须保持。
- ac-store-format-frozen: `formatVersion` 不变、不新增 `horizontalAccuracy` 字段、不写迁移、不改归档文件命名与 schema；原始 `samples` 语义不变，`scripts/check-gpx-export.sh` 仍绿（GPX 字段与屏幕渲染数据同源）。
- ac-no-demo-entry: 生产代码 demo/seed 入口数 = 0（`demo 入口=0` 门仍绿）；结束态/详情页出图所需的轨迹数据只允许在 UITests target 内 fixture + DEBUG 门控 launch-arg 注入（复用既有确定性定位源机制）。

### 地图
- ac-map-empty-state: 轨迹为空（无坐标）或定位失败时，地图区域渲染明确 zh-Hans 空态文案 + 图标，不得留空白地图；反例=删掉该文案/图标必须红。
- ac-map-break-segments: 采样时间间隔 >60s 处切分为多段 polyline 分开绘制（纯函数用例：59s 不断、61s 断、跨 3 段夹具输出 3 段）；不改 schema。
- ac-map-rdp-render-only: RDP 抽稀 ε=3m 在局部米制投影（`lat*111320`、`lon*111320*cos(lat)`）下执行，固定夹具上**每点最大偏差 < 3m**；抽稀只作用于渲染输入，归档 `samples` 与 GPX 导出不受影响（两处断言：抽稀误差 + GPX 全量点仍在）；阈值常量先写进代码/注释再跑，禁止红了再调。
- ac-map-camera-fit: 相机按轨迹包围盒一次定位，padding 取包围盒尺寸的 8–12%（纯函数断言：给定包围盒 → 期望区域；输入 8% 与 12% 边界都合法、7%/13% 判红）；`onMapCameraChange` 内不回写任何 state（静态门断言该修饰符内无赋值）。
- ac-map-polyline-cached: `TrackPolyline` 在 `body` 外构造并由 `@State`（或等价）持有缓存，不得每次 body 重建（静态门断言构造点不在 body 内）；坐标/相机逻辑收敛在 `TrackMapView` 单一文件内，视图外不散落；仅 `import MapKit`，无第三方地图/UI 框架。

### 结束态
- ac-finished-summary-blocks: 结束态同时含「距离 / 时长 / 配速」数值 + 轨迹预览卡 + 分段明细，三者各有可断言 identifier 或可及文案（删任一块即红）。
- ac-finished-no-split-fallback: 无分段数据时显示「本轮无分段数据」类明确文案或替代信息，不得只留空卡（反例=删文案必须红）。
- ac-finished-save-discard-hierarchy: 保存为主操作（accent 实底、`Radius.control`）、丢弃为次操作（弱底/描边），两者位置与形状可区分，主次不得同权。
- ac-detail-map-parity: 历史详情页可回看同一条轨迹（同一 `RunRecord.samples` 渲染，地图卡存在），且与结束态共用同一 `TrackMapView`。

### 门禁与证据
- ac-code-gates-22: `.munk/code-gates.json` 全量 **22 门退出码 0**（含 `check-gpx-export` / `check-shell-expansion` / `test-ios` `--unit-only`），证据绑 commit sha。
- ac-screenshots-12: `docs/screenshots/` 下 6 屏 × 浅/深 = 12 张同名覆盖（`run-not-started / run-running / run-finished / history-list / history-detail / settings` × `light/dark`），`SHA256SUMS` 重算且 `shasum -c` 全 OK。
- ac-a11y-evidence: 6 棵可及树（`docs/evidence/a11y/`）+ AX5 最大字号实拍存在且与本次构建一致。
- ac-evidence-commit-bound: 截图与证据绑定 commit 全 sha，并给出「截图构建与 main 的 App target 无差异」的比对结论（列出比对命令与结论行）。
- ac-no-true-device-claims: 证据中不得出现「真机已验证」表述；真机相关项一律 `pending: 待人现场`。

## 非目标（出现即打回）

- 不做跑步中实时地图；不做中国区双 SDK / 高德接入 / 审图号 / 购买任何地图许可。
- 不新增第 19 个色键；不改字号档数与字重集合；不引入第三方 UI 框架或第三方地图 SDK。
- 不改 identifier 冻结集（删除/改名一律回退）；不做社交 / 账号 / 云同步 / Apple Watch / 健康 App 写入 / Android / 主题切换器。
- 不做任何分发动作（ASC App 记录、ipa 导出、TestFlight、tag、GitHub Release）；不改 `VERSION` 与版本指向（验收候选固定 `0.1.0(1)`）。
- 不改 GPX 导出字段与原始样本语义；不加生产 demo/seed 入口。
- 不迁 SwiftData、不升 `formatVersion`、不加 `horizontalAccuracy` 字段、不写迁移（那是 v2）；不为派生 `track.polyline` 改归档格式（预算紧就用进程内缓存）。
- 不做平滑/降噪改写归档数据（平滑=伪造证据，GPX 必须与屏幕一致）。
- 不排真机窗口、不排人手步骤，不做产品自判定达标。

## 实现约束（已约定的锚点，不是完整技术方案）

**色值唯一真源（禁止截图取色、禁止自行微调 hex）**
- 18×2 hex 表：公司调研 digest `/Users/zhutao/Library/Application Support/Munk-AI/munk-auto/company/projects/ops_955931433a2c50ea/.munk/runs/trun_cff114e082a2fb0e/digest.md` §3「方向 A」（兼容 §3.4 禁区表）。
- 逐键对比度复算脚本与原始数字：同 run `notes/palette_check.py`、`notes/palette-report.txt`；同屏效果参考 `.../company/notes/2026-11-11-palette-alignment.html`。
- 待替换文件与位置：`ios/PurePace/Design/DesignTokens.swift` 的 `Colors.palette`（当前 18 行 `ColorPair(light:dark:)`）；`purposes` 与 18 个 `static let` 不动。参照值：light `background #FAFAF9 / surface #FFFFFF / surfaceMuted #F2F2F1 / primary #17181A / secondary #5C5F63 / accent #B4400B / onAccent #FFFFFF / accentSoft #FCEFE7 / separator #D8D8D3 / warning #7A5A00 / onWarning #FFFFFF / warningSoft #FBF1DC / success #1F6B45 / onSuccess #FFFFFF / successSoft #E7F2EB / danger #A5231C / onDanger #FFFFFF / dangerSoft #FBEAE8`；dark 依次 `#0B0C0D / #16181A / #1E2124 / #F2F3F4 / #A2A7AC / #FF9A5C / #2A1206 / #3A1F12 / #33383D / #F0B44C / #2B1A00 / #3A2A0D / #58CF9B / #042416 / #11311F / #FF8A80 / #3A0906 / #3A1A17`。

**裁决 A（Neutral-purity 阈值，已上报 `owe_7e84f7f059177094` 并按其「不阻塞、默认按 A 继续」口径落地）**
- 事实：方向 A 深色中性三键 HSV 饱和度为 15.38% / 15.38% / 16.67%（旧值 44.44% / 35.48% / 33.33%；公司 `palette-report.txt` 的 `S` 列是 HSL 饱和度 8.3/8.3/9.1）。brief 原文「≤4%」对正确实现同样判红，与「hex 一字不改」互斥。
- 落法：阈值取 **HSV_S ≤ 20%**（新值全 PASS、旧值全 FAIL，回归判红能力完整）；浅色三键额外断言 ≤4%（0.40/0.00/0.41）。代码注释里写清这组实测数字与为何不是 4%，避免复评时误判为「放宽门」。

**对比度矩阵**
- 现状 `ios/PurePace/Design/ContrastPolicy.swift:30-70` 实际是 **36 对**（body 30 + large 3 + decorative 3），需新增恰 1 对到 37 且不删不改既有对；建议新增 `accentSoft/surface`（decorative 1.10，对应新增轨迹光晕叠在卡片面上的可辨识下限）。37 对 ×2 = 74 条证据行。

**设计门落点（现有门，改数值不改结构）**
- `scripts/check-ios-shell.sh`：`validate_design_tokens`（≈L535）含 18 键冻结（L658-671）、字号档/间距/圆角/字重/等宽数字（≈L722-773、L856-860）、零字面量门（L780-816）、identifier 冻结 33 项（L864）+ 必需新增 3 项 `run.cancelCountdown / run.discard / run.save`（L873，下限 36）。
- `ios/PurePaceTests/DesignTokensTests.swift`（18 项）与 `ContrastPolicyTests.swift`（7 项）是数值断言落点；新增断言必须同 commit 附反例。

**地图**
- 依据 `/Users/zhutao/Library/Application Support/Munk-AI/munk-auto/company/projects/ops_955931433a2c50ea/.munk/runs/trun_c99e57284cec0b8a/digest.md` §3 抽象层 / §4 抽稀与渲染 / §4.3 存储。SwiftUI `Map(position:)` + `MapPolyline(...).stroke`（iOS 17+），`TrackPolyline` 在 body 外构造并由 `@State` 缓存；需分段着色才退 `MKPolyline` + `MKPolylineRenderer`（不子类化 renderer）。相机一次定位包围盒、padding 8–12%，`onMapCameraChange` 内不回写 state。
- RDP 投影 `x = lon*111320*cos(lat)`、`y = lat*111320`，ε=3m；>60s 间隔断线；原始 `samples` 不动，GPX 保持与屏幕同源。
- 渲染/相机/分段纯逻辑优先放 `ios/RunCore`（可 `swift test` 的 L1 层），`TrackMapView` 只做 MapKit 接线，保留将来上双 SDK 的抽象缝。
- 现有可复用资产：`ios/PurePace/History/RunDetailContent.swift`（详情内容模型）、`ios/PurePace/Run/RunLaunchArguments.swift` + `ios/PurePace/Location/RunTestLocationSource.swift`（DEBUG `-uiTestLocation` 确定性定位源），出图走 `-screenshotRunFinished` / `-screenshotHistoryDemo` 既有机制，不新增生产入口。

**协作与环境**
- 窄项 `wi_intake_c1a670784196dbd8`（RunView 的 TabBar 隐藏与权限横幅位置）当前**尚未进 main**；本项自带该行为。若期间它先合入 main，交付前必须先 merge 最新 main，冲突以「保留 tab 数=0 + 横幅移出主视区」为准，不得回退其结论。
- 只做模拟器 + 代码层验证；不排真机窗口与人工步骤。预算 ≤120 分钟 / ≤35M tokens，超时即停手交回执（写清已绿项与未闭合项），不得长会话自查补绿。
- 交付流程仍为本地 merge（fold → commit → `munk_local_merge` → submit）；不做任何分发动作。
