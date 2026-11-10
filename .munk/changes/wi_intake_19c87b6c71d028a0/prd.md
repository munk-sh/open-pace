# 真机锁屏验收的机器判读能力：锁屏/前后台遥测 + LaunchServices 自报 + `-autoStartRecording` + 新 Release 候选包

## 范围

范围冻结（公司裁决 `owe_40cfb6923633ccc4`，补充约束 `owe_94bb7b17031e90de` ack），只做以下三块，且全部为 additive：

1. **App 侧锁屏/前后台遥测**：观察 `UIApplication.protectedDataWillBecomeUnavailableNotification` / `protectedDataDidBecomeUnavailableNotification` / `didEnterBackgroundNotification` / `willEnterForegroundNotification`，把 `{事件名, UTC 时刻(ISO8601), 当刻样本计数 / 累计距离 / 累计时长}` 按到达顺序追加进**既有跑次 JSON 的 `telemetry.events` 数组**（明确选定「内嵌跑次档案」这一种落点，不再新增同目录 sidecar telemetry JSON；理由：沿用既有 `RunTelemetryWriter` 单写回路径，零新增文件/契约分裂）。
2. **设备侧自报字段**：跑次结束写遥测时，把**运行中已装包自身**的 `Bundle.main.infoDictionary` 实际值写入同一份 `telemetry.bundle`：`UIBackgroundModes` 实际数组、`CFBundleIdentifier`、`CFBundleShortVersionString`、`CFBundleVersion`。这是「设备侧」断言的**唯一来源**，替代已裁决降级的「设备侧 Info.plist 文件读回（`devicectl copy from` 无 bundle 域 exit 64）」。
3. **`-autoStartRecording` launch-arg 门控**：默认关；新增启动参数使 App 启动后自动进入记录态，支持 `devicectl device process launch <bundleid> -autoStartRecording 1` 透传；无该 flag 时行为与现路径逐字节一致。该 flag 必须编译进 Release（候选包是 Release，设备端不能靠 Debug-only 通道）。
4. **出新 Release 候选包**：在 `abacaa757`（launch-arg 确定性定位源门控）**合入 main 之后的最新 main** 上构建，`-configuration Release` + dev 签名（Apple Development / Team `3X4J53U6RY`，`-allowProvisioningUpdates`），禁手改 pbxproj；实算 zip sha256 + exec sha256，并落 `artifacts/candidates/Release-candidate-*.txt`。一次构建、一个窗口，不重出包。

## 验收

