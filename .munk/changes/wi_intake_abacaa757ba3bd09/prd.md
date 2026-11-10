# Release 候选包可验证性：launch-arg 门控的确定性定位源（默认关）+ 新候选包

## 范围

**目标**：让「跨公里 TTS 不打断音乐 + duck 恢复」这一项在 **Release 候选包**上可取到机器证据。
当前 Release 包上 `-uiTestLocation` 被 `#if DEBUG` 关掉，设备静止也无法走出 1 km，导致 (b) 只能落「未观测」。
本项只补「Release 可用的显式 launch-arg 确定性定位源」及其断言、文档、候选包，不改变真实 CoreLocation 生产路径。

**A. 确定性源（Release 可用，默认关）**
- 新增 `ios/PurePace/Location/ReleaseDeterministicLocationSource.swift`：实现既有 `RunLocationProviding` 契约，**不得**包在 `#if DEBUG` 内，不 import CoreLocation、不读写磁盘、不做播报。
- 新增 `ios/PurePace/Location/RunLocationSourceSelection.swift`：纯参数选择逻辑（Foundation + PurePaceRunCore，无 IO）。仅当参数中显式出现 `-releaseDeterministicLocation <scenario>` 时返回确定性源；否则返回真实 `RunLocationSource()`，`telemetryDebugEnabled=false`。
- 场景 `km-crossing`：固定基准坐标，经度不变，纬度按每 tick 20 m 推进，tick 间隔 1.0 s；从「跑步开始后的首个位置锚点」起约 50 个样本跨过 1 km，保证 60–90 s 跑动内恰好跨一次公里边界。
- flag 缺值、未知 scenario、或仅出现 flag 名而无值：一律 fail-closed 回真实 `RunLocationSource()`，确定性源构造次数为 0。
- `ContentView` 现有 `#if DEBUG` + `-uiTestLocation` 分支**保持原样**（Debug UI 用例继续走 `RunTestLocationSource`）；非该分支统一经 `RunLocationSourceSelection`（Debug/Release 均可用），默认落真实源。

**B. 代码层断言（缺一不算完成）**
- 默认路径单测：无 flag 时选择器返回注入的真实源，确定性工厂调用次数 0、未构造/未 start 确定性源、无任何样本注入（注入桩计数为 0）。
- flag 路径单测：注入时钟驱动，样本按 1.0 s 严格递增时序产生；把样本喂给既有 `RunSessionOrchestrator`，按 RunCore 既有 `RunMetricsEngine.splitDistanceMeters = 1000` 契约恰好触发 1 条 `AnnouncementCommand`（`splitIndex == 1`、`trigger == .kilometerCompleted`），之前不触发。
- 能力诚实单测：确定性源 `sampleSource == .simulated`、`authorization == .authorizedWhenInUse`、`allowsBackgroundLocationUpdates == false`、`pausesLocationUpdatesAutomatically == false`。

**C. 结构/静态门**
- 在既有 `scripts/check-ios-shell.sh` 内新增 release-deterministic 断言块（不新增 code-gates 门，门数保持 22）：
  - 确定性源存在、实现 `RunLocationProviding`、不含 `#if DEBUG`、不 import CoreLocation/AVFoundation；
  - 选择器默认分支构造 `RunLocationSource`（或经默认闭包），flag 字符串不出现在 `RunLocationSource.swift`；
  - `ios/PurePaceUITests/**` 不出现 `-releaseDeterministicLocation`（现有 Debug 用例语义不变）；
  - 普通用户路径无注入入口：除 `ContentView` init 与选择器外，任何 UI/Settings/Run 视图不得引用确定性源或 flag；
  - 无 flag 时无额外权限/后台行为：`ios/project.yml` 仍只有两条既有 `NS*UsageDescription` 键，`UIBackgroundModes` 仍为 `location` + `audio`，`ios/PurePace/Info.plist` 零 diff；
  - 至少 1 条负向自检（把确定性源临时包进 `#if DEBUG` 或在默认分支改回确定性源，断言必须失败）。

**D. 文档**
- `docs/device-flow-usage.md`：新增「Release 确定性源（仅设备验证场）」小节，写清 flag 语法、`km-crossing` 场景、默认关、Release 候选包用法、样本标记 `simulated`、不计入真实 CoreLocation 判据、正常用户不可达。
- `docs/device-assertion-matrix.md`：在「Release 候选包『公里播报 + 音乐 duck』结论行」表内新增一行「Release 确定性源门控」，并只修正该表现有结论行的证据档位/原因（真实 CoreLocation 仍只能人耳），不重写其他表。

