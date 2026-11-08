# 模拟器注入轨迹端到端脚本、外部解析与证据

## Scope

在既有真实链路（Run 页 → 结束归档 → History → RunDetail → 导出 GPX → ShareLink）之上补齐**端到端取证**，不改产品逻辑：

1. **新增 `scripts/verify-ios-ui-e2e.sh`**（`#!/usr/bin/env bash`、`set -euo pipefail`、`--help` 退出 0 且含「用法」、未知参数退出 2、以 `BASH_SOURCE` 推导仓库根、可重复执行）编排一条真实链路：
   - `scripts/sync-ios-version.sh` 同步版本 → XcodeGen/现有工程生成（复用 `scripts/build-ios.sh` 的判定口径，不手写 `project.pbxproj`）→ `xcodebuild` 构建并安装到 iPhone 16 / iOS 18.6 模拟器；
   - `xcrun simctl uninstall com.chaxiu.purepace` 保证空容器，`xcrun simctl location clear` 清残留；
   - `xcrun simctl location <udid> start --speed=3 --interval=1 <≥20 km 长航点>` 注入真实 CoreLocation，`trap` 中 `clear` 清理；
   - 只跑 `PurePaceUITests/RunFlowUITests` 的真实流程用例（定向到 `testRunPauseResumeFinishAndHistory`，避免播报开关用例的 terminate/relaunch 干扰「恰 1 条跑次」），`-resultBundlePath` 落 `.build/verify-ios-ui-e2e/`；
   - 结束后用 `xcrun simctl get_app_container <udid> com.chaxiu.purepace data` 读取真实容器并做断言与外部解析；
   - 产出 `.build/verify-ios-ui-e2e/report.json` 与截图。
2. **UI 用例补两处**（`ios/PurePaceUITests/RunFlowUITests.swift`）：
   - 点击 `runDetail.share` 后断言系统分享面板/活动视图真实出现（有界等待，不用固定 `sleep`），随后关闭；
   - 在「结束 / 历史 / 详情 / 分享」四个节点保存 `XCTAttachment` 截图（固定名称、`lifetime = .keepAlways`），由脚本经 `xcrun xcresulttool export attachments` 导出为 PNG。
3. **容器内真实文件断言**：
   - `Documents/Runs` 恰 1 个 `.json`，`formatVersion == 1`、`distance > 0`、`samples` 非空、`activeDuration > 0`、`startedAt < endedAt`；
   - `Documents/Exports` 至少 1 个 `.gpx`，`xmllint --noout` 通过，根节点为 GPX 1.1 且命名空间正确。
4. **独立外部解析**：脚本内嵌 `python3`（仅标准库，**不 import App/RunCore 代码、不复用 `GPXCodec`**）解析导出 GPX 与跑次 JSON，核对 `trkpt` 数 == `samples` 数、首末 `trkpt` 时间 == 首末 `samples` 时间（容差 ≤1 s）、首末经纬度一致（≤1e-6），并把实际值写入报告。
5. **报告与证据**：`report.json` 含 `ok`、口径字段（固定「模拟器 + 代码层」）、模拟器信息、每步实际值、容器/导出/解析数值、截图清单、`failures[]`（含 `failureReason`）；摘要、解析结果与截图副本落 `docs/evidence/stage3-e2e/`。
6. **门禁**：`.munk/code-gates.json` 追加真实执行门 `verify-ios-ui-e2e`（`command` 为单一 argv `bash scripts/verify-ios-ui-e2e.sh`），现有 22 门原样保留；`scripts/check-ios-scripts.sh` 的 `targets` / `strict_targets` 纳入新脚本，使 shebang / `set -euo pipefail` / `BASH_SOURCE` / `--help` / 未知参数退出码被 lint 覆盖。

## Acceptance Criteria

