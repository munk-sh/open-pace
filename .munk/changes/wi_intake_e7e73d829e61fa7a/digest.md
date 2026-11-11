# Digest — 视图层用途重映射（accent / warning / danger）+ 未开始态间距收敛

> 公司裁决 `owe_1af0fad2441dc226`；本项把「语义重映射」与「未开始态间距收敛」合成一次改动。
> 36 hex、对比度阈值、`RunLayoutBalancePolicy` 80/80/16 与四条反例全程零改动（B/C 项不做）。

## 0. 起点 / 修后实测（未开始态，iPhone 16 竖屏）

运行命令（同一 UI 用例，阈值与反例零改动）：

```bash
xcodebuild test -project ios/PurePace.xcodeproj -scheme PurePace \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' \
  -derivedDataPath .build/ios \
  -only-testing:PurePaceUITests/RunFlowUITests/testZhHansCopyDatesAndBottomAnchoredPrimaryAction
```

### 起点 HEAD `f907faf` 实测（原样摘录，修前工作树）

```
ac-run-metrics-balanced 未开始: top=68.58333333333334 bottom=64.58333333333326 largest=84.58333333333331 imbalance=4.000000000000085 contentFrames=[(185.5, 218.25, 22.0, 13.333333333333343), (117.33333333333333, 239.58333333333334, 158.33333333333331, 76.66666666666666), (188.5, 324.25, 16.0, 13.333333333333371), (99.25, 422.1666666666667, 22.0, 13.333333333333314), (54.583333333333336, 443.5, 111.33333333333331, 43.0), (260.75, 422.1666666666667, 44.0, 13.333333333333314), (260.4166666666667, 443.5, 44.666666666666686, 43.0), (88.25, 519.5, 44.0, 13.333333333333258), (104.08333333333333, 540.8333333333334, 12.333333333333343, 15.666666666666629), (271.75, 519.5, 22.0, 13.333333333333258), (278.5833333333333, 540.8333333333334, 8.333333333333314, 15.666666666666629), (22.166666666666686, 617.0833333333334, 348.66666666666663, 31.33333333333337)]
```

判定（起点）：`largest=84.58 > 80` 判红，其余三项在上界内。

### 修后实测（本项提交 `a5c4017`（`a5c4017e7389d1083760b0a493c74eef202a71b5`），原样摘录）

```
ac-run-metrics-balanced 未开始: top=64.58333333333334 bottom=72.58333333333326 largest=72.58333333333337 imbalance=7.999999999999915 contentFrames=[(185.5, 214.25, 22.0, 13.333333333333343), (117.33333333333333, 235.58333333333334, 158.33333333333331, 76.66666666666666), (188.5, 320.25, 16.0, 13.333333333333371), (99.25, 402.1666666666667, 22.0, 13.333333333333314), (54.583333333333336, 423.5, 111.33333333333331, 43.0), (260.75, 402.1666666666667, 44.0, 13.333333333333314), (260.4166666666667, 423.5, 44.666666666666686, 43.0), (88.25, 499.5, 44.0, 13.333333333333371), (104.08333333333333, 520.8333333333334, 12.333333333333343, 15.666666666666629), (271.75, 499.5, 22.0, 13.333333333333371), (278.5833333333333, 520.8333333333334, 8.333333333333314, 15.666666666666629), (22.166666666666686, 609.0833333333334, 348.66666666666663, 31.33333333333337)]
```

判定（修后）：`top=64.58 ≤ 80`、`bottom=72.58 ≤ 80`、`largest=72.58 ≤ 80`、`imbalance=8.0 ≤ 16`，几何断言转绿。

实现只重排既有空白：hero 卡既有上内边距 `Spacing.lg → Spacing.sm`（`RunView.swift` `.padding(.top, .sm)`）、指标卡既有下内边距收 `.xxs`，四个既有 `Spacer()` 相对权重不变；未新增占位内容视图、未硬编码帧，`RunLayoutBalancePolicy` 80/80/16 与四条反例源码零改动。

## 1. tab=0 三态 + restore 四行实跑（`RunFlowUITests/testRunPauseResumeFinishAndHistory`，TEST SUCCEEDED）

```
ac-tabbar-hidden-paused 暂停: state=paused didSave=false tabBarCount=0 expected=0
ac-tabbar-hidden-recording 恢复运行: state=running didSave=false tabBarCount=0 expected=0
ac-tabbar-hidden-finished-pending 结束待保存: state=finished didSave=false tabBarCount=0 expected=0
ac-tabbar-restore-no-deadend 保存态: state=finished didSave=true tabBarCount=1 expected=1
```

四行全部期望＝实测（0/0/0/1），无断头路：`save` 后 Tab 栏回到 1。

## 2. UI 像素样式断言（`ac-finish-ui-rendered-accent`，期望值由 `DesignTokens.Colors.palette["accent"].light` 派生，容差 ≤ 2/255）

```
ac-finish-ui-rendered-accent 运行中暂停按钮: expected=(180,64,11) nearest=(180,64,11) delta=0 matches=27
ac-finish-ui-rendered-accent 结束按钮: expected=(180,64,11) nearest=(180,64,11) delta=0 matches=27
ac-finish-ui-rendered-accent 保存主操作: expected=(180,64,11) nearest=(180,64,11) delta=0 matches=27
```

三处均采样按钮内非文字区域（左缘 1pt 竖线），`delta=0` 且匹配像素 27 个；`finish` 已从 secondary/warning 描边提升为 accent 填充主操作族，旧实现（无 accent 填充）必然 delta > 2 判红。

## 3. 四栏回执

### 已改文件

