# iOS 轨迹数据单独同意门 + 隐私政策正文真源

## 范围

分发前补齐「轨迹（行踪轨迹类敏感个人信息）」的**单独同意**与**政策正文**，本项只做 iOS 侧与应用内政策正文真源；Android 对等实现由并行的另一写项负责（本项不碰 `android/**`）。

现状（已核实）：仓库只有 `docs/release/*` 与 `docs/device-manual-acceptance.md`；`ios/PurePace` 无同意门、无政策页；启动直落 `ContentView` 的 Run/History/Settings 三 Tab，`run.start` 无条件可点。政策正文目录 `docs/privacy/` 尚不存在。

本项交付四块：

1. **政策正文唯一真源**：`docs/privacy/privacy-policy-zh-Hans.md`，覆盖采集项 / 用途 / 权限清单 / 存储与保留 / 共享 / 删除 / 撤回同意 / 未成年人 / 联系方式 / 生效日期。
2. **iOS 单独同意门**：首次启动独立同意屏（不是长文里的一行勾选）、同意态单键持久化、未同意态记录入口禁用并给原因、设置页「关于」入口可读政策全文并撤回同意。
3. **文案与令牌纪律**：新增用户可见文案 100% 走 String Catalog；新 identifier 只增不改；只用现有 `DesignTokens`（18 色键、6 字号档、既有间距/圆角/描边不变）。
4. **断言 + 反例同 commit**：单测 + UI 用例覆盖「未同意 → 同意 → 撤回」三态，政策关键词断言配「删条目必红」反例，`scripts/check-ios-shell.sh --self-test` 全绿且 identifier 计数同步，`docs/verification-matrix.md` 回填本项接缝行。

## 验收

- ac-policy-single-source: `docs/privacy/privacy-policy-zh-Hans.md` 存在且是应用内政策正文的唯一真源；App 内渲染文本与该文件字节一致（bundle 副本由同步脚本生成，sha256 与 docs 文件不等即判红），仓库内不存在第二份可独立漂移的政策正文。
- ac-policy-covers-required-items: 正文含且仅含一类「采集项 / 用途 / 权限清单 / 存储与保留 / 共享 / 删除 / 撤回同意方式 / 未成年人 / 联系方式 / 生效日期」条目，且逐条命中关键词：采集项含「定位坐标」「时间戳」「距离」「配速」「分段」与「账号」「通讯录」「广告标识」的**不涉及**表述；用途含「本机」「导出」「GPX」「TCX」「分享」；权限含「使用期间」「后台」「通知」「音频播放」「语音播报」；存储含「仅本机」「沙盒」「无账号」「无云同步」「不上传服务器」；共享含「用户主动导出」「接收方」；删除含「应用内删除」「卸载」；撤回含「撤回同意」。
- ac-policy-keyword-red-proof: 政策断言脚本自带沙箱反例：从正文删除任一必需条目（至少覆盖「撤回同意」「不出本机」「敏感个人信息」三个关键词所在条目）必须判红，未改动副本必须先判绿；反例不自证（断言读正文、反例改副本后重跑同一断言）。
- ac-policy-permission-truthful: 权限条目与工程事实一致——`ios/project.yml` 仅声明 `NSLocationWhenInUse` / `NSLocationAlwaysAndWhenInUse` 与 `UIBackgroundModes: location, audio`，无通知/麦克风请求，故正文中「通知」与「音频播放/语音播报」条目必须如实写成「未请求 / 无需授权（无麦克风录音）」类否定表述；正文出现「已请求通知权限」「读取通讯录」「使用广告标识」类肯定采集声明即判红。
- ac-consent-screen-first-launch: 无同意记录的首次启动展示独立同意屏：标题「轨迹与位置数据授权」，正文至少含「敏感个人信息」「只存在本机」「可以拒绝」「可随时撤回」四句语义，主操作 accent 填充「同意并继续」、次操作「不同意」；同意屏不与记录页同屏堆叠（独立呈现，非长文内勾选）。
- ac-consent-decline-blocks-record: 未同意（从未同意 / 点了「不同意」）态下 `run.start` 不可用（XCUITest `isEnabled == false`），且页面出现说明原因的原因文案；点按不会进入记录态（state 仍为 ready 且无倒计时）。
- ac-consent-persist-single-key: 同意态只落在单一 storage 键（一个 `UserDefaults` key，类型外不散落字面量）；点「同意并继续」后同进程与冷启动重进均不再弹同意屏且 `run.start` 可用；点「不同意」不写同意，冷启动仍为未同意态且不可开始。单测断言该键唯一且读写往返一致。
- ac-consent-revoke-restores-gate: 设置页「关于」入口可打开政策全文（应用内渲染同一真源文本；外链不得是唯一路径），并可撤回同意；撤回后回到未同意态（键值置为未同意）、`run.start` 再次禁用、重进可再次看到同意屏。
- ac-copy-and-identifier-discipline: 新增视图零裸字面量（含中文），所有新增用户可见文案经 `L10n` 键落 `Resources/Localizable.xcstrings`；`scripts/check-ios-shell.sh` 的 33 项冻结 identifier 一个不改，新增 identifier 全局唯一且带中文可读 `accessibilityLabel`（语义与可见文字一致）；`DesignTokens.Colors.palette` 仍 18 键、`Typography.sizes` 仍 6 档，同意屏/政策页无字面色值、字号、间距、圆角。
- ac-consent-assertions-red-proof: 单测/UI 用例覆盖「未同意 → 同意屏存在且开始按钮 disabled」「同意后 → 进入 ready 且可开始」「撤回后 → 回到未同意态且不可开始」三条转换，且每条至少一处反例（把门拆掉/把键写错/把撤回做成空操作时必须判红）；`bash scripts/check-ios-shell.sh --self-test` 全绿，identifier 计数下限随新增项同步提高（≥ 冻结 33 + 既有必需 3 + 本项新增）。
- ac-verification-matrix-updated: `docs/verification-matrix.md` 新增本项接缝行（建议两条：政策正文真源与关键词断言、同意门三态），每行含「接缝 / 现状（本项实测口径）/ 断言名 / 反例 / 证据路径 / 归属 `wi_intake_4fbbc7fe48870717`」；`ios/RunCore/Tests/PurePaceRunCoreTests/DocsVerificationMatrixTests.swift` 的 `expectedSeamCount`（现 23）与 seams 清单同 commit 更新，`swift test --package-path ios/RunCore` 绿。
- ac-gates-green: `bash scripts/check-baseline.sh` 退出 0；`bash scripts/test-ios.sh` 全绿（含 UI 腿四段）；同 commit CI `ios.yml` 全绿（权威腿）。
- ac-commit-surface-split: 提交按面拆分且无混面——`code`（`ios/PurePace/**`、`ios/PurePaceTests/**`、`ios/PurePaceUITests/**`、`scripts/**`、必要 `project.yml`）与 `fold`（`docs/privacy/**`、`docs/verification-matrix.md`）与 `prd`（`.munk/**`）各自独立 commit；`VERSION`、`android/**`、bundle id 零 diff。