- ac-telemetry-events-fields: 新跑次 JSON 顶层 `telemetry.events` 为数组，每元素含 `name`（字符串）、`at`（ISO8601 UTC 字符串，形如 `2026-11-10T03:04:05Z`）、`sampleCount`（整数）、`distanceMeters`（数值）、`elapsedSeconds`（数值）；字段名与类型固定，无占位值。落点：`ios/PurePaceTests/RunLifecycleTelemetryTests.swift`（真实临时目录落盘后按原始 JSON 回读）。
- ac-telemetry-event-names: 四条通知分别记录为 `protectedDataWillBecomeUnavailable`、`protectedDataDidBecomeUnavailable`、`didEnterBackground`、`willEnterForeground`；注入四条通知后 `events` 恰好 4 条且名称集合相等、无重复。落点：同文件单测。
- ac-telemetry-event-order-and-time: 注入四条通知（含注入可序列化时钟）后，`events` 顺序与通知到达顺序严格一致；每条 `at` 等于注入时钟在该事件时刻的 UTC ISO8601 秒级（或毫秒级，格式固定）字符串，`at` 可被 `ISO8601DateFormatter` 解析且不随时间本地化漂移。落点：同文件单测断言名称序列、时刻字符串与顺序。
- ac-telemetry-event-snapshot: 每条事件的 `sampleCount` / `distanceMeters` / `elapsedSeconds` 等于**该事件发生当刻**的跑次快照（注入桩给出 3→7→9→12 等递增样本数、对应距离与活跃时长），不得写成跑次结束时的终值；样本计数是本跑次内自增计数（`start()` 归零），不得复用跨跑次累加的 `sampleSources` 字典。落点：同文件单测。
- ac-telemetry-additive-no-behavior-change: 无事件时 `events` 为 `[]` 且既有 `telemetry` 键（授权/精度/后台开关/`announcements`）与 `samples[].source` 逐字段不变；事件观察器在任何状态（未开跑/暂停/已结束）都只记录、不改变 `RunSessionState`、不触发 `locationSource.start()/stop()`、不改距离/时长/配速/分段/GPX 输出。落点：新增单测 + 既有 `RunTelemetryTests` / `RunSessionViewModelTests` / `test-ios-run-core` / `check-gpx-export` 回归。
- ac-bundle-self-report: 新跑次 JSON 的 `telemetry.bundle` 含 `backgroundModes`（字符串数组，取值即 `Bundle.main.infoDictionary["UIBackgroundModes"]` 实际数组）、`identifier`、`shortVersion`、`buildVersion`（后三者来自同一 `infoDictionary` 的 `CFBundleIdentifier` / `CFBundleShortVersionString` / `CFBundleVersion`）；本机跑 App target 单测时断言 `bundle.identifier == "sh.munk.purepace"` 且 `bundle.backgroundModes` 含 `location` 与 `audio`；注入假字典时按同一映射输出。落点：新增单测（注入 `Bundle.main` 型字典与假字典两条路径）。
- ac-autostart-default-off: 无 `-autoStartRecording` 参数时解析结果为 `false`；`["PurePace"]`、空数组、仅其它 launch-arg 均不得开启。该断言为代码层单测，并落在**默认模拟器腿**（`bash scripts/test-ios.sh --unit-only`，即 `code_gates` 的 `test-ios`）真实执行。落点：`ios/PurePaceTests/RunLaunchArgumentsTests.swift`。
- ac-autostart-on-and-value: 参数为 `-autoStartRecording 1` 时解析结果为 `true`；裸 `-autoStartRecording`（无值）为 `true`；`-autoStartRecording 0` / 非法值为 `false`；解析器编译进 Release（不含 `#if DEBUG` 包裹）。落点：同文件单测 + 源码断言（`check-ios-shell.sh`）。
- ac-autostart-wiring: 开启时 App 出现过一次自动开跑：ViewModel 收到 `autoStartRecording == true` 且状态为 `.ready` 时由首屏出现触发 `start()` 恰好一次（重复 `onAppear` 不重复开跑）；关闭时 `onAppear` 后状态仍为 `.ready` 且不产生 `RunRecord`。落点：`RunLaunchArgumentsTests` / `RunSessionViewModelTests`（默认模拟器腿）。
- ac-autostart-isolation: `-autoStartRecording` 与定位源门控 `-uiTestLocation` **互不读取**：仅 `-autoStartRecording` 时定位源仍是真实 `RunLocationSource`（`sampleSource == .device`），仅 `-uiTestLocation` 时不会自动开跑；`-autoStartRecording` 不改变权限请求时机（仍在首屏出现时请求「使用期间」定位授权）、不改变后台/锁屏语义与 `telemetry` 既有字段。落点：单测断言两种参数组合下的定位源与自动开跑组合。
- ac-local-gates-green: 本地 `lint` / `lint-ios-shell` / `lint-ios-scripts` / `lint-ios-core` / `lint-ios-run-core` / `build-ios` / `build-ios-core` / `build-ios-run-core` / `test-ios-core` / `test-ios-run-core` / `test-ios --unit-only` / `test` 相关门全绿；`ios/project.yml` 与 `.munk/code-gates.json` 门 id/command 不变；新增源码与测试文件按既有口径登记进 `scripts/check-ios-shell.sh`（不弱化任何既有断言）。重 UI E2E 不作本地阻断门，由 `.github/workflows/ios.yml` 判。
- ac-candidate-preflight: 出包前先断言当前 `main` 已包含 `abacaa757` 的交付合入（`git log main --oneline` 含 `wi_intake_abacaa757` 或其合入 commit，`git rev-parse main` 可回溯到该 commit），且构建树源码同时含 `-autoStartRecording` 与 `abacaa757` 的收录式定位源门控；任一缺失则**不构建、不产出 zip/txt**，以 `munk_report_owner` 报出缺失依赖后停止（不得先出一个缺该门控的候选）。
- ac-candidate-tree-provenance: 候选从「最新 main + 本项变更」的干净 worktree 构建（`mainTipAtBuild`、`commit`、`treeSha` 写入记录）；build 前 `xcodegen generate --spec project.yml` 后 `ios/PurePace.xcodeproj` 零 diff；构建命令含 `-configuration Release`、`-destination 'generic/platform=iOS'`、`CODE_SIGNING_ALLOWED=YES`、`CODE_SIGN_STYLE=Automatic`、`DEVELOPMENT_TEAM=3X4J53U6RY`、`-allowProvisioningUpdates`；派生数据落 `.build/` 或仓外临时目录。
- ac-candidate-evidence-keys: `<productDir>/artifacts/candidates/Release-candidate-*.txt` 至少含 zip **绝对路径**、zip sha256、exec sha256、构建配置（Release）、签名身份、`commit`/`mainTipAtBuild`/`treeSha`、以及**解包 `.app/Info.plist` 的 `UIBackgroundModes` 实际数组 dump**；`验收键` 行改为 **zip sha256 + 设备侧运行中已装包自报（run telemetry 的 `bundle.backgroundModes`/`identifier`/版本）**，exec sha 只作辅助；同时注明「设备侧＝运行中已装包自报，非文件拷贝断言」。
- ac-candidate-hashes-real: `zipBytes` / `zipSha256` / `execBytes` / `execSha256` 均为对 zip 与解包 `.app/PurePace` 的实算值（`stat -f%z`、`shasum -a 256`），sha 为 64 位小写十六进制，且 `zipSha256` 不等于历史包 `81b9f2de…`；记录不含 `TBD` / `<sha256>` / `PLACEHOLDER`。
- ac-candidate-identity: `.app` 内无 `PurePace.debug.dylib`（`debugDylibCount=0`）；`signingIdentity` 含 `Apple Development` 与 `Team 3X4J53U6RY`，`provisioningProfile` 非空；解包 plist 可 grep 出 `CFBundleIdentifier=sh.munk.purepace`、`CFBundleShortVersionString=0.1.0`、`CFBundleVersion=1`、`MinimumOSVersion=17.0`、`UIBackgroundModes=["location","audio"]`（顺序可变，两项必含）。
- ac-no-external-side-effects: 出包过程不 `git push`、不打 tag、不建 GitHub Release、不做 TestFlight / ASC 上传；候选内容不含 CI boot 提速与 ASC 两项待办，不改 `ios/project.yml` 签名设置，不手改 `.xcodeproj/project.pbxproj`；回执与记录中真机项一律 `pending: 待人现场`。
- ac-evidence-wording: 交付回执与候选记录只准写「设备侧＝运行中已装包自报」；不出现「文件拷贝断言」「设备侧 Info.plist 读回成功」「真机已验证」「阶段整体通过」；回执必写清「遥测字段与写入位置」「autoStart 默认关证据（单测名 + 默认模拟器腿命令）」「候选双 sha 与 commit」。

