# 真机 TCC 授权自动化（`--phase=tcc`）

对应脚本：`scripts/verify-ios-device-flow.sh --phase=tcc`（**需真机连接**）。
用例：`ios/PurePaceUITests/TCCAuthorizationUITests.swift` →
`PurePaceUITests/TCCAuthorizationUITests/testTCCFreshInstallReachesAuthorizedAlways`。

本阶段的目标链路：**新装首启 → 首次系统弹窗 → Always 升级 → App 自报 `authorizedAlways`**。
授权是否达成只看跑次 JSON 的 App 自报，不看「弹窗点到了」，也不看截图。

```bash
bash scripts/verify-ios-device-flow.sh --list     # 无需真机，列出阶段与用例（exit 0）
bash scripts/verify-ios-device-flow.sh --phase=tcc
```

## 驱动口径

| 项 | 取值 |
|---|---|
| 构建 | Debug（真实 `RunLocationSource`，**不传** `-uiTestLocation` / `-releaseDeterministicLocation`） |
| 用例选择 | `-only-testing:PurePaceUITests/TCCAuthorizationUITests/testTCCFreshInstallReachesAuthorizedAlways` |
| 默认模拟器 UI 腿 | 排除：`scripts/test-ios.sh` 的 UI 调用带 `-skip-testing:PurePaceUITests/TCCAuthorizationUITests` |
| 证据目录 | `artifacts/device-audit/<UTC>/`（`tcc-result.json`、`run-*.json`、`report.md` 等） |
| 通过判据 | 本次新跑次 `telemetry.authorizationStatus.name == "authorizedAlways"` 且 `rawValue == 3` |

## 链路（用例内步骤）

1. `app.launch()`，启动参数仅 `-uiTestResetArchive`（清历史归档，不重置 TCC；不改变包签名与授权）。
2. 有界等待进入前台（≤ 30s），并**处理首个系统弹窗**（≤ 20s）：按 label 而不是按时序分类——
   命中「使用App时允许」类 → `authorizationMode=grantedThisRun`、`firstPromptHandled=true`；
   命中「更改为始终允许」类 → 设备预先 `WhenInUse`（首启即由 `RunLocationSource.start()`
   发起 Always 升级），记 `authorizationMode=preAuthorized` + `upgradePrompt`；
   整窗无弹窗 → `authorizationMode=preAuthorized`（已预先授权，幂等通过）。
3. 首启就绪判定：`run.distance` 出现（≤ 60s；系统弹窗可能盖在 App 上方，故放在步骤 2 之后）。
4. 有界等待 `run.backgroundDegraded`（WhenInUse 的 App 自报降级提示，≤ 15s），短窗口超时即继续。
5. **发起升级**：点击 `run.start`，App 侧 `RunLocationSource.start()` 对 `authorizedWhenInUse`
   发起 `requestAlwaysAuthorization()`（每实例一次）。升级弹窗已在步骤 2 处理过时不再重复等待。
6. **处理升级弹窗**（≤ 20s）：命中「更改为始终允许」类即点击。
7. 等待 `run.backgroundDegraded` 消失（≤ 20s，App 自报已非 WhenInUse），
   再 `run.finish` 并等 `run.saved`（**结束跑次**，≤ 30s）。
8. 落 `tcc-result.json` 附件，脚本 `copy_container` 后读取本次新跑次 JSON 断言自报授权。

失败时用例不会提前中断：`tcc-result.json` 仍会落盘，脚本按其中的失败阶段与 label 集合判读。

## label 兜底表（精确匹配，不做包含匹配）

| 阶段 | 点击（命中即用） | 仅诊断（只记录，不点击） |
|---|---|---|
| 首次（WhenInUse） | `Allow While Using App`、`使用App时允许`、`使用 App 期间允许`、`Allow Once`、`允许一次` | `Don't Allow`、`不允许`、`Allow`、`允许` |
| Always 升级 | `Change to Always Allow`、`更改为始终允许`、`允许改为始终允许`、`Always Allow`、`始终允许` | `Keep Only While Using`、`仅在使用App期间允许`、`仅在使用 App 期间允许` |

