# AX5 取证腿收口摘要（wi_intake_17fe09b83e2a3df0）

单测 / 反例 / 单用例腿日志见同目录；运行时原始日志在 `.munk/logs/`（gitignore）。

## 1. 顺序依赖（测试侧）

- `EvidenceCaptureUITests` 的真实 seed 链路抽成唯一 `private seedRealArchive(onNotStarted:onRunning:onFinished:)`；
  `testEvidenceTreesAndRealArchive` 在原取证点用闭包回调（6 个 `attachTree`、6 条 `evidence-primary` 顺序不变）。
- `testEvidenceAx5Layout` 详情步前先只读检测（`-screenshotInitialTab history` 读 `history.row` / `history.empty`），
  仅空态 seed，非空打印 `AX5-SEED action=skip`；每次换 `XCUIApplication` 前显式 `app.terminate()`。
- 干净容器单跑：exit 0，`AX5-SEED action=seed reason=archive-empty`，容器 `Documents/Runs` = 1 条。

## 2. 结束态 AX5 溢出（生产侧，共享策略）

`RunFinishedSummaryLayoutPolicy`（`ios/PurePace/Design/RunFinishedSummaryLayoutPolicy.swift`）

| 参数 | AX5 值 | 标准档值 | 消费点 |
|---|---|---|---|
| `trackPreviewHeight` | 96（3 × `Spacing.xl`） | 180 | `RunView.swift:218` |
| `blockSpacing` | `Spacing.xxs`(4) | `Spacing.sectionGap`(12) | `RunView.swift:101`、`RunView.swift:212` |
| `cardPadding` | `Spacing.xs`(8) | `Spacing.sm`(12) | `RunView.swift:261` |
| `rowSpacing` | `Spacing.xxs`(4) | `Spacing.metricGroupSpacing`(8) | `RunView.swift:230` |

03-run-finished 前后实测（393×852，AX5）：

| 元素 | 改前 frame（bottom） | 改后 frame（bottom） |
|---|---|---|
| `run.mapPreview` | (15.5, 554.5, 362, 181) → 735.5 | (15.5, 538.5, 362, 97) → 635.5 |
| `run.finished.splits` | y=759 | y=647 |
| `run.finished.splitsEmpty` | y=785 | y=669 |
| `run.backgroundDegraded` | (22.2, 827.0, 348.7, 31.3) → **858.3（越窗）** | (22.2, 699.0, 348.7, 31.3) → 730.3 |
| `run.save` | (16, 762, 287, 44)（固定底部） | 同左 |

`AX5-FIT screen=03-run-finished ... outOfBounds=0 overlaps=0`（改前 `outOfBounds=1 overlaps=1`）。

## 3. 05-history-detail：断言口径改为滚动感知（测试侧，生产零改动）

`05` 的实际现象是惰性 `List` 未 realize 第二页（导出节点不在可及树），不是 frame 越窗。

- `Ax5ScrollAudit`（`ios/PurePaceUITests/Ax5ScrollAudit.swift`）：交互元素（button/link/switch/textField 且 App 自有
  identifier）必须「滚动可达 + frame 完整落在视口内 + 不被另一交互元素覆盖」；静态文本 / cell 只判水平不溢出，
  垂直滚出视口仅计数。视口 = window 去掉底部 Tab 栏（393×769）。
- 实测行：`AX5-SCROLL screen=05-history-detail scrolls=0 interactive=1 unreachable=0 scrollRequiredStatic=4
  interactiveViolations=0 horizontalViolations=0`；`AX5-FIT screen=05-history-detail ... outOfBounds=0 overlaps=0`。
- 四屏 `AX5-FIT screen=` 契约保留（01 / 03 / 05 / 06）。

## 4. 反例（同 commit，真跑）

| 反例 | 构造 | 失败点 |
|---|---|---|
| 水平溢出 | 静态文本 frame 宽 420 > 窗宽 393（`Ax5ScrollAuditCounterexampleTests:testHorizontalOverflowIsRejectedOnHorizontalCriterion`） | `horizontalViolations` 非空；`interactiveViolations` 为空 |
| 滚动到底仍不可点 | 交互元素 `isHittable=false`（`testUnreachableInteractiveIsRejectedOnHittableCriterion`） | `interactiveViolations` 含 `hittable=false`；`horizontalViolations` 为空 |
| 正向对照 | 仅静态文本垂直滚出视口（`testVerticalScrollingStaticContentPassesAndIsCounted`） | `passes=true` 且 `scrollRequiredStaticCount=1` |

两条反例失败点不同（水平口径 vs 交互可达性），且都区别于「空归档 30s 未出现导出」。

## 5. 腿状态

- 干净容器单用例（`uninstall → install → warmup → grant location/location-always`，AX5 字号）：
  `-only-testing:PurePaceUITests/EvidenceCaptureUITests/testEvidenceAx5Layout` → **exit 0**（`ax5-single-green.log`）。
- 同容器整包（`-only-testing:PurePaceUITests`，标准字号档 large，与 ios.yml 权威腿同口径）：
  整包腿未跑齐。事实依据：`ax5-pack-standard.log` 被截断，末行停在后续用例 `t = 7.67s`
  （`Waiting 10.0s for NavigationBar (First Match) to exist`），无整包结论。已绿范围只到单用例
  `testEvidenceAx5Layout` exit 0 与两条反例/正向对照（`ax5-counterexamples.log`）。
- 反例/口径证据：`ax5-counterexamples.log`（两条合成反例 + 正向对照）。
- 未修清单（第三处及以上，只记录不动手；其中 1) / 2) 已由 `wi_intake_1127fd3553df6ea7` 收口——标准字号档结束态压缩与详情导出固定底部，证据见 `docs/verification-matrix.md` 对应行与 `.munk/logs/g-final-ax5.log`）：
  1) 标准字号档 `03-run-finished`：`run.backgroundDegraded` (22.2, 806.0, 348.7, 31.3) 与 `run.save`
     (16, 762, 287, 44) 相交。根因是 `balancedMetrics` 的 `.frame(maxHeight: .infinity)`（RunView.swift:93）
     让 `ViewThatFits` 永远选第一分支、回退不到 `ScrollView`；建议参数：该 frame 改 `maxWidth` only，
     或在策略里加「标准档也压缩结束态」开关（需重跑 `RunLayoutBalancePolicy` 的 4 条 L1 与 3 屏截图）。
  2) 标准字号档 `05-history-detail`：`runDetail.export` 仍在第二页（trees 用例与 `RunFlowUITests`
     的同一入口），属同一惰性 List 现象；本项只在 `EvidenceCaptureUITests/testEvidenceAx5Layout` 落地了
     滚动感知口径，未改其他用例入口。
- `05-history-detail` 生产代码零改动（保持 List 可滚动）。
