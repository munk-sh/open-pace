# 真机 TCC 授权改走 XCUITest 官方路径（可复用 TCC 步骤）

## 范围

- 新增 `ios/PurePaceUITests/TCCAuthorizationUITests.swift`：可复用 TCC 授权步骤 + 真机专属用例
  `testTCCFreshInstallReachesAuthorizedAlways`。只走官方可及性路径：
  SpringBoard 应用查询（`XCUIApplication(bundleIdentifier: "com.apple.springboard")`）+
  `addUIInterruptionMonitor` 兜底 + 精确 label 匹配；对 App 自身控件仅用 accessibility 定位。
- 在 `scripts/verify-ios-device-flow.sh` 增加 `tcc` 阶段登记（`-only-testing` 驱动）与
  `--list`（无真机也可列出阶段/用例）；`tcc` 阶段用 Debug 构建 + 真实 CoreLocation
  （不传 `-uiTestLocation` / `-releaseDeterministicLocation`）。
- 让新用例不进默认模拟器 UI 腿：`scripts/test-ios.sh` 的 UI 调用追加
  `-skip-testing:PurePaceUITests/TCCAuthorizationUITests`。
- 新增 `docs/device-tcc-automation.md`：链路、label 兜底表、失败判读、与 P0-2 `scripts/device-*.sh`
  的调用关系。
- 用 `xcodegen generate --spec ios/project.yml --project ios` 重新生成并入库 `.xcodeproj`
  （生成产物，禁止手写 pbxproj）。

## 验收

- ac-tcc-list-no-device: `bash scripts/verify-ios-device-flow.sh --list` 在无真机环境下退出 0，且输出包含
  `tcc` 与 `PurePaceUITests/TCCAuthorizationUITests/testTCCFreshInstallReachesAuthorizedAlways`。
- ac-tcc-official-api-only: TCC 授权路径不含像素采样、颜色判定、归一化坐标点击或「截图找按钮」；
  仅使用 SpringBoard/App 的 accessibility 元素查询与精确 label 匹配（结构断言可 grep 自证）。
- ac-tcc-fresh-grant: 未授权状态下首启出现首次系统弹窗时，按「使用App时允许」类 label 匹配并点击；
  随后 App 发起 Always 升级请求时，若出现「更改为始终允许」类弹窗则同样匹配点击；
  步骤产物记录 `authorizationMode=grantedThisRun`、`firstPromptHandled=true` 与实际命中的 label。
- ac-tcc-preauth-idempotent: 设备已预先授权（无任何系统弹窗）时用例不红，记录
  `authorizationMode=preAuthorized`、`firstPromptHandled=false`，并继续执行同一自报校验。
- ac-tcc-self-report-always: `tcc` 阶段以 App 自报为准：容器 `Documents/Runs` 中本次新跑次的
  `telemetry.authorizationStatus.name == "authorizedAlways"` 且 `rawValue == 3` 才通过；
  不靠人看截图，也不以「弹窗点到了」代替授权结果。
- ac-tcc-failure-diagnostics: 任一步骤失败时证据含 `tcc-result.json`，写明失败阶段（等待首启/处理首次弹窗/
  发起升级/处理升级弹窗/结束跑次）、期望 label 列表与当时实际存在的 SpringBoard 与 App 弹窗按钮 label 集合；
  `report.md` 的失败项能直接判读是哪一步、缺哪个 label。
- ac-tcc-default-leg-excluded: 默认模拟器 UI 腿不执行该套件（`scripts/test-ios.sh` 带
  `-skip-testing:PurePaceUITests/TCCAuthorizationUITests`）；`.github/workflows/**` 不变，
  不新增 CI 腿，600s 预算与三件套测试执行预算参数不变。
- ac-tcc-compile-gates: 模拟器目标 `xcodebuild build-for-testing` 成功（新测试 target 编译通过），
  既有 `code_gates` 全绿；重新生成的 `.xcodeproj` 包含新文件且非手写。
