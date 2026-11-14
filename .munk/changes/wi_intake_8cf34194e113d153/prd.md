# Android 出包目录覆盖硬化 + manifest commit 口径纠偏（不改包、不改版本）

## 范围

把一处**口径漂移**收敛成可断言事实，不重跑出包、不改任何产品功能：

1. **脚本硬化（`scripts/package-android.sh`）**：目标产物目录 `${PUREPACE_DIST_ROOT:-${TMPDIR:-/tmp}}/purepace-dist/android/<versionName>-<versionCode>/` 已存在时**默认拒绝覆盖**并给出明确错误；只有显式 `--force` 才允许原地覆盖。二选一里选它（相对于「自动改用带时间戳/构建序号子目录」），因为改动面更小：产物路径保持确定性，手册/证据里的 `<versionName>-<versionCode>` 路径口径不需要二次改写。
2. **反例随代码同 commit（`scripts/check-android.sh`）**：新增「先造出已存在目录再跑脚本 → 必须红」的行为断言，附**去守卫副本必须绿**的自检（证明红由守卫触发，而非别的原因）；既有「同 commit 幂等」用例改为经 `--force` 运行，断言强度不降（sha 变化仍判红）。
3. **证据与手册说真话**：`docs/evidence/wi_intake_9dc4d2c5af703568/` 与 `docs/distribution/manual-test-guide.md` 1.1 节把 commit 口径改准确——验收键是 **sha256 + 版本 + APK 字节**；`manifest.json.commit` 记的是**构建时工作树 commit**（本次盘上为 `48b3e5c`，与 `2873ae2` 在 `android/ ios/ shared/ scripts/` 路径上零差异，依据 = `git diff --name-only 2873ae2 707da7f | grep -E '^(android|ios|shared|scripts)/'` 为空）；同一 sha256 对应两个构建 commit 时两行都写并注明「字节一致」，不再宣称 manifest 里是 `2873ae2`。

本项**不产生新包**：盘上 `.../android/0.1.0-1/purepace-0.1.0-1-debug.apk` 的 sha256 必须保持 `8b80c8e2252fbbd20ccacadfad67bf2b49410b7976926ae507282d9b242990e0`，不改名、不删除、不搬迁。

## 验收

