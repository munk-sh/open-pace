# Domain: ios-privacy-consent

轨迹（行踪轨迹类敏感个人信息）的 iOS 单独同意门与隐私政策正文真源子域：政策正文只有 `docs/privacy/privacy-policy-zh-Hans.md` 一份真源，bundle 副本由 `scripts/sync-privacy-policy.sh` 逐字节生成；首次启动以全屏独立同意屏取值，同意态落在单一 `UserDefaults` 键（`TrajectoryConsentStore.consentKey`），未同意态记录入口禁用并给原因，设置页「关于」组可读政策全文并撤回同意。设置页视觉范式归 `ios-settings-visual`，令牌与标识符纪律归 `ios-ui-design` / `design-token-gates`，跑次状态机归 `ios-run-interaction`。

## 范围

- 政策正文真源：`docs/privacy/privacy-policy-zh-Hans.md`（采集项 / 用途 / 权限清单 / 存储与保留 / 共享 / 删除 / 撤回同意 / 未成年人 / 联系方式 / 生效日期十个二级标题条目）。
- 同步脚本：`scripts/sync-privacy-policy.sh` 把真源逐字节复制到 `ios/PurePace/Resources/privacy-policy-zh-Hans.md`（与 `sync-ios-version.sh` 同口径，不手抄第二份正文）。
- 政策断言：`scripts/check-privacy-policy.sh`（条目 + 关键词 + 虚假采集声明 + 正本/副本 sha256 一致 + `mktemp` 沙箱删条目反例），由 `scripts/check-baseline.sh` 调用，进入 `.munk/code-gates.json` 的 `test` 门。
- 渲染与存储：`ios/PurePace/Privacy/PrivacyPolicyDocument.swift`（按二级标题切分正文）、`PrivacyPolicyView.swift`（应用内全文）、`PrivacyConsentGateView.swift`（独立同意屏）、`TrajectoryConsentStore.swift`（单键持久化 + DEBUG UI 用例预置/清空）。
- 挂载与门控：`ios/PurePace/ContentView.swift` 全屏 `fullScreenCover` 呈现同意屏；`RunInteractionPlan` 新增 `startEnabled` 与 `Notice.consentRequired`；`RunView` 主操作 `run.start` 置 disabled 并显示 `run.consentRequired` 原因行。
- 设置页「关于」组：`settings.privacyPolicy`（进全文）、`settings.consentRevoke`（撤回），仅同意态显示撤回行。
- UI 用例兼容：`RunLaunchArguments` 新增 DEBUG-only `-uiTestConsentGranted` / `-uiTestResetConsent`；既有 13 条 UI 用例与截图取证套件预置已同意，三态用例并入既有 `RunFlowUITests`（不新增 xcodebuild 分段）。

## 验收