## 非目标

- 不改 `CoreLocation` / `AudioSession` / 持久化与归档格式 / GPX 编码与导出 / 播报契约与业务逻辑；不改距离、时长、配速、分段算法。
- 不新增 UI 控件、不改视觉与 History/RunDetail 展示（`run.telemetry` DEBUG 摘要不扩展为新 UI）。
- 不改 Bundle ID（保持 `sh.munk.purepace`）；不改 `VERSION`；不把签名配置写进 `ios/project.yml`；不手改 `project.pbxproj`。
- 不排真机、不跑设备场、不驱动锁屏、不提 assist、不 `devicectl copy from` 读回 Info.plist；真机窗口由公司开 needs-you 卡另排。
- 不采用 XCUITest `Bundle.main.infoDictionary` 方案（Debug host 会顶掉候选包，证据不绑候选 sha）。
- 不新增 sidecar telemetry JSON（遥测只走既有跑次 JSON 的内嵌 additive 键）；不新增遥测展示页 / 数据库 / 第三方依赖。
- 不新增或放宽 `code_gates` 门 id / command；不夹带 CI boot 提速与 ASC 待办；不改 `.github/workflows/*` 语义。
- 不启动第二个真机窗口、不重出第二个候选包（一次构建、一次窗口）。

## 实现约束