## 非目标

- 不做账号、云同步、第三方 SDK、遥测（含同意行为埋点）；不把政策发布到外网（`munk.sh` 由人发布，见 `docs/human-gate-distribution.md`）。
- 不改 `VERSION`、不打 tag、不建 GitHub Release、不改 bundle id、不提交 App 审核、不改分发状态。
- 不改既有 UI 范式（三 Tab 结构、跑步页四层版式、设置页分组形态）、不改 18 色键/字号档/间距刻度，不新增布局范式，不重做历史页与详情页。
- 不做 Android 对等实现（并行写项负责），不动 `android/**`、`shared/**`。
- 不新增门禁腿或调整 `.munk/code-gates.json` 阈值、`scripts/test-ios.sh` 的 600s 分段与用例强度。
- 不发表任何「已发布 / 已分发」口径；不修改 `docs/release/**` 与 `README.md` 的版本/状态段。

## 实现约束

已核实的事实锚点（非正式技术方案，Coding 直接按此落地，不需要重扫仓库）：

- **政策真源与同步**：真源 `docs/privacy/privacy-policy-zh-Hans.md`（新建目录）。App 侧渲染需要 bundle 内文本，采用与 `scripts/sync-ios-version.sh` 同口径的生成方式：新增同步脚本把 docs 文件逐字节复制到 `ios/PurePace/Resources/`（不要手抄第二份正文），并由断言比对两份 sha256/字节；`ios/project.yml` 的 `sources: - path: PurePace` 会带上该资源，若 xcodegen 未纳入需在 spec 显式声明。单测可从 bundle 取文本、经既有 `repoRoot()` 惯例（见 `DocsVerificationMatrixTests`）读 docs 原文做逐字节比对。
- **政策正文渲染**：按 Markdown 二级标题切分渲染为章节块（标题 + 正文），全部样式取 `DesignTokens`（`Typography`/`Spacing`/`Colors`/`Radius`/`Stroke`），复用 `SettingsView` 的 section 头 + surface 行容器形态，不引入新布局范式；正文内容不在 Swift 里重复写一遍。
- **同意态存储**：新建 `ios/PurePace/Privacy/` 下 store，形态对齐 `ios/PurePace/Settings/AnnouncementSettingsStore.swift`（`static let` 单一键、可注入 `UserDefaults`、`@Published` 回读），建议键名 `privacy.trajectoryConsent.v1`；键名只在类型内出现一次。
- **挂载点与门控**：`ios/PurePace/ContentView.swift` / `PurePaceApp.swift` 是唯一根；首次启动未同意时以全屏覆盖呈现同意屏（`不同意` 关闭后落到跑步页但记录被禁用）。记录门控落在 `RunInteractionPlan`（`ios/PurePace/Run/RunInteractionPlan.swift`）与 `RunView` 主操作分支：必须保留 `run.start` identifier 与既有 `L10n.runActionStart` / `L10n.runStartLabel` 不改名，只把该控件置 disabled 并附原因文案（新增 L10n 键）；`RunSessionViewModel.state` 在未同意态不得离开 ready。
- **设置页「关于」入口**：`ios/PurePace/Settings/SettingsView.swift` 现有单 section 形态扩展一个分组行（政策全文 + 撤回同意），沿用 surface 行 + hairline + `Radius.card`；identifier 建议用 `settings.` 前缀（`settings.privacyPolicy`、`settings.consentRevoke`、`settings.consentAgree`、`settings.consentDecline` 等），因为 `scripts/check-ios-shell.sh` 的 `raw_identifier_occurrences()` 只识别 `run|runDetail|history|tab|settings` 前缀；若坚持新前缀，必须同 commit 扩正则并同步自检计数，否则新 identifier 会静默逃出计数守卫。
- **可读 label 硬约束**：`identifier_has_readable_label()` 要求标识出现处 ±4 行内有 `accessibilityLabel(Text(L10n.X))` 或 `label: L10n.X`；新 identifier 必须满足，且中文语义与可见文字一致（例：可见「同意并继续」→ label 亦为「同意并继续」）。
- **UI 腿不被同意门打断（关键风险）**：现有 13 条 UI 用例（`RunFlowUITests` 6 / evidence 7）与截图取证套件都假设启动即 ready；同意门会让它们全部落到同意屏。必须在 `ios/PurePace/Run/RunLaunchArguments.swift` 增加 DEBUG-only 启动参数（如 `-uiTestConsentGranted` 预置已同意、`-uiTestResetConsent` 清空该键，与 `-uiTestResetArchive` 同口径），并同步既有 UI 辅助构造与 `scripts/test-ios.sh` 四段 `ui_call` 的调用点；截图腿必须预置已同意，否则 `docs/screenshots` 与设计稿比对会整体失真。
- **新增 UI 套件必须入权威腿**：`scripts/check-ios-scripts.sh` 的 `ac-ui-suite-coverage-guard` 要求 `ios/PurePaceUITests` 下每个建 `XCTestCase` 的套件都进 `scripts/test-ios.sh` 的 `ui_call -only-testing` 目标（否则写 `scripts/ios-ui-local-only-suites.txt` 且带非空理由）；优先把三态用例并入既有 `RunFlowUITests` 以免再加一段 xcodebuild 预算；若新开套件，必须同时更新 `ui_call`。
- **测试稳定性**（AGENTS 硬约束）：禁止 `sleep`/墙钟断言，tap 前后用状态判据（元素 `exists && isHittable`、页面根元素出现），允许按状态重试 ≤2 次；单次 `xcodebuild` ≤600s 不变。
- **断言脚本落点**：政策关键词 + 删条目反例 + bundle 漂移比对建议放新脚本（如 `scripts/check-privacy-policy.sh`，`set -euo pipefail` + `--help` + `mktemp` 沙箱反例），并由 `scripts/check-baseline.sh`（即 `.munk/code-gates.json` 的 `test` 门）调用，保证 CI 真跑；iOS 侧 identifier/文案纪律继续放 `scripts/check-ios-shell.sh`（自检里加正负反例）。注意 Android 并行写项可能新建同名脚本，命名上尽量少跨面（政策脚本可共享，iOS 专属断言留 `check-ios-shell.sh`）。
- **localization 扫描范围**：`validate_localization()` 目前只扫 `ContentView.swift`、`Run/RunView.swift`、`History/HistoryView.swift`、`History/RunDetailView.swift`、`Track/TrackMapView.swift`、`Settings/SettingsView.swift` 六个文件的裸英文；新增同意屏/政策页视图必须加入该扫描列表（建议同时把裸中文字面量也纳入本项新视图的判据），否则「100% 走 String Catalog」只是口头承诺。
- **矩阵结构守护**：`DocsVerificationMatrixTests` 现断言恰 23 行接缝、表头逐字一致、6 列非空、无 `pending`/`缺口` 标记；新增行必须同步 `expectedSeamCount`（23 + N）与 `seams` 数组，并把本项 id 写进对应行归属列。
- **现有事实与缺口**：目标里引用的 `docs/human-gate-distribution.md` 当前仓库不存在（`docs/` 只有 `design`、`design-draft-v12`、`device-manual-acceptance.md`、`evidence`、`plans`、`release`、`screenshots`、`verification-matrix.md`）；本项不创建该文件（不属 iOS 侧与政策真源范围），交付回执需记录该引用悬空，供人决定是否另开写项。
- **提交与证据**：`code` / `fold` / `prd` 三面分开提交（`.munk/**` 记录独立）；回执须给门禁命令的原文输出（红绿逐条），未跑齐的腿写「未跑齐」+ 截断原因（真机项按既有口径记 `pending: 待人现场`）。
- 路由：本项为显式规格直通，`needPm` / `needDesign` / `needArchitect` / `needChangePackReview` 全为 false，按 `Intake → Coding → code_gates → Delivery` 执行。