- ac-script-contract: `scripts/verify-ios-ui-e2e.sh` 存在且 `bash -n` 通过，首行 `#!/usr/bin/env bash`、含 `set -euo pipefail` 与 `BASH_SOURCE` 推导仓库根；`bash scripts/verify-ios-ui-e2e.sh --help` 退出 0 且输出含「用法」；`bash scripts/verify-ios-ui-e2e.sh --definitely-invalid` 退出 2。
- ac-script-idempotent: 在任意 cwd 执行脚本均以仓库根为基准；连续两次运行不因上次残留失败（运行前清空 `.build/verify-ios-ui-e2e/`、卸载 App、`location clear`），且 `trap` 在成功与失败路径都执行 `xcrun simctl location <udid> clear`。
- ac-simulator-target: 脚本固定 `iPhone 16` / `iOS 18.6` destination 与 `com.chaxiu.purepace`；模拟器缺失或 boot 失败时以非零退出，并在 `report.json` 的 `failures[]` 写明原因（不静默跳过、不降级为「通过」）。
- ac-empty-container-before-run: 测试前执行 `xcrun simctl uninstall` 后，`get_app_container` 取不到 `Documents/Runs` 下任何跑次文件（或容器不存在），保证「恰 1 条」来自本次运行。
- ac-real-location-injection: 脚本用 `xcrun simctl location <udid> start --speed=3 --interval=1` 注入 ≥20 km 长航点；脚本内不出现 `--harness direct`、launch-arg 假流、`shared/fixtures` 或任何夹具路径。
- ac-single-run-archived: 测试结束后容器 `Documents/Runs` 恰 1 个 `.json`；解析后 `formatVersion == 1`、`distance > 0`、`samples` 非空、`activeDuration > 0`、`startedAt < endedAt`，实际值写入 `report.json`。
- ac-export-gpx-valid: 容器 `Documents/Exports` 至少 1 个 `.gpx` 且字节数 > 0；`xmllint --noout <file>` 退出 0；根元素为 `gpx` 且 `version="1.1"`、`xmlns="http://www.topografix.com/GPX/1/1"`。
- ac-external-parse-consistency: 内嵌 `python3` 独立解析器（仅标准库、不 import App/RunCore 源码）输出 `trkpt` 数 == 跑次 `samples` 数；首个 `trkpt` 的 `<time>` 与 `samples[0].timestamp`、末个与 `samples[-1].timestamp` 的绝对差 ≤1 s；首末 `lat`/`lon` 与对应采样绝对差 ≤1e-6；任一不等即脚本非零退出并记录实际值与期望值。
- ac-share-sheet-asserted: XCUITest 点击 `runDetail.share` 后在有界等待内断言系统分享面板/活动视图出现（命中 `ActivityListView`/sheet/分享动作之一即通过），随后关闭面板；断言不使用 `Thread.sleep`/固定 `sleep`，该用例在门禁中真实通过。
- ac-screenshots: 测试在「结束」「历史」「详情」「分享」四个节点各产出一张固定名称的 `XCTAttachment` 截图；脚本用 `xcrun xcresulttool export attachments` 导出后断言 4 张 PNG 均存在且字节数 > 0，并复制到 `.build/verify-ios-ui-e2e/screenshots/` 与 `docs/evidence/stage3-e2e/screenshots/`。
- ac-report-json: `.build/verify-ios-ui-e2e/report.json` 为合法 JSON，含 `ok`（布尔）、`caliber` 固定为「模拟器 + 代码层」、模拟器 `udid`/`name`/`runtime`、各步骤实际值、容器与导出解析数值、`screenshots[]`、`failures[]`；任一步失败时 `ok == false`、`failures[].failureReason` 非空且脚本退出非零。
- ac-evidence-docs: `docs/evidence/stage3-e2e/` 存在报告摘要、独立解析结果（JSON 或文本）与 4 张截图副本；文案只出现「模拟器 + 代码层」「模拟器链路通过」「导出逐字段对齐通过」，不出现「真机已验证」「实听通过」「阶段 2 已通过」「阶段 3 已通过」。
- ac-no-fabrication: 脚本不 `echo`/`printf` 任何 `BUILD SUCCEEDED`/`TEST SUCCEEDED` 伪造成功行；导出与跑次证据只来自 `get_app_container` 读出的真实文件，不读取 `shared/fixtures`、不用内存字符串冒充。
- ac-gates-preserved: `.munk/code-gates.json` 追加 `verify-ios-ui-e2e`（`command` 为单一 argv）且原 22 门 id 与 `command` 完全不变；`lint-ios-shell` / `lint-ios-scripts` / `build-ios` / `test-ios` / `verify-ios-ui-e2e` 全绿。

## Non-Goals