- ac-policy-single-source: `docs/privacy/privacy-policy-zh-Hans.md` 是应用内政策正文唯一真源；bundle 副本由同步脚本生成，两者 sha256 / 字节不等即判红；仓库内不存在第二份可独立漂移的政策正文。
- ac-policy-covers-required-items: 正文含且仅含一类「采集项 / 用途 / 权限清单 / 存储与保留 / 共享 / 删除 / 撤回同意 / 未成年人 / 联系方式 / 生效日期」条目，并逐条命中关键词：采集项「定位坐标 / 时间戳 / 距离 / 配速 / 分段」与「不涉及账号 / 通讯录 / 广告标识」；用途「本机 / 导出 / GPX / TCX / 分享」；权限「使用期间 / 后台 / 通知 / 音频播放 / 语音播报」；存储「仅本机 / 沙盒 / 无账号 / 无云同步 / 不上传服务器」；共享「用户主动导出 / 接收方」；删除「应用内删除 / 卸载」；撤回「撤回同意」。
- ac-policy-keyword-red-proof: 断言脚本自带沙箱反例——删除任一必需条目（至少覆盖「撤回同意」「存储与保留 / 不出本机」「采集项 / 敏感个人信息」）必须判红，未改动副本必须先判绿；反例不自证（断言读正文，反例改副本后重跑同一断言函数）。
- ac-policy-permission-truthful: 权限条目与工程事实一致——`ios/project.yml` 仅声明 `NSLocationWhenInUse` / `NSLocationAlwaysAndWhenInUse` 与 `UIBackgroundModes: location, audio`，故「通知」「音频播放 / 语音播报」写成「未请求 / 无需额外授权（无麦克风录音）」否定表述；正文出现「已请求通知权限」「读取通讯录」「使用广告标识」类肯定采集声明即判红。
- ac-consent-screen-first-launch: 无同意记录首次启动展示独立同意屏（`fullScreenCover`，不与记录页同屏堆叠）：标题「轨迹与位置数据授权」，正文含「敏感个人信息 / 只存在本机 / 可以拒绝 / 可随时撤回」四句语义；主操作 accent 填充「同意并继续」（`settings.consentAgree`），次操作「不同意」（`settings.consentDecline`）。
- ac-consent-decline-blocks-record: 未同意（从未同意 / 点「不同意」）态下 `run.start` 的 `isEnabled == false`，且页面出现原因文案（`run.consentRequired` = 「未同意轨迹与位置数据授权，暂不能开始记录。」）；点按不进入记录态（`state` 仍为 ready、无倒计时）。
- ac-consent-persist-single-key: 同意态只落单一 `UserDefaults` 键（`TrajectoryConsentStore.consentKey`，键名字面量只在类型内出现一次）；点「同意并继续」后同进程与冷启动重进均不再弹同意屏且 `run.start` 可用；点「不同意」不写同意，冷启动仍不可开始；单测断言键唯一与读写往返一致。
- ac-consent-revoke-restores-gate: 设置页「关于」入口可打开政策全文（应用内渲染同一真源文本，外链不是唯一路径）并可撤回同意；撤回后键值置为未同意、`run.start` 再次禁用、重进可见同意屏。
- ac-copy-and-identifier-discipline: 新增视图零裸字面量（含中文），新增用户可见文案经 `L10n` 键落 `Resources/Localizable.xcstrings`；33 项冻结 identifier 一个不改，新增项全局唯一且带中文可读 `accessibilityLabel`；`DesignTokens.Colors.palette` 仍 18 键、`Typography.sizes` 仍 6 档，同意屏 / 政策页无字面色值、字号、间距、圆角。
- ac-consent-assertions-red-proof: 单测 / UI 用例覆盖「未同意 → 同意屏存在且开始按钮 disabled」「同意后 → ready 且可开始」「撤回后 → 未同意态且不可开始」三条转换，每条至少一处反例（拆门 / 写错键 / 撤回空操作必红）；`bash scripts/check-ios-shell.sh --self-test` 全绿，identifier 计数下限随新增项同步提高。
- ac-verification-matrix-updated: `docs/verification-matrix.md` 新增本项接缝行（隐私政策正文真源、轨迹数据单独同意门），每行含接缝 / 现状（本项实测口径）/ 断言名 / 反例 / 证据路径 / 归属 `wi_intake_4fbbc7fe48870717`；`DocsVerificationMatrixTests` 的 `expectedSeamCount`（23 → 25）与 seams 清单同 commit 更新。
- ac-gates-green: `bash scripts/check-baseline.sh` 退 0；`bash scripts/test-ios.sh` 全绿（含 UI 腿四段）；CI `ios.yml` 权威腿绿。
- ac-commit-surface-split: `code`（`ios/PurePace/**`、`ios/PurePaceTests/**`、`ios/PurePaceUITests/**`、`scripts/**`、`project.yml` 必要项）与 `fold`（`docs/privacy/**`、`docs/verification-matrix.md`）与 `prd`（`.munk/**`）各自独立 commit；`VERSION`、`android/**`、bundle id 零 diff。

## 非目标

- 不做账号、云同步、第三方 SDK、遥测（含同意行为埋点）；不把政策发布到外网；不建 `docs/human-gate-distribution.md`（PRD 引用的该文件当前仓库不存在，本项不创建，悬空引用留待另开写项）。
- 不改 `VERSION`、不打 tag、不建 GitHub Release、不改 bundle id、不提交 App 审核、不改分发状态；不发表「已发布 / 已分发」口径。
- 不改既有 UI 范式（三 Tab、跑步页四层版式、设置页分组形态）、不改 18 色键 / 字号档 / 间距刻度，不新增布局范式。
- 不做 Android 对等实现，不动 `android/**`、`shared/**`。
- 不新增门禁腿或调整 `.munk/code-gates.json` 阈值、`scripts/test-ios.sh` 的 600s 分段与用例强度。
- 真机项（定位授权、锁屏、音频实听）仍按既有口径 `pending: 待人现场`，agent 只跑 L1 单测与模拟器 UI 腿。

