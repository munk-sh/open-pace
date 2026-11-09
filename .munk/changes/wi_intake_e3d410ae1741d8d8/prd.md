# XCUITest 全链路 GPX 导出自证（开始 → 结束 → 导出，容器级机器断言）

## Scope

用 XCUITest 把「开始跑步 → 结束 → 导出 GPX」整条 UI 路径自动化，并在用例退出后从 App 真实沙盒容器直取产物做机器断言，使 GPX 导出验收不再需要人手点击。当前已有 `ios/PurePaceUITests/RunFlowUITests.swift` 的 2 条 UI 用例（`-uiTestLocation` DEBUG 确定性定位源）与 `scripts/verify-ios-ui-e2e.sh` 的容器取证门 `verify-ios-ui-e2e`，本项在其之上补齐「一条独立的全链路导出用例 + UUID/哈希/时间跨度级断言 + 证据文件 + 人手清单文档」，不改产品业务逻辑。

具体范围：

1. `ios/PurePaceUITests/RunFlowUITests.swift` 新增一条独立全链路用例（建议名 `testStartFinishExportGPXArtifact`，必须按 XCTest 字母序排在 `testRunPauseResumeFinishAndHistory` 之后）：`app.launchArguments += ["-uiTestLocation"]` → 开始 → 有界等待首个真实样本 → 结束 → History 选中本次记录 → 详情 → 导出 → 断言完成态含 `.gpx` → 点分享并在有界等待内断言系统分享面板出现后自行关闭/取消 → 回到详情。全程无人工点击、无 `Thread.sleep`/固定 `sleep`、不存在无界等待。
2. `scripts/verify-ios-ui-e2e.sh` 改为定向执行上述新用例（在 `simctl uninstall` 后的干净容器上，恰 1 条跑次），并扩展容器断言与证据：
   - `Documents/Exports/` 出现新 `.gpx`，文件名含该跑次 `Documents/Runs/*.json` 的 `id`（UUID，忽略大小写）；
   - `xmllint --noout` 通过、根元素 `{http://www.topografix.com/GPX/1/1}gpx`、`version="1.1"`；
   - `trkpt` 数 == 该记录 `samples` 数（现有实现 1:1 全量写入，无有意过滤）；
   - GPX 首末时间跨度 == 记录首末样本时间跨度，且首末绝对时间差均 ≤1s（现有实现容差口径）；
   - 写证据文件（含 `recordId` / `gpxFile` / `sha256` / `trkptCount` / `sampleCount` / `timeSpanSeconds` 等），默认落 `.build/verify-ios-ui-e2e/`，`--refresh-evidence` 时复制到 `docs/evidence/stage3-e2e/`，并在脚本 stdout 打印证据文件绝对/仓库相对路径。
3. `scripts/check-ios-shell.sh` 同步结构门：UI 用例数由 2 改为 3，断言新用例方法名存在，保留 `-uiTestLocation`、禁用固定 sleep、`XCTAssert` 次数阈值不降，并新增/更新反例自检（删除新用例必须被判红）。
4. `README.md`（或 `docs/`）新增「跑步链路验收自动化」小节：写明新用例名、本机/门禁命令、证据路径、真机执行命令（`xcodebuild test -destination id=00008101-001C701E0A68001E -only-testing:PurePaceUITests/RunFlowUITests/testStartFinishExportGPXArtifact`），并把人手清单收敛为仅两件：改系统定位授权、按电源键锁屏；导出/开始/结束/分享/选记录/滚动全部由用例覆盖。
5. `.munk/code-gates.json` 不新增门 id（保持 24 门），由既有 `verify-ios-ui-e2e` 门在每次门禁/推送执行新用例与容器断言。

## Acceptance Criteria

