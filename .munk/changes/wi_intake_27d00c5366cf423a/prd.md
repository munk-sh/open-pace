# 清除 scripts/check-ios-shell.sh 在 `set -euo pipefail` 下的 SIGPIPE 伪红

## 范围

只改 `scripts/check-ios-shell.sh` 中「上游写者（`printf` / `sed` / `grep` / `find`）→ 提前退出消费者（`grep -q` / `grep -m` / `head`）」的管道形态，改为让最后一段读全量或改用 here-string，**断言语义、文案、阈值、失败原因串一律不动**。实测根因：`printf '%s\n' "$block" | grep -Fq ...` 中 `grep -q` 命中首行即关读端，`printf` 收到 SIGPIPE(141)，`pipefail` 把整条管道判失败，`|| problems=...` 于是假红（重试即过）。

基线 commit：`5925310`（`git show 5925310:scripts/check-ios-shell.sh` 为本项旧写法真源）。基线脚本命中「提前退出消费者」形态 **10 处**：

| 行 | 现形态 | 目标形态 |
|---|---|---|
| 670 | `printf '%s\n' "$group_block" \| grep -Fq "static let $member"` | `grep -Fq "static let $member" <<< "$group_block"` |
| 673 | `printf '%s\n' "$appearance_block" \| grep -Fq 'supportsDarkMode = true'` | `grep -Fq 'supportsDarkMode = true' <<< "$appearance_block"` |
| 535 | `sed -n "${start},${end}p" "$file" \| grep -Eq '...'` | 先 `local window; window="$(sed -n "${start},${end}p" "$file" 2>/dev/null || true)"`，再 `grep -Eq '...' <<< "$window"` |
| 2110 | `sed -n '/onMapCameraChange/,/^        }/p' "$map_shell" \| grep -Eq 'cameraPosition[[:space:]]*='` | 同口径：sed 输出存变量，再 herein `grep -Eq` |
| 457 | `printf '%s\n' "$1" \| sed -nE ... \| head -n 1` | 去掉 `head`：sed 输出存变量后取首行（`${var%%$'\n'*}`），语义仍是「首个匹配值」 |
| 165 / 177 / 244 | `grep -E '...' "$spec_file" \| head -n 1` | 去掉管道：`grep -m1 -E '...' "$spec_file"`（同为文件读取，首条命中，无 SIGPIPE 面） |
| 1934 / 1937 | `find ... \| head -20` | `find ... \| sed -n '1,20p'`（末段读全量，保留「前 20 行」语义） |

消费者本就读全量的管道**保持原样**（不属同类，不动）：`:102`（`printf | grep -Ev`）、`:499`（`grep -nE | grep -vE`）、`:849`（`... | sed | grep -vF`）、`:1027`（`printf | grep -Fxc`）、`:1917`（`git ls-files | grep -F`）、`:511`（`... | sed | sort`）。

同时落一份可重跑证据脚本与日志：`docs/evidence/wi_intake_27d00c5366cf423a/`（红→绿反例、仍红反例、两条显式命令的原始输出）。

## 验收

