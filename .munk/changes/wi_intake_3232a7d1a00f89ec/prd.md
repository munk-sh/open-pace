# 重出 V1.2 复评运行态截图证据，并把证据 sha256 重新绑定到权威 commit c122dbb

## 范围

纯证据重出与重绑定项，**零产品代码改动**：

1. 用仓内既有机制（`ios/PurePaceUITests/ScreenshotEvidenceUITests.swift` 的 `testEvidenceScreensLight` /
   `testEvidenceScreensDark`，经 `xcodebuild` 驱动 iOS 模拟器 + `xcrun xcresulttool export attachments` 导出）
   实取两张运行态截图：`docs/screenshots/run-running.png`、`docs/screenshots/run-running-dark.png`。
2. 重跑 `scripts/compose-ios-screenshots-side-by-side.sh` 重建 `docs/screenshots/side-by-side/` 下 7 张并排图
   （run-not-started / run-running / run-finished / history-list / history-detail / settings / discard-confirmation），
   并更新该目录 `SHA256SUMS`。
3. 其余 12 张屏（run-not-started、run-finished、history-list、history-detail、settings、discard-confirmation
   各自浅/深）**不主动重出**，但必须把本次实取附件逐张与已入库 sha 比对：一致的保留原文件（字节零改动）；
   不一致的用本次实取替换，并在证据 README 逐张写明旧 sha / 新 sha 与原因。
4. 重写 `docs/screenshots/SHA256SUMS`：sha256 全部实取，头部补齐绑定四要素与零 diff 声明。
5. 新建本次证据目录 `docs/evidence/wi_intake_3232a7d1a00f89ec/`：截图与并排图的 `SHA256SUMS`、
   浅/深并排对照说明、逐图断言来源文件路径、`xcodebuild-light.log` / `xcodebuild-dark.log` 原始运行日志。

绑定基线（前提事实，已核）：产品代码最终 commit = `c122dbb1f38b3fd2bde9b23a93bfb67f7b8b3089`（main，merge），
该 head 的 `ios.yml` RUN#43268890057 = success、`android.yml` RUN#43268890273 = success；
运行/暂停态指标区垂直居中已修（暂停 79.42/79.33/79.5，未开始 72.5/72.33/72.67，保存 48.17，均 ≤80）。
本项**不再改任何 UI、token、阈值、identifier、CI 脚本与门禁**。

## 验收标准

- ac-shots-fresh-from-c122dbb: `docs/screenshots/run-running.png` 与 `docs/screenshots/run-running-dark.png` 由
  `c122dbb1f38b3fd2bde9b23a93bfb67f7b8b3089` 产品树构建的 `ScreenshotEvidenceUITests` 实取；采集时
  `git diff --stat c122dbb1f38b3fd2bde9b23a93bfb67f7b8b3089 -- ios/PurePace ios/RunCore` 输出为空（非空即未闭合）；
  两张新图 sha256 均不等于采集前旧值（`run-running` = `9a9ba019e1b3e964d648475c34b96390a6db03652c23cabcbbbe1bd3c72d3699`，
  `run-running-dark` = `b42fb536cbab1972640a2d6b822af69c66a03a3ee3e58e896a3e0a499b8da996`），且两张互相不同。