- ac-package-refuse-existing-default: 沙箱里预置目标目录 `.../purepace-dist/android/<version>-1/`（含哨兵文件与旧 `checksums.txt`）后，**不带参数**运行 `scripts/package-android.sh`（stub gradlew）→ 非零退出；日志同时含「已存在」与 `--force`；预置目录内既有文件字节不变（未被 `rm -rf` 清掉、未被新产物覆盖）。
- ac-package-force-explicit-overwrite: 同一预置目录加 `--force` 运行 → 退出 0，目录内 APK / `manifest.json` / `checksums.txt` 为新产物，stdout `SHA256=` 等于 APK 实测 sha256，且哨兵文件已不在。
- ac-package-idempotent-under-force: 同 commit 以 `--force` 连跑两次 → 退出 0 且两次 `SHA256=` 相同、分发目录数量仍为 1；把 stub 切到 sha 变化模式并以 `--force` 运行 → 仍非零退出且日志命中「幂等」（既有幂等断言未放宽）。
- ac-package-guard-red-proof: 从生产脚本副本中删掉守卫块（`guard-begin: refuse-existing-dist` … `guard-end: refuse-existing-dist`）后，同一「目标目录已存在」场景退出 0 → 证明 ac-package-refuse-existing-default 的红由守卫触发；该自检在 `check-android.sh` 内实跑，不依赖人工日志。
- ac-package-cli-contract-preserved: `--help` 退出 0 且帮助文本含 `--force` 与「拒绝覆盖」语义；未知参数（如 `--bogus`）退出 2；`PUREPACE_DIST_ROOT` 指向仓库内仍被拒绝（「仓库外」断言保留）。
- ac-evidence-manifest-truth: `docs/evidence/wi_intake_9dc4d2c5af703568/README.md` 不再出现「manifest.json 里是 `2873ae2`」的肯定表述；改为写明验收键 = sha256 + 版本 + APK 字节，并写明 `manifest.commit` 语义 = 构建时工作树 commit。
- ac-evidence-two-builds-same-bytes: 证据目录同时给出两次构建的 commit/buildTime（`2873ae2` / `2026-11-14T19:59:46Z` 与 `48b3e5c` / `2026-11-14T20:17:29Z`）两行，两行 sha256 均为 `8b80c8e2…` 并注明「字节一致」；同时落一份在盘 `manifest.json` 的快照文件，使两行都能在仓内找到对应文件。
- ac-evidence-zero-diff-basis: 证据内给出「代码路径零差异」的可核验依据（`git diff --name-only 2873ae2 707da7f | grep -E '^(android|ios|shared|scripts)/'` 为空、退出码 1），并附该命令输出段落；不得只写结论不写输出。
- ac-guide-android-truth: `docs/distribution/manual-test-guide.md` 1.1 节把「本次实测产物（commit `2873ae2…`）」改成以 sha256 + 版本 + APK 字节为准的验收写法，并写清 manifest.commit 为构建时工作树 commit（盘上 `48b3e5c`，与 `2873ae2` 代码路径零差异）；该节不再出现「manifest 里是 `2873ae2`」的肯定表述。
- ac-guide-zero-release-claims: 对 `docs/distribution/manual-test-guide.md` 全文 grep「已发布|已分发|可下载|已上架|真机已验证」零命中；三条人耳结论（音乐不被打断 / 不切歌 / 播完音量恢复）仍逐条为 `pending: 待人现场`。命中结果与三条状态行落 evidence 日志。
- ac-artifact-bytes-untouched: 本项不执行真实出包；`${TMPDIR:-/tmp}/purepace-dist/android/0.1.0-1/purepace-0.1.0-1-debug.apk` 的文件名与 sha256 仍为 `8b80c8e2252fbbd20ccacadfad67bf2b49410b7976926ae507282d9b242990e0`，目录内 APK 文件未被改名/删除；evidence 记录本项运行前后该 sha256 的实测对照。
- ac-gates-green: `bash scripts/check-baseline.sh`、`bash scripts/check-android.sh`、`bash scripts/check-ios-release.sh`、`bash scripts/check-privacy-policy.sh` 实跑退出码均为 0，输出段落入 evidence。
- ac-commit-split-faces: 提交按面拆分——code 面（`scripts/package-android.sh` + `scripts/check-android.sh`）与 fold 面（`docs/evidence/**`、`docs/distribution/manual-test-guide.md`）不混在同一提交；`git diff` 不含 `VERSION`、不含 `.github/workflows/`、不新增 CI 腿、不改 `docs/verification-matrix.md` 行数口径。

## 非目标

- 不重跑出包、不覆盖盘上产物、不改 APK 字节、不改名/删除/搬迁产物目录；不产生新 APK/新 ipa。
- 不改产品代码（`ios/`、`android/`、`shared/` 业务与 UI）、不改 `VERSION`、不改 UI 与 design tokens、不改 `android/app/build.gradle.kts` 的 `versionCode`。
- 不改 `.github/workflows/**`、不新增 CI 腿、不改 `.munk/code-gates.json` 的门定义、不新增验证基建脚本。
- 不改 `docs/verification-matrix.md` 行数口径（已声明接缝行数与列结构不动）；不动 `docs/release/testflight-runbook.md`、`docs/device-manual-acceptance.md`、政策正文。
- 不把「回目录拒绝覆盖」扩成保留策略/清理策略（不自动删旧目录、不加时间戳子目录、不加归档逻辑）。
- 不写「已发布 / 已分发 / 可下载 / 已上架 / 真机已验证」，不把模拟器读数当人耳结论。
- 不为了凑绿去削弱既有断言：幂等、checksums 对照、仓内路径拒绝、零明文凭据、空 APK 判红全部保持。

## 实现约束

**锚点（派发已点名，无需 Architect 重扫）**