- 只做**精确** label 匹配，不使用包含匹配，避免误点其它按钮。
- 禁止在 TCC 路径使用 `XCUICoordinate`、`normalizedOffset`、截图 / 颜色像素读取或「按图找按钮」；
  像素探测路径永久排除。`addUIInterruptionMonitor` 仅作为兜底，命中判据仍是同一张精确 label 表。
- 系统文案随 iOS 版本变化时不承诺自动修复：兜底表未命中即按失败阶段判读（见下节）。

## 失败判读（`tcc-result.json`）

关键字段：

| 字段 | 含义 |
|---|---|
| `authorizationMode` | `grantedThisRun`（本次处理过首次弹窗）/ `preAuthorized`（无弹窗，已预先授权） |
| `firstPromptHandled` | 是否点击过首次弹窗允许项（`grantedThisRun` 必为 `true`，`preAuthorized` 必为 `false`） |
| `hitLabels` | 各阶段实际命中的 label（`firstPrompt` / `upgradePrompt`） |
| `failureStage` | 首个失败阶段，取值：`等待首启` / `处理首次弹窗` / `发起升级` / `处理升级弹窗` / `结束跑次` |
| `failures[]` | 每项含 `stage`、`reason`、`expectedLabels`、`actualPromptButtons.springboard / .app` |
| `backgroundDegradedGone` / `saved` | 降级提示是否消失 / 结束是否得到「已保存」 |

`report.md` 的失败项会把每条失败写成
`tcc-<阶段>: 阶段 <名>：<原因>；期望 label=[...]；实际弹窗按钮 SpringBoard=[...] App=[...]`，
据此可直接判读是哪一步、缺哪个 label；脚本断言表另有 `tcc-self-report-authorized-always` 一行，
写明自报的 `{name, rawValue}`。

常见组合：

| 现象 | 判读 |
|---|---|
| `authorizationMode=preAuthorized` + 自报 `authorizedAlways` | 已授权设备幂等通过 |
| `处理首次弹窗` 失败且实际按钮集合非空 | 系统首次弹窗文案不在兜底表内，按实际集合补表 |
| `处理升级弹窗` 失败且实际含 `Keep Only While Using` | 升级弹窗被判为降级项，未命中升级 label |
| 各阶段无失败但自报 `authorizedWhenInUse` | 弹窗流程走通但系统未升级，以自报为准判失败 |
| `tcc-result-json` FAIL | 用例未产出诊断附件（构建/启动/崩溃），先查 `xcodebuild-tcc.log` |

## 与 P0-2 `scripts/device-*.sh` 的调用关系

- 本阶段**不修改**也**不接管** P0-2 正在新增的 `scripts/device-*.sh` 主入口脚本；
  它只负责装包 / 启停 / 容器读取等设备动作，本阶段只负责授权链路与自报校验。
- 推荐调用顺序（由设备侧入口编排）：`device-install`（装新包）→
  `bash scripts/verify-ios-device-flow.sh --phase=tcc`（授权 + 自报校验）→
  后续 audit / audio / background 取证阶段。
- 需要「新装包」语义时先卸载再装，TCC 才会回到未授权态：`xcrun simctl` 不适用于真机，
  真机用 `xcrun devicectl device uninstall` / 重新安装候选包完成；本脚本不代做卸载。
- 脚本侧只加阶段与 `--list`，不改既有 audit / audio / background 的预算与行为；
  `.github/workflows/**` 与 600s 预算参数不变。

## 真机验证归属与退化策略

- 本项交付：代码 + 文档 + 本地可验证项（`--list`、模拟器目标 `build-for-testing`、既有 `code_gates`）。
- 「新装包首启到 `authorizedAlways` ≤ 3 分钟」由 Owner 走既有设备 ops task `task_97c958a247a259ff`
  执行；本项回执写**等待设备验证**，不宣称真机已通过。
- 若真机实测证明系统弹窗确实不可自动化：退化为「装包后预置授权 + App 自报校验」，
  把实测原文与退化理由写入回执与本文件；**不得**退回像素探测。
