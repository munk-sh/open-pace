# 清理写项 A：删除 agent 级真机验收基建（代码与门）

## 范围

公司已核清点并批准：停止 agent 级真机验收，删除为该项搭的脚本/用例/证据基建（约 5,549 行脚本与用例、72 个历史证据）。本项只做「代码与门」这一半：

- 收口门断言：`scripts/check-ios-scripts.sh` 去掉 `device-run.sh` / `verify-ios-device-flow.sh` 的 targets、严格模式与 `--help` 覆盖、plan/self-test、候选包双布局、audio 契约、缺候选包 fail-closed 等断言块及对应 usage 文案。
- 删脚本：`scripts/device-run.sh`、`scripts/verify-ios-device-flow.sh`。
- 删真机专用 UI 用例：`ios/PurePaceUITests/DeviceFlowUITests.swift`、`ios/PurePaceUITests/TCCAuthorizationUITests.swift`，并清掉 `scripts/test-ios.sh` 里对这两个 suite 的 `-skip-testing` 与被删脚本的注释/回显。
- 拆 `ios/PurePaceUITests/MusicSource.swift`：只删 `AudioLaunchArguments`、`MusicAppProbe` 两个枚举；保留 `MusicStrategy` / `OtherAudioSnapshot` / `RunnerMusicSource`。
- 清证据：删除入库的 `artifacts/device-audit/**`（72 个文件）；确认 `artifacts/device-run/` 未入库后删除，并在 `.gitignore` 加 `artifacts/device-run/`。

执行顺序不可调换（先让门与目标集合一致，再删被断言对象），每一步跑对应门到 0 再进下一步。

## 验收

- ac-check-ios-scripts-green：改完 `scripts/check-ios-scripts.sh` 后 `bash scripts/check-ios-scripts.sh` 退出 0，stdout 无 `[FAIL]`，且该文件中 `device-run.sh` / `verify-ios-device-flow.sh` 零命中（`rg -n "device-run\.sh|verify-ios-device-flow\.sh" scripts/check-ios-scripts.sh` 无输出）。
- ac-device-scripts-deleted：`scripts/device-run.sh` 与 `scripts/verify-ios-device-flow.sh` 均不存在（`test ! -e`），且 `bash scripts/check-shell-expansion.sh` 退出 0。
- ac-shell-expansion-green：`bash scripts/check-shell-expansion.sh` 退出 0（零命中 + 内置三组自检通过），退出码为唯一判据。
- ac-uitest-device-suites-deleted：`ios/PurePaceUITests/DeviceFlowUITests.swift` 与 `ios/PurePaceUITests/TCCAuthorizationUITests.swift` 不存在；`scripts/test-ios.sh` 中这两个 suite 名与被删脚本文本零命中，且仍含 `-only-testing:PurePaceUITests`。
- ac-test-ios-unit-only-green：`bash scripts/test-ios.sh --unit-only` 退出 0，输出含 Executed 摘要且 failures 为 0。
- ac-simulator-ui-leg-green：全量模拟器 UI 腿（`bash scripts/test-ios.sh`，不带 `--unit-only`）退出 0；回执给出该腿的 Executed 用例数与失败数（失败数必须为 0）。
- ac-music-source-minimal-split：`rg -n "AudioLaunchArguments|MusicAppProbe" ios/` 无输出；`ios/PurePaceUITests/MusicSource.swift` 仍含 `MusicStrategy`、`OtherAudioSnapshot`、`RunnerMusicSource` 与常量 `static let defaultBundleIdentifier = "com.apple.Music"`。
- ac-check-ios-shell-green：`bash scripts/check-ios-shell.sh` 退出 0，stdout 无 `[FAIL]`（删除 `AudioLaunchArguments` 后 Release `-releaseDeterministicLocation` 门控仍由 App 侧 `ios/PurePace/Location/ReleaseDeterministicLocationSource.swift` 承载，不得为该门回填 UI 测试侧常量）。
- ac-artifacts-device-purged：`git ls-files artifacts/device-audit | wc -l` 为 0 且该目录不存在；`grep -Fxq 'artifacts/device-run/' .gitignore` 为真；`rg -n "artifacts/device-run" scripts/ docs/ README.md AGENTS.md .github/` 无输出（`.gitignore` 自身命中不计）。
- ac-repo-zero-hits：在可执行面执行 `rg -i "device-run|verify-ios-device-flow|DeviceFlowUITests|TCCAuthorizationUITests" scripts/ ios/ .github/ shared/ README.md AGENTS.md artifacts/` 无输出（`.munk/**` 归档记录与 `docs/**` 属写项 B 范围，按本节口径排除）。
- ac-sim-harness-intact：`git diff --stat -- ios/PurePace/Harness scripts/verify-ios-sim-runtime.sh scripts/verify-ios-ui-e2e.sh` 为空；Harness 驱动的 4 个单测文件仍存在。
- ac-no-must-device-wording：`rg -n "必须真机" README.md AGENTS.md .munk/baseline` 无输出；本项新增/修改的脚本文案与回执不出现「真机已验证」宣称，真机相关项只写 `pending: 待人现场`。
- ac-workflow-untouched：`git diff -- .github/workflows` 为空（不改 job 结构、不加 `continue-on-error`、不删腿、不抬超时）。
- ac-gates-unchanged：`bash scripts/check-ios-scripts.sh` 的 22 门断言仍通过，`.munk/code-gates.json` 未被修改（`git diff -- .munk/code-gates.json` 为空）。