- 出包脚本：`scripts/package-android.sh`。现状关键行：参数解析在文件头 `case "${1:-}"`；`target_dir="${dist_root}/purepace-dist/android/${version}-${version_code}"`；随后 `if [ -f "${target_dir}/manifest.json" ]` 读 `previous_sha` / `previous_commit`；再 `rm -rf "${target_dir}"` 原地覆盖。守卫插在 `rm -rf` **之前**（且在 dist root 解析、仓外路径断言之后）。
- 门脚本：`scripts/check-android.sh` 第 1001-1261 行「打包脚本静态 + 行为反例」段；`run_package_case()` 当前只透传 3 个位置参数，需要能追加脚本参数。既有用例：`ok-first` / `ok-second` / `varysha` / `emptyapk` / `inside-path` / 凭据反例。断言标签页头部清单（第 30-40 行）需同步登记新断言名。
- 证据目录：`docs/evidence/wi_intake_9dc4d2c5af703568/`（已交付项的证据，本次只做口径纠偏与补快照，不删除既有文件）。本项自身的运行日志建议落 `docs/evidence/wi_intake_8cf34194e113d153/`（新增目录），至少含脚本反例红绿两态日志、四条门禁日志、手册禁词与三条人耳状态 grep 日志、盘上 APK sha256 前后对照。
- 手册落点：`docs/distribution/manual-test-guide.md` 1.1 节（第 45 行「本次实测产物（commit `2873ae2…`）」及其下表）；`docs/distribution/android.md` 第 1 节「出包」可补一句「目标目录已存在时默认拒绝覆盖，需 `--force`」——只加这一句，不重构该文档。
- 事实锚点（已实测，可直接引用）：盘上 manifest = `commit 48b3e5c82c7988df8bc1a1e0c5cf949006c45602` / `buildTime 2026-11-14T20:17:29Z` / sha256 `8b80c8e2…`；证据 manifest 快照 = `2873ae21ee05c890980be28a63dda1d7da573bcf` / `2026-11-14T19:59:46Z` / 同一 sha256；`git diff --name-only 2873ae2 707da7f` 仅 `docs/` 与 `.munk/` 路径，`android|ios|shared|scripts` 前缀为空（grep 退出码 1）。

**行为约束（脚本）**

- 默认行为：目标目录已存在（无论内容是否完整）→ `exit 1`，错误文本需含「已存在」「`--force`」，并尽量回显既有 manifest 的 `commit` / `buildTime`，提示可改 `PUREPACE_DIST_ROOT` 或显式 `--force`。
- `--force` 语义：允许覆盖，但**不豁免**既有同 commit 幂等断言（同 commit + sha 变化仍非零退出）；不同 commit + 不同 sha 允许覆盖（这是显式请求）。
- 保留 `check-android.sh` 静态断言依赖的字面量：`PUREPACE_DIST_ROOT`、`purepace-dist/android`、`manifest.json`、`checksums.txt`、`printf 'APK=%s`、`printf 'SHA256=%s`、`shasum -a 256`、「仓库外」。
- 守卫块用注释标记 `# guard-begin: refuse-existing-dist` / `# guard-end: refuse-existing-dist` 包起来，供门脚本按区间删除做「去守卫必绿」自检；标记只是注释，不参与运行语义。
- 参数契约：`-h|--help` → 0；`--force` 可单独出现；未知参数 → 2；不引入位置参数。

**证据与文档约束**

- 证据与手册不得再断言「manifest.commit 等于手册引用 commit」这一旧口径；新口径为「验收键 = sha256 + 版本 + APK 字节，commit 只是构建时的树标记」。若同一 sha256 对应两个构建 commit，两行并列且每行注明「字节一致」。
- 手册状态词表不变：只用「机器已验：<真实测试名>」与 `pending: 待人现场`；禁词表不变。
- 不写死版本字面值到构建配置；手册继续用 `<versionName>-<versionCode>` 占位（本次只在实测表格里写实值抄录）。

**验证与提交**

- 四条门禁必须真跑：`bash scripts/check-baseline.sh`、`bash scripts/check-android.sh`、`bash scripts/check-ios-release.sh`、`bash scripts/check-privacy-policy.sh`；改动前后各跑一次，改前 30/29/49 项断言全绿作为基线对照。
- 脚本反例必须有红绿两态实证：用改动前的脚本（`git show 707da7f:scripts/package-android.sh`）在沙箱里制造「目标目录已存在」→ 旧脚本退出 0（红：该拦未拦）；改后脚本同场景退出 1 并给出错误（绿）。两态日志入 evidence，不得只贴结论。
- 提交分面：code 面与 fold（docs/evidence）面分开；`.munk/changes/**` 与 change-pack 单独提交。
- 环境缺失（无 JDK 21 / Android SDK）不影响本项：门脚本用 stub gradlew 在沙箱跑，不需要真实 SDK；若真实出包被误触发即视为越界。