- `ios/PurePace/Run/RunInteractionPlan.swift`
  - `items`：`finish` 由 `.secondary` 改 `.accent`（accent 描边族）；新增 `discardConfirmation`（`cancel`=secondary / `confirm`=`discard`@danger），破坏性动作只存在于确认层。
  - `Item.tint` / `Item.style`：样式到 palette 键的单一机械派生；新增 `Tint.primary` 与 `heroTint(state:didSave:)`，hero 主值色也可 L1 断言（running/paused=accent、saved=success、ready=primary，永不 warning）。
- `ios/PurePace/Run/RunView.swift`
  - `control(for: .discardRequest)` 改为打开确认 sheet 的入口；`run.discard` 只在 `.sheet` 内（danger 描边、不填充），取消回结束待保存态。
  - 删除视图内 `stateTint` 的 `switch`，hero 统一 `valueTint: color(for: plan.heroTint)`；`actionTint` 记录态一律 accent；`warning` 只剩非阻断内联提示与其 `warningSoft` 弱底。
  - 未开始态空白收敛：hero 上内边距 `lg → sm`、指标卡下内边距 `.xxs`（既有 Spacer 分布不变）。
  - `.toolbar(.hidden, for: .tabBar)` 由 `ContentView` 移到本页 `NavigationStack`，使记录态真正收起 Tab 栏。
- `ios/PurePace/ContentView.swift`：移除 `TabView` 外层同名 `.toolbar`（避免层级冲突，tab=0 证据前置条件）。
- `ios/PurePace/Design/DesignTokens.swift`：仅注释（`warning`/`accent`/`danger` 与 `purposes` 注册表同口径），36 hex 一字未动。
- `ios/PurePace/Design/L10n.swift` + `ios/PurePace/Resources/Localizable.xcstrings`：确认层标题 / 说明 / 确认 / 取消四键，sourceLanguage=zh-Hans 单语。
- `ios/PurePaceTests/RunInteractionPlanTests.swift`：旧 `finish == .secondary` 断言按新语义改写（保留 discard / save 覆盖并新增确认层断言）；新增 hero 主值 tint 正例 + warning 反例（断言数只增不减）。
- `ios/PurePaceUITests/RunFlowUITests.swift`：`ac-finish-ui-rendered-accent` 像素断言（暂停 / 结束 / 保存）、四条 tabbar 行、`finished && !didSave` 只出 `run.discardRequest`、sheet 取消后 `run.discard` 不在屏且距离 / 时长逐字节不变、确认后才丢弃并回 `ready`。
- `ios/project.yml`：仅 `PurePaceUITests.sources` 增补 `PurePace/Design/DesignTokens.swift`（像素断言从 token 派生期望值）；签名配置与 deployment target 未动。
- `scripts/check-ios-shell.sh`：`ac-design-tokens` 的三态断言改读单一真源（`RunInteractionPlan.heroTint` + `plan.heroTint`），断言行数不减。
- `docs/verification-matrix.md` + `ios/RunCore/Tests/PurePaceRunCoreTests/DocsVerificationMatrixTests.swift`：新增 5 行（palette hex 锁定 / accent↔warning 与 accent↔danger 分离 / 深色中性 chroma / finish=accent / discard 仅在确认层），并把结构守护由 10 行同步扩到 15 行（加严，非放宽）。
- `.munk/changes/wi_intake_e7e73d829e61fa7a/digest.md`（本文件）。

### 已过门（本地实跑，原文见 `.build/logs/`）

- `bash scripts/test-ios.sh --unit-only`：`PurePaceTests` 231 tests / 0 failures；`RunCore` 165 tests / 0 failures（`unit-final2.log`）。
- `PurePaceUITests/RunFlowUITests` 5 tests / 0 failures，含 `testRunPauseResumeFinishAndHistory`（58.7s）与 `testZhHansCopyDatesAndBottomAnchoredPrimaryAction`（40.9s）（`full-final.log`）。
- `bash scripts/check-ios-shell.sh`：30 项断言 0 失败；`check-ios-scripts` 27/0；`check-ios-run-core` 11/0；`check-baseline` 11/0。
- `DocsVerificationMatrixTests` 2 tests / 0 failures（15 行矩阵）。

### 未跑门 / 已知偏差

- `xcodebuild` UI 全腿（`bash scripts/test-ios.sh` 无参）跑出 9 tests / 1 failure：仅 `EvidenceCaptureUITests/testEvidenceAx5Layout` 失败「AX5 详情缺少导出主操作」。该用例属 C 项取证套件（本项未改该文件），失败原因是全量按字母序先跑 AX5、容器被脚本 uninstall 后尚无真实归档；同会话单独重跑该用例 `TEST SUCCEEDED`（`.build/logs/ax5-alone.log`，`AX5-FIT` 四行 outOfBounds=0 overlaps=0）。属既有取证套件的前置顺序依赖，不是本项回归。
- 未跑 Android 全部门（无 Android 改动）、`.github/workflows/**`（不在范围）；最终门禁由 Host 在下一阶段统一执行。

## 4. 风险

- `RunFlowUITests` 新增的「确认丢弃 → 回 ready → 再开跑 → 再结束 → 保存」闭环多一个倒计时 + 采样周期（单用例 ~59s），是该状态机唯一可行路径（`discardFinished()` 复位会话），未删改既有保存 / 历史 / 详情断言。
- 已保存态唯一填充主操作仍是 `viewHistory`（success），本项按 PRD「记录态主操作族」口径未改其用途色。
- tab=0 收起由 `RunView` 的 `NavigationStack` 层承担，若后续在 `TabView` 外层再加 toolbar 修饰符会与子页冲突（`check-ios-shell.sh` 已覆盖 identifier 与样式契约，未覆盖该层级）。