## 非目标

- 不删 `ios/PurePace/Harness/`（模拟器运行时取证 harness）、`scripts/verify-ios-sim-runtime.sh`、`scripts/verify-ios-ui-e2e.sh`，不改其断言语义。
- 不改 App 业务源码（除第 4 步 `MusicSource.swift` 的最小拆分，且该文件属 UITests 目标）。
- 不改 `docs/**` 与模板（文档侧残留引用归写项 B，另项执行）；不更新 `.munk/baseline` 域记录。
- 不改 `.munk/code-gates.json` 门列表、不改 Android 侧、不动 `ios/project.yml`（UITests 目标按目录收录，删文件无需改工程）。
- 不推 tag、不建 Release、不手改 main（正常走门与 delivery）。
- 不为删除顺带重构、不顺手优化其他脚本或测试。

## 实现约束

- 顺序硬约束（每步门绿再进下一步）：
  1. 改 `scripts/check-ios-scripts.sh`：`targets` / `strict_targets` 去掉 `device-run.sh`（约 :83-84）、删 `ac-device-run-plan-self-test` 与反例自检（约 :141-236）、删候选包双布局与 audio 契约、缺候选包 fail-closed 块（约 :237-295），同步删 usage 中相关条目；跑 `bash scripts/check-ios-scripts.sh` 必须 0。
  2. 删两个脚本；跑 `bash scripts/check-shell-expansion.sh` 必须 0。
  3. 删两个 UITests 文件并清 `scripts/test-ios.sh` 的 skip 行（约 :16-19、:589-591、:607-608），保留 `-only-testing:PurePaceUITests` 语义；跑 `bash scripts/test-ios.sh --unit-only` 与全量模拟器 UI 腿须绿。
  4. 拆 `ios/PurePaceUITests/MusicSource.swift`：只删 `AudioLaunchArguments`（约 :60-76）与 `MusicAppProbe`（约 :82-144）；跑 `bash scripts/check-ios-shell.sh` 必须 0。
  5. 删 `artifacts/device-audit/**` 与未入库的 `artifacts/device-run/**`，`.gitignore` 加 `artifacts/device-run/`。
- 引用现状（已核）：`AudioLaunchArguments` / `MusicAppProbe` 的唯一引用方是 `DeviceFlowUITests.swift`，第 3 步删完后第 4 步应为纯删除、无需额外改引用；若仍出现引用按最小改动清理，不得重构其他。
- 门脚本锚点：`scripts/check-ios-scripts.sh` 内部对 `device-run.sh` / `verify-ios-device-flow.sh` 的断言块必须整块删除，不能改成 skip 或注释掉；usage 摘要（约 :5-7、:16-24）同步去掉「真机脚本」措辞。
- `docs/device-scripts.md`、`docs/device-flow-usage.md`、`docs/device-assertion-matrix.md`、`docs/device-tcc-automation.md` 会残留指向已删脚本的引用：已确认无任一 gate 断言这些文档内容，故本项不动（归写项 B），回执中如实写明残留面。
- `artifacts/device-audit/**` 的外部引用只存在于 `docs/**`、`scripts/verify-ios-device-flow.sh`（本项删除）与 `.munk/baseline/**`（归档记录），删除不产生门失败。
- 预算：≤8M token / ≤90 分钟；超时即停手，回执现状（哪些步已绿、哪些未跑、红在哪）。
- 若某步门变红且原因属被删资产残留引用 → 本项内最小修复到绿；若红在业务代码或与删除无关 → 停手回执现状，不得越界改代码。
- 回执口径：三条门脚本逐条给真实退出码与输出摘要，UI 腿给用例数与失败数，零命中项给实际 `rg` 输出（无输出即零命中）；真机相关一律 `pending: 待人现场`，不写「真机已验证」。