- ac-sums-screenshots-pass: 在仓库根执行 `shasum -a 256 -c docs/screenshots/SHA256SUMS` 退出码 0；
  清单恰 14 行 PNG 哈希（与 `docs/screenshots/*.png` 一一对应），头部含四要素：
  构建 head sha = `c122dbb1f38b3fd2bde9b23a93bfb67f7b8b3089`（完整 40 位）、构建 tree sha = 实取、采集时
  `git rev-parse HEAD` 实值、归属项 `wi_intake_3232a7d1a00f89ec`；并含「采集时 ios/PurePace/**、ios/RunCore/**
  相对 c122dbb 零 diff」声明。

- ac-sums-side-by-side-pass: 在仓库根执行 `shasum -a 256 -c docs/screenshots/side-by-side/SHA256SUMS` 退出码 0；
  7 张并排图齐备且每张像素尺寸 = 宽 2×原宽、高 = 原高（浅色原图 1178×2556 → 并排 2356×2556）；
  6 张非运行态并排图的内容若因原图未变而字节不变，则其 sha 保持原值（可对照采集前清单）。

- ac-twelve-verified: 其余 12 张逐张给出「已入库 sha ⟷ 本次实取 sha ⟷ 判定（一致/替换）」三列对照，落入
  `docs/evidence/wi_intake_3232a7d1a00f89ec/README.md`；判定为一致的图，`git diff --name-only` 中不得出现该
  文件（即字节零改动）；判定为替换的图必须写明旧/新 sha 与非布局漂移原因（如运行计时读数差异），且不得借该
  替换改动任何判据、阈值或断言口径。

- ac-evidence-dir: `docs/evidence/wi_intake_3232a7d1a00f89ec/` 至少含 `README.md`、`SHA256SUMS`、
  `xcodebuild-light.log`、`xcodebuild-dark.log`；在该目录 `shasum -a 256 -c SHA256SUMS` 退出码 0；
  两份日志各含 7 条 `evidence-shot screen=` 行（深色带 `-dark` 后缀）、含 `** TEST SUCCEEDED **` 结论行，
  且含 `ac-run-metrics-balanced` 的「未开始」「暂停」「保存态」三态实测行，各态 top / bottom / largest 均 ≤ 80；
  日志为完整 xcodebuild 输出，不得为截断片段。

- ac-assert-sources-listed: 证据 README 逐图列出断言来源文件路径（至少
  `ios/PurePaceUITests/ScreenshotEvidenceUITests.swift`、`ios/PurePaceUITests/AXSnapshotBatch.swift`、
  `ios/PurePaceUITests/RunFlowUITests.swift`（`ac-run-metrics-balanced` 打印处）），并在回执中给全路径。

- ac-scope-purity: `git diff --stat c122dbb1f38b3fd2bde9b23a93bfb67f7b8b3089 -- ios scripts .github android shared .munk/code-gates.json`
  输出为空；全量改动只落在 `docs/screenshots/**`、`docs/evidence/**`（可含 `.munk/changes/wi_intake_3232a7d1a00f89ec/**`
  与 `.munk/baseline/**`）。

- ac-no-overclaim: 交付回执只列实际产出的文件、sha 与校验结果；不得出现「UI 达标」「可发布」「已验证真机」类
  结论；未取到新图或未能完成 c122dbb 绑定时，回执必须写「未闭合」，不得复用旧 sha 冒充新证据。

## 非目标

- 不改 UI 代码、`DesignTokens`、`RunView` / 结束态版式、`RunFinishedSummaryLayoutPolicy`、任何 token 数值。
- 不改 identifier、不改文案、不改 `RunFlowUITests.swift` 的断言与 80pt 阈值 / 采样口径。
- 不改 `scripts/**`（含 `capture-ios-screenshots.sh`、`compose-ios-screenshots-side-by-side.sh`）、
  不改 `.github/workflows/**`、不改 `.munk/code-gates.json`（仍 22 门）。
- 不跑真机、不做分发包（ipa / TestFlight / tag / Release / ASC）、不新建人任务卡、不重跑 CI。
- 不重建 `docs/evidence/screenshot-refresh/`、`docs/evidence/wi_intake_93f2857d51330b9d/` 等既往批次证据。

## 实现约束（已核对的落点与红线，非正式技术方案）

**绑定四要素（`docs/screenshots/SHA256SUMS` 头部必须逐项写明）**

| 字段 | 取值要求 |
|---|---|
| 构建 head sha | `c122dbb1f38b3fd2bde9b23a93bfb67f7b8b3089`（完整 40 位，不得缩写） |
| 构建 tree sha | 实取 `git rev-parse c122dbb1f38b3fd2bde9b23a93bfb67f7b8b3089^{tree}`（当前已知 `bf32815bc8a5dd788f0735d975ae530cc1fa1588`，采集时重取比对） |
| 采集时 HEAD | 实取 `git rev-parse HEAD`（采集时值，可为本项 prd/baseline 提交） |
| 归属项 | `wi_intake_3232a7d1a00f89ec` |
| 零 diff 声明 | 「采集时 `ios/PurePace/**`、`ios/RunCore/**` 相对 c122dbb 零 diff」；命令与空输出同时贴进证据 README |

**采集链路（照 `docs/evidence/screenshot-refresh/README.md` 的口径，但落到本项目录）**

1. 工程生成：`ios/PurePace.xcodeproj` 为 gitignore 产物，先
   `xcodegen generate --spec ios/project.yml --project ios`（本机 xcodegen 已在 `/opt/homebrew/bin/xcodegen`）。
2. 构建测试包：`xcodebuild build-for-testing -project ios/PurePace.xcodeproj -scheme PurePace
   -destination "platform=iOS Simulator,id=B3F00298-E08A-41E0-876E-6E8A75C730FD" -derivedDataPath .build/ios
   CODE_SIGNING_ALLOWED=NO`（派生数据 `.build/ios` 与既有脚本一致；模拟器 iPhone 16 / Xcode 26.3）。
3. 截图为 `test-without-building` + `-resultBundlePath`，浅色前 `xcrun simctl ui <udid> appearance light`，
   深色前 `... dark`，采集结束恢复 `light`；导出用
   `xcrun xcresulttool export attachments --path <bundle> --output-path <staging>`，
   **附件名即文件名（`<screen>` / `<screen>-dark`），不裁切、不重编码、不改名**。
4. 一张图只有真取到才算数：`ScreenshotEvidenceUITests` 的测试方法一次跑出全部 7 屏附件，故把 14 张全部导出到
   `staging`（不得直接覆盖 `docs/screenshots/`），只把差异图落库；可比对判定按 ac-twelve-verified 执行。
5. `ac-run-metrics-balanced` 由 `ios/PurePaceUITests/RunFlowUITests.swift:885` 打印，不在截图用例内。为让
   `xcodebuild-light.log` / `xcodebuild-dark.log` 自带实测行，每种外观在截图腿之外追加一次
   `-only-testing:PurePaceUITests/RunFlowUITests/testRunPauseResumeFinishAndHistory`（暂停）
   与 `-only-testing:PurePaceUITests/RunFlowUITests/testZhHansCopyDatesAndBottomAnchoredPrimaryAction`
   （未开始 / 运行中 / 保存态），按小节标注来源后追加进同一份外观日志（保留完整输出与 `TEST SUCCEEDED` 结论）。
   参考耗时：截图腿 ~83s/种、RunFlow 单测 ~15–85s/条，整体远低于预算。

**不得使用 `bash scripts/capture-ios-screenshots.sh`（--stage screenshots / all）**

该脚本把 `refresh_dir` 硬编码为 `docs/evidence/screenshot-refresh`、归属项硬编码为
`wi_intake_85d08fa7106efc3f`（`scripts/capture-ios-screenshots.sh:94,318`），运行会覆盖上一批证据并写入错误归属；
而本项 `scripts/` 必须零 diff，不得改脚本。因此按其内部同一组命令手动复刻，产物只写本项目录与
`docs/screenshots/`。`scripts/compose-ios-screenshots-side-by-side.sh` 可直接运行（输入只读、输出确定性）——
若其生成的 `side-by-side/SHA256SUMS` 头部缺绑定字段，按 docs 允许的方式补写头部（不改脚本）。

**顺序要求（保证 HEAD 绑定干净）**

先提交本项 prd/baseline 记录使工作树 clean → 再采集（记录 `git rev-parse HEAD` 与
`git diff --stat c122dbb… -- ios/PurePace ios/RunCore ios/PurePaceUITests` 结果）→ 再提交证据改动。
采集时若工作树非 clean 或 ios 相对 c122dbb 非零 diff，不得写绑定字段。

**约束事实清单（采集前复核，避免误伤）**

- 图片尺寸基准：浅/深原图 1178×2556，并排 2356×2556；`run-running` 旧 sha `9a9ba019…`、`run-running-dark` 旧 sha `b42fb536…`。
- 门禁与证据无耦合：`.munk/code-gates.json` 22 门不含 `docs/screenshots` 哈希断言，故改证据不触发门禁变化；
  本项也不得为了让门禁通过而改任何门禁定义。
- `docs/evidence/screenshot-refresh/README.md` 里「修红后需 rebind 的最小集合」即本项范围（2 张 + 1 张并排 +
  两份清单 + 回执），本项按更严口径额外重建 7 张并排并逐张核对 12 张。
- 预算：≤8M token / ≤90 分钟；反范围项任何一条被触碰即视为越界，需回报 Owner 而不是继续。
