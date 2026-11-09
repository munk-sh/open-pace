# 修复 check-ios-scripts.sh 的管道 SIGPIPE 伪红

## 范围

只改 `scripts/check-ios-scripts.sh` 一个文件的判定写法：把「把长字符串 printf 到管道、由会提前退出的消费者（`grep -q` / `head -n 1`）读取」的判定，改成不产生 SIGPIPE 的等价写法，使 `lint-ios-scripts` 门（`bash scripts/check-ios-scripts.sh`）确定可复现。

一手证据（2026-11-09 远端实测，main@`7dcd852a2df694a83fe7a83364baa3345208b57e`，ios run 42585856042，lint job exit 1）：

```
scripts/check-ios-scripts.sh: line 122: printf: write error: Broken pipe
[FAIL] ac-ios-scripts-help:  scripts/check-ios-scripts.sh --help 输出缺少「用法」;
```

同 job 其它断言全 PASS，main@`8db1a167` 同 job 已转绿 → 偶发伪红，不是业务回归。根因：`printf '%s' "$var" | grep -Fq ...` 中 `grep -q` 命中即退出并关闭读端，`printf` 收到 SIGPIPE（141），`set -euo pipefail` 下整条管道判失败，断言随竞态随机 FAIL。

当前已定位的同类位置（需自行 `grep` 全量核对，行号为 main 现状）：

- `printf | grep -Fq/-Fxq/-Eq` 共 11 处：122、515、523、525、534、536、542、544、547、557、559。
- 同源风险 `printf | sed | head -n 1` 1 处：554（`gradle_expected`，无 `|| true` 兜底，pipefail 下同样可能整条赋值失败并因 `set -e` 中断脚本）。
- 文件型 `grep/sed | head -n 1 | cut`（204–207、241、518、529、540、553）已带 `|| true` 且捕获值在退出前已产生，功能上不受影响；Coding 只需确认，不要求重写。

## 验收

- ac-ios-scripts-help-green: `bash scripts/check-ios-scripts.sh` exit 0，输出含 `[PASS] ac-ios-scripts-help`，且全量 `[FAIL]` 计数为 0（保持现有 25 项断言、0 项失败）。
- ac-version-tools-still-green: 同一次运行中 `ac-version-tools-no-gradlew`、`ac-version-tools-report`、`ac-version-tools-idempotent` 均 PASS，`VERSION` / `Xcode` / `Swift` / `JDK` / `Gradle`（含「未就绪」降级分支）判定期望值与改前完全一致。
- ac-signpipe-free-20x: 连续执行 `bash scripts/check-ios-scripts.sh` 20 次，20 次均 exit 0，且 20 次合并 stderr 中 `write error: Broken pipe` 与 `printf: write error` 出现次数均为 0。
- ac-no-printf-grep-pipe: `grep -n "printf .*| *grep" scripts/check-ios-scripts.sh` 无输出（无残留模式）；`printf` 不再作为任何「消费者可能提前退出」的管道的写端。
- ac-fail-path-preserved: 改写后的判定在目标串缺失时仍返回非零——对同一判定喂入不含目标串的输入（如 `用法`、`Xcode:` 行）实测 exit 1，交付证据附实跑命令与退出码（不得用 `|| true`、`set +e`、`continue-on-error` 或删断言换取绿灯）。
- ac-strict-mode-kept: 脚本仍为 `#!/usr/bin/env bash` 且正文含 `set -euo pipefail`，`bash -n scripts/check-ios-scripts.sh` 通过。
- ac-diff-scope: `git diff --name-only` 仅含 `scripts/check-ios-scripts.sh`；`.munk/code-gates.json` 门数仍为 22、`.github/workflows/**` 无改动、`ios/` / `android/` / `shared/` 业务与源码无改动，`VERSION` / `README.md` 未改。
- ac-local-fast-gates-green: 本地 `code_gates` 快腿全绿，至少覆盖 `lint`、`lint-ios-scripts`、`check-shell-expansion`、`lint-ios-workflow`、`test`（`bash scripts/check-baseline.sh`）；不跑重 UI E2E 腿（`verify-ios-ui-e2e` / `verify-ios-sim-runtime` 不在本地阻断）。

