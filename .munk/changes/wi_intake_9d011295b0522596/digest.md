# 首屏 hero 间距收敛（token 级）+ 布局平衡断言收紧 — 交付 digest

Work item: `wi_intake_9d011295b0522596`
范围：`ios/PurePace/Run/RunView.swift` 四层垂直分布 + `DesignTokens.Spacing` 语义 token + `RunLayoutBalancePolicy` 阈值/反例 + 6 图 6 树重采。配色、字号、组件形态、identifier、状态机、定位、音频、GPX、CI、Android、`project.yml`、本地化键均未改动（`project.yml` 仅被静态断言读取，内容未变）。

## 1) 布局改法（固定间距取 token，余量由等权 Spacer 吸收）

`RunView` 的 `ViewThatFits` 首分支改为：

```swift
VStack(spacing: .zero) {
    Spacer(minLength: DesignTokens.Spacing.screenTop)   // 顶部呼吸位
    distanceHero
    Spacer(minLength: DesignTokens.Spacing.cardGap)     // hero → 次级指标
    metricsPanel
    Spacer(minLength: DesignTokens.Spacing.sectionGap)  // 指标 → 提示
    hintLayer
    Spacer(minLength: DesignTokens.Spacing.sectionGap)  // 提示 → 底部主操作
}
.padding(.horizontal, DesignTokens.Spacing.cardGap)
```

四个 `Spacer` 等权吸收「导航栏下沿 → 主操作顶边」的全部余量，旧布局那种「居中后上下各留 ~120pt 单块死白」不再出现。滚动退路 `ScrollView { metricsContent }` 保留，只做小屏/大字号溢出兜底。

## 2) 改动的 token（全部落在既有 `Spacing.scale` 4/8/12/16/24/32 内）

| 语义 token | 取值 | 来源档位 | 用途 |
|---|---|---|---|
| `Spacing.screenTop` | 24pt | `lg` | 首屏内容区距导航栏下沿的呼吸位 |
| `Spacing.cardGap` | 16pt | `md` | hero ↔ 次级指标卡片的层间距；同时作为内容区左右内边距 |
| `Spacing.sectionGap` | 12pt | `sm` | 指标卡片 ↔ 提示片 ↔ 底部主操作的层间距 |

另为「收紧→等量分布」腾出可测量余量，`metricsPanel` 内部行间距由 `Spacing.sm(12)` 提到 `Spacing.xl(32)`、hero 面板纵向内边距由 `sm(12)` 降到 `xs(8)`（均为既有档位，不改配色/字号/圆角/描边/组件结构）。三项语义 token 由 `scripts/check-ios-shell.sh` 静态钉死，RunView 必须出现 ≥4 个 `Spacer(minLength: DesignTokens.Spacing.*)`。

## 3) 阈值先定后测（未因判红回调）

阈值在**本轮代码实现开始前**（2026-11-11 03:5x，先于任何新截图/新 frame 采集）写入 `RunLayoutBalancePolicy` 与注释，推导依据：

- `maximumTopGap = maximumBottomGap = maximumGap = 80`：`80 = 2.5 × Spacing.xl(32)`，约 iPhone 16 竖屏（852pt）的 9.4%，且小于旧布局实测死白 116.3pt / 128.0pt 的 2/3，肉眼不再构成「块级死白」。
- `maximumImbalance = 16`：`16 = Spacing.md`，等于卡片内一档固定间距，保证上下不偏而非机械居中。

四个常量均被 `scripts/check-ios-shell.sh` 逐值锁定（改回 160/40 或 96/24 立即判红），并被 `testPolicyThresholds` 逐值断言。

## 4) 旧布局判红（原始输出，纯函数实跑）

旧布局实测帧（顶 28 / 底 251.6，导航栏下沿 149.7 / 主操作顶边 699.0）：

```
legacy(28/251.6): passes=false top=28.0 bottom=251.60000000000002 largest=251.60000000000002 imbalance=223.60000000000002
  problem: 底部留白 251.60000000000002pt > 80.0pt
  problem: 最大单一垂直空洞 251.60000000000002pt > 80.0pt
  problem: 上下留白差 223.60000000000002pt > 16.0pt
```

本轮截图实测帧（`docs/screenshots/run-not-started.png` 旧版 PNG 逐行扫描：导航内容下沿 137.3 → hero 面板顶 265.3 = 顶 128.0；提示片底 584.7 → 主操作顶边 701.0 = 底 116.3）：

```
screenshot-legacy(128.0/116.3): passes=false top=128.0 bottom=116.29999999999995 largest=128.0 imbalance=11.700000000000045
  problem: 顶部留白 128.0pt > 80.0pt
  problem: 底部留白 116.29999999999995pt > 80.0pt
  problem: 最大单一垂直空洞 128.0pt > 80.0pt
```