- 不做真机验证、不产出真机结论、不做锁屏/后台连续定位、音乐 duck、TTS 实听（一律 `pending: 待人现场`，属阶段 4 硬门）。
- 不改 App 产品逻辑与 RunCore 契约：不改归档/导出/播报/度量实现，不改 GPX 字段顺序与命名规则，不改 UI 布局与无障碍标识语义（只新增 UI 测试断言与截图）。
- 不做 Android、不改 `.github/workflows/*` 的触发条件/权限/步骤语义，不推 tag、不动 Release。
- 不新增第三方运行时或脚本依赖（只用 bash、xcrun、xcodebuild、xmllint、python3 标准库）。
- 不做 CI 产物上传、不做截图比对/视觉回归、不做报告可视化页面。
- 不重跑或替代 `verify-ios-sim-runtime` 的三条 Harness 链路；不删除/降级现有 22 门。
- 不创建或修改 Host 托管文件（`goal.md`、`handoff.md`、`now.md`、`product.json`、`close-proposal.json`）。

## Implementation Constraints

- **复用现有脚本口径**：模拟器选择、destination `platform=iOS Simulator,name=iPhone 16,OS=18.6`、`bundle_id="com.chaxiu.purepace"`、`.build/` 产物目录、退出码 0/1/2 语义沿用 `scripts/test-ios.sh` 与 `scripts/verify-ios-sim-runtime.sh`；不要另造第二套模拟器选择逻辑。
- **定向用例**：用 `-only-testing:PurePaceUITests/RunFlowUITests/testRunPauseResumeFinishAndHistory` 只跑真实流程用例；`testAnnouncementTogglePersistsAcrossRelaunch` 不在本门内跑（其 terminate/relaunch 与「恰 1 条跑次」断言冲突）。若确需跑整类，必须先在报告中证明容器仍恰 1 条。
- **定位注入时序**：先 boot 并 uninstall，再 `location start`，然后 `xcodebuild test`；航点总长 ≥20 km（3 m/s 下 ≥110 min 窗口），不依赖固定 `sleep` 判成功；`trap` 同时清理 location 与临时结果包残留。
- **容器读取**：只认 `xcrun simctl get_app_container <udid> com.chaxiu.purepace data` 下的 `Documents/Runs/*.json` 与 `Documents/Exports/*.gpx`；不要用 `.build/ios/Build/Products` 或测试宿主沙盒代替。
- **RunRecord JSON 事实**（供解析器对齐，勿改产品侧）：文件名 `<UTC yyyyMMdd'T'HHmmss'Z'>-<uuid>.json`，键为 `formatVersion`/`id`/`startedAt`/`endedAt`/`distance`/`activeDuration`/`splits`/`samples`；`id` 为 uuidString，`distance` 为米（Double），`startedAt`/`endedAt`/`samples[].timestamp` 编码为 **Unix epoch 秒（Double）**，不是 ISO8601；`samples[]` 键为 `latitude`/`longitude`/`altitude`/`timestamp`/`heartRate`/`cadence`。GPX 侧 `<time>` 为 ISO8601 UTC。
- **外部解析器**：`python3` heredoc/内联脚本，只用 `json`、`xml.etree.ElementTree`、`datetime`、`argparse` 等标准库；命名空间用 `{http://www.topografix.com/GPX/1/1}` 匹配；解析失败/计数不一致必须给出实际值与期望值并退出非零。
- **截图导出**：`XCTAttachment(name:)` 名称固定（如 `e2e-finish`/`e2e-history`/`e2e-detail`/`e2e-share`），`lifetime = .keepAlways`；脚本按 `xcresulttool export attachments` 生成的 `manifest.json` 映射名称到文件，不靠文件名猜测顺序；4 张缺失即失败。
- **分享面板断言**：`ShareLink` 呈现的是 App 内 `UIActivityViewController`，优先断言 `app.otherElements["ActivityListView"]`，备选 `app.sheets.firstMatch` / 分享动作按钮（如 `Copy`/`拷贝`/`Save to Files`）；断言后点关闭（`Close`/`取消`/下滑）恢复详情页，避免影响后续截图。
- **门禁与 lint 同步**：`check-ios-scripts.sh` 的 `targets` 与 `strict_targets` 追加 `verify-ios-ui-e2e.sh`（只增不减，现有 4 项检查全部保留）；`check-ios-shell.sh` 若因 UI 测试新增内容需要调整，只允许精确增补，不得放宽 import/夹具/占位断言。
- **证据目录**：`docs/evidence/stage3-e2e/` 由脚本每次运行覆盖写入（幂等），内容必须是本次运行的产物副本，不得手工编造或提交历史残留。
- **口径**：所有报告、摘要、提交信息只写「模拟器 + 代码层」「模拟器链路通过」；不写「真机已验证」「阶段 2/3 已通过」。