## 非目标

- 不改 `.github/workflows/ios.yml` 及任何 workflow；不新增门腿、不新增脚本、不改 `.munk/code-gates.json` 的 22 门拓扑。
- 不加 `|| true`、`set +e`、`continue-on-error`，不去掉 `pipefail`，不弱化/删除任何既有断言与自测样本，不为过门改期望值。
- 不改 `scripts/version.sh` 及其它兄弟检查脚本（同一 `printf | grep` 模式在 `check-baseline.sh` / `check-ios-release.sh` / `check-ios-shell.sh` 等亦存在，本项不扩面）。
- 不动业务源码与 `ios/` / `android/` / `shared/`；不动 candidates 与 Release 候选包；不改 `VERSION` / `README.md`；不推 tag。
- 不做 drive-by 重构、不做格式美化、不重命名变量、不调整断言顺序与文案（`[PASS]` / `[FAIL]` 名称与既有 25 项一一对应）。

## 实现约束

（用户已明确流水线与改法，属约定约束，非正式技术方案）

- 流水线：Intake → Coding → code_gates → Delivery；不开 PM / Design / Architect。
- 唯一可写文件：`scripts/check-ios-scripts.sh`（必须为单文件改动，便于评审与回滚）。
- 允许的等价写法（bash 3.2 兼容，远端 macOS 为 bash 3.2）：
  - here-string：`grep -Fq -- "用法" <<<"$help_out"`（here-string 由 bash 预先写入临时 fd，消费者提前退出不会反噬写端，无 SIGPIPE）；
  - bash 内建匹配：`[[ "$tools_out" == *"VERSION: ${version_value}"* ]]`、`[[ "$tools_out" =~ ^Xcode:\ 未就绪 ]]`。
  - 多行「存在某一行完全相等」语义（原 `grep -Fxq`）不得降级成子串匹配；须保持逐行全等语义（如 `grep -Fxq -- "Xcode: $xcode_expected" <<<"$tools_out"` 或用 `while read` / `case` 逐行比对），且 `-F`/`-E` 的正则 vs 字面量语义与改前一致。
- 每处必须逐条等价映射（改前 → 改后期望不变）：
  - 122 `-Fq "用法"`；515 `-Fq "VERSION: $version_value"`；
  - 523 `-Fxq "Xcode: $xcode_expected"`；525 `-Eq '^Xcode: 未就绪'`；
  - 534 `-Fxq "Swift: Apple Swift version $swift_expected"`；536 `-Eq '^Swift: 未就绪'`；
  - 542 `-Eq "^JDK: .*${jdk_expected}"`；544 / 547 `-Eq '^JDK: 未就绪'`；
  - 557 `-Fxq "Gradle: $gradle_expected"`；559 `-Eq '^Gradle: 未就绪'`。
- 554（`gradle_expected`）优先去掉无意义的 `| head -n 1`（`gradle_url` 本就是单行）或改 here-string，消除 `printf | sed | head` 断链风险。
- 变量展开一律 `${var}` 形式，禁止 `$var` 紧邻全角字符（bash 3.2 + `set -u` 下会 `unbound variable`）；中文模式串保持原样。
- 验证分层按 `AGENTS.md`：本地只跑快腿（`bash -n`、`bash scripts/check-ios-scripts.sh`、`bash scripts/check-baseline.sh`、`check-shell-expansion`、`lint-ios-workflow`），重 UI E2E 不本地跑。
- 交付证据必须含：单次运行尾部输出（`25 项断言，0 项失败` / `ios scripts OK`）、20 连跑脚本及其汇总（0 次 SIGPIPE、0 次非零）、`grep -n "printf .*| *grep"` 空结果、失败路径负向实跑（缺目标串 exit 1）、`git diff --name-only` 单文件。
