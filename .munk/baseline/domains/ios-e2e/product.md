# Domain: ios-e2e

PurePace iOS 端到端取证域：在既有真实链路（Run 页 → 结束归档 → History → RunDetail → 导出 GPX → ShareLink）之上补齐「模拟器 + 代码层」的一次性取证——用 `xcrun simctl location` 注入真实 CoreLocation、定向跑一条真实 UI 用例、从 App 真实沙盒容器读取跑次 JSON 与导出 GPX、用独立 `python3` 标准库解析逐字段对齐，产出机读报告与截图证据。不改产品逻辑与 RunCore 契约；不产出真机结论。

## 范围

- `scripts/verify-ios-ui-e2e.sh`：`#!/usr/bin/env bash`、`set -euo pipefail`、`--help` 退出 0 且含「用法」、未知参数退出 2、以 `BASH_SOURCE` 推导仓库根、可重复执行。编排：`scripts/sync-ios-version.sh` 同步版本 → XcodeGen/现有工程生成（复用 `scripts/build-ios.sh` 判定口径，不手写 `project.pbxproj`）→ `xcodebuild` 构建安装到 `iPhone 16` / `iOS 18.6`（`com.chaxiu.purepace`）→ `simctl uninstall` 保证空容器 + `simctl location clear` 清残留 → `simctl location <udid> start --speed=3 --interval=1` 注入 ≥20 km 长航点（`trap` 清理）→ 只跑 `-only-testing:PurePaceUITests/RunFlowUITests/testRunPauseResumeFinishAndHistory`，`-resultBundlePath` 落 `.build/verify-ios-ui-e2e/` → `simctl get_app_container` 读真实容器断言 → 内嵌 `python3`（仅标准库，不 import App/RunCore 源码、不复用 `GPXCodec`）独立解析 → 写 `report.json` 与截图。
- `ios/PurePaceUITests/RunFlowUITests.swift`：点击 `runDetail.share` 后在有界等待内断言系统分享面板/活动视图真实出现（`ActivityListView` / sheet / `Copy` / `拷贝` / `Save to Files` / `存储到“文件”`），随后经关闭按钮或下滑关闭回到详情页；在「结束 / 历史 / 详情 / 分享」四节点各保存固定名称 `XCTAttachment` 截图（`e2e-finish` / `e2e-history` / `e2e-detail` / `e2e-share`，`lifetime = .keepAlways`），不使用固定 `sleep`。
- `.build/verify-ios-ui-e2e/report.json` 与截图：含 `ok`（布尔）、`caliber` 固定「模拟器 + 代码层」、模拟器 `udid`/`name`/`runtime`、每步实际值、容器/导出/解析数值、`screenshots[]`、`failures[]`（含 `failureReason`）；截图经 `xcresulttool export attachments` 按 `manifest.json` 名称映射导出为 PNG。
- `docs/evidence/stage3-e2e/`：每次运行覆盖写入本次产物副本——报告摘要、独立解析结果、4 张截图副本（`report.json` / `external-parse.json` / `summary.md` / `screenshots/*.png`）。
- 门禁：`.munk/code-gates.json` 追加单一 argv 门 `verify-ios-ui-e2e`（`bash scripts/verify-ios-ui-e2e.sh`），既有门 id 与 `command` 不变；`scripts/check-ios-scripts.sh` 的 `targets` / `strict_targets` 纳入新脚本，使 shebang / 严格模式 / `BASH_SOURCE` / `--help` / 未知参数退出码被 lint 覆盖。

## 验收