- ac-no-early-exit-consumer-pipe: 对 `scripts/check-ios-shell.sh`（排除注释行）执行 `grep -nE '(^|[^|])\|[[:space:]]*(head|grep[[:space:]]+-[^|]*[qm])'` 为 0 命中；同一命令对基线 `git show 5925310:scripts/check-ios-shell.sh` 命中 10 行（守卫非空转）。
- ac-token-member-herestring: 670/673 已为 here-string 形态，`Token 缺少 $group.$member;` / `Appearance.supportsDarkMode 必须为 true;` 两条失败文案逐字不变；干净仓 `bash scripts/check-ios-shell.sh` 打印 `[PASS] ac-design-tokens`。
- ac-identifier-label-no-sed-pipe: `identifier_has_readable_label`（:535）改为 sed 结果先入变量、再 `grep -Eq ... <<< "$window"`；判据正则与 `return 0/1` 分支不变，干净仓该路径仍随 `ac-design-tokens` PASS（49 个 identifier 的可读 label 检查）。
- ac-map-camera-no-sed-pipe: `onMapCameraChange` 回写检查（:2110）同口径改写；对真实 `ios/PurePace/Track/TrackMapView.swift` 切片判定为「无回写」，对注入 `cameraPosition =` 的切片判定为「有回写」。
- ac-red-proof-old-form-nonzero: 证据脚本用基线 commit 逐字提取的旧形态，在 `set -euo pipefail` 下喂「首行即命中 + 后续 >64 KiB」block，退出码非 0（实测 `141`），原始退出码写入 `docs/evidence/wi_intake_27d00c5366cf423a/old-form.log`。
- ac-red-proof-new-form-zero: 同一输入经改后脚本中实际的新形态行，退出码为 0；日志 `new-form.log` 记录两向退出码。
- ac-red-proof-negative-still-red: 新形态喂「确实缺 token」的 block（删掉 `static let durationState` 一行）必须非 0 退出且打印缺项判定；sed 两条（可读 label / `cameraPosition =`）各给一正一反，证明改写未把断言写空；日志 `negative-still-red.log`。
- ac-full-check-green: `bash scripts/check-ios-shell.sh` 退出 0，断言数 ≥ 32 且 0 失败（基线 32 项），日志 `check-ios-shell.log`（含 `[PASS] ac-design-tokens` 与 `ios shell OK`）。
- ac-self-test-green: `bash scripts/check-ios-shell.sh --self-test` 退出 0，末行为 `102 项断言，0 项失败` 与 `self-test OK`（当前门不覆盖此模式，必须显式单跑），日志 `check-ios-shell-self-test.log`。
- ac-code-gates-green: `.munk/code-gates.json` 仍 22 门且 id/`command` 零 diff，全部门退出 0（含 `lint-ios-shell`）。
- ac-scope-frozen: `git diff --name-only` 仅含 `scripts/check-ios-shell.sh` 与 `docs/evidence/wi_intake_27d00c5366cf423a/**`；`git diff --exit-code -- ios VERSION .github shared android docs/verification-matrix.md` 为空，其它 `scripts/*.sh` 零改动。
- ac-evidence-receipt: 证据目录 README 列明「被清除的管道形态清单（文件:行 → 新形态）」「旧写法伪红原始退出码」「`--self-test` 与全量脚本两条命令的结果」「证据脚本重跑命令与不改仓的说明」。

## 非目标

- 不改任何断言语义：不删断言、不放宽正则、不改阈值/超时/重试、不改 `problems=` 文案与 `pass`/`fail` 计数逻辑。
- 不新增门、不新增脚本内断言项、不改 `.munk/code-gates.json`、不加 `continue-on-error`、不删腿。
- 不动 `ios/**`、`VERSION`、`.github/workflows/**`、`docs/verification-matrix.md` 行数口径、Android/`shared/` 任何文件。
- 不改其它检查脚本的非同类形态（`check-ios-core.sh` / `check-ios-run-core.sh` / `check-ios-scripts.sh` / `check-android*.sh` 等零改动；如需处理另立工作项）。
- 不做真机、不改 CI 远端行为；本项结论只限「本地门与脚本形态」，不写「CI 通过」。

## 实现约束

- 形态改写必须是**行为等价替换**：`grep -q` 语义（是否存在命中）用 here-string 保持；`head -n N` 语义用末段读全量保持；`sed` 窗口切片的起止行号与正则一个字都不动。
- 证据脚本 `docs/evidence/wi_intake_27d00c5366cf423a/verify-sigpipe-redgreen.sh`：`set -euo pipefail`、幂等、无网络、临时目录用 `${TMPDIR:-/tmp}` 且退出时清理；默认只读仓（不改工作树），所有产物写到自身目录；`OLD_REF` 默认 `5925310`，取不到时允许内联旧形态字面量但须在 README 注明。
- 伪红复现必须用「首行即命中 + 后续大块」构造（实测 928,939 字节 block 稳定 `141`；小 block 只是竞态、不可作证据），且旧形态取自基线提交整行，不得手改字形。
- 证据脚本另建两条闸：`ac-no-early-exit-consumer-pipe` 的 grep 判定（注释行用 `grep -vE '^[[:space:]]*#'` 剔除），以及对 `HEAD`/基线版本做命中数对比（防止守卫恒真）。
- 提交拆分：code commit = `scripts/check-ios-shell.sh` + 证据脚本；fold commit = `docs/evidence/wi_intake_27d00c5366cf423a/` 下的日志/README。fold 只落在脚本所属既有域（`ios-shell` / `assertion-red-proof`），不新建域文件。
- 交付回执必须写明：哪些管道形态被清除（文件:行 → 新形态）、旧写法伪红的原始退出码、`--self-test` 与全量脚本两项结果、以及 22 门全绿的口径（门数/断言数）。
