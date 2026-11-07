# shell 展开卫生与静态门（仅脚本/门禁）

## Scope

只做脚本与门禁卫生，把「裸 `$var` 紧跟非 ASCII 字符」的展开写法改为 `${var}`，并用静态门锁死不再回流。

1. **全仓扫描并修正展开写法**（注释行除外）：
   - 扫描范围：`scripts/**/*.sh`、`android/**`（shell 文件，含无扩展名的 `android/gradlew`）、`.github/workflows/*.yml|*.yaml`。
   - 命中判据：变量名以 ASCII 字母/下划线开头，后接非 ASCII 字节（UTF-8 全角标点、汉字等），且未用 `${...}` 包裹。
   - 已实测命中 15 处（排除 1 处注释）：
     - `scripts/test-android.sh`：L96 `$ANDROID_HOME（`、L127 `$results_dir（` / `$gradle_status）`、L137、L227 `$gradle_status）`、L231 `$total_errors）`
     - `scripts/check-ios-scripts.sh`：L116 `$bad_rc（`、L222 `$xcode_expected）`、L233 `$swift_expected）`、L241 `$jdk_expected）`
     - `scripts/build-android.sh`：L91 `$ANDROID_HOME（`、L117 `$build_status）`
     - `scripts/check-shared.sh`：L81 `$missing_tools（`、L623 `$py_status）`
     - `scripts/check-android.sh`：L126 `$bad_rc（`
     - `.github/workflows/android.yml`：L58 `$java_version，`
   - 唯一注释命中 `android/gradlew:37`（`«$var»` 文档注释）**不改**，作为门的注释豁免正例活样本。
2. **新增静态门脚本** `scripts/check-shell-expansion.sh`：按上述判据扫描同一范围、注释豁免、内置正反例自检，作为 `code-gates` 门真实执行体。
3. **注册门禁**：`.munk/code-gates.json` 追加 `check-shell-expansion` 门，command 为单一 argv `bash scripts/check-shell-expansion.sh`，cwd 为 `.`。

## Acceptance Criteria

- ac-scan-zero-hits: 静态扫描 `scripts/**/*.sh`、`android/**`（shell 文件，含 `android/gradlew`）、`.github/workflows/*.yml|*.yaml` 的非注释行，`$标识符` 紧跟非 ASCII 字节的展开命中数为 0；`grep`/脚本两种口径结果一致。
- ac-fix-checklist-complete: 上列 15 处命中全部改为 `${var}` 形式（变量名与语义不变），`android/gradlew` 保持逐字节未改（注释命中仍存在且被门豁免）。
- ac-gate-registered: `.munk/code-gates.json` 含 `id` 为 `check-shell-expansion`、`cwd` 为 `.`、`command` 恰为 `bash scripts/check-shell-expansion.sh` 的门；JSON 仍可解析且 `version=1`、门 id 唯一。
- ac-prior-gates-unchanged: 原有 20 个门（`lint` … `check-gpx-export`）的 `id` 与 `command` 逐字未变，门集合只增不减。
- ac-gate-clean-run: `bash scripts/check-shell-expansion.sh` 在真实仓库上退出 0 并逐条 PASS。
- ac-gate-self-test-positive: 脚本内置自检构造含 `${var}中文` 的样本文件，判定为通过（不误报）。
- ac-gate-self-test-negative: 内置自检构造含 `$var中文` 的样本，判定为命中并使门非零退出（证明断言非恒真）。
- ac-gate-comment-exempt: 内置自检构造 `# $var中文` 注释行样本，判定为豁免（不命中）。
- ac-gate-help-and-args: `bash scripts/check-shell-expansion.sh --help` 退出 0 且输出含「用法」；未知参数退出 2，且不执行扫描。
- ac-gate-no-bypass: 门脚本不新增 `set -e` 之外的静默放行分支；扫描器缺失（python3/perl 均不可用）时显式 fail 并非零退出，不用 `true`/空转冒充通过。
- ac-workflow-single-echo-change: `.github/workflows/android.yml` 的改动仅限 L58 一处 echo 行的变量包裹（如需引号亦仅此一行），workflow 仍通过 `bash scripts/check-android-workflow.sh`。
- ac-regression-green: `bash scripts/check-baseline.sh`、`bash scripts/check-android.sh`、`bash scripts/check-android-workflow.sh`、`bash scripts/check-ios-core.sh`、`bash scripts/check-ios-scripts.sh`、`bash scripts/check-ios-shell.sh`、`bash scripts/check-ios-workflow.sh`、`bash scripts/check-ios-run-core.sh` 均退出 0。
- ac-script-contract-preserved: 被修改脚本的 `--help` 退出 0 且含「用法」、未知参数退出 2、`blocked:` 降级与退出码语义不变（既有 `check-*` 门真实断言通过即视为证据）。

## Non-Goals

- 不改 Android 业务实现、Compose 页面、`android/app/src/**`、gradle 配置与 `android/gradlew`。
- 不改 `build-android.sh` / `test-android.sh` / `build-ios.sh` / `test-ios.sh` 的入口语义（参数、退出码、`blocked:` 降级、输出契约），只做 `${var}` 包裹。
- 不重构、不重排、不统一脚本风格，不顺手修其它 lint/文案问题。
- 不新增 CI workflow、不调整 CI 结构、不改 job/step 划分；workflow 只允许那一处 echo 行。
- 不引入第三方工具链、不改 locale 全局设置、不新增运行时依赖。
- 不改 `ios/**`、`shared/**`、`.munk/baseline/**`；不写 `tech.md`。
- 不为「脚本卫生」扩张出代码质量/安全扫描等新门。

## Implementation Constraints

- 允许写入路径：`scripts/*.sh`（含新增 `scripts/check-shell-expansion.sh`）、`.munk/code-gates.json`、`.github/workflows/android.yml`（仅 L58 一行）。其余路径禁止写入。
- `android/gradlew` 是 Gradle wrapper 生成物且命中在注释行，**禁止编辑**；门的注释豁免必须能覆盖它。
- 非 ASCII 判定用字节级比较（`LC_ALL=C`，字节 ≥ 0x80），不得依赖当前 locale 的字符分类；扫描器不得假定 GNU `grep -P` 可用（macOS BSD grep 无 `-P`），优先 python3 或 perl，缺失即 fail。
- 门脚本自身位于 `scripts/` 内且会被自己扫描：其源码不得出现裸 `$var` + 非 ASCII 的字面组合（正则用 `[^ -~]` 一类 ASCII 取反类表达，或显式排除自身路径并在 PR 说明原因）。
- 自检样本必须落在 `mktemp -d` 临时目录，不得在仓库内落地 `.sh` 夹具（避免被自身扫描与 `check-baseline` 的脚本枚举误伤）。
- `$var` → `${var}` 是纯语法包裹：仅加花括号，不改变量名、不做额外引用化（除 workflow L58 那一行允许的必要引号修正）。
- 门新增为 append-only：不得删除、重排、重命名或改写既有 20 个门的 `id`/`command`；`description` 可追加一句说明。
- `scripts/check-baseline.sh` 断言 `scripts/*.sh` 中不得出现 `VERSION` 字面值：新脚本不得写死版本号。
- `.github/workflows/android.yml` 改动属 CI 面风险（本次唯一 workflow 触碰点），交付说明必须显式标注该行改动与「CI 未在本 WorkSet 内远端复跑」的风险，不得声称 CI 已通过。