- ac-tcc-boundary-clean: 变更不触碰 `scripts/device-*.sh`、App 业务源码、`ios/project.yml`、
  `Info.plist`、签名配置与 `VERSION`。

## 非目标

- 不复活、不改写任何 BMP/逐行像素测蓝字或坐标硬编码实现；像素探测路径永久排除。
- 不改 App 业务源码与定位/音频契约；不新增 App launch flag 来暴露授权状态。
- 不修改 P0-2 正在新增的 `scripts/device-*.sh` 主入口脚本，也不与其抢同一文件。
- 不在本工作项内起真机设备场；不跑正式验收窗口；不改 pbxproj 入库策略（P1-1）。
- 不做日志降噪（P1-2）；不改 `.github/workflows/**`、不新增 CI 腿、不改 600s 预算。
- 不承诺修好 TCC 弹窗在特定 iOS 版本上的系统文案差异，只提供 label 兜底与可判读失败。

## 实现约束

- 文件锚点：
  - 新增 `ios/PurePaceUITests/TCCAuthorizationUITests.swift`（用例 + 可复用 label 表/弹窗处理/诊断附件）。
  - 改 `scripts/verify-ios-device-flow.sh`：`--list` 早退（preflight 之前，不需设备）；新增
    `tcc` 阶段（Debug）、`run_tcc`、分析分支与报告用例名；不动既有 audit/audio/background 预算与行为。
  - 改 `scripts/test-ios.sh`：默认 UI 腿追加 `-skip-testing:PurePaceUITests/TCCAuthorizationUITests`，
    同步 usage 说明；保留既有 600s/测试执行预算与三件套参数。
  - 新增 `docs/device-tcc-automation.md`。
  - 重新生成 `ios/PurePace.xcodeproj`（xcodegen），仅作生成产物入库。
- 真实链路（Debug，真机）：
  1. `app.launch()`（真实定位源，`-uiTestResetArchive` 可清历史但不强制重装 TCC）；
  2. 有界等待 SpringBoard/App 弹窗；命中首次弹窗则按「使用App时允许」/「允许一次」类 label 处理；
  3. 等待 `run.backgroundDegraded` 出现（WhenInUse 的 App 自报降级提示）或短窗口超时；
  4. 点击 `run.start` 触发 `requestAlwaysAuthorization`；若出现「更改为始终允许」类弹窗则处理；
  5. 有界等待 `run.backgroundDegraded` 消失（App 自报已非 WhenInUse）；点击 `run.finish` 并等 `run.saved`；
  6. 落 `tcc-result.json` 附件：`authorizationMode`、`firstPromptHandled`、各阶段命中/缺失 label、
     SpringBoard 与 App 实际弹窗按钮集合。
  7. 脚本侧 `copy_container` 后读取本次新跑次 JSON，断言 App 自报授权为 authorizedAlways/rawValue=3。
- label 兜底至少覆盖（中英双语，精确匹配，不做包含匹配）：
  - 首次：`Allow While Using App` / `使用App时允许`、`使用 App 期间允许`；`Allow Once` / `允许一次`；
    `Don't Allow` / `不允许`（仅用于诊断，不点击拒绝）。
  - 升级：`Change to Always Allow` / `更改为始终允许`、`允许改为始终允许`；`Always Allow` / `始终允许`；
    `Keep Only While Using` / `仅在使用App期间允许`（仅诊断）。
- 禁止在 TCC 路径使用 `XCUICoordinate`、`normalizedOffset`、截图/颜色像素读取、按图片找按钮；
  失败诊断只输出可及性 label 集合，不靠截图判读。
- 真机验证归属：本项只交代码 + 文档 + 本地可验证项（`--list`、模拟器 build-for-testing、既有 code_gates）。
  「新装包首启到 authorizedAlways ≤3 分钟」由 Owner 走既有设备 ops task `task_97c958a247a259ff` 执行；
  本项回执写「等待设备验证」。
- 若真机实测证明系统弹窗确不可自动化：退化为「装包后预置 + App 自报校验」，把实测原文与退化理由写入
  回执与 `docs/device-tcc-automation.md`；不得退回像素探测。
