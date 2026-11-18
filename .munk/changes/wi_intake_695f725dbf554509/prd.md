# 补定位失败链路：didFailWithError 与 locationServicesEnabled 前置检查（含必红反例）

## 范围

- `ios/PurePace/Location/RunLocationSource.swift`：`RunLocationManagerHandler`（约 :117-120）增加错误回调；`SystemLocationManager` 的 delegate 扩展（约 :402-424）实现 `locationManager(_:didFailWithError:)`，把 `CLError` 转成可发送快照（照既有 `LocationPayload` 模式），经 `RunLocationSource` 转发给 `RunLocationSourceDelegate`；`RunLocationProviding` 增加只读成员（如 `lastErrorCode` / `lastErrorMessage`）并在协议扩展给默认值，保证现有 fake 全部照常编译。
- `ios/PurePace/Location/SystemAuthorizationProbe.swift` 与 `ios/PurePace/Run/RunLocationReadiness.swift`：把 `CLLocationManager.locationServicesEnabled()` 纳入 readiness（新增 `servicesDisabled` 或复用 `unavailable` + 明确文案），`L10n.swift` + `Resources/Localizable.xcstrings` 增加 zh-Hans 文案键，并给 `UIApplication.openSettingsURLString` 引导。
- `ios/PurePace/Run/RunDiagnostics.swift`（约 :11-60）与 `Settings/SettingsView.swift`：诊断快照增加最近一次定位错误字段（无错误时明确写「无」），并进 text/复制导出。
- 断言：`ios/PurePaceTests/RunPermissionAndDiagnosticsTests.swift` 补两条 spy 断言并各附造错必红反例；`docs/verification-matrix.md` 对应行更新「断言 / 反例 / 证据」。
- `.munk/baseline/domains/ios-run-resilience/product.md:112` 目前宣称「已补 didFailWithError 与 locationServicesEnabled」，与代码现状不符；只改这一句为真实状态（fold 面，不扩写）。

## 验收

- ac-location-error: 系统定位失败（`didFailWithError`，至少覆盖 `.denied` 与 `.locationUnknown`）被记录进状态/诊断且不静默；断言：注入错误后 `lastErrorCode` 与诊断 text 可见对应值，反例 = 断开错误转发后同一断言必红。
- ac-services-disabled: `locationServicesEnabled() == false` 时点「开始」不进入记录态，呈现 zh-Hans 明确原因文案 + 跳系统设置引导；断言：注入 services=false → readiness 为对应状态且 `start()` 不进入 running，反例 = 去掉该前置检查后必红。
- ac-diagnostics-error: 诊断快照含最近错误字段（无错误时明确空态文案），断言按「该行存在 + 值匹配」写，不断言总行数。
- ac-no-silent-loss: 错误或服务关闭状态下结束，详情页仍给 时长 / 采样点数 / 「未获取到定位，距离为空」，不空白、不崩溃。
- ac-fast-legs: 同一 commit 本地快腿全绿并写进回执：`swift test --package-path ios/RunCore`、`PurePaceTests`、`scripts/check-ios-shell.sh --self-test`（若改了受管视图/identifier 必须显式跑）。

## 非目标

- 不改 UI 设计与版式、不新增功能面、不动 `VERSION` / release notes、不推 tag、不上传、不碰 Android 侧。
- 不做真机 / 模拟器窗口验收（真机待人现场），不新建验证脚手架，不重写历史 commit。
- 不顺手修既有混面 commit，不扩大 `.munk/baseline/**` 改动范围。

## 实现约束

- 文案全部走 String Catalog 单一来源 zh-Hans，禁裸英文字面量、禁中英混排；identifier 只增不改。
- 错误注入必须能在不改生产代码的前提下造红（经既有 `StubLocationManager` / handler 或 spy 注入），不得靠改生产代码才红。
- 诊断字段只扩展 `RunDiagnostics` 单一快照，不新建第二套计时/定位真源。
- 新增文案键不改既有 icon/identifier 计数契约；改受管视图时同步 `scripts/check-ios-shell.sh` 夹具与计数。

## 本单执行约束（不 fold）

- 预算硬上限 ≤3M token / ≤45 分钟墙钟；到点立即停手交未闭合回执（已做 / 未做 / 已过门 / 未闭合点），不续命、不重跑已绿门、不弱化断言。
- 只许改 `ios/`、`docs/verification-matrix.md`、`.munk/baseline/domains/ios-run-resilience/product.md` 那一句；其余路径不动。
- commit 按面拆分：code（源码 / 测试）/ fold（矩阵 / baseline）不得同 commit；混面会被 delivery 拦下。
- 回执只写实际跑到的范围与命令结果；未跑齐的腿如实写「未跑齐」及截断位置，不写绿。
- 不建人闸卡、不派直装、不做任何上传。
