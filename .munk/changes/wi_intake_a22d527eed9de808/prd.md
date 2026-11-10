# 音频门绑 Release 候选包，并收进 device-run 的 audio step

## 范围

把 V1 音频门从「Debug 构建 + `-uiTestLocation`」升级为「最终 Release 候选包 + `-releaseDeterministicLocation`」，并让一条 `scripts/device-run.sh --phase=audio` 一次跑全证据。

1. `scripts/verify-ios-device-flow.sh --phase=audio`
   - audio 分支默认 `Release`（新增 `--configuration Debug|Release`，audio 缺省 `Release`；audit/background 默认值保持现状）。
   - Release 下音频用例必须用 `-releaseDeterministicLocation km-crossing`，不得用 `-uiTestLocation`；默认用户路径与 `ios/PurePace/**` 零改动。
   - 被测 App 必须是候选 zip 里的 `.app`（不是 xcodebuild 自产的同配置 App）；证据落 candidate zip / exec 双 sha256 与证据目录路径。
   - `--phase=audio` 固定跑三遍：`app`（系统 Music + 人已导入的本地曲目）→ `runner`（正例，`isOtherAudioPlaying=true`）→ `none`（负对照，`false`），一次产出全部证据。
   - `app` 遍证据必须落曲目标题 / 时长 / 是否本地文件（含判定依据）。
   - duck 三字段 `duckRevoked` / `sessionDeactivated` / `categoryOptions` 成对取自同一条 `telemetry.announcements[]`（含 km 触发、duck 应用与撤销、播报文本与时间戳）。
2. `scripts/device-run.sh`
   - 新增 `audio` phase，顺序插在 `tcc` 之后、`record` 之前，同步文件头 phase 顺序、`PHASES` / `VALID_PHASES` / `--help` / `--phase=plan` / summary step 顺序 / `run_real_phase`。
   - audio step 只调用 `scripts/verify-ios-device-flow.sh`（run 内禁止手搓 xcodebuild/devicectl/curl 序列），把证据收进 `artifacts/device-run/<candidateKey>/audio/` 并写 step 级证据索引。
   - fail-closed：缺任一必备产物（配置、三遍证据、曲目元数据、duck 三字段、zip/exec sha256、证据路径）即非 0 退出，日志写缺失清单。
3. `ios/PurePaceUITests/`（只改测试代码）：音频用例按构建配置选择 launch-arg，并把 `launchArguments`、音源元数据、announcements 结构观测落进附件。
4. 同步受影响静态断言与文档口径：`scripts/check-ios-scripts.sh`（9 → 10 step）、`docs/device-flow-usage.md`（audio 口径）、必要的矩阵行。

## 验收

### 构建配置与 launch-arg

- ac-audio-default-release: `scripts/verify-ios-device-flow.sh --phase=audio` 不带 `--configuration` 时，meta / report / 分析 JSON 的 `configuration` 均为 `Release`；`--configuration=Debug|Release` 合法，其余取值退出 2；`--phase=audit` 与 `--phase=background` 的默认配置不变（`Release`）。
- ac-audio-release-launch-args: Release 音频用例实际启动参数含 `-releaseDeterministicLocation`（值为 `km-crossing`）且不含 `-uiTestLocation`；Debug 显式构建时仍用 `-uiTestLocation`；用例把实际 `launchArguments` 写入 `audio-result.json`，分析侧对 Release 缺该参数判 FAIL。
- ac-audio-no-debug-substitute: 显式 `--configuration=Debug` 的 audio 证据在 meta / report 标 `evidenceGrade=debug` 且明确「不可计入 V1 Release 门」；默认路径与 `device-run --phase=audio` 只接受 Release，不存在 Debug 证据顶替。
- ac-audio-candidate-bound: audio 证据记录 `candidatePath`、candidate zip sha256、候选 `.app` exec sha256（均 64 位 hex）与证据目录路径；并记录实际被驱动 App 的 `.app` 路径与 exec sha256，二者必须一致，否则 FAIL（不得只记 zip sha 就宣称候选包已验证）。
- ac-audio-candidate-missing-fail-closed: 无 `--candidate` 且 `artifacts/candidates/PurePace-Release-*.zip` 缺失或多义时，audio 在跑任何用例前非 0 退出并写明原因。

### 三遍音源与元数据

- ac-audio-triple-pass: 一次 `--phase=audio` 产出 `audio-app` / `audio-runner` / `audio-none` 三个独立证据子目录、result bundle、run JSON 与 `music-source.json`；三遍的 `configuration` 同为 `Release`。
- ac-audio-app-track-metadata: `app` 遍从系统 Music（bundle id `com.apple.Music`）读到正在播放的本地曲目，证据含非空 `nowPlayingTitle`、可解析时长（`durationText` 匹配 `\d{1,2}:\d{2}` 或 `durationSeconds > 0`）、`isLocalFile ∈ {true,false,unknown}` 且带 `localFileBasis`，以及原始可及树/截图附件；读不到元数据判 FAIL（不写 `unknown` 空过）。
- ac-audio-runner-positive: `runner` 遍 `announcements[].isOtherAudioPlaying == true`，且 runner 自播可归因证据齐全（asset 名/字节/sha256、`playerStarted=true`、`isPlayingAtStart=true`、`playbackStartedAt < runStartedAt`、`currentTimeAtFinish > 0`）；缺任一项判 FAIL。
- ac-audio-none-negative: `none` 遍 `announcements[].isOtherAudioPlaying == false`（播报前快照时间戳与实际取样时刻成对）；无音源场景只记 `not-applicable`，不得因缺席而判 pass。
- ac-audio-negative-not-green: `audio-other-audio-*` / `duckOthers` 实际 duck / `duckRevoked` / `sessionActivated` / `sessionDeactivated` 在 `none` 或 runner 未真正起播时一律 `status=not-applicable` 并带原因，仍计入分析 JSON 但不计入通过项。

