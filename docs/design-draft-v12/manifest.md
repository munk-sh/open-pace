# V1.2 设计稿渲染清单（docs/design-draft-v12/）

- 设备：iPhone 16（iOS 18.6 模拟器，UDID `B3F00298-E08A-41E0-876E-6E8A75C730FD`）
- 逻辑尺寸：393 × 852 pt（竖屏，iPhone 16）
- 缩放倍率：@3x；像素尺寸：1179 × 2556
- 生成入口：`bash scripts/capture-design-draft-v12.sh`（本轮运行日志 `render.log`）
- 校验：`shasum -a 256 -c docs/design-draft-v12/SHA256SUMS`

| # | 文件 | 逻辑尺寸 | 倍率 | 像素尺寸 |
|---|---|---|---|---|
| 1 | `a1-history-detail.png` | 393×852pt | @3x | 1179×2556 |
| 2 | `a1-history-list.png` | 393×852pt | @3x | 1179×2556 |
| 3 | `a1-run-finished.png` | 393×852pt | @3x | 1179×2556 |
| 4 | `a1-run-not-started.png` | 393×852pt | @3x | 1179×2556 |
| 5 | `a1-run-running.png` | 393×852pt | @3x | 1179×2556 |
| 6 | `a1-settings.png` | 393×852pt | @3x | 1179×2556 |
| 7 | `a2-history-detail.png` | 393×852pt | @3x | 1179×2556 |
| 8 | `a2-history-list.png` | 393×852pt | @3x | 1179×2556 |
| 9 | `a2-run-finished.png` | 393×852pt | @3x | 1179×2556 |
| 10 | `a2-run-not-started.png` | 393×852pt | @3x | 1179×2556 |
| 11 | `a2-run-running.png` | 393×852pt | @3x | 1179×2556 |
| 12 | `a2-settings.png` | 393×852pt | @3x | 1179×2556 |
| 13 | `b1-finished-dark.png` | 393×852pt | @3x | 1179×2556 |
| 14 | `b1-finished-light.png` | 393×852pt | @3x | 1179×2556 |
| 15 | `b2-finished-dark.png` | 393×852pt | @3x | 1179×2556 |
| 16 | `b2-finished-light.png` | 393×852pt | @3x | 1179×2556 |
| 17 | `c1-discard-dark.png` | 393×852pt | @3x | 1179×2556 |
| 18 | `c1-discard-light.png` | 393×852pt | @3x | 1179×2556 |
| 19 | `c2-discard-dark.png` | 393×852pt | @3x | 1179×2556 |
| 20 | `c2-discard-light.png` | 393×852pt | @3x | 1179×2556 |

共 20 张 PNG。

## 运行期实测高度（pt，取最后一次量测）

| 变体 | 量测点 | 实测高 |
|---|---|---|
| `a1-run-not-started` | `run.content` | 551.3 |
| `a1-run-not-started` | `run.hero` | 135.3 |
| `a1-run-not-started` | `run.metrics` | 166.3 |
| `a1-run-running` | `run.content` | 551.3 |
| `a1-run-running` | `run.hero` | 135.3 |
| `a1-run-running` | `run.metrics` | 187.7 |
| `a1-run-finished` | `run.content` | 568.3 |
| `a1-run-finished` | `run.hero` | 135.3 |
| `a1-run-finished` | `run.map` | 96.0 |
| `a1-run-finished` | `run.metrics` | 155.7 |
| `a1-run-finished` | `run.splits` | 90.0 |
| `a1-history-list` | `history.row` | 101.7 |
| `a1-history-detail` | `detail.distance` | 128.3 |
| `a1-history-detail` | `detail.map` | 232.0 |
| `a1-history-detail` | `detail.metrics` | 117.7 |
| `a1-history-detail` | `detail.splits` | 88.0 |
| `a1-settings` | `settings.toggleRow` | 85.7 |
| `a2-run-not-started` | `run.content` | 551.3 |
| `a2-run-not-started` | `run.hero` | 135.3 |
| `a2-run-not-started` | `run.metrics` | 166.3 |
| `a2-run-running` | `run.content` | 551.3 |
| `a2-run-running` | `run.hero` | 135.3 |
| `a2-run-running` | `run.metrics` | 187.7 |
| `a2-run-finished` | `run.content` | 568.3 |
| `a2-run-finished` | `run.hero` | 135.3 |
| `a2-run-finished` | `run.map` | 96.0 |
| `a2-run-finished` | `run.metrics` | 155.7 |
| `a2-run-finished` | `run.splits` | 90.0 |
| `a2-history-list` | `history.row` | 101.7 |
| `a2-history-detail` | `detail.distance` | 128.3 |
| `a2-history-detail` | `detail.map` | 232.0 |
| `a2-history-detail` | `detail.metrics` | 117.7 |
| `a2-history-detail` | `detail.splits` | 88.0 |
| `a2-settings` | `settings.toggleRow` | 85.7 |
| `b1-finished` | `finished.hint` | 23.7 |
| `b1-finished` | `finished.map` | 360.0 |
| `b1-finished` | `finished.metrics` | 117.7 |
| `b1-finished` | `finished.splits` | 114.0 |
| `b1-finished` | `screen.actionBar` | 68.0 |
| `b1-finished` | `screen.content` | 667.3 |
| `b2-finished` | `finished.hint` | 23.7 |
| `b2-finished` | `finished.map` | 220.0 |
| `b2-finished` | `finished.metrics` | 117.7 |
| `b2-finished` | `finished.summary` | 60.0 |
| `b2-finished` | `screen.actionBar` | 68.0 |
| `b2-finished` | `screen.content` | 652.3 |
| `b2-finished-expanded` | `finished.hint` | 23.7 |
| `b2-finished-expanded` | `finished.map` | 220.0 |
| `b2-finished-expanded` | `finished.metrics` | 117.7 |
| `b2-finished-expanded` | `finished.splits` | 103.0 |
| `b2-finished-expanded` | `finished.summary` | 171.0 |
| `b2-finished-expanded` | `screen.actionBar` | 68.0 |
| `b2-finished-expanded` | `screen.content` | 652.3 |
| `c1-discard` | `finished.hint` | 23.7 |
| `c1-discard` | `finished.map` | 220.0 |
| `c1-discard` | `finished.metrics` | 117.7 |
| `c1-discard` | `finished.summary` | 60.0 |
| `c1-discard` | `screen.actionBar` | 68.0 |
| `c1-discard` | `screen.content` | 652.3 |
| `c1-discard` | `sheet.panel` | 210.0 |
| `c1-discard` | `sheet.primary` | 44.0 |
| `c1-discard` | `sheet.title` | 24.0 |
| `c2-discard` | `finished.hint` | 23.7 |
| `c2-discard` | `finished.map` | 220.0 |
| `c2-discard` | `finished.metrics` | 117.7 |
| `c2-discard` | `finished.summary` | 60.0 |
| `c2-discard` | `screen.actionBar` | 68.0 |
| `c2-discard` | `screen.content` | 652.3 |
| `c2-discard` | `sheet.panel` | 143.7 |
| `c2-discard` | `sheet.title` | 24.0 |
