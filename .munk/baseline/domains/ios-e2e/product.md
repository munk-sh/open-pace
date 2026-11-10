# Domain: ios-e2e

PurePace iOS 端到端取证域：在真实链路（Run 页 → 结束归档 → History → 详情 → 导出 GPX → 系统分享）之上，用一条 XCUITest 全链路用例加干净容器级机器断言，把「开始 → 结束 → 导出 GPX」的验收从人手点击变成可重复执行的自证。定位走 `-uiTestLocation` DEBUG 确定性测试源（真实 CoreLocation 由 `verify-ios-sim-runtime` 承担）；不改产品逻辑与 RunCore 契约；不产出真机结论。

## 范围

- `ios/PurePaceUITests/RunFlowUITests.swift`（4 条 UI 用例）：新增独立全链路用例 `testStartFinishExportGPXArtifact`，单次执行内完成「开始 → 首个真实样本增长 → 结束（已保存）→ History 选中本次记录 → 详情 → 导出（完成态含 `.gpx`、无失败态）→ 点分享 → 有界等待系统活动视图出现 → 用例自行关闭 → 回详情」。按「开始前行数 N → 结束后 N+1」「降序首行即本次记录」取数，不依赖全局恰 1 条；四节点固定附件名 `e2e-finish` / `e2e-history` / `e2e-detail` / `e2e-share`（`.keepAlways`）；无 `Thread.sleep`/固定 `sleep`，分享出现 ≤20s、关闭 ≤10s 均为有界等待。
- `scripts/verify-ios-ui-e2e.sh`：`#!/usr/bin/env bash`、`set -euo pipefail`、以 `BASH_SOURCE` 推导仓库根、`--help` 退出 0、未知参数退出 2、可重复执行。编排：版本同步 → 工程生成 → 构建安装 → `simctl uninstall` 干净容器 → 只跑上述新用例（`-only-testing`，恰 1 条跑次，`-resultBundlePath` 落 `.build/verify-ios-ui-e2e/`）→ 真实容器断言；正文不得出现 `simctl location`。
- 容器断言：`Documents/Runs` 恰 1 个 `.json`（`formatVersion == 1`、`distance > 0`、`samples` 非空、`activeDuration > 0`、`startedAt < endedAt`）；`Documents/Exports` 至少 1 个 `.gpx`，字节数 > 0、文件名忽略大小写包含该跑次 `id`（UUID）；`xmllint --noout` 退出 0、根元素 `{http://www.topografix.com/GPX/1/1}gpx`、`version="1.1"`。
- 内嵌 `python3`（仅标准库，不 import App/RunCore 源码、不复用 `GPXCodec`）独立解析：`trkpt` 数严格 == `samples` 数；GPX 时间跨度与记录时间跨度绝对差 ≤1s；首末 `trkpt` 与对应样本时间差各 ≤1s；首末经纬度差 ≤1e-6。任一不等即非零退出并记录实际值与期望值。
- 证据：`.build/verify-ios-ui-e2e/report.json` 与 `export-evidence.json`（含 `recordId` / `gpxFile` / `sha256`（64 hex）/ `bytes` / `trkptCount` / `sampleCount` / `timeSpanSeconds` / `timeSpanDeltaSeconds` / `ok`），默认只写 `.build/`；显式 `--refresh-evidence` 才覆盖 `docs/evidence/stage3-e2e/`（报告、导出证据、解析结果、4 张截图副本）。成败路径都留下证据文件（前置失败补写 `ok=false`）。
- 门禁定位：`.munk/code-gates.json` 保持 22 门；`verify-ios-ui-e2e` 是按需执行的持锁串行本地旁证、不作本地阻断，权威绿为 `.github/workflows/ios.yml` 同 commit run（回执须引真实 run id + headSha）。`lint-ios-shell` 断言 4 条 UI 用例、`func testStartFinishExportGPXArtifact` 存在、`XCTAssert` ≥112，并对「删除新用例」反例判红。
- `README.md`：新增「跑步链路验收自动化」小节，写明新用例名、本机定向跑命令、干净容器断言入口、证据路径，并把人工清单收敛为两件；真机验收改由人手按 `docs/device-manual-acceptance.md` 在交付后执行，README 不再给 agent 侧真机命令。