**E. 新候选包**
- 代码/测试/文档形成本地提交且工作树干净后，从该 HEAD 出 Release 候选（xcodegen 生成、Release 配置、dev 签名命令行走 CLI），zip 落仓外 `<productDir>/artifacts/candidates/`，实算双 sha，读 `.app/Info.plist` 本体，写 `Release-candidate-<shortsha>.txt`。

## 验收

- ac-default-selects-real: 无 `-releaseDeterministicLocation` 时，`RunLocationSourceSelection` 返回注入的真实源实例；返回值的 `source === makeReal()`、`telemetryDebugEnabled == false`。
- ac-default-no-injection: 无 flag 时确定性源工厂调用次数为 0，确定性源未构造、未 `start()`、注入桩收到 0 个样本；该断言在单测中可直接读计数。
- ac-flag-selects-release-source: 参数含 `-releaseDeterministicLocation km-crossing` 时返回 `ReleaseDeterministicLocationSource`，且 `sampleSource == .simulated`；该选择在 Debug 与 Release 配置下均编译、均可用（判断逻辑不依赖 `#if DEBUG`）。
- ac-flag-sample-timing: 注入递增时钟后，样本时间戳严格递增且相邻差 == 1.0 s；纬度单调推进，经度固定；单测不出现 `sleep`/`Thread.sleep`。
- ac-flag-km-boundary: 将 `km-crossing` 产生的样本按序喂入既有 `RunSessionOrchestrator`（先 `start(at:)`），在累计距离跨过 1000 m 时恰好产生 1 条 `AnnouncementCommand`，`splitIndex == 1`、`trigger == .kilometerCompleted`；跨过前为 0 条，跨过后 `metrics.completedKilometers == 1`。
- ac-flag-fail-closed: flag 无值、值以 `-` 开头、或 scenario 未知（如 `-releaseDeterministicLocation bogus`）时，确定性源工厂调用次数 0，返回真实源。
- ac-flag-honest-capabilities: `ReleaseDeterministicLocationSource` 的 `allowsBackgroundLocationUpdates == false`、`pausesLocationUpdatesAutomatically == false`、`authorization == .authorizedWhenInUse`；源码不 import CoreLocation，也不调用任何授权/`startUpdatingLocation` API。
- ac-production-source-untouched: `git diff <base> -- ios/PurePace/Location/RunLocationSource.swift ios/PurePace/Run/RunSessionViewModel.swift ios/RunCore/Sources ios/PurePace/Audio ios/PurePace/History ios/PurePace/Settings ios/PurePace/Info.plist ios/project.yml` 为空；采样阈值、状态机、播报调度零改动。
- ac-ui-tests-untouched: `git diff -- ios/PurePaceUITests` 为空；现有 Debug 用例仍以 `-uiTestLocation`（及 `-uiTestLocationFast`）启动；`ios/PurePaceUITests/**` 中 `-releaseDeterministicLocation` 零命中。
- ac-static-gate-default-path: `scripts/check-ios-shell.sh` 的 release-deterministic 块在默认分支被改为直接注入确定性源、或选择器默认分支不再构造真实源时退出非 0；在正常仓库上 `bash scripts/check-ios-shell.sh` 退出 0。
- ac-static-gate-permissions-unchanged: 该静态块断言 `ios/project.yml` 的 `NS*UsageDescription` 键恰为既有两条（WhenInUse / AlwaysAndWhenInUse），`UIBackgroundModes` 数组含 `location` 与 `audio` 且无第三项；`ios/PurePace/Info.plist` 零 diff。
- ac-static-gate-negative-selftest: 新静态块至少含 1 条负向自检：对临时副本去掉/加上被禁止的结构后必须报错；自检不恒真，且不影响正常仓库通过。
- ac-gate-topology-unchanged: `.munk/code-gates.json` 仍为 22 个门，id/command 语义不变；`scripts/check-ios-scripts.sh` 与 `scripts/check-ios-release.sh` 的门数断言不改；不新增 timeout、不出现 `continue-on-error`、不删腿；`git diff -- .github/workflows` 为空。
- ac-docs-flag-documented: `docs/device-flow-usage.md` 含 `-releaseDeterministicLocation`、`km-crossing`、默认关、仅设备验证场、`simulated`、不计入真实 CoreLocation 判据的明确表述；不写「真机已验证」。
- ac-matrix-row-added: `docs/device-assertion-matrix.md` 的 Release 公里播报结论表新增一行「Release 确定性源门控」，同时含「默认关」「仅设备验证场」「不计入真实 CoreLocation 判据」三要素。
- ac-matrix-conclusion-honest: 该表现有结论行不再声称「Release 上取不到机器证据/只能人耳」为绝对结论；改为「真实 CoreLocation 只能人耳；Release 机器证据来自显式 launch-arg 确定性源（非真实移动）」，且不出现「候选包已验证真实定位」类措辞。
- ac-candidate-build-provenance: 候选包从本次 worktree 的已提交 HEAD 构建（构建时 `git status --porcelain` 为空）；`ios/` 内 `xcodegen generate --spec project.yml` 生成工程（`project.pbxproj` 由生成器更新，无手写），`xcodebuild -configuration Release -destination 'generic/platform=iOS'` 且命令行传 `CODE_SIGNING_ALLOWED=YES CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=3X4J53U6RY -allowProvisioningUpdates`；派生数据在 `.build/`（不进 git）；`.app` 内无 `PurePace.debug.dylib`。
- ac-candidate-hashes-real: zip 与 zip 内 `.app/PurePace` 的 sha256/字节数为实算值（`shasum -a 256`、`stat -f%z`）；`zipSha256`、`execSha256` 均为 64 位小写十六进制，且 `zipSha256` 不等于历史包 `81b9f2de…` 与 `7258d2e3…`；记录不含 `TBD` / `<sha256>` / `PLACEHOLDER`。
- ac-candidate-plist-readback: 从解压后的 `.app/Info.plist` 本体读回并写入记录：`CFBundleIdentifier=sh.munk.purepace`（精确相等）、`UIBackgroundModes` 实际数组同时含 `location` 与 `audio`、`CFBundleShortVersionString=0.1.0`、`CFBundleVersion=1`、`MinimumOSVersion=17.0`；记录文本可 grep 出 `CFBundleIdentifier=sh.munk.purepace` 与含 `location`、`audio` 的数组 dump。
- ac-candidate-record-format: `<productDir>/artifacts/candidates/Release-candidate-<shortsha>.txt` 存在，字段顺序沿用既有 `Release-candidate-667e1bc.txt`（builtAt / commit / buildConfig / signingIdentity / provisioningProfile / scheme+target / zipPath / zipSha256 / zipBytes / execName / execSha256 / execBytes / infoPlist / codesign / 验收键 / iosCI / note）；`zipPath` 为绝对路径；`signingIdentity` 含 `Apple Development: Tao Zhu (H47755VBGF)` 与 `Team 3X4J53U6RY`；`commit` 与构建时 `git rev-parse HEAD` 完全一致（完整 sha）。
- ac-candidate-no-side-effects: 出包过程不 `git push`、不打 tag、不建 GitHub Release、不做 TestFlight/ASC 上传；`git tag --points-at HEAD` 无新增；`ios/project.yml`、`.github/workflows/**` 零 diff；记录中真机侧结论仍为 `pending: 待人现场`。
- ac-candidate-ci-honest: 记录 `iosCI` 只能填真实取得的同 commit `ios.yml` run id，或明确写 `pending: 待同 commit ios.yml run 判定`；不得编造 run id，不得把未观测的真机项写成 PASS。
- ac-local-gates-green: 本地 `code_gates` 全部 22 门真实执行退出 0（lint* / build-ios-core / build-ios-run-core / build-ios / test-ios-core / test-ios-run-core / test-ios / build-android / test-android / test / check-*），无 skip、无 continue-on-error、无降断言；本地 UI E2E 不作阻断门。
- ac-scope-contained: `git diff --name-only` 与 `git status --porcelain` 的并集只含：`ios/PurePace/ContentView.swift`、`ios/PurePace/Location/ReleaseDeterministicLocationSource.swift`、`ios/PurePace/Location/RunLocationSourceSelection.swift`、`ios/PurePaceTests/ReleaseDeterministicLocationSourceTests.swift`、`ios/PurePace.xcodeproj/project.pbxproj`、`scripts/check-ios-shell.sh`、`docs/device-flow-usage.md`、`docs/device-assertion-matrix.md`、`.munk/changes/wi_intake_abacaa757ba3bd09/prd.md`；`android/**`、`shared/**`、`ios/RunCore/**`、`ios/Core/**`、`.github/workflows/**`、`.munk/code-gates.json` 零 diff。

