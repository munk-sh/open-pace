# B1 结束态 / C2 丢弃确认层 截图证据

- work item：`wi_intake_93f2857d51330b9d`（V1.2 定稿落地：B1 结束态版式与 C2 丢弃确认弹窗）；本目录由机械收口项 `wi_intake_677e501cd4f74e4f` 入仓
- 构建 head sha：`96b7d0162340ed2de3e5cf52f26a1b65c8b2471a`（本项唯一实现 commit，parent `eceedb90948706b813073c9b664074e3df3b116a`）
- 构建树 sha：`c06abafc1f0cbc843570a7ecd13f23f840d452de`（`git rev-parse 96b7d01^{tree}`：截图构建树 = 交付代码树，证据 commit 只改 `docs/evidence/**`）
- patch sha256：`f3ed82dd52ac21dbaa7039460126045fb305a5e7f52b71eb11359a0dfba8ccae`（`b1c2-staged.patch`，15 文件 / +759 −208，机械 apply 后在本项补 inline 权限胶囊单行化与取数闭环）
- 版本：`VERSION` = `0.1.0`；Xcode 26.3 (17C529)；模拟器 iPhone 16 / iOS 18.6
- 断言源：`ios/PurePaceUITests/ScreenshotEvidenceUITests.swift`（`testEvidenceScreensLight` / `testEvidenceScreensDark`）
- 版式源：`ios/PurePace/Run/RunView.swift`、`ios/PurePace/Design/RunFinishedSummaryLayoutPolicy.swift`、`ios/PurePace/Run/RunInteractionPlan.swift`

## 命令

```bash
bash scripts/test-ios.sh --unit-only   # build-for-testing + simctl install（test-without-building 不装 App）

xcrun simctl ui <udid> appearance light
xcodebuild test-without-building -project ios/PurePace.xcodeproj -scheme PurePace \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' \
  -derivedDataPath .build/ios \
  -only-testing:PurePaceUITests/ScreenshotEvidenceUITests/testEvidenceScreensLight \
  -resultBundlePath /tmp/ev-light.xcresult CODE_SIGNING_ALLOWED=NO

xcrun simctl ui <udid> appearance dark
xcodebuild test-without-building ... -only-testing:PurePaceUITests/ScreenshotEvidenceUITests/testEvidenceScreensDark
xcrun simctl ui <udid> appearance light   # 段后恢复浅色
```

两条腿均 exit 0；`xcrun xcresulttool export attachments` 直出 PNG，未裁切/未改色/未改名（按 `suggestedHumanReadableName` 取 `b1-finished[-dark]` / `c2-discard[-dark]` 四个附件）。

## 实测断言（本项 commit 的同一构建）

- `evidence-b1-finished mapHeight=361.0 screenHeight=852.0`：`run.mapPreview` = 361pt（容差 1 内视为 360），≥ 852×40% = 340.8。
- 结束待保存态同屏存在 `run.distance` / `run.elapsed` / `run.averagePace`。
- `evidence-inline-hint hint=(72.67, 679.33, 248.0, 23.67) maxHeight=32.0`：inline 权限胶囊实测 **248.0 × 23.67pt**（≤32 且宽 248.0 < 内容宽 361，不占满整行）。改前同屏实测为整行 360 × 39.33pt（zh-Hans 长句换 2 行），本次按设计稿 B/C 组形态改为「图标 + 短文案」单行胶囊；完整长句仍挂 `accessibilityLabel`（VoiceOver 语义不丢）。
- `evidence-c2-discard screenHeight=852.0 sheetTop=682.33 sheetHeight=169.67 title=(68,690.33,125,24) confirm=(16,750,235.67,44) cancel=(263.67,750,113.33,44)`：sheet 顶边由确认层标题静态文本 `frame.minY − Spacing.xs` 推导（不再用 `app.sheets`：iOS 18.6 上它不匹配 SwiftUI `.presentationDetents` sheet，旧日志出现 `sheetExists=false` 与 `height=167` 并存的矛盾），推导顶边 682.33 ≥ 852×70% = 596.4、高度 169.67 ≤ 200；`run.discard` 44pt、confirm 与 cancel 同行（中心差 0pt）。
- sheet 高度由 `onGeometryChange` 实测内容高度驱动 `.presentationDetents([.height(...)])`，无 `.medium` 固定档。
- B1 内容预算（RunFlow 腿同构建）：`contentHeight=593.83 contentBottom=703.0 saveTop=762.0`（≤691 且不压主操作）；主操作条 68pt（save 44pt）。

## 证据新鲜度（旧归档 → 本项 commit）

| 文件 | 旧 sha256（归档） | 新 sha256（本项构建） |
|---|---|---|
| `b1-finished-light.png` | `1aff922a…e1890` | `bd05500a…907a0` |
| `b1-finished-dark.png` | `51f2fd46…86f9` | `e7c77ec7…2930` |
| `c2-discard-light.png` | `486c8020…5a24` | `e19de805…4c53` |
| `c2-discard-dark.png` | `987f66f1…ee65` | `934415e8…514f` |

四张哈希全部变化（inline 权限胶囊由整行两行改为单行紧凑胶囊，属已授权的唯一视图改动），因此按 `ac-evidence-fresh-or-proven` 用本项构建重出的图替换归档图，并同步 `SHA256SUMS` 与本文实测值。`shasum -a 256 -c SHA256SUMS` 通过。

## 文件

| 文件 | 说明 |
|---|---|
| `b1-finished-light.png` / `b1-finished-dark.png` | B1 结束待保存态（地图 hero 360 + 距离常显 + 指标行 + 分段 + 单行 inline 胶囊） |
| `c2-discard-light.png` / `c2-discard-dark.png` | C2 丢弃确认层（danger 实心主操作 + 无填充文字次操作） |
| `xcodebuild-light.log` / `xcodebuild-dark.log` | 两条证据 UI 腿原始日志（本项 commit 构建） |
| `xcodebuild-runflow-b1c2.log` | B1/C2 真实链路腿日志（`ac-inline-hint-measured` / `ac-c2-sheet-autosize` 实测行） |
| `xcodebuild-runflow-saved.log` | 保存态无分段腿日志（地图 ≥360 与 80/80/16 平衡判据） |
| `SHA256SUMS` | 4 张 PNG 的 sha256（`shasum -a 256 -c SHA256SUMS` 通过） |

## 未做（非本项范围）

- 未跑 `.github/workflows/ios.yml` 权威腿；未重出 14 张复评截图（写项③）。
- 未改 `VERSION`（0.1.0）、未改 token 色值/对比度阈值、未新增/改名 accessibilityIdentifier。