## 实现约束

- 政策正文唯一真源在 `docs/privacy/`，bundle 副本必须由 `scripts/sync-privacy-policy.sh` 生成；禁止手改副本，漂移由 `check-privacy-policy.sh` 的 sha256 比对判红。
- 正文渲染按 Markdown 二级标题切分为章节块（标题 + 正文），样式只取 `DesignTokens`（`Typography` / `Spacing` / `Colors` / `Radius` / `Stroke`），复用 `SettingsView` 的 section 头 + surface 行容器；正文不在 Swift 里重复写一遍。
- 同意态存储形态对齐 `AnnouncementSettingsStore`：`static let` 单键 + 可注入 `UserDefaults` + `@Published` 回读；键名只在类型内出现一次。
- 门控落在 `RunInteractionPlan`（`startEnabled` / `Notice.consentRequired`）与 `RunView` 主操作分支：保留 `run.start` identifier 与既有 `L10n.runActionStart` / `L10n.runStartLabel` 不改名，只置 disabled 并附原因；`RunSessionViewModel.state` 在未同意态不得离开 ready。
- identifier 前缀限制：`check-ios-shell.sh` 的 `raw_identifier_occurrences()` 只识别 `run|runDetail|history|tab|settings` 前缀，本项新增项全部沿用 `settings.` / `run.` 前缀，未扩正则；`identifier_has_readable_label()` 要求标识出现处 ±4 行内有 `accessibilityLabel(Text(L10n.X))` 或 `label: L10n.X`。
- UI 腿不被同意门打断：DEBUG-only 启动参数与 `-uiTestResetArchive` 同口径；截图腿必须预置已同意，否则 `docs/screenshots` 与设计稿比对整体失真；新增套件若出现必须进 `scripts/test-ios.sh` 的 `ui_call` 或写 `scripts/ios-ui-local-only-suites.txt`（本项并入 `RunFlowUITests`）。
- 测试稳定性（AGENTS 硬约束）：禁止 `sleep` / 墙钟断言，tap 前后用状态判据（`exists && isHittable`、页面根元素出现），允许按状态重试 ≤2 次；单次 `xcodebuild` ≤600s 不变。
- 矩阵结构守护：`DocsVerificationMatrixTests` 断言接缝行数、表头逐字、6 列非空、无 `pending` / `缺口` 标记；新增行必须同 commit 更新 `expectedSeamCount` 与 seams 数组并写归属 id。
- 本项为显式规格直通（`needPm` / `needDesign` / `needArchitect` / `needChangePackReview` 全 false），执行 `Intake → Coding → code_gates → Delivery`。

## 最近交付证明

- workItemId: wi_intake_4fbbc7fe48870717（2026-11-15，pass）；22 门全绿（attempt 002，含 `build-ios` / `test-ios` UI 四段 / `test-ios-core` / `test` / `check-shared`）。
- 交付：政策真源 + 生成式 bundle 副本 + `check-privacy-policy.sh`（条目/关键词/虚假声明/字节一致/沙箱删条目反例）并入 `check-baseline.sh`；`TrajectoryConsentStore`（单键 `privacy.trajectoryConsent.v1`）、`PrivacyConsentGateView`（fullScreenCover 独立同意屏）、`PrivacyPolicyDocument` + `PrivacyPolicyView`（应用内全文，设置页「关于」组）、`RunInteractionPlan.startEnabled` / `.consentRequired` 与 `RunView` 禁用 + 原因行、`-uiTestConsentGranted` / `-uiTestResetConsent` 两参；`RunFlowUITests.testTrajectoryConsentGateThreeStates` 覆盖三态，`RunInteractionPlanTests` 4 例覆盖门控正反；`expectedSeamCount` 23 → 25。
- 断言与自检：identifier 33 项冻结集不变、新增 7 项（`run.consentRequired`、`settings.consentGate/consentAgree/consentDecline/privacyPolicy/consentRevoke/privacyPolicyBody`）计入计数下限，`--self-test` 计数 42 → 49 与用例数 6 → 7 同步；`Localizable.xcstrings` 新增文案全经 `L10n`，新视图零裸中文由 `check-ios-shell.sh` 扫描。
- 偏离与边界：PRD 引用的 `docs/human-gate-distribution.md` 未创建（悬空引用已记录）；真机项沿用 `pending: 待人现场`；未做同意行为埋点与云侧校验（非目标）。
