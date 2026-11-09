# 消除 7 个检查脚本的 `printf | grep -q` SIGPIPE 伪红（公司裁决 owe_e430dc4474be1c79 剩余部分）

## Scope

在 `set -euo pipefail` 下，`上游命令 | grep -q/-Fq` 会在 grep 命中后提前退出、上游写入进程收到 SIGPIPE（141），pipefail 把该非零码透传给整条管道，导致判定反转产生**偶发伪红**。上一项已把 `scripts/check-ios-scripts.sh` 用 here-string 判定修复并合入 main（事实基线 main=`a4592226`）。

本项只把**剩余 7 个文件**里的同类伪红点确定化，修法统一为 here-string / 内建变量替代管道，语义与判定文案零改动：

1. `scripts/check-ios-release.sh` —— 10 处 `printf ... | grep -Fq`，另加 `:247` 的 `grep -A1 file | grep -Fq`（同属 SIGPIPE 类）
2. `scripts/check-ios-shell.sh` —— 6 处
3. `scripts/check-baseline.sh` —— 5 处
4. `scripts/check-android.sh` —— 3 处
5. `scripts/check-ios-workflow.sh` —— 1 处
6. `scripts/check-android-workflow.sh` —— 1 处
7. `scripts/version.sh` —— 1 处（版本收敛脚本，风险最高，单独处置）

同时恢复 `scripts/check-ios-release.sh` 的可执行位（上一项曾误丢，当前 main 为 `100644`）。

## Acceptance Criteria

- ac-no-grep-pipe-sites: 7 个文件中，`printf ... | grep` 与 `| grep -[A-Za-z]*[qF]` 的管道判定点数量均为 0（改造前各文件分别为 10/6/5/3/1/1/1 处，含 release 的 `:247` 文件管道 1 处）。用 `grep -nE 'printf[^|]*\|[[:space:]]*grep'` 与 `grep -nE '\|[[:space:]]*grep[[:space:]]+-[A-Za-z]*[qF]'` 逐文件断言为空。
- ac-here-string-form: 每个原管道判定点改为 `grep ... <<< "$var"` 形式；`scripts/check-ios-release.sh:247` 的 `grep -A1 file | grep -Fq` 改为先用 `$(grep -A1 ...)` 完整捕获到变量再 here-string 喂给 `grep -Fq`（消除首个 grep 的 SIGPIPE 面）。
- ac-error-mode-preserved: 每个文件 `set -euo pipefail` 出现次数与改造前一致（release=3、android=3、其余=1）；改造点未新增 `|| true`、未引入 retry 循环、未出现 `set +e`，退出码未被吞。
- ac-output-identical: 在未改动的同一棵树上，逐脚本改造前后各跑一遍，输出中 `^\[PASS\]` / `^\[FAIL\]` 行序列与末尾 `N 项断言，M 项失败` 汇总行**逐行完全一致**，且退出码一致（release/shell/baseline/android/ios-workflow/android-workflow 六脚本）。
- ac-twenty-run-stable: 7 个脚本各自连跑 20 次，每次 stdout/stderr 与退出码完全一致（`scripts/version.sh` 以「stdout+退出码」为一致口径）。
- ac-version-script: `scripts/version.sh` 改动仅限 `:65` 的管道判定；`bash scripts/version.sh` 裸输出仍等于根 `VERSION` 内容；空值/非 `x.y.z` 错误路径仍以原文案 `exit 1`；连跑 20 次结果恒同。交付 digest 单独写明处置、影响面与验证方式。
- ac-exec-bits: 交付后 7 个文件 git mode 均为 `100755`；其中 `scripts/check-ios-release.sh` 由当前 `100644` 恢复为 `100755`，其余 6 个保持 `100755` 不变。
- ac-scope-only-7: 代码改动 `git diff --name-only` 仅含上述 7 个文件；`.github/**`、`.munk/code-gates.json`、其他脚本均未改动；断言文案与判定语义零改动。

## Non-Goals

- 不改 `scripts/check-ios-scripts.sh`（已在上项修复并合入 main）。
- 不新增门腿、不改 `.munk/code-gates.json`、不改任何 `.github/workflows/*`。
- 不加 retry、不用 `|| true`、不吞退出码、不重跑到绿。
- 不动 7dcd852 分支内容（未入 main，本项不涉及）。
- 不做任何与 SIGPIPE 判定无关的重构、格式化或文案调整。

## Implementation Constraints

- **事实基线**：main=`a4592226`（含上项 `95e9e9e`）。`7dcd852` 未入 main，本项不引用其内容。
- **精确可写集合**（仅这 7 个文件）：
  - `scripts/check-ios-release.sh`
  - `scripts/check-ios-shell.sh`
  - `scripts/check-baseline.sh`
  - `scripts/check-android.sh`
  - `scripts/check-ios-workflow.sh`
  - `scripts/check-android-workflow.sh`
  - `scripts/version.sh`
- **判定点锚点（行号基于 `a4592226`，供逐点核对）**：
  - `check-ios-release.sh`：`:91` `:228` `:254` `:255` `:270` `:273` `:276` `:325` `:326` `:327`（`printf|grep`）+ `:247`（`grep -A1 file | grep -Fq`）。
  - `check-ios-shell.sh`：`:94` `:190` `:192` `:212` `:214` `:773`。
  - `check-baseline.sh`：`:96` `:195` `:199` `:202` `:232`。
  - `check-android.sh`：`:128` `:460` `:477`（`:301` 为对文件直连 grep，非管道，不动）。
  - `check-ios-workflow.sh`：`:255`。
  - `check-android-workflow.sh`：`:255`。
  - `version.sh`：`:65`。
- **统一修法**：`printf '%s' "$var" | grep -Fq -- pat` → `grep -Fq -- pat <<< "$var"`；`printf '%s\n' "$var" | grep -Eq pat` → `grep -Eq pat <<< "$var"`；`grep -Fxq -- "$name"` 同理改 here-string。here-string 追加的换行对 `-Fq`/`-Eq` 子串与 `-Fxq` 指定行匹配无影响。`release:247` 用 `ctx="$(grep -A1 -F -- '<key>uploadSymbols</key>' "$export_options")"; if ! grep -Fq -- '<false/>' <<< "$ctx"; then`。
- **可执行位**：`check-ios-release.sh` 从 `100644` 恢复为 `100755`（`git update-index --chmod=+x` 或 `chmod +x` 后 `git add`），其余 6 个不得丢 `100755`。
- **确定性证明方法（交付 digest 必含）**：
  1. 改造前在 HEAD 树上逐脚本运行，保存 `[PASS]/[FAIL]` 行序列 + 汇总行 + 退出码为基线。
  2. 改造后同树逐脚本再跑，`diff` 基线；必须逐行完全一致。
  3. 每个脚本 `for i in $(seq 20); do bash scripts/X.sh; echo "EXIT:$?"; done`，20 次输出与退出码全同；digest 写明执行命令、次数、执行时刻（含时区）。
  4. 这不是「重跑到绿」：比对的是改造前后同树确定性一致，而非反复重试至通过。
- **version.sh 单独处置**：仅替换 `:65` 管道；验证裸输出等于 `VERSION`、错误路径文案与 `exit 1` 不变、20 次恒同；影响面为版本读取入口，digest 单列。
