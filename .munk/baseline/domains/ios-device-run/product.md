# Domain: ios-device-run

PurePace iOS **agent 级真机验收脚本底座**域。2026-11-10 公司清点后整体退役（清理写项 A，「代码与门」半）：`scripts/device-run.sh`、`scripts/verify-ios-device-flow.sh`、`ios/PurePaceUITests/DeviceFlowUITests.swift`、`ios/PurePaceUITests/TCCAuthorizationUITests.swift`、入库的 `artifacts/device-audit/**`（72 文件）已删除，`scripts/check-ios-scripts.sh` 内对应断言块与 `scripts/test-ios.sh` 内对应 `-skip-testing` 同步移除。后续真机验收不再由脚本承载；模拟器取证 harness（`ios/PurePace/Harness/`、`scripts/verify-ios-sim-runtime.sh`、`scripts/verify-ios-ui-e2e.sh`）继续有效且本域不得改动其语义。

## 范围

- 退役形态（当前事实）：上述两脚本、两 UI 用例、`artifacts/device-audit/**` 零存在；`artifacts/device-run/` 不入库（`.gitignore` 固定行）。
- 仍生效的门面：`scripts/check-ios-scripts.sh` 的 `targets` / `strict_targets` 只覆盖 `build-ios.sh test-ios.sh check-ios-scripts.sh version.sh verify-ios-ui-e2e.sh verify-ios-sim-runtime.sh`；`scripts/test-ios.sh` 默认 UI 腿为纯 `-only-testing:PurePaceUITests`（无 skip 套件）。
- 保留资产：`ios/PurePace/Harness/`、`scripts/verify-ios-sim-runtime.sh`、`scripts/verify-ios-ui-e2e.sh` 及其 4 个驱动单测；`ios/PurePace/Location/ReleaseDeterministicLocationSource.swift` 继续承载 Release `-releaseDeterministicLocation` 门控。
- 历史归档（已失效，不得据其恢复资产）：旧 10 phase 流水（`preflight`→`wda`→`install`→`launch`→`tcc`→`audio`→`record`→`lock`→`collect`→`evidence`）、`artifacts/device-run/<candidateKey>/` 证据结构、`summary.json` schema、launch 双路径与 tcc「ok 仅 authorizedAlways」判定。
- 已知残留：`docs/device-scripts.md`、`docs/device-flow-usage.md`、`docs/device-assertion-matrix.md`、`docs/device-tcc-automation.md` 仍在仓库且指向已删脚本/证据；无任一门断言这些文档，清理归写项 B。

## 验收

- ac-check-ios-scripts-green: `bash scripts/check-ios-scripts.sh` 退出 0，stdout 无 `[FAIL]`；该文件内 `device-run.sh` / `verify-ios-device-flow.sh` 零命中（目标集合、严格模式与 `--help` 覆盖、plan 自证、候选包双布局、audio 契约、缺候选包 fail-closed 等整块断言与 usage 文案一并删除，不得改 skip 或注释保留）。
- ac-device-scripts-deleted: `scripts/device-run.sh` 与 `scripts/verify-ios-device-flow.sh` 均不存在（`test ! -e`）。
- ac-shell-expansion-green: `bash scripts/check-shell-expansion.sh` 退出 0（当前 7 项断言，0 失败），退出码为唯一判据。
- ac-uitest-device-suites-deleted: `ios/PurePaceUITests/DeviceFlowUITests.swift` 与 `ios/PurePaceUITests/TCCAuthorizationUITests.swift` 不存在；`scripts/test-ios.sh` 对两个 suite 名与被删脚本零命中，且仍含 `-only-testing:PurePaceUITests`。
- ac-test-ios-unit-only-green: `bash scripts/test-ios.sh --unit-only` 退出 0，输出含 Executed 摘要且 failures 为 0。
- ac-simulator-ui-leg-green: 全量模拟器 UI 腿（`bash scripts/test-ios.sh`，不带 `--unit-only`）退出 0；回执给出 Executed 用例数与失败数（失败数必须为 0）。
- ac-music-source-minimal-split: `rg -n "AudioLaunchArguments|MusicAppProbe" ios/` 无输出；`ios/PurePaceUITests/MusicSource.swift` 仍含 `MusicStrategy`、`OtherAudioSnapshot`、`RunnerMusicSource` 与 `static let defaultBundleIdentifier = "com.apple.Music"`。
- ac-check-ios-shell-green: `bash scripts/check-ios-shell.sh` 退出 0、stdout 无 `[FAIL]`；删 `AudioLaunchArguments` 后 Release `-releaseDeterministicLocation` 门控仍由 `ios/PurePace/Location/ReleaseDeterministicLocationSource.swift` 承载，不得为门回填 UI 测试侧常量。
- ac-artifacts-device-purged: `git ls-files artifacts/device-audit | wc -l` 为 0 且目录不存在；`grep -Fxq 'artifacts/device-run/' .gitignore` 为真；`rg -n "artifacts/device-run" scripts/ docs/ README.md AGENTS.md .github/` 无输出（`.gitignore` 自身命中不计）。
- ac-repo-zero-hits: 可执行面 `rg -i "device-run|verify-ios-device-flow|DeviceFlowUITests|TCCAuthorizationUITests" scripts/ ios/ .github/ shared/ README.md AGENTS.md artifacts/` 无输出；`.munk/**` 与 `docs/**` 按 PRD 口径排除（归写项 B）。
- ac-sim-harness-intact: `git diff --stat -- ios/PurePace/Harness scripts/verify-ios-sim-runtime.sh scripts/verify-ios-ui-e2e.sh` 为空；Harness 驱动的 4 个单测文件仍在。
- ac-no-must-device-wording: `README.md`、`AGENTS.md` 与 `.munk/baseline` 中「必须」与「真机」连写的断言用词零命中（`rg` 校验无输出）；新增/修改脚本文案不出现「真机已验证」宣称，真机相关项只写 `pending: 待人现场`。
- ac-workflow-untouched: `git diff -- .github/workflows` 为空（不改 job 结构、不加 `continue-on-error`、不删腿、不抬超时）。
- ac-gates-unchanged: `.munk/code-gates.json` 零 diff（`git diff -- .munk/code-gates.json` 为空），22 门列表不变。

