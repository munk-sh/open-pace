# Digest — 记录态收起 TabBar + 权限横幅降为卡片次级行

> 本文件先落预算回执；实测证据、sha256、门禁退出码与 diff 清单由 Coding/Delivery 在本轮内追加，不得预填未实测值。

## 0. 预算回执

- 预算上限：≤90 分钟、≤8M token。
- 开工时刻：2026-11-11 19:27 CST（Intake 落 prd）。
- 期望收口时刻：≤ 2026-11-11 20:57 CST。
- 超时处理：立即停手回执实际完成/未完成项，不得靠长会话自查补绿。
- **实际结果：已超墙钟。** 公司裁决 `owe_8837a88ae39e1160` 判定 128 分钟墙钟，下令即刻冻结改动并只跑必要快门。

## 1. Coding 收口回执（冻结后按裁决口径单列）

### ① 已改文件清单

| 文件 | 行数 | 性质 |
|---|---|---|
| `ios/PurePace/ContentView.swift` | +8 | 三 Tab 容器按状态显式 `.toolbar(.hidden/.visible, for: .tabBar)` |
| `ios/PurePace/Run/RunView.swift` | +7 / −3 | 后台定位降级提示由 warning 胶囊改为 `caption` 次级行（无胶囊底、无整宽弱底） |
| `ios/PurePace/Design/TabBarVisibilityPolicy.swift` | 新增（50 行） | 纯判定：`hidesTabBar` / `expectedTabBarCount` / `evaluate` |
| `ios/PurePaceTests/TabBarVisibilityPolicyTests.swift` | 新增（61 行） | L1 单测 5 例，含 2 个真实判红反例 |
| `ios/PurePaceUITests/RunFlowUITests.swift` | +81 | 实测 tab 数断言、主操作锚定在 Tab 隐藏时的等价锚点、降级提示 frame 断言 |
| `ios/project.yml` | +4 | `TabBarVisibilityPolicy.swift` 列入 UITests sources；UITests 显式声明 RunCore 包依赖 |
| `ios/PurePace.xcodeproj` | 生成物 | 由 `xcodegen generate --spec project.yml` 生成，`.gitignore` 忽略，diff 不含工程文件 |

`git diff --stat`：4 files changed, 97 insertions(+), 3 deletions(-)（不含 2 个新增未跟踪文件）。
零颜色/字号 token 改动：`RunView` 只把提示的 `Typography.caption` + `Colors.secondary` 语义 token 用于次级行，未新增/改动 token 定义。

### ② 已跑过的门与逐门结果（原文）

| 门 | 结果 |
|---|---|
| `bash -n scripts/version.sh` | rc=0 |
| `bash -n scripts/check-baseline.sh` | rc=0 |
| `bash scripts/check-baseline.sh` | rc=0 — `11 项断言，0 项失败` / `baseline OK (VERSION=0.1.0)` |
| `bash scripts/check-ios-core.sh` | rc=0 — `8 项断言，0 项失败` / `ios/Core OK` |
| `bash scripts/check-ios-scripts.sh` | rc=0 — `27 项断言，0 项失败` / `ios scripts OK` |
| `bash scripts/check-ios-release.sh` | rc=0 — `17 项断言，0 项失败` / `ios release OK` |
| `bash scripts/check-ios-shell.sh` | rc=0 — `30 项断言，0 项失败` / `ios shell OK` |
| `bash scripts/check-ios-shell.sh --self-test` | rc=0 — `self-test OK` |
| `bash scripts/check-ios-workflow.sh` | rc=0 — `ios workflow OK` |
| `bash scripts/check-ios-run-core.sh` | rc=0 — `11 项断言，0 项失败` / `ios/RunCore OK` |
| `bash scripts/check-ios-run-core.sh --self-test` | rc=0 — `ios/RunCore self-test OK` |
| `bash scripts/check-shared.sh` | rc=0 — `共 13 项断言，失败 0 项` |
| `bash scripts/check-gpx-export.sh` | rc=0 — `12 项断言，0 项失败` |
| `bash scripts/check-shell-expansion.sh` | rc=0 — `7 项断言，0 项失败` |
| `swift build --package-path ios/Core` | rc=0 — `Build complete!` |
| `swift build --package-path ios/RunCore` | rc=0 — `Build complete!` |
| `swift test --package-path ios/Core` | rc=0 — `Executed 9 tests, with 0 failures` |
| `swift test --package-path ios/RunCore` | rc=0 — `Executed 152 tests, with 0 failures` |
| `bash scripts/build-ios.sh` | rc=0 — `** BUILD SUCCEEDED **` |
| `bash scripts/test-ios.sh --unit-only` | rc=0 — xcodebuild `-only-testing:PurePaceTests`：`Executed 223 tests, with 0 failures` / `** TEST EXECUTE SUCCEEDED **`；`TabBarVisibilityPolicyTests` 5/5 passed |
| 单测反例逐条（`TabBarVisibilityPolicyTests`） | `testRecordingStateWithVisibleTabBarFails` / `testIdleStateWithHiddenTabBarFails` 真实判红（断言 `problems == ["Tab 栏数量 1 ≠ 期望 0"]` / `["Tab 栏数量 0 ≠ 期望 1"]`），正例全绿 |