## 验收

- ac-ui-case-exists-and-runs: `RunFlowUITests.swift` 存在方法名以 `testStartFinishExport` 开头的用例且按字母序排在 `testRunPauseResumeFinishAndHistory` 之后；`-only-testing:PurePaceUITests/RunFlowUITests/<新用例>` 可执行；源码不含 `Thread.sleep`/`sleep(`。
- ac-full-flow-no-human: 单次执行内完成「开始 → 首个样本增长 → 结束 → 已保存 → History 选中本次记录 → 详情 → 导出 → 分享面板出现 → 自行关闭 → 回详情」，不依赖外部人手点击；分享出现 ≤20s、关闭 ≤10s 均为有界等待。
- ac-export-gpx-in-container: `simctl uninstall` 后的干净容器执行新用例后，`Documents/Exports/` 至少有 1 个本次新 `.gpx`，字节数 > 0，文件名包含本次 `.json` 记录 `id` 的 UUID 字符串（忽略大小写）。
- ac-gpx-1-1-parse: 该 `.gpx` 经 `xmllint --noout` 退出 0；根元素 `{http://www.topografix.com/GPX/1/1}gpx` 且 `version == "1.1"`。
- ac-trkpt-equals-samples: `trkpt` 数严格等于对应跑次 JSON `samples` 长度（0 差异；现有导出 1:1 全量写入，不做有意过滤）。
- ac-time-span-matches: `samples[-1].timestamp - samples[0].timestamp` 与 GPX `lastTrkpt.time - firstTrkpt.time` 绝对差 ≤1.0s；首末 `trkpt` 与对应样本绝对时间差各 ≤1.0s。
- ac-evidence-artifact: 每次运行写出 `export-evidence.json`，字段至少含 `recordId`、`gpxFile`、`sha256`（64 位十六进制）、`trkptCount`、`sampleCount`、`timeSpanSeconds`、`ok`；stdout 打印路径；任一断言失败时 `ok == false` 且脚本非零退出。
- ac-e2e-leg-topology: `verify-ios-ui-e2e` 不新增本地阻断门，保持「持锁串行本地旁证 + `ios.yml` 权威」口径；脚本执行的是新全链路用例并完成上述容器断言，不是仅本地手动的旁路脚本。
- ac-existing-suites-preserved: 既有 3 条 UI 用例逐条保留、断言不减；`PurePaceTests` 全量单测不删不弱化；`check-ios-shell.sh` 的 `XCTAssert` 阈值只升不降。
- ac-simulator-runnable-manual-device-doc: 模拟器可跑——新用例只依赖 XCUITest + `-uiTestLocation` DEBUG 门控，不使用模拟器专属 API；真机按 `docs/device-manual-acceptance.md` 由人手测，本域不要求真机可执行，也不再由 README 提供真机命令。
- ac-docs-manual-checklist: README 明确「人手清单只剩两件：改系统定位授权、按电源键锁屏」，并说明开始/结束/选记录/滚动/导出/分享由用例覆盖。
- ac-no-product-change: `ios/PurePace/**` 产品源码、`ios/RunCore/**`、`ios/Core/**`、`ios/project.yml`、`VERSION`、导出/持久化/CoreLocation/AudioSession 契约零改动；不加种子数据；不新增第三方运行时或脚本依赖（仅 bash / xcrun / xcodebuild / xmllint / python3 标准库）。
- ac-gates-green: 本地 `.munk/code-gates.json` 全量绿（含 `lint-ios-shell`、`lint-ios-scripts`），回执给出新用例名、断言落点、证据文件路径与实跑输出摘要。

## 非目标