- ac-script-contract: 脚本存在且 `bash -n` 通过，首行 `#!/usr/bin/env bash`、含 `set -euo pipefail` 与 `BASH_SOURCE` 推导仓库根；`--help` 退出 0 且输出含「用法」；未知参数退出 2。
- ac-script-idempotent: 任意 cwd 执行均以仓库根为基准；连续两次运行不因残留失败（运行前清空 `.build/verify-ios-ui-e2e/`、卸载 App、`location clear`），`trap` 在成功与失败路径都执行 `simctl location <udid> clear`。
- ac-simulator-target: 固定 `iPhone 16` / `iOS 18.6` destination 与 `com.chaxiu.purepace`；模拟器缺失或 boot 失败时非零退出并在 `report.json` 的 `failures[]` 写明原因，不静默跳过、不降级为通过。
- ac-empty-container-before-run: 测试前 `simctl uninstall` 后 `get_app_container` 取不到 `Documents/Runs` 下任何跑次文件（或容器不存在），保证「恰 1 条」来自本次运行。
- ac-real-location-injection: 用 `simctl location <udid> start --speed=3 --interval=1` 注入 ≥20 km 长航点；脚本内不出现 `--harness direct`、launch-arg 假流、`shared/fixtures` 或任何夹具路径。
- ac-single-run-archived: 测试后容器 `Documents/Runs` 恰 1 个 `.json`；`formatVersion == 1`、`distance > 0`、`samples` 非空、`activeDuration > 0`、`startedAt < endedAt`，实际值写入 `report.json`。
- ac-export-gpx-valid: 容器 `Documents/Exports` 至少 1 个 `.gpx` 且字节数 > 0；`xmllint --noout` 退出 0；根元素 `gpx` 且 `version="1.1"`、`xmlns="http://www.topografix.com/GPX/1/1"`。
- ac-external-parse-consistency: 内嵌 `python3` 独立解析器输出 `trkpt` 数 == 跑次 `samples` 数；首末 `trkpt` `<time>` 与 `samples` 首末 `timestamp` 绝对差 ≤1 s；首末 `lat`/`lon` 与对应采样绝对差 ≤1e-6；任一不等即非零退出并记录实际值与期望值。
- ac-share-sheet-asserted: 点击 `runDetail.share` 后在有界等待内断言系统分享面板/活动视图出现，随后关闭；不使用 `Thread.sleep`/固定 `sleep`，该用例在门禁中真实通过。
- ac-screenshots: 四个节点各产出一张固定名称 `XCTAttachment` 截图；脚本用 `xcresulttool export attachments` 导出后断言 4 张 PNG 存在且字节数 > 0，并复制到 `.build/verify-ios-ui-e2e/screenshots/` 与 `docs/evidence/stage3-e2e/screenshots/`。
- ac-report-json: `.build/verify-ios-ui-e2e/report.json` 为合法 JSON，含 `ok`、`caliber` = 「模拟器 + 代码层」、模拟器 `udid`/`name`/`runtime`、各步骤实际值、容器与导出解析数值、`screenshots[]`、`failures[]`；任一步失败时 `ok == false`、`failureReason` 非空且脚本退出非零。
- ac-evidence-docs: `docs/evidence/stage3-e2e/` 存在报告摘要、独立解析结果与 4 张截图副本；文案只出现「模拟器 + 代码层」「模拟器链路通过」「导出逐字段对齐通过」，不出现「真机已验证」「实听通过」「阶段 2 已通过」「阶段 3 已通过」。
- ac-no-fabrication: 脚本不 `echo`/`printf` 任何 `BUILD SUCCEEDED`/`TEST SUCCEEDED` 伪造成功行；导出与跑次证据只来自 `get_app_container` 读出的真实文件，不读 `shared/fixtures`、不用内存字符串冒充。
- ac-gates-preserved: `.munk/code-gates.json` 追加 `verify-ios-ui-e2e`（单一 argv），既有门 id 与 `command` 完全不变；`lint-ios-shell` / `lint-ios-scripts` / `build-ios` / `test-ios` / `verify-ios-ui-e2e` 全绿。

## 非目标

- 不做真机验证、不产出真机结论、不做锁屏/后台连续定位、音乐 duck、TTS 实听（一律 `pending: 待人现场`，属阶段 4 硬门）。
- 不改 App 产品逻辑与 RunCore 契约：不改归档/导出/播报/度量实现，不改 GPX 字段顺序与命名规则，不改 UI 布局与无障碍标识语义（只新增 UI 测试断言与截图）。
- 不做 Android、不改 `.github/workflows/*` 的触发条件/权限/步骤语义，不推 tag、不动 Release。
- 不新增第三方运行时或脚本依赖（只用 bash、xcrun、xcodebuild、xmllint、python3 标准库）。
- 不做 CI 产物上传、不做截图比对/视觉回归、不做报告可视化页面。
- 不重跑或替代 `verify-ios-sim-runtime` 的三条 Harness 链路；不删除/降级现有门。
- 不创建或修改 Host 托管文件（`goal.md`、`handoff.md`、`now.md`、`product.json`、`close-proposal.json`）。

