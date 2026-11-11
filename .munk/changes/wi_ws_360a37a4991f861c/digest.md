# History 列表 / 详情 / 空态重建 — 施工回执

## 预算（开工先写）

- 开工时刻：2026-11-11 12:41 CST（2026-11-11T04:41Z）
- 预算时长：100 分钟（列表 ≤30 / 详情 ≤40 / 空态与回归 ≤20 / 证据 ≤10）
- 期望收口绝对时刻：2026-11-11 14:21 CST（2026-11-11T06:21Z）
- 实际收口：2026-11-11 12:51 CST（预算内，未超时）
- 超时处置：预算耗尽仍未完成时落盘现状，写明「超时停手」与未完成项，不静默延长会话。

## 改动文件清单与 diff 范围

`git diff --name-only`：

```
ios/PurePace/History/HistoryView.swift
ios/PurePace/History/RunDetailView.swift
ios/PurePaceTests/RunDetailContentTests.swift
```

- 未新增源文件，因此未重生成 `ios/PurePace.xcodeproj`（`xcodegen` 无需运行）。
- `git diff --stat`：3 files changed, 209 insertions(+), 74 deletions(-)。
- 冻结面 `git diff --name-only -- ios/PurePace/Resources ios/PurePace/Design ios/PurePace/ContentView.swift ios/PurePace/Run ios/PurePace/Settings ios/project.yml ios/PurePaceUITests scripts docs/screenshots android shared .munk/code-gates.json` 输出为空。
- 实现要点：
  - `HistoryView`：行改为三层（日期 `title`+`primary`；距离/用时/配速三数值同一行、`body`+`primary`+`monospacedDigit()`；三个 `metricLabel`+`secondary` 标签按列一一对应）；三数值组装抽为 `HistoryView.swift` 内纯值类型 `HistoryRowContent`（复用 `RunFormatting`，含 `accessibilityLabel`）；空态保持「标题 + 一句说明 + 唯一 CTA」并以 `metricGroupSpacing/Gap` 收紧层距。
  - `RunDetailView`：纵向序改为 元信息 → hero 距离（`display`）→ 指标网格（`primaryValue` 值在上 / `metricLabel` 标签在下）→ 分段 → 导出；块间用 `.listSectionSpacing(Spacing.sectionGap)`，卡内用 `metricGroupSpacing`，`hairline` + `separator` 仅作卡内分隔；导出流程、`RunExportState`、identifier 与文案键零改动。
  - `RunDetailContentTests`：新增 2 条 L1 断言（行与详情三数值逐字符相等、行日期是详情开始时间前缀、行 a11y label 含 ` km` / `:` / `/km`）。

## identifier 集合 / 冻结面证据

- 按门禁同口径统计 `ios/PurePace/**/*.swift` 的 `(run|runDetail|history|tab|settings).*` identifier 去重数量：`33`（与冻结清单一致）。
- `bash scripts/check-ios-shell.sh` 中 `ac-design-tokens` / `ac-live-run-ui` 均 PASS（内含 33 项等值断言）。
- `Resources/Localizable.xcstrings`、`Design/L10n.swift`、`DesignTokens.swift`、`docs/screenshots/**` 零 diff。

## 门禁输出片段（本地实测）

- `bash scripts/check-ios-shell.sh` → 末尾 `29 项断言，0 项失败`、`ios shell OK`，exit 0（含 design token 正反例自检与 33 项 identifier 等值断言）。
- `bash scripts/test-ios.sh --unit-only` → exit 0；`PurePaceTests` 腿 `Executed 181 tests, with 0 failures (0 unexpected)`；`RunCore` SwiftPM 腿 `Executed 141 tests, with 0 failures`；其中 `RunDetailContentTests testHistoryRowSharesDetailTextsAndDatePrefix / testHistoryRowLabelCarriesDateAndThreeMetrics` passed。
- `bash scripts/build-ios.sh` → `** BUILD SUCCEEDED **`，产物 `.build/ios/Build/Products/Debug-iphonesimulator/PurePace.app`。
- 其余门禁（lint-ios-* / test / build-android / test-android / check-*）本次未改动其受管面；由 Host 统一跑 22 门作交付真值，本回执不预判全绿。

## 静态证据

- `grep -rnE "Color\(|UIColor|colorScheme|\.shadow\(|\.font\(\.|Font\.system\(|lineLimit\(|minimumScaleFactor|truncationMode|\.animation\(|withAnimation\(" ios/PurePace/History/` → 无命中。
- `Colors.accent` 仅出现在可点击控件：`history.runAgain` 背景、`runDetail.export`、`runDetail.share`、以及 `.tint`。

## 模拟器旁证截图（只作旁证，非验收前置；均落本目录，未写 `docs/screenshots/**`）

| 文件 | 场景 | sha256 |
|---|---|---|
| `history-list-light.png` | History 列表行三层（浅色） | `ff471fddb9855fd9049c59538f7f675ea071cd0f1206039ba1944aae084560d6` |
| `detail-light.png` | 跑次详情五段纵向序（浅色） | `5d542b9a1b445dddbc2c9576a0a2448a08126c883daa737a65deea0ecddc7312` |
| `history-empty-light.png` | History 空态单 CTA（浅色） | `5fec50a9619440548e7e0a2272de45bd50d54ec0239c709e1ced76867b454569` |
| `detail.png` | 跑次详情（深色） | `f569d01674534ae9d545b0ea49a4e25937399b94985cd93ffe02b27c496f4944` |

- 截图中 `runDetail.export`（导出 GPX 按钮）位于首屏、未滚动即可见，导出区与 footer 均在 Tab 栏之上。
- 真机项（锁屏定位、音频实听、授权弹窗观感）：`pending: 待人现场`。