反例与生产代码同 commit：`LocalizationPolicyTests.testLegacyTopStackedLayoutFailsBothCriteria`、`testScreenshotLegacyLayoutFailsAllThreeGapCriteria`、`testRejectsLargeInterBlockHole`、`testRejectsAsymmetricWhitespaceEvenWhenGapsFit` 都只喂旧/畸形 frame，不靠改生产代码才红。

## 5) 四态实测（真实模拟器 frame，iPhone 16 / iOS 18.6，导航栏下沿 149.7、主操作按钮顶 713.0）

| 状态 | 顶部留白 | 底部留白 | 块间最大空洞 | 上下差 | 判据（≤80 / ≤80 / ≤80 / ≤16） |
|---|---|---|---|---|---|
| 未开始 `.ready` | 64.17pt | 76.00pt | 76.17pt | 11.83pt | 通过 |
| 运行中 `.running` | 64.17pt | 76.00pt | 76.17pt | 11.83pt | 通过 |
| 暂停 `.paused` | 64.17pt | 76.00pt | 76.17pt | 11.83pt | 通过 |
| 已保存 `didSave` | 54.17pt | 66.00pt | 66.17pt | 11.83pt | 通过 |

`ac-run-metrics-balanced <state>: top=… bottom=… largest=… imbalance=…` 由 UI 用例打印，暂停态在 `testRunPauseResumeFinishAndHistory` 补齐；`assertRunMetricsBalanced` 的采集口径仍是「staticTexts 的 frame + `navigationBars.firstMatch.frame.maxY` + 主操作 `frame.minY`」，只把 identifier 白名单改为**内容区内的全部 staticTexts**（排除 `run.telemetry` 与导航标题），让面板内 caption 也被算作可见内容，避免块内说明文案被误算成块间空洞。

## 6) identifier diff = 0

`docs/evidence/a11y/01..06` 重采后逐棵树的 `identifier:` 集合与上一版逐项比对，全部 `OK`（无新增、无改名、无删除）；冻结 33 项由 `check-ios-shell` 继续断言。

## 7) 截图与可及树 sha256（同名覆盖）

截图均为本轮 `xcrun simctl io <udid> screenshot` 产物（iPhone 16，1179×2556），非 XCTest attachment、未手绘；`run-running-dark.png` 在 `xcrun simctl ui <udid> appearance dark` 之后重跑产出，随后已切回 `light`（真实 dark appearance 模拟器产物）。

```
d1c8e2c1bb89945ab10096a200bbb82fcdd663eaa4333a81dccc9afa2a7cd040  docs/screenshots/history-detail.png
c61cb8141df27d530eada63fe0ebc56e1d458d2954a9367076b79694a50b7a0b  docs/screenshots/history-empty.png
17d1d40a3d87d2ed8523855b0c4c5f4037a7dd02f1c37854b790e6b2861467b1  docs/screenshots/run-not-started.png
35a35473cb1c89bd8ba88f8578507621a084d02aaf2558fd9dfe304b3b472164  docs/screenshots/run-running-dark.png
7e36859873059359840e9cd46815e51ab718e905b9a912af20efefa75c1f2b53  docs/screenshots/run-running.png
18dfd87c9483eaa94ba0165cff041daa191be53dadac85e43ae59a050cd6a30a  docs/screenshots/settings.png
ca7163c3e4b7c94c1ecf01054845c359d1d2e79ebd6c0550fbb8f4cbf02f60fc  docs/evidence/a11y/01-run-not-started.txt
fc11eff83440beb3a941ddda4522bc61061b2a5a3c132d39a2abbd140f442b70  docs/evidence/a11y/02-run-running.txt
1c5a133b5d9eae54df2437d2e046a686a231ce18686d4617f0c3dd6d9507cfba  docs/evidence/a11y/03-history-empty.txt
b98c853a7e67a14ca9efd7836b7e536336c5bc6abf97d4635aeff493bb7d1dc7  docs/evidence/a11y/04-history-detail.txt
320f489b725ae025bbeebce86e8a42f825bd66e76d9de1210e72da3dc64b6c51  docs/evidence/a11y/05-settings.txt
385854607cc2a9686fc98d312adaeb05273e91ba147fd90f2332adac7f7d4160  docs/evidence/a11y/06-tabs.txt
```

## 8) 视觉复核（ac-visual-gap-closed）

对照旧布局实测顶 128.0pt / 底 116.3pt，新布局实测顶 64.17pt / 底 76.00pt：导航标题与 hero 之间、提示片与底部主操作之间不再出现块级死白；hero → 次级指标 → 提示 → 主操作四层层级仍成立（hero 仍是最大字号，主操作仍固定底部）。暗色产物为真实 dark appearance 下重跑。

## 9) 竖屏锁定（公司裁决范围修订，替代旋转/size class 验收）

