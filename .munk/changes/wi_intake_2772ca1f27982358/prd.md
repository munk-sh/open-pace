# 补齐 iOS 后台音频声明（location + audio）并加构建产物 Info.plist 读回断言

## Scope

这是**打包声明缺口**修复，不是业务代码问题。范围严格锁定为：

1. `ios/project.yml` 的 `targets.PurePace.info.properties.UIBackgroundModes` 改为数组 `[location, audio]`（当前仅 `[location]`）。
2. 删除 `ios/project.yml` 中 `targets.PurePace.settings.base.INFOPLIST_KEY_UIBackgroundModes: location` 这条重复声明——它在构建期会覆盖 `info.properties`，留着等于没改。
3. 用 XcodeGen 从 `project.yml` 重新生成 `ios/PurePace.xcodeproj`（`xcodegen generate --spec ios/project.yml`，本机已装 2.46.0），**禁止手改 `project.pbxproj`**。
4. 在 `ios/PurePaceTests`（走 `code_gates` 的 `test-ios` unit 腿）新增**构建产物本体读回断言**：从已构建 App 的 `Info.plist` **文件本体**读取并解析 `UIBackgroundModes`，断言实际数组**同时包含** `location` 与 `audio`；不得只断言 `project.yml` 文本、不得只做 `Bundle.main` 之外的推理、不得 skip。断言在缺任一值时必须变红（先做负向自检/夹具证明）。
5. 同步更新**直接耦合**的既有结构断言：`scripts/check-ios-shell.sh` 的 `validate_location_config` 及其自检夹具当前强制要求存在 `INFOPLIST_KEY_UIBackgroundModes: location` 且 Info.plist 仅含 `location`。该断言与本项「删除重复 setting + 数组含 audio」直接冲突，必须改为校验「无重复 setting + 数组含 location 与 audio」，强度不降（保留正负反例自检）。除该直接耦合断言外不改 `scripts/*` 其它逻辑。
6. 既有用例一律保留不删不降：`ios/PurePaceTests/RunLocationSourceTests.swift` 的 `testInfoPlistBackgroundModesContainsLocation` 继续保留（可扩展但不得弱化）。

## Acceptance Criteria

- ac-project-yml-array-both: `ios/project.yml` 中 `targets.PurePace.info.properties.UIBackgroundModes` 解析后为数组且同时包含 `location` 与 `audio`。
- ac-project-yml-no-duplicate-setting: `ios/project.yml` 中不再存在任何 `INFOPLIST_KEY_UIBackgroundModes` 设置项（避免构建期覆盖数组声明）。
- ac-xcodeproj-regenerated: `ios/PurePace.xcodeproj/project.pbxproj` 由 XcodeGen 重新生成（无手工编辑痕迹），生成后的 App target 构建设置中不含 `INFOPLIST_KEY_UIBackgroundModes`，且 App 仍以 `PurePace/Info.plist` 作为 `INFOPLIST_FILE`。
- ac-built-plist-readback-both: `ios/PurePaceTests` 中存在通过 `code_gates` 的 `test-ios` unit 腿执行的自动化用例，用 `Data(contentsOf:)` + `PropertyListSerialization` 读取已构建 `PurePace.app/Info.plist` **文件本体**，断言 `UIBackgroundModes` 实际数组同时包含 `location` 与 `audio`；用例在缺少 `location` 或缺少 `audio` 时断言失败（含可复现的负向自检/夹具证据）。
- ac-code-gates-green: 本地 `code_gates` 全部门禁通过，包含新增的 plist 读回断言与更新后的 `lint-ios-shell`，无门禁被删除或降级。
- ac-no-business-source-change: `ios/PurePace/` 下业务源码（Audio/播报、AudioSession 适配器、CoreLocation/定位、持久化、UI）零改动；`ios/Core`、`ios/RunCore` 业务逻辑零改动。
- ac-release-candidate-artifact: 合入 main 后按既有「候选包与证据转移口径」重出 Release 候选，生成 `artifacts/candidates/Release-candidate-*.txt`，内容至少含：zip **绝对路径**、**zip sha256**、**exec sha256**、构建配置（Release）、签名身份、合入 main 的 commit sha、以及**构建产物 Info.plist 中 `UIBackgroundModes` 的实际数组 dump**；并明确以 **zip sha256 + plist 实际数组** 作为候选与真机窗口验收键（旧 exec sha 可能因本次仅改 plist 而与旧包相同，不能用于区分新旧包）。
- ac-merge-commit-reported: 交付合入 main 后立即回报 merge 后 main commit sha。

## Non-Goals

- 不改 `.github/workflows/*`，不做 CI 分类扩围。
- 除 `scripts/check-ios-shell.sh` 中与本项直接耦合的定位/后台模式结构断言外，不改 `scripts/*` 其它逻辑。
- 不改 UI / 业务功能，不改 AudioSession 适配器、播报逻辑、CoreLocation、持久化。
- 不引入任何新依赖（含第三方库、远程 package）。
- 不自行约人、不自行起设备场、不做真机验收结论；真机窗口由公司约人后派发。
- PLA 未接受前禁止重试 produce/sigh。
- 不顺手重构、不扩大范围、不降级任何既有门禁与断言。

## Implementation Constraints

- 关键落点（已核对）：
  - `ios/project.yml:45-49`：`info.path: PurePace/Info.plist` + `info.properties.UIBackgroundModes: [location]` → 改为 `[location, audio]`。
  - `ios/project.yml:59`：删除 `INFOPLIST_KEY_UIBackgroundModes: location`。
  - `ios/PurePace/Info.plist`：数组键本体，当前仅 `location`；若 XcodeGen 生成工程不自动改写它，需同步补齐为 `location` + `audio`（该文件是 App Info.plist 真源，改它属于本项的声明补齐，不属于业务源码）。
  - `ios/PurePaceTests/RunLocationSourceTests.swift:62-73`：现有 `Bundle.main` 断言保留；新增读回文件本体的用例（建议独立文件如 `BackgroundModesPlistTests.swift`，定位 App 用 `Bundle(for:)` 的 `.xctest` 路径向上取 `.app`，再读其 `Info.plist` 文件字节，不依赖 `Bundle` 缓存解析）。
  - `scripts/check-ios-shell.sh:150-193`（`validate_location_config`）与 `:384-408`（自检夹具）：改为校验 project.yml 无 `INFOPLIST_KEY_UIBackgroundModes`、Info.plist 数组含 `location` 与 `audio`，并补负向夹具（缺 audio / 缺 location / 重复 setting 均应 fail）。
- XcodeGen 版本 2.46.0 已在本机 `/opt/homebrew/bin/xcodegen`；生成命令：`xcodegen generate --spec ios/project.yml`（cwd 可设为 `ios/` 或仓库根，产物落 `ios/PurePace.xcodeproj`）。
- 生成工程为入库产物，必须与 spec 一致提交；不得手写 `project.pbxproj`。
- 单元测试由 `bash scripts/test-ios.sh` 的 `-only-testing:PurePaceTests` 腿执行，App 产物路径为 `.build/ios/Build/Products/Debug-iphonesimulator/PurePace.app`（test target 已由 XcodeGen 自动设置 `TEST_HOST`）。
- 交付阶段：合并 main 后先跑完整 `code_gates`，再重出 Release 候选与证据文件；真机窗口验收由公司派发，本项不产出真机结论。