- ac-new-ui-case-exists-and-runs: `ios/PurePaceUITests/RunFlowUITests.swift` 存在新测试方法（名以 `testStartFinishExport` 开头或以等价命名排在 `testRunPauseResumeFinishAndHistory` 之后），`xcodebuild test -only-testing:PurePaceUITests/RunFlowUITests/<新用例>` 真实通过；源码不含 `Thread.sleep`/`sleep(`。
- ac-full-flow-no-human: 新用例单次执行内完成「开始 → 首个样本增长 → 结束 → 已保存 → History 选中本次记录 → 详情 → 导出 → 分享面板出现 → 自行关闭 → 回到详情」，不依赖任何外部人手点击；分享面板断言与关闭均为有界等待（≤20s 出现、≤10s 关闭）。
- ac-export-gpx-in-container: 门禁在 `simctl uninstall` 后的干净容器上执行新用例后，`xcrun simctl get_app_container <udid> com.chaxiu.purepace data` 的 `Documents/Exports/` 恰有/至少有 1 个本次新 `.gpx`，且文件名包含 `Documents/Runs/*.json` 中本次记录 `id` 的 UUID 字符串（忽略大小写），字节数 > 0。
- ac-gpx-1-1-parse: 该 `.gpx` 经 `xmllint --noout` 退出 0；根元素为 `{http://www.topografix.com/GPX/1/1}gpx` 且 `version == "1.1"`。
- ac-trkpt-equals-samples: 该 `.gpx` 的 `trkpt` 数严格等于对应跑次 JSON 的 `samples` 数组长度（0 差异；现有导出为 1:1 全量写入，不做有意过滤）。
- ac-time-span-matches: 记录时间跨度 `samples[-1].timestamp - samples[0].timestamp` 与 GPX 时间跨度 `lastTrkpt.time - firstTrkpt.time` 的绝对差 ≤1.0s；同时首末 trkpt 与对应样本的绝对时间差各 ≤1.0s。
- ac-evidence-artifact: 每次门禁运行写出证据文件（默认 `.build/verify-ios-ui-e2e/export-evidence.json`，`--refresh-evidence` 另复制为 `docs/evidence/stage3-e2e/export-evidence.json`），字段至少含 `recordId`、`gpxFile`、`sha256`（64 位十六进制）、`trkptCount`、`sampleCount`、`timeSpanSeconds`、`ok`；脚本 stdout 打印该路径；任一断言失败时 `ok == false` 且脚本非零退出。
- ac-gate-runs-on-push: `.munk/code-gates.json` 保持 24 个门且 `verify-ios-ui-e2e` 门仍为 `bash scripts/verify-ios-ui-e2e.sh`；该门执行的是新全链路用例并完成上述容器断言（不允许只在本地手动执行的旁路脚本）。
- ac-existing-suites-preserved: 既有 2 条 UI 用例逐条保留、断言不减；`PurePaceTests` 全量单测不得删除或弱化（真实执行数不低于交付前）；`check-ios-shell.sh` 的 `XCTAssert` 次数阈值只升不降。
- ac-device-runnable: 新用例只依赖 XCUITest + `-uiTestLocation` DEBUG 门控，不使用模拟器专属 API；README/docs 给出 `xcodebuild test -destination id=00008101-001C701E0A68001E -only-testing:PurePaceUITests/RunFlowUITests/testStartFinishExportGPXArtifact` 可执行命令；本项不连接真机。
- ac-docs-manual-checklist: README（或 docs）明确「人手清单只剩两件：改系统定位授权、按电源键锁屏」，并说明导出/开始/结束/分享/选记录/滚动由用例覆盖。
- ac-no-product-change: `ios/PurePace/**` 产品源码、`ios/RunCore/**`、`ios/Core/**`、`ios/project.yml`、`VERSION`、导出/持久化/CoreLocation/AudioSession 契约零改动；不向业务流程加种子数据；不新增第三方运行时或脚本依赖（仅 bash / xcrun / xcodebuild / xmllint / python3 标准库）。
- ac-gates-green: 本机 `.munk/code-gates.json` 全量绿（至少含 `lint-ios-shell`、`lint-ios-scripts`、`test-ios`、`verify-ios-ui-e2e`），回执给出新用例名、断言落点、证据文件路径与一次本机模拟器实跑输出。

## Non-Goals

