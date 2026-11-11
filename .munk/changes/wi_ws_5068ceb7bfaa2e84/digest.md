# 历史路径闭环：下钻/返回、空态 CTA、读取失败态 — 交付回执

## 预算与时间窗

- 开工时刻：2026-11-11 14:00 CST
- 预算时长：80 分钟（路径与状态机 ≤30 / 失败态与重试 ≤25 / 断言与回归 ≤15 / 证据 ≤10）
- 期望收口绝对时刻：2026-11-11 15:20 CST

### 执行跟踪

- 实际收口时刻：2026-11-11 14:15 CST（预算内）
- 是否超时停手：否
- 未完成项：
  - 失败态说明句：既有 L10n 键中无语义相符者（`run.action.retryLocation` 只覆盖「重试」动作），按约束不渲染任何说明句，登记 `pending: 待人现场`。
  - 真机 / 模拟器观感与手势返回项：`pending: 待人现场`（本项明确不做 UI/XCUITest 用例）。

## 改动文件清单

`git diff --name-only`（已跟踪文件）：

```
ios/PurePace/History/HistoryView.swift
```

新增文件（未跟踪）：

```
ios/PurePace/History/HistoryViewState.swift
ios/PurePaceTests/HistoryViewStateTests.swift
```

- `ios/PurePace.xcodeproj` 已由 `xcodegen generate --spec ios/project.yml --project ios` 重生成，但该产物在 `.gitignore` 中（仓库不入库 `.xcodeproj`），故 `git status` 无此项。
- 范围外零 diff：`git diff --name-only -- ios/PurePace/Design ios/PurePace/Resources ios/PurePace/Run ios/PurePace/Settings ios/project.yml scripts docs android shared ios/PurePace/ContentView.swift` → 0 行（`ContentView.swift` 未改，空态 CTA 的 Tab 切换沿用既有 `onRunAgain: { selection = .run }`）。

## 实现要点

- **单一导航真源**：`NavigationStack(path: $state.path)` + 行 `NavigationLink(value: record.id)` + `navigationDestination(for: UUID.self)`；删除 `detailPresented` / `detailRecord` 双轨。路径只存 `UUID`，详情按 id 在 `state.records` 就地查找构造 `RunDetailView(record:)`。
- **读取触发守卫**：`onAppear` + `onChange(of: refreshToken)` 统一走 `HistoryViewState.load(token:force:)`，`loadedToken` 守卫使同一 token 只读 1 次；返回列表根不重建数据 / 顺序 / 滚动。
- **失败态独立**：`archiveStore.list()` 在 `HistoryView.swift` 内用 `try` 交给 `state.load`，抛错映射 `.failed`，与 `.loaded([])`（空态）可判等区分；失败态只渲染 `L10n.runActionRetryLocation`（「重试」）按钮，`accessibilityLabel` + `minHeight: minTapTarget`，可重复重试。
- **空态 CTA**：`state.popToRoot()` + `onRunAgain()`，不触达 `RunSessionViewModel`。
- **刷新收敛**：`reconcilePath()` 在新读取结果中找不到当前 id 时清空路径；仍存在则保留。
- **截图门控保留**：`autoOpenFirstDetail` 改为初始化路径（`openFirstDetailIfNeeded`），仍只执行一次。

## 证据

### 1. identifier 集合（33 项等值不变）

合并 `accessibilityIdentifier("...")` 与 `identifier: "..."` 两种写法后 `sort -u` 计数：

```
$ { grep -rhoE --include='*.swift' 'accessibilityIdentifier\("(run|runDetail|history|tab|settings)\.[A-Za-z0-9_.]+"\)' ios/PurePace; \
    grep -rhoE --include='*.swift' 'identifier: "(run|runDetail|history|tab|settings)\.[A-Za-z0-9_.]+"' ios/PurePace; } \
  | sed -E 's/.*"([^"]*)".*/\1/' | sort -u | tr '\n' ' ' | wc -w
33
```

`lint-ios-shell` 内 `validate_design_tokens` 的 33 项等值断言通过（见门禁片段）。

### 2. 冻结面零 diff

```
$ git diff --name-only -- ios/PurePace/Design ios/PurePace/Resources ios/PurePace/Run ios/PurePace/Settings ios/project.yml scripts docs android shared ios/PurePace/ContentView.swift | wc -l
0
```

`Localizable.xcstrings` / `Design/L10n.swift` / `scripts/**` 均无改动（`git status --porcelain` 仅列出上节 4 项）。

### 3. 新增 L1 用例（`ios/PurePaceTests/HistoryViewStateTests.swift`）

- `testEmptyArchiveAndFailureAreDistinctStates`
- `testRetryRecoversIntoRecords`
- `testRetryRecoversIntoEmptyState`
- `testRetryAfterRepeatedFailureStaysFailedAndRetryable`
- `testSameTokenLoadsOnceAcrossDrilldownAndBack`
- `testRefreshClearsStaleDetailAndKeepsExistingDetail`
- `testFailureClearsOpenDetailPath`
- `testRunAgainClearsPathAndPreservesLoadedRecords`
- `testAutoOpenFirstDetailRunsOnlyOnce`

`bash scripts/test-ios.sh --unit-only` 执行摘要（`.build/logs/xcodebuild-unit.log`）：

```
Executed 208 tests, with 0 failures (0 unexpected) in 2.532 (2.596) seconds
info: RunCore SwiftPM 测试完成（Executed 152 tests, with 0 failures）
```

### 4. 门禁命令 + exit code

```
$ bash scripts/check-ios-shell.sh
30 项断言，0 项失败
ios shell OK
exit=0

$ bash scripts/check-ios-shell.sh --self-test
84 项断言，0 项失败
self-test OK
exit=0

$ bash scripts/test-ios.sh --unit-only
Executed 208 tests, with 0 failures
exit=0

$ bash scripts/build-ios.sh
** BUILD SUCCEEDED **
exit=0

$ bash scripts/check-baseline.sh
11 项断言，0 项失败
baseline OK (VERSION=0.1.0)
exit=0
```

同批静态门（均 exit=0）：`check-ios-core`、`check-ios-scripts`、`check-ios-release`、`check-ios-workflow`、`check-ios-run-core`、`check-gpx-export`、`check-shared`、`check-shell-expansion`。

### 5. 不作为本项验收

截图、模拟器观感、手势返回、真机项：`pending: 待人现场`。
