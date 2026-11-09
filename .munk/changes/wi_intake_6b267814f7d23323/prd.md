# iOS 后台锁屏连续定位（Always 授权 + 后台采集 + 恢复连续性）

## Scope

补齐「后台锁屏连续定位」这一未实现能力（当前 main@0864b83a 全仓 0 命中 `allowsBackgroundLocationUpdates`，`RunLocationSource` 仅做前台采集、只 `requestWhenInUseAuthorization()`，锁屏后系统会挂起更新）。只改定位数据源与其授权/后台路径、必要的配置声明与单测，落点在既有契约内补能力。

1. **后台采集开关**：跑步进行态开启 `CLLocationManager` 后台更新（`allowsBackgroundLocationUpdates = true`、`pausesLocationUpdatesAutomatically = false`）；跑步结束/暂停/停止时复位 `allowsBackgroundLocationUpdates = false` 防耗电。`Info.plist` / `project.yml` 复核并保留 `UIBackgroundModes: location`。
2. **授权迁移到 Always**：新增 `requestAlwaysAuthorization` 升级路径与状态处理；用户只给 WhenInUse 时记录降级状态并由 UI 明确提示（不 crash、不静默失败）；授权状态变化回调改为可注入、可用 `CLLocationManager` 桩单测。
3. **后台 ingest 连续性**：锁屏/进后台/进程被挂起再恢复后，样本 ingest 不重复、不丢段；复用既有「已完成段落盘与重启恢复」契约，不重写持久化。
4. **可断言项进 XCTest**：plist background mode 存在、跑步态后台属性为 true / 结束态为 false、授权状态迁移分支（桩注入）、后台 ingest 恢复后连续。

## Acceptance Criteria

- ac-plist-background-mode: `ios/PurePace/Info.plist` 与 `ios/project.yml` 都声明 background mode `location`，且 `bash scripts/check-ios-shell.sh` 的定位配置断言通过（含缺 plist / 非 location 反例仍 fail）。
- ac-bg-enabled-while-running: 会话进入跑步进行态（`start()` 后已授权）时，定位管理器的 `allowsBackgroundLocationUpdates == true` 且 `pausesLocationUpdatesAutomatically == false`。
- ac-bg-disabled-after-stop: 调用 `stop()`（结束/停止）后 `allowsBackgroundLocationUpdates == false`，且不再继续后台更新。
- ac-always-request-path: 授权为 `notDetermined` 时走 `requestWhenInUseAuthorization`；已 WhenInUse 且未获得 Always 时存在 `requestAlwaysAuthorization` 升级调用路径，且工程声明了 Always 用途描述键（`NSLocationAlwaysAndWhenInUseUsageDescription` 非空）。
- ac-wheninuse-degraded-visible: 用户仅授予 WhenInUse 时，对外授权状态带明确降级标记（可断言 `backgroundCapable == false` 或等价字段），UI 呈现明确的降级提示文案（可断言标识/文案存在），进程不 crash、不静默无提示。
- ac-auth-transitions-injectable: 通过注入 `CLLocationManager` 桩可驱动授权变化，XCTest 覆盖 `notDetermined → authorizedWhenInUse → authorizedAlways` 与 `denied`/`restricted` 分支，且每次变化都回调 delegate。
- ac-bg-ingest-continuous: 模拟锁屏/后台挂起后恢复（重叠时间窗与重复投递），最终 ingest 的样本无重复、无丢失段落，与既有 checkpoint 重启恢复结果一致。
- ac-ios-local-gates-green: `xcodebuild build` + `xcodebuild test`（`scripts/test-ios.sh`）全绿并输出 `** TEST SUCCEEDED **`，`scripts/check-ios-shell.sh`、`scripts/check-ios-scripts.sh` 等 iOS 相关门全绿。
- ac-delivery-artifacts: Delivery 阶段产出候选 zip 与可执行 `sha256` 校验值，供真机硬门绑定。

## Non-Goals

- 不改 GPX 导出与 `shared/` 数据契约。
- 不改播报队列 / TTS / `Audio/` 播报行为。
- 不改 UI 布局与导航结构（仅允许必要的授权降级提示文案/标识）。
- 不重写定位/音频/持久化的既有冻结契约（阶段 3 口径），只在 `RunLocationSource.swift` 及相关必需配置内补能力。
- 不引入第三方运行时依赖；不改 `.github/workflows`。
- 不做真机验收（产品层后续统一约窗）；任何「真机已验证」措辞禁止出现在代码、文档与交付说明中。

## Implementation Constraints

- 主落点：`ios/PurePace/Location/RunLocationSource.swift`（唯一允许改定位逻辑的文件）；配置落点 `ios/PurePace/Info.plist` 与 `ios/project.yml`；单测落点 `ios/PurePaceTests/`（可新增 `RunLocationSourceTests.swift`）。
- 必须保留 `scripts/check-ios-shell.sh` 现有静态契约：`CLLocationManager`、`requestWhenInUseAuthorization`、`activityType = .fitness`、`distanceFilter = kCLDistanceFilterNone`、`pausesLocationUpdatesAutomatically = false` 均不得被删；新增后台/Always 断言时同步扩该脚本（含正例与反例自检），不得放宽既有门。
- 授权回调可注入：把 `CLLocationManager` 的授权请求/状态读取抽象成可替换 seam（协议或工厂注入），`RunLocationSource` 生产默认用真实 `CLLocationManager`；测试用桩。
- 若扩展 `RunLocationProviding` 协议，必须同步更新既有实现 `RunTestLocationSource` 与 `ios/PurePaceTests/RunSessionViewModelTests.swift` 的 `FakeLocationSource`，保持编译与既有断言不回归；`RunTestLocationSource` 仍只允许在 `#if DEBUG` + `-uiTestLocation` 门控下使用。
- `CoreLocation` import 仅限 `ios/PurePace/Harness/` 与 `ios/PurePace/Location/`（脚本 import 允许表约束）。
- 后台 ingest 复用既有 `RunSessionOrchestrator` / checkpoint 契约，不改持久化格式；连续性测试可基于既有 Harness 恢复路径（`HarnessResumeTests` / `RunSessionViewModelTests`）扩展。
- 版本号仍以根 `VERSION` 为单一真源，不得写死。