### duck 三字段与播报上下文

- ac-audio-duck-pair: 每个 pass 的 `duckRevoked` / `sessionDeactivated` / `categoryOptions` 取自**同一条** `telemetry.announcements[]` 条目，并同时落该条目的 `splitIndex`、`text`、`startedAt`、`finishedAt`、`sessionActivated`；三字段不得跨条目/跨 pass 拼接。
- ac-audio-km-trigger: `app` 与 `runner` 遍的该条目 `splitIndex == 1` 且 `text` 含「第 1 公里」；Release 确定性源节奏下 `activeDuration` 落在 35–90s 窗口（`km-crossing` 为 20 m/s），证据注明节奏来源。
- ac-audio-duck-record-only: `duckRevoked` / `sessionDeactivated` 只记录实测布尔值 + 时间戳 + `pending-classification: wi_intake_f76b858c0c2376f5`，不写 pass/fail；`categoryOptions` 含 `duckOthers` 可断言；`sessionActivated` 可断言 true（有音源时）。
- ac-audio-announcements-structure: 每个 pass 的 `announcements-*.json` 与 `audio-result.json` 同时落播报条目、duck 应用/撤销上下文与 `music-source.json`，结构观测先于语义结论。

### device-run audio step

- ac-device-run-order: `scripts/device-run.sh` 文件头、`--help`、`PHASES`、`VALID_PHASES`、summary step 顺序一致为 `preflight wda install launch tcc audio record lock collect evidence`；`--phase=audio` 合法，非法 phase 仍退出 2；`--phase=plan` 输出 `step=audio` 与命令/证据模板且两次幂等。
- ac-device-run-audio-single-call: `phase_audio` 只调用 `scripts/verify-ios-device-flow.sh --phase=audio --configuration=Release` 及其参数（candidate/device），不在 run 内重写 xcodebuild/devicectl/curl 音频命令；失败沿用 `begin_step` / `fail_step` / `end_step` 语义。
- ac-device-run-audio-artifacts: 成功后 `artifacts/device-run/<candidateKey>/audio/` 含语音证据入口（analysis/report/announcements/track metadata/candidate sha256）与 `audio-step.json`（证据目录路径 + 必备产物清单）；缺任一必备产物 → 退出非 0 且日志写缺失项。
- ac-device-run-static: `bash scripts/check-ios-scripts.sh` 更新为 10 step 硬断言后退出 0；`scripts/device-run.sh --self-check` 退出 0；`bash -n scripts/device-run.sh scripts/verify-ios-device-flow.sh` 与 `scripts/check-shell-expansion.sh` 通过；门数与 id 不变（22 门）。

### 可运行性与诚实边界

- ac-one-command: 在候选包存在、真机可达、系统 Music 已有本地曲目的前提下，`bash scripts/device-run.sh --phase=audio`（或 `--phase=audio --candidate <zip>`）一条命令跑完 audio 腿并以 0 退出；证据目录同时含 Release 配置、曲目元数据、runner 正例、none 负对照、duck 三字段、候选 zip/exec sha256 与证据路径。
- ac-structural-fail-honest: 若「Release 候选包 + XCUITest runner」结构性不可行（例如 xcodebuild 重新安装自产 App 顶掉候选包且无法通过产品路径替换/xctestrun 绑定），立即停止并写清失败项、已试路径与替代方案（如 WDA 驱动已装候选包），不得用 Debug 或自产 Release 构建证据顶替，不得宣称候选包已验证。
- ac-gates-scope: 只跑受影响门（`lint` / `lint-ios-scripts` / `lint-ios-shell` / `lint-ios-release` / `check-shell-expansion` / `test-ios`（`--unit-only`）+ `bash -n`），不重跑全量模拟器 UI 或真机门；不改 `.munk/code-gates.json`、不新增 CI 阻断腿。
- ac-no-app-source-diff: `git diff --name-only` 不含 `ios/PurePace/**`、`ios/Core/**`、`ios/RunCore/**`、`ios/project.yml`、`ios/PurePace.xcodeproj/project.pbxproj`、`.github/workflows/**`；`AudioSessionAdapter` / `AnnouncementSpeaker` / `RunTelemetry` / `RunSessionViewModel` 零 diff。

## 非目标