## 实现约束

- **复用现有脚本口径**：destination `platform=iOS Simulator,name=iPhone 16,OS=18.6`、`bundle_id="com.chaxiu.purepace"`、`.build/` 产物目录、退出码 0/1/2 语义沿用 `scripts/test-ios.sh` 与 `scripts/verify-ios-sim-runtime.sh`，不另造第二套模拟器选择逻辑。
- **定向用例**：`-only-testing:PurePaceUITests/RunFlowUITests/testRunPauseResumeFinishAndHistory`；`testAnnouncementTogglePersistsAcrossRelaunch` 不在本门内跑（其 terminate/relaunch 与「恰 1 条跑次」断言冲突）。
- **定位注入时序**：先 boot 并 uninstall，再 `location start`，然后 `xcodebuild test`；航点总长 ≥20 km（3 m/s 下 ≥110 min 窗口），不依赖固定 `sleep` 判成功；`trap` 同时清理 location 与临时结果包残留。
- **容器读取**：只认 `simctl get_app_container <udid> com.chaxiu.purepace data` 下的 `Documents/Runs/*.json` 与 `Documents/Exports/*.gpx`，不用 `.build/ios/Build/Products` 或测试宿主沙盒代替。
- **RunRecord JSON 事实**（只读对齐，勿改产品侧）：文件名 `<UTC yyyyMMdd'T'HHmmss'Z'>-<uuid>.json`，键 `formatVersion`/`id`/`startedAt`/`endedAt`/`distance`/`activeDuration`/`splits`/`samples`；`startedAt`/`endedAt`/`samples[].timestamp` 为 Unix epoch 秒（Double），非 ISO8601；GPX 侧 `<time>` 为 ISO8601 UTC。
- **外部解析器**：`python3` heredoc/内联，只用 `json`、`xml.etree.ElementTree`、`datetime`、`argparse` 等标准库；命名空间用 `{http://www.topografix.com/GPX/1/1}` 匹配；失败必须给出实际值与期望值并非零退出。
- **截图导出**：`XCTAttachment(name:)` 名称固定、`lifetime = .keepAlways`；脚本按 `xcresulttool export attachments` 的 `manifest.json` 映射名称到文件，不靠文件名猜顺序；4 张缺失即失败。
- **分享面板断言**：优先 `app.otherElements["ActivityListView"]`，备选 `app.sheets.firstMatch` / 分享动作按钮；断言后点关闭恢复详情页。
- **门禁与 lint 同步**：`check-ios-scripts.sh` 的 `targets` 与 `strict_targets` 追加 `verify-ios-ui-e2e.sh`（只增不减）；不改放宽 import/夹具/占位断言。
- **证据目录**：`docs/evidence/stage3-e2e/` 每次运行覆盖写入（幂等），内容必须是本次运行产物副本。
- **口径**：报告、摘要、提交信息只写「模拟器 + 代码层」「模拟器链路通过」，不写「真机已验证」「阶段 2/3 已通过」。

## 最近交付证明

- workItemId: wi_ws_7f42ce11f04623e8（2026-11-09，pass）
- 交付：新增 `scripts/verify-ios-ui-e2e.sh`（770 行，编排版本同步 → 工程生成 → 构建安装 → 空容器 → 长航点注入 → 定向真实 UI 用例 → 真实容器断言 → 内嵌 `python3` 独立解析 → `report.json` + 截图证据）；`RunFlowUITests` 补分享面板有界断言与 4 节点截图；`.munk/code-gates.json` 追加单一 argv 门 `verify-ios-ui-e2e`，`check-ios-scripts.sh` 的 `targets`/`strict_targets` 纳入新脚本；`docs/evidence/stage3-e2e/` 落本次副本（`report.json` / `external-parse.json` / `summary.md` / 4 张 PNG）。
- 实测：`code_gates` 全绿（含 `lint-ios-scripts` / `lint-ios-shell` / `build-ios` / `test-ios` / `verify-ios-ui-e2e`）；容器恰 1 条跑次、GPX 通过 `xmllint`、外部解析 `trkpt`/`samples` 逐字段对齐。口径：模拟器链路通过、导出逐字段对齐通过；真机与 TTS 实听仍为 `pending: 待人现场`。
