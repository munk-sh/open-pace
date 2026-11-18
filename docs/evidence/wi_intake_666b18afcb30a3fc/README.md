# 三屏视觉达发布线证据（设置 / 历史列表 / 历史详情）

- work item：`wi_intake_666b18afcb30a3fc`
- 唯一代码 commit：`a8c61f9`（八文件：`DesignTokens.swift` / `L10n.swift` / `HistoryView.swift` / `RunDetailView.swift` / `SettingsView.swift` / `Localizable.xcstrings` / `DesignTokensTests.swift` / `scripts/check-ios-shell.sh`）
- 构建树 = 该 commit 树；本目录为同 commit 的 fold 面（`docs/evidence/**` 零代码改动）
- 环境：Xcode 26.3 (17C529)、模拟器 **iPhone 16 / iOS 18.6**、UDID `B3F00298-E08A-41E0-876E-6E8A75C730FD`
- 断言源：`ios/PurePaceUITests/ScreenshotEvidenceUITests.swift`（`testEvidenceScreensLight` / `testEvidenceScreensDark`）与 `ios/PurePaceUITests/EvidenceCaptureUITests.swift`（`testEvidenceAx5Layout`）

## 命令

```bash
xcodebuild build-for-testing -project ios/PurePace.xcodeproj -scheme PurePace \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' \
  -derivedDataPath .build/ios CODE_SIGNING_ALLOWED=NO
xcodebuild test-without-building -project ios/PurePace.xcodeproj -scheme PurePace \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' -derivedDataPath .build/ios \
  -only-testing:PurePaceTests/DesignTokensTests CODE_SIGNING_ALLOWED=NO
# AX5：先 simctl ui <udid> content_size accessibility-extra-extra-extra-large
xcodebuild test-without-building … -only-testing:PurePaceUITests/EvidenceCaptureUITests/testEvidenceAx5Layout
xcrun simctl ui <udid> content_size medium
# 截图：simctl ui appearance light|dark 后各跑一条
xcodebuild test-without-building … -only-testing:PurePaceUITests/ScreenshotEvidenceUITests/testEvidenceScreensLight
xcodebuild test-without-building … -only-testing:PurePaceUITests/ScreenshotEvidenceUITests/testEvidenceScreensDark
xcrun xcresulttool export attachments --path <xcresult> --output-path <dir>   # 直出 PNG，未裁切/未改色
```

两条截图腿均 exit 0（`xcodebuild-light.log` / `xcodebuild-dark.log`），每条 9 张附件；9 屏 × 浅/深 = 18 张入库。

## AX5 越界（同一断言、阈值未放宽）

| 屏 | 改前（HEAD `9560b69`） | 改后（`a8c61f9`） |
|---|---|---|
| 06-settings | `outOfBounds=2`，两个 consent cell 底边 **860.67 > 852（越界 8.67pt）** → 判红 | `outOfBounds=0 overlaps=0` → 绿 |
| 01-run-not-started / 03-run-finished / 05-history-detail | 0 / 0 / 0 | 0 / 0 / 0 |

改前失败原文见 `ax5-before-failure.txt`，改后逐屏实测行见 `ax5-after.txt`。修法是把诊断区收进「高级」分组并默认折叠（折叠态不渲染诊断卡），首屏内容整体收进窗口；断言本体 `assertFitsAndNoOverlap` 与 `window±1` 阈值零改动。

## 其余实测

- `PurePaceTests/DesignTokensTests`：33 例 0 失败（含新增 `testScreenSpacingPolicyAcceptsReleaseLineTokens` / `testScreenSpacingPolicyRejectsBelowFloorValues`，12/12/12 三项同输入必红）。
- `bash scripts/check-ios-shell.sh --self-test`：102 项断言 0 失败（identifier 计数随新增 `settings.advanced` 同步 63/64）。
- 间距：`Spacing.sectionGap` 12→24（`lg`）、历史行与详情卡内边距取 `cardPadding 16`、三张 List 走 `.listSectionSpacing(Spacing.sectionGap)`；设置 / 历史 / 详情每组都有分组标题 + 一句说明。

## 文件

| 文件 | 说明 |
|---|---|
| `run-not-started-*.png` / `run-running-*.png` / `run-finished-*.png` / `b1-finished-*.png` / `discard-confirmation-*.png` / `c2-discard-*.png` | 跑步域既有屏（浅/深各一张，回归旁证） |
| `history-list-*.png` / `history-detail-*.png` / `settings-*.png` | 本项三屏（浅/深各一张） |
| `xcodebuild-light.log` / `xcodebuild-dark.log` | 两条截图腿原始日志（本 commit 构建） |
| `ax5-before-failure.txt` / `ax5-after.txt` | 06-settings AX5 越界改前失败原文与改后同一断言实测 |
| `SHA256SUMS` | 18 张 PNG 的 sha256（`shasum -a 256 -c SHA256SUMS` 通过） |

## 未做

- 未跑 CI 全量 UI 腿（`RunFlowUITests` 等）作为本项判定依据，仅跑本项三屏相关 UI 腿与单测类；完整门禁由 Host `code_gates` 判定。
- 真机观感 `pending: 待人现场`；未改 `VERSION`、未打 tag、未出包。