- 不修 App 业务源码：AudioSession / 播报 / CoreLocation / 持久化 / GPX 契约冻结；不改默认用户路径。
- 不碰 `ios/project.yml` 与 `ios/PurePace.xcodeproj/project.pbxproj`（P1-1 在飞），不新增 target / 资源声明 / plist 键。
- 不做 Tuist / Swift Testing 迁移；不换 WDA 通道；不把真机音频腿放进 CI 阻断集合（只由脚本驱动）。
- 不重跑全量模拟器 UI / 真机门；不做 Android、不做发布、不打 tag。
- 不替 `wi_intake_f76b858c0c2376f5` 定性 duck 语义：`duckRevoked` / `sessionDeactivated` 不写死 pass/fail。
- 不为了面板好看伪造 `app` 音源：Music 未起播或元数据读不到就 FAIL，不用合成音源冒名顶替。

## 实现约束

### 已知锚点（Intake 已核对 HEAD，Coding 需复核）

- `scripts/verify-ios-device-flow.sh:162`：`audio) test_case=...; build_configuration="Debug"`——本项改为缺省 `Release`，新增 `--configuration` 并同步 usage/退出码 2。
- `scripts/verify-ios-device-flow.sh:374-395` `run_case`、`:338-371` `build_for_testing`：`-configuration "$build_configuration"`；audio 需在 build-for-testing 后把 `Build/Products/Release-iphoneos/PurePace.app` 替换为候选 zip 的 `Payload/*.app`（或在 xctestrun 里把 `UITargetAppPath` 指向候选 App），并记录替换后 exec sha256；两条路任选其一，以「实际驱动 App exec sha == 候选 exec sha」为通过判据。
- `scripts/verify-ios-device-flow.sh:964-1159`：audio 分析目前是「primary + none」两遍且 `activeDuration` 窗口 60–90s、`-uiTestLocation` 文案；本项改为 `app/runner/none` 三遍固定、窗口 35–90s、Release 文案，并新增 configuration / candidate binding / track metadata 检查。
- `scripts/verify-ios-device-flow.sh:601-706` `announce_checks`：已有 duck 三字段结构观测与 `not-applicable` 口径，扩到同一 `announcements[]` 条目成对取值即可；`duckRevoked` / `sessionDeactivated` 保持 `status=recorded` + `pending-classification: wi_intake_f76b858c0c2376f5`。
- `ios/PurePaceUITests/DeviceFlowUITests.swift:156`：`app.launchArguments += ["-uiTestLocation", "-uiTestResetArchive"]`——改为按配置选择：Debug 用 `-uiTestLocation`，Release 用 `["-releaseDeterministicLocation", "km-crossing"]`；`-uiTestResetArchive` 仅 Debug 生效，Release 不依赖归档清空（分析侧按 `phase_started_epoch` 取最新跑次）。
- `ios/PurePace/Location/ReleaseDeterministicLocationSource.swift`：Release 确定性源 20 m/s、50 步跨 1 km，`sampleSource = .simulated`；`-uiTestLocation` 仅 Debug（`ContentView.swift:31-33`）。
- `ios/PurePaceUITests/MusicSource.swift`：策略解析与 runner 播放器在此；`app` 遍的曲目元数据探针建议放同文件（Music App 可及树 + 截图 + 标题/时长解析，`isLocalFile` 三态 + `localFileBasis`），不改 App target。
- `scripts/device-run.sh:3-13`（phase 清单）、`:403-484`（`print_plan`）、`:684`（summary order）、`:1727-1778`（`run_real_phase`）、`:971-1110`（preflight 已算 zip/exec sha 并写 `state_dir/app.path`、`candidate.json`）。
- `scripts/check-ios-scripts.sh:156`（9 step 硬断言）、`:182-184`（help phase 列表）需同步为 10 step；`:15-17` 注释与 `check-ios-scripts.sh` usage 文案一并更新。
- 真机 iPhone 12 Pro Max UDID `00008101-001C701E0A68001E`；Music bundle id `com.apple.Music`；WDA 起法与端点按仓库 AGENTS.md「真机自动化通道：WDA」（`http://127.0.0.1:8100`，`scripts/device-run.sh` 已封装）。

### 口径与边界

- audio 固定三遍（app → runner → none）；`--music-strategy` 只对 `background` 生效，audio 若显式传入冲突值按固定三遍执行并在 meta 记 `musicStrategyIgnored`（不静默）。
- `app` 遍必须证明「外部 App 在播」优先于 `isOtherAudioPlaying` 单布尔；读不到曲目元数据判 FAIL，`isLocalFile` 无依据时允许 `unknown` 但必须写 `localFileBasis`，且不得据此判「本地文件已验证」。
- 负对照语义：`none` 只记 `not-applicable`；`isOtherAudioPlaying != false` 或缺少播报前快照即 FAIL。
- 若候选包与（自产）Release 构建产物结构不兼容（bundle id / executable / 签名 / 架构不一致），在替换前 fail-closed 写清差异，不回退 Debug。
- 预算：≤1 小时、≤8M token；触及预算或结构性阻塞立即停手回执，写清已完成步骤、失败项与替代方案，不延期、不伪绿。