- 不在本项连接或执行真机（设备执行由公司排窗）；不产出真机容器断言或「真机已验证」结论；真机锁屏/后台连续定位仍为 `pending: 待人现场`。
- 不改导出业务逻辑、GPX 编码器、文件名规则、持久化契约与 CoreLocation/AudioSession（阶段 2 技术路径冻结）；除非实测暴露缺陷，且必须在回执说明原因并重跑受影响门。
- 不降门、不删或弱化既有单测与 2 条 UI 用例；不为让用例通过而放宽断言或加入无限 sleep。
- 不引入自拼桌面驱动、自拼截屏或 WDA 以外的验收判据；不新增 `code-gates` 门 id；不改 `.github/workflows` 触发条件与步骤语义；不推 tag、不动 Release。
- 不做截图视觉回归、CI 产物上传、Android 侧改动。

## Implementation Constraints

- **文件锚点（只改这些）**：`ios/PurePaceUITests/RunFlowUITests.swift`、`scripts/verify-ios-ui-e2e.sh`、`scripts/check-ios-shell.sh`、`README.md`；必要时同步 `scripts/check-ios-scripts.sh` 中仅与 verify 脚本契约相关的断言。禁止改 `ios/PurePace/**` 产品源码与 `ios/RunCore/**`。
- **用例命名与顺序**：新方法名必须按 XCTest 字母序排在 `testRunPauseResumeFinishAndHistory` 之后（推荐 `testStartFinishExportGPXArtifact`），避免其新增跑次破坏既有用例「启动时 History 为空、结束后恰 1 条」的前提；新用例自身按「开始前记录行数 N → 结束后 N+1」与「最新一行即本次记录」取数，不依赖全局恰 1 条。
- **验证脚本定向执行**：`scripts/verify-ios-ui-e2e.sh` 的 `-only-testing` 改为新用例；干净容器断言仍为「恰 1 条跑次」，因此该门只跑新用例，不并发跑其它会产生跑次的用例。
- **既有截图契约**：`verify-ios-ui-e2e.sh` 现有 4 张固定附件名（`e2e-finish` / `e2e-history` / `e2e-detail` / `e2e-share`）必须由新用例产出，或脚本与断言同步修改；不得删掉截图证据。
- **事实口径**：跑次 JSON 文件名 `<UTC yyyyMMdd'T'HHmmss'Z'>-<uuid>.json`，键 `id` 为 UUID 字符串；`startedAt`/`endedAt`/`samples[].timestamp` 为 Unix epoch 秒（Double）；GPX `<time>` 为 ISO8601 UTC。`RunGPXExporter.export` 把 `record.samples` 全量映射为 `GPXTrack.points`，`GPXCodec.encode` 逐点写 `<trkpt>`，无过滤，故 `trkpt == samples` 必须严格相等。
- **证据文件**：默认只写 `.build/verify-ios-ui-e2e/`（`check-ios-scripts.sh` 要求默认不 churn 仓库证据）；`--refresh-evidence` 才覆盖 `docs/evidence/stage3-e2e/`。sha256 由 python3 `hashlib` 对真实导出文件字节计算。
- **不得出现 `simctl location`**：`check-ios-scripts.sh` 明令 verify 脚本正文不得出现 `simctl location`；定位仍走 `-uiTestLocation`，真实 CoreLocation 由 `verify-ios-sim-runtime` 门承担。
- **门禁同步**：`check-ios-shell.sh` 的 UI 用例数 2 → 3、`XCTAssert` 阈值不降、负例自检覆盖「删除新用例」；`check-ios-scripts.sh` 的 24 门计数与 `verify-ios-ui-e2e` 契约不得改坏。
- **真机可跑**：新用例只用 `XCUIApplication` 与 `-uiTestLocation` DEBUG 门控；README 给出 `-destination id=00008101-001C701E0A68001E` 命令；真机签名由排窗时处理，本项不执行。
- **回执要求**：写明新用例名、断言落点（文件/函数/断言项）、证据文件路径、一次本机模拟器实跑输出摘要；结论只写「模拟器 + 代码层」，不写「真机已验证」。