## 非目标

- 不驱动锁屏/解锁、不排人、不约窗、不在 run 内提 assist；真机证据仍由后续设备窗口产出。
- 不修改 AudioSession、持久化、GPX 契约语义；不改播报调度、采样阈值、状态机。
- 不把 `-uiTestLocation` 开进 Release；不改现有 Debug UI 用例语义。
- 不修改 `ios/project.yml` 的签名/包标识/后台能力声明，不手写 `project.pbxproj`。
- 不改 `.github/workflows/**` 的触发或判定语义；不新增本地阻断门或长耗时 UI 门腿。
- 不修改 Android / shared 业务代码；不引入第三方运行时依赖。
- 不 push tag、不建 GitHub Release、不做 TestFlight / ASC 上传、不动远端仓库设置。

## 实现约束

**基线事实（Intake 已核）**
- 起点 main tip 为 `d6f46d9`（本 worktree 分支 `munk/wi_intake_abacaa757ba3bd09`）。
- 现有 Debug 确定性源在 `ios/PurePace/Location/RunTestLocationSource.swift:4-79`，整体包在 `#if DEBUG`。
- 现有点位选择在 `ios/PurePace/ContentView.swift:26-43`；`RunLocationProviding` 契约在 `ios/PurePace/Location/RunLocationSource.swift:58-70`。
- 公里分段契约在 `ios/RunCore/Sources/PurePaceRunCore/RunMetricsEngine.swift:9`（1000 m）；播报契约回归样例见 `ios/RunCore/Tests/PurePaceRunCoreTests/RunSessionOrchestratorTests.swift:173-185`。
- 既有静态门 `ac-ui-test-location-source` 在 `scripts/check-ios-shell.sh:753-906`，要求 `RunTestLocationSource` 只出现在 `#if DEBUG` 区域；本项新源必须独立文件、独立类型，避免触碰该断言。