- 不在本项连接或执行真机；不产出真机容器断言或「真机已验证」结论；真机锁屏/后台连续定位仍为 `pending: 待人现场`。
- 不改导出业务逻辑、GPX 编码器、文件名规则、持久化契约与 CoreLocation/AudioSession；不向业务流程加种子数据。
- 不降门、不删或弱化既有单测与 3 条 UI 用例；不为让用例通过而放宽断言或加入无限 sleep。
- 不引入 WDA 以外的验收判据；不改 `.github/workflows` 触发条件与步骤语义；不推 tag、不动 Release。
- 不做截图视觉回归、CI 产物上传、Android 侧改动；A 授权遥测 / B 音频机器自证已拆至独立工作项，本域不含。

## 实现约束

- **文件锚点**：只改 `ios/PurePaceUITests/RunFlowUITests.swift`、`scripts/verify-ios-ui-e2e.sh`、`scripts/check-ios-shell.sh`、`README.md`；必要时同步 `scripts/check-ios-scripts.sh` 中仅与 verify 脚本契约相关的断言。禁止改 `ios/PurePace/**` 与 `ios/RunCore/**`。
- **用例命名与顺序**：新方法名须按 XCTest 字母序排在 `testRunPauseResumeFinishAndHistory` 之后（推荐 `testStartFinishExportGPXArtifact`），避免新跑次破坏既有用例「启动时 History 为空、结束后恰 1 条」的前提。
- **定向执行**：`-only-testing` 改为新用例；干净容器断言仍为「恰 1 条跑次」，故该门只跑新用例，不并发跑其它会产生跑次的用例；构建/安装/预热/授权与串行锁沿用 main 口径。
- **事实口径**：跑次 JSON 文件名 `<UTC yyyyMMdd'T'HHmmss'Z'>-<uuid>.json`，键 `id` 为 UUID 字符串；`startedAt`/`endedAt`/`samples[].timestamp` 为 Unix epoch 秒（Double）；GPX `<time>` 为 ISO8601 UTC；`RunGPXExporter` 全量映射 `samples` → `GPXTrack.points`，故 `trkpt == samples` 严格相等。
- **证据目录**：默认只写 `.build/verify-ios-ui-e2e/`（不 churn 仓库证据）；`--refresh-evidence` 才覆盖 `docs/evidence/stage3-e2e/`；`sha256` 由 `python3 hashlib` 对真实导出字节计算。
- **分享面板断言**：优先 `ActivityListView`，备选 `app.sheets.firstMatch` / 分享动作按钮；关闭按钮在系统远程视图内时用归一化坐标点击，失败再下滑兜底；断言与关闭都不使用固定 sleep。
- **门禁与 lint 同步**：`check-ios-shell.sh` 用例数 4、`XCTAssert` 阈值 ≥112、负例自检覆盖「删除新用例」；`check-ios-scripts.sh` 的 22 门计数与 `verify-ios-ui-e2e` 契约不得改坏。
- **口径**：报告、摘要、提交信息只写「模拟器 + 代码层」；不写「真机已验证」「阶段 3 已通过」。

## 最近交付证明

- workItemId: wi_intake_1aa34f98b6e5f9a3（2026-11-10，pass）
- 交付：`ac-device-runnable` 撤除，改写为 `ac-simulator-runnable-manual-device-doc`——模拟器可跑（仅 XCUITest + `-uiTestLocation` DEBUG 门控），真机改由人手按 `docs/device-manual-acceptance.md` 在交付后手测；README 不再给 agent 侧真机命令，本域不再要求真机可执行。该断言无门脚本承载，删除不削弱任何门。
- 实测：`code_gates` 22 门全绿；`bash scripts/test-ios.sh` 全量腿退出 0——单测 125 例 0 失败、UI 6 例（`RunFlowUITests` 4 + `MusicSourceSelfCheckUITests` 2）0 失败；断言回执 `lint-ios-shell` 27 项 / `lint-ios-scripts` 27 项 / `check-shell-expansion` 7 项，失败 0。口径：模拟器 + 代码层；真机 `pending: 待人现场`。