- 落点选定：跑次 JSON 顶层 `telemetry` 下新增 `events[]` 与 `bundle{}` 两个键（additive，旧记录不触碰、不迁移）；沿用 `RunTelemetry` / `RunTelemetryWriter`（`JSONSerialization` 读顶层 → 只加键 → 临时文件 + `replaceItemAt` 原子替换），不新增 sidecar、不新增归档文件名规则。
- 事件采集接缝：新增 `ios/PurePace/Run/RunLifecycleTelemetry.swift`（`RunLifecycleTelemetryRecording` 协议 + 线程安全 recorder），构造参数可注入 `NotificationCenter`、`now: () -> Date`、`snapshot: () -> (sampleCount: Int, distanceMeters: Double, elapsedSeconds: TimeInterval)`；观察 `UIApplication.protectedDataWillBecomeUnavailableNotification`、`protectedDataDidBecomeUnavailableNotification`、`didEnterBackgroundNotification`、`willEnterForegroundNotification`（`UIKit`）。recorder 在 App 启动即注册（ContentView 持有，随 ViewModel 生命周期），deinit 移除观察者；事件名映射固定为 `protectedDataWillBecomeUnavailable` / `protectedDataDidBecomeUnavailable` / `didEnterBackground` / `willEnterForeground`。
- 快照来源：`sampleCount` 由 `RunSessionViewModel` 内本跑次自增计数（`start()` 归零），`distanceMeters` 取 `metrics.distance.meters`，`elapsedSeconds` 取 `metrics.elapsed`；不得复用未按跑次重置的 `sampleSources` 字典。事件快照在通知到达当刻由 recorder 调快照闭包取得。
- Bundle 自报接缝：新增 `BundleInfoProviding`（或等价最小协议），生产实现读 `Bundle.main.infoDictionary`，测试注入字典；`bundle` 只在 `injectTelemetry(for:)` 时写入。禁止 `#if DEBUG` 包裹（Release 候选包同样自报）。
- `-autoStartRecording` 形态沿用既有 launch-arg 先例（`CommandLine.arguments.contains` / `RunStorage.resetArchiveIfRequested(arguments:)` 风格）：新增 `ios/PurePace/Run/RunLaunchArguments.swift`，纯函数解析（如 `RunLaunchArguments.autoStartRecordingEnabled(arguments:)`），支持 `-autoStartRecording` 后跟 `1`/`true` 或裸 flag，其它值/缺省为 `false`；Release 可编译，**不与** `-uiTestLocation` 门控互相读取。
- 自动开跑接线：`RunSessionViewModel` 增加 `autoStartRecording: Bool = false` 与一次性守卫；仅在 `onAppear` 且 `state == .ready` 时自动 `start()` 一次，不改 `onAppear` 既有的定位授权请求链路；`ContentView` 只把解析结果作为参数传入，不改变定位源选择分支。
- 测试落点：新增 `ios/PurePaceTests/RunLifecycleTelemetryTests.swift`（四通知注入 → 名称/时刻/快照/顺序；bundle 自报两条路径）与 `ios/PurePaceTests/RunLaunchArgumentsTests.swift`（默认关、`1`/裸 flag/`0`、与定位源门控正交、auto start 恰好一次）；在 `scripts/check-ios-shell.sh` 的 `live_sources` / `unit_tests` 列表登记新文件（不弱化既有断言）。
- 候选包：`<productDir>` = `/Users/zhutao/Library/Application Support/Munk-AI/munk-auto/products/codebase_19e8ad47434ff059`（仓外），zip 与 `Release-candidate-<commit7>.txt` 落 `<productDir>/artifacts/candidates/`，字段顺序沿用既有 `Release-candidate-*.txt`（builtAt / commit / mainTipAtBuild / treeSha / buildConfig / signingIdentity / provisioningProfile / scheme+target / zipPath / zipSha256 / zipBytes / execName / execSha256 / execBytes / infoPlist dump / codesign / 验收键口径 / note）；解压校验用仓外临时目录，不污染 `git status`。
- 排期约束：本项优先，`abacaa757` 并行；两者合入后的唯一最终候选只构建一次。若构建时代码基（main）尚未包含 `abacaa757` 的交付合入，按 `ac-candidate-preflight` 走 `munk_report_owner`，不得先用当前 main 出一个候选再重出。
- 证据口径：只报本地门与单测实际结果、候选实算 sha；真机锁屏判读结论不在本项产出。