- `scripts/check-ios-shell.sh` 新增 `validate_orientation_config` 与断言 `ac-portrait-orientation-lock`：`project.yml` 必须 `INFOPLIST_KEY_UISupportedInterfaceOrientations: UIInterfaceOrientationPortrait`（出现 Landscape/倒置判红）+ `TARGETED_DEVICE_FAMILY: "1"`（family 2 判红）；构建产物存在时再读 `Info.plist` 的 `UISupportedInterfaceOrientations` / `UIDeviceFamily`，实测分别为 `["UIInterfaceOrientationPortrait"]` 与 `[1]`。
- `--self-test` 新增正例 + 三个反例（横屏、family 2、缺竖屏声明）全部生效；连同「布局阈值改回 160/40」「缺语义间距 token」「首屏余量未用语义间距」共新增 6 项正负反例，self-test 合计 52 项断言、0 失败。
- 本项未新增任何 size-class 参数或旋转分支；Dynamic Type 最大档几何断言未做（本项预算下置于阶段 2 打磨清单，未虚报）。

## 10) 门禁与命令结果

- `bash scripts/build-ios.sh` → exit 0，`info: .app 产物 .build/ios/Build/Products/Debug-iphonesimulator/PurePace.app`
- `bash scripts/test-ios.sh --unit-only` → exit 0，`PurePaceTests.xctest passed`（含 `LocalizationPolicyTests` 15 项）；unit-only 模式按约定跳过 UITests
- `bash scripts/check-ios-shell.sh --self-test` → exit 0，`52 项断言，0 项失败 / self-test OK`
- `bash scripts/check-ios-shell.sh`（lint-ios-shell 全量）→ exit 0，`30 项断言，0 项失败 / ios shell OK`，字面色值/零散字体命中 0
- `.munk/code-gates.json` 仍为 22 门，gate id 未增删
- UI 用例：`testZhHansCopyDatesAndBottomAnchoredPrimaryAction` 与 `testRunPauseResumeFinishAndHistory` 均 `** TEST SUCCEEDED **`（四态 metrics 见上表）

## 11) 接缝 / 现状 / 断言名 / 反例 / 证据路径 / 归属项（verification-matrix 未建表，行记于此）

| 接缝 | 现状 | 断言名 | 反例 | 证据路径 | 归属项 |
|---|---|---|---|---|---|
| `DesignTokens.Spacing` 语义间距 | screenTop/cardGap/sectionGap 均在 scale 内 | `ac-design-tokens`（`validate_design_tokens` 语义 token 段） | self-test「缺首屏语义间距 token」「首屏余量未用语义间距」 | `ios/PurePace/Design/DesignTokens.swift`、`scripts/check-ios-shell.sh` | 本项 `wi_intake_9d011295b0522596` |
| `RunLayoutBalancePolicy` 阈值 | 80/80/80/16，先定后测 | `testPolicyThresholds` + `validate_design_tokens` 阈值锁定 | self-test「布局阈值改回 160/40」 | `ios/PurePace/Design/RunLayoutBalancePolicy.swift` | 本项 |
| 旧布局判红 | 28/251.6 与 128.0/116.3 均判红 | `testLegacyTopStackedLayoutFailsBothCriteria`、`testScreenshotLegacyLayoutFailsAllThreeGapCriteria` | 上述两帧 | `ios/PurePaceTests/LocalizationPolicyTests.swift`、本 digest §4 | 本项 |
| 四态判绿 | 真实模拟器四态 top/bottom/largest/imbalance 全绿 | `testFourStatesBalancedLayoutPasses`、`ac-run-metrics-balanced` | `testRejectsLargeInterBlockHole` / `testRejectsAsymmetricWhitespaceEvenWhenGapsFit` | 本 digest §5 | 本项 |
| 竖屏锁定 | portrait-only + family 1（源码与产物双向） | `ac-portrait-orientation-lock` | self-test「横屏方向」「device family 2」「缺竖屏声明」 | `scripts/check-ios-shell.sh`、`.build/ios/.../Info.plist` | 本项（公司裁决范围修订） |
| 可及 identifier 冻结 | 33 项，重采后 diff = 0 | `validate_design_tokens` identifier 段 | self-test「identifier 重命名/追加」 | `docs/evidence/a11y/01..06` | 本项 |
| 截图证据 | 6 张 simctl 产物（含真实 dark） | `ac-screenshots-refreshed` | 非空 PNG + sha256 上表 | `docs/screenshots/` | 本项 |

## 12) 未做 / 待人现场

- 真机验收（锁屏后台定位、音频实听、真实定位授权弹窗）未做：`pending: 待人现场`。
- 未做 Dynamic Type 最大档几何断言（本项预算优先保四态与澄清口径）。
- 未新增 `docs/verification-matrix.md`（由 `wi_intake_9738f1ec924207f9` 建表），接缝行见 §11。