**文件与接线**
- 新增 `ReleaseDeterministicLocationSource.swift` 与 `RunLocationSourceSelection.swift`；`ios/project.yml` 的 `sources: - path: PurePace` 会自动纳入，需运行 `xcodegen generate --spec project.yml` 并提交生成的 `ios/PurePace.xcodeproj/project.pbxproj`；禁止手改 pbxproj。
- `ContentView` 的 `#if DEBUG` + `-uiTestLocation` 分支逐字保留；`#else` 分支改为经选择器取源。选择器默认闭包必须构造 `RunLocationSource()`，flag 闭包构造 `ReleaseDeterministicLocationSource(scenario:)`。
- 选择器为纯函数式 seam：`@MainActor static func select(arguments:makeReal:makeDeterministic:)`，便于单测注入两个工厂并断言调用次数；不得在 seam 内读 `CommandLine.arguments` 以外的全局状态。
- `ReleaseDeterministicLocationSource` 必须提供可测的时钟/生成器 seam（注入 `now: () -> Date` 或等价的纯 tick→sample 生成器），使单测无需 `sleep` 即可验证时序与公里边界；`Timer` 只允许出现在本文件（`Location/`），不得进 `Run/`。
- 未知/缺值 scenario 一律回真实源，不抛异常、不弹 UI、不写日志到用户可见位置。

**门禁**
- 结构断言并入既有 `scripts/check-ios-shell.sh`，不新增 `.munk/code-gates.json` 门；门数保持 22，`scripts/check-ios-scripts.sh`、`scripts/check-ios-release.sh` 的门数断言不动。
- 禁止 `continue-on-error`、禁止提高/新增 timeout、禁止删腿；`check-ios-shell.sh` 保持 `--help` / `--self-test` / 退出码 0/1/2 契约。
- 本地快门至少跑：`bash -n scripts/check-ios-shell.sh`、`bash scripts/check-ios-shell.sh`、`bash scripts/check-ios-release.sh`、`bash scripts/check-ios-scripts.sh`、`bash scripts/check-baseline.sh`、`swift test --package-path ios/Core`、`swift test --package-path ios/RunCore`、`bash scripts/test-ios.sh --unit-only`、`bash scripts/build-ios.sh`。全 22 门以 Host `code_gates` 结果为准。

**候选包与交付顺序**
- 候选包目录：`/Users/zhutao/Library/Application Support/Munk-AI/munk-auto/products/codebase_19e8ad47434ff059/artifacts/candidates/`（仓外；不复制 zip 进仓库）。
- 出包前先在本次 worktree 形成包含全部代码/测试/文档/pbxproj 的本地提交（不 push、不打 tag），工作树干净；记录 `commit` 为 `git rev-parse HEAD` 完整 sha，文件名用其前 7 位。
- 交付（Delivery）合入 main 后：执行 `git diff --name-only <candidateCommit>..<newMainTip> -- ios shared android`；结果必须为空，并按既有 `equivalence-667e1bc-vs-d6f46d9.txt` 格式写 `equivalence-<candidateShort>-vs-<mainShort>.txt`。若非空（合并冲突解决触及源码），该候选作废，必须从新 main tip 重出候选并重算双 sha；在重出前不得把旧候选写成「新 main tip 候选」。
- 记录里的 `iosCI` 不得编造：有真实同 commit run id 才写；否则写 `pending: 待同 commit ios.yml run 判定`。真机三项保持 `pending: 待人现场`。
- 预算 ≤15M token、≤120 分钟；超时即停手并回执：已落代码、已跑门、未闭合项（不得用降断言换绿）。