**唯一实跑 UI 用例（定向、非全量）**：`xcodebuild test-without-building -only-testing:PurePaceUITests/RunFlowUITests/testZhHansCopyDatesAndBottomAnchoredPrimaryAction` → **FAILED（8.6s）**，原文：
`ac-run-metrics-balanced 未开始: top=72.58333333333334 bottom=68.58333333333326 largest=88.58333333333326 imbalance=4.000000000000085`
`error: XCTAssertTrue failed - 未开始 指标区未垂直居中（顶部留白 72.58pt，底部留白 68.58pt，最大空洞 88.58pt）：["最大单一垂直空洞 88.58333333333326pt > 80.0pt"]`

### ③ 未跑的项与原因

- `test-ios` 全量（含 `PurePaceUITests` 其余 4 例）：未跑。冻结令禁止再补断言/再跑 UI 腿，仅保留上述 1 例定向实测结果。
- `capture-ios-screenshots.sh --stage trees` / `--stage screenshots`：未跑。冻结令明确「不要再重出截图」。
- `lint-android` / `lint-android-workflow` / `build-android` / `test-android`：未在本机跑（本项零 Android diff；且收口窗口只跑 iOS 快腿），交由 Host 门禁执行。
- 真机、设备场、CI 轮询：按裁决第 5 条不跑。

### ④ 未闭合的验收点

1. **ac-layout-balance-thresholds-unchanged：红（源码阈值零改动，但运行态判红）。** 提示从 36.7pt 高胶囊降为 28.7pt 高 caption 行，四等权 Spacer 各增 2pt，`未开始` 态 hero→指标卡文本空洞由 86.6pt 变为 88.58pt > 80pt。阈值仍为 80/80/80/16；按冻结令未再调整布局或断言。
2. **ac-tabbar-hidden-recording / -paused / -finished-pending / -restore-no-deadend：未实测。** 定向 UI 用例在 `未开始` 态几何断言即中止，未走到 running/paused/finished 分支；`tabBarCount` 的实跑证据只有 `未开始: state=ready didSave=false tabBarCount=1 expected=1`。判定层已由 L1 单测（含 2 反例）覆盖。
3. **ac-permission-banner-demoted：部分闭合。** 代码已将提示改为 caption 次级行、无胶囊底；实跑 frame 证据：`ac-permission-banner-demoted hint=(17.5, 615.75, 358.0, 28.67) distance=(133.67, 243.58, 125.67, 67.0) averagePace=(104.58, 536.83, 11.33, 14.33)`（hint.minY 615.75 > distance.maxY 310.58，> averagePace.maxY 551.17）。缺浅/深截图与可及树复核。
4. **ac-evidence-screenshots：未闭合。** `run-running(-dark).png` / `run-finished(-dark).png` 未重出，`docs/screenshots/SHA256SUMS` 未更新（冻结令第 1 条）。
5. **ac-evidence-a11y-trees：未闭合。** `docs/evidence/a11y/02-run-running.txt` / `03-run-finished.txt` 未重出，现有树仍是旧胶囊帧。
6. **ac-digest-budget-receipt：本回执即回填**（墙钟超 38 分钟，按裁决冻结收口）。
7. 已闭合：`ac-a11y-identifier-diff-zero`（`git diff` 零 `accessibilityIdentifier` 行增删，`check-ios-shell` identifier 契约 30 项断言绿）、`ac-l10n-copy-preserved`（提示仍取既有 `backgroundDegradationHint` / `L10n`，无新字面量）、`ac-xcodegen-generated`（`xcodegen generate --spec project.yml` + `check-ios-shell` 的 xcodegen 双次生成断言绿）、`ac-code-gates-green` 的本地快腿部分、`ac-tabbar-assert-red-proof`（L1 纯函数 + 2 反例）。