## 非目标

- 不恢复已删脚本、真机 UI 用例与 `artifacts/device-audit/**`；不为删除顺带重构或优化其他脚本/测试。
- 不删 `ios/PurePace/Harness/`、`scripts/verify-ios-sim-runtime.sh`、`scripts/verify-ios-ui-e2e.sh`，不改其断言语义。
- 不改 App 业务源码（除 `MusicSource.swift` 的最小拆分，该文件属 UITests 目标）。
- 不改 `docs/**` 与模板（文档侧残留引用归写项 B）、不改 Android 侧、不动 `ios/project.yml`（UITests 目标按目录收录）。
- 不推 tag、不建 Release、不手改 main；不在 coding 会话内连真机或宣称「真机已验证」。

## 实现约束

- 顺序硬约束（每步门绿再进下一步）：① 先收口 `scripts/check-ios-scripts.sh`（去 targets、断言块与 usage 文案）并跑绿；② 再删两脚本与 `check-shell-expansion` 跑绿；③ 删两 UI 用例并清 `test-ios.sh` 的 skip 与回显，跑 `--unit-only` 与全量 UI 腿；④ 拆 `MusicSource.swift` 后跑 `check-ios-shell.sh`；⑤ 删 `artifacts/device-audit/**`、清未入库的 `artifacts/device-run/` 并补 `.gitignore`。
- 门脚本锚点必须整块删除，不得改成 skip 或注释；`--help` / usage 摘要同步去掉「真机脚本」措辞，`-only-testing:PurePaceUITests` 语义保留。
- `MusicSource.swift` 只删 `AudioLaunchArguments` 与 `MusicAppProbe`（唯一引用方是被删的 `DeviceFlowUITests.swift`）；若仍出现引用按最小改动清理，不得重构其他。
- 证据清理：`artifacts/device-audit/**` 全部 72 个入库文件删除且不产生门失败（外部引用只在 `docs/**` 与已删脚本）；`artifacts/device-run/` 确认未入库后删除并写入 `.gitignore`。
- 回执口径：三条门脚本逐条给退出码与输出摘要，UI 腿给用例数与失败数，零命中项给实际 `rg` 输出（无输出即零命中），真机项一律 `pending: 待人现场`。
- 若某步门红因被删资产残留引用 → 本项内最小修复到绿；若红在业务代码或与删除无关 → 停手回执现状，不越界改代码。

## 最近交付证明

- workItemId: wi_intake_e4d409ec52cb46d4（2026-11-10，pass）— 清理写项 A「代码与门」半完成
- 交付：`git diff --stat` 仅 5 个文件（`scripts/check-ios-scripts.sh` -173 行、`ios/PurePaceUITests/MusicSource.swift` -95 行、`scripts/test-ios.sh` -12 行、`MusicSourceSelfCheckUITests.swift` -1/+1 注释、`.gitignore` +1 行 `artifacts/device-run/`），并删除 `scripts/device-run.sh`、`scripts/verify-ios-device-flow.sh`、`DeviceFlowUITests.swift`、`TCCAuthorizationUITests.swift` 与 `artifacts/device-audit/**` 72 文件（已 stage 为 deleted）。`check-ios-scripts.sh` 的 `targets`/`strict_targets` 收为 6 个脚本，断言总数由含 device 块降为 27 项，全 PASS；`test-ios.sh` UI 腿改为纯 `-only-testing:PurePaceUITests`，usage 与 echo 去掉真机套件说明。
- 实测：`bash scripts/check-ios-scripts.sh` 退出 0（27 项断言 / 0 失败，stdout 无 `[FAIL]`，对兩脚本零命中）；`bash scripts/check-shell-expansion.sh` 退出 0（7 项 / 0 失败）；`rg -i "device-run|verify-ios-device-flow|DeviceFlowUITests|TCCAuthorizationUITests" scripts/ ios/ .github/ shared/ README.md AGENTS.md artifacts/` 无输出；`rg -n "AudioLaunchArguments|MusicAppProbe" ios/` 无输出且 `MusicSource.swift` 仍含 `MusicStrategy`/`OtherAudioSnapshot`/`RunnerMusicSource`/`com.apple.Music`；`git ls-files artifacts/device-audit | wc -l` 为 0 且目录不存在；`ios/PurePace/Harness`、`scripts/verify-ios-sim-runtime.sh`、`scripts/verify-ios-ui-e2e.sh`、`.github/workflows`、`.munk/code-gates.json`（22 门）零 diff。
- 边界：`docs/device-scripts.md`、`docs/device-flow-usage.md`、`docs/device-assertion-matrix.md`、`docs/device-tcc-automation.md` 仍保留指向已删脚本的引用（无门断言，归写项 B）；真机相关一律 `pending: 待人现场`，本项不宣称真机已验证。
