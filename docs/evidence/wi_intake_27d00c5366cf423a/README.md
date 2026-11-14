# 清除 `scripts/check-ios-shell.sh` 的 SIGPIPE 伪红（wi_intake_27d00c5366cf423a）

`set -euo pipefail` 下「上游写者 → 提前退出消费者」的管道会假红：`printf '%s\n' "$block" | grep -Fq ...` 中
`grep -q` 命中首行即关读端，`printf` 收到 SIGPIPE（`141`），`pipefail` 把整条管道判失败，于是
`|| problems="$problems ..."` 写入并不存在的缺项。本项只做**行为等价替换**，断言语义 / 文案 / 阈值 / 计数逻辑零变化。

## 1. 被清除的管道形态清单（基线 `5925310` 文件:行 → 新形态）

基线 `git show 5925310:scripts/check-ios-shell.sh` 命中 10 处；现行脚本 0 处。

- 基线 `165`：`grep -E 'NSLocationWhenInUse…' "$spec_file"` → `head -n 1`
  ⇒ 现行 `165` `grep -m1 -E 'NSLocationWhenInUse…' "$spec_file"`
- 基线 `177`：`grep -E 'NSLocationAlwaysAndWhenInUse…' "$spec_file"` → `head -n 1`
  ⇒ 现行 `177` `grep -m1 -E 'NSLocationAlwaysAndWhenInUse…' "$spec_file"`
- 基线 `244`：`grep -E 'UISupportedInterfaceOrientations…' "$spec_file"` → `head -n 1`
  ⇒ 现行 `244` `grep -m1 -E 'UISupportedInterfaceOrientations…' "$spec_file"`
- 基线 `457`（`token_number_value`）：`printf` → `sed` → `head -n 1`
  ⇒ 现行 `456-458`：sed 输出先入 `first`，再取首行 `${first%%$'\n'*}`，仍是「首个匹配值」
- 基线 `535`：`sed -n "${start},${end}p" "$file"` → `grep -Eq '…L10n…'`
  ⇒ 现行 `535-536`：`window="$(sed …)"` + `grep -Eq '…L10n…' <<< "$window"`，正则与 `return 0/1` 分支不变
- 基线 `670`：`printf '%s\n' "$group_block"` → `grep -Fq "static let $member"`
  ⇒ 现行 `671`：`grep -Fq "static let $member" <<< "$group_block"`
- 基线 `673`：`printf '%s\n' "$appearance_block"` → `grep -Fq 'supportsDarkMode = true'`
  ⇒ 现行 `674`：`grep -Fq 'supportsDarkMode = true' <<< "$appearance_block"`
- 基线 `1934`：`find … -print` → `head -20`
  ⇒ 现行 `1935`：`find … -print` → `sed -n '1,20p'`（末段读全量，仍是「前 20 行」）
- 基线 `1937`：`find … -print` → `head -20`
  ⇒ 现行 `1938`：`find … -print` → `sed -n '1,20p'`
- 基线 `2110`：`sed -n '/onMapCameraChange/,/^        }/p'` → `grep -Eq 'cameraPosition…'`
  ⇒ 现行 `2111-2112`：`camera_window="$(sed …)"` + `grep -Eq '…' <<< "$camera_window"`，sed 起止行号与正则一个字未动

消费者本就读全量的管道**未动**：`102` / `499` / `849` / `1027` / `1917` / `511`（`grep -Ev` / `grep -vE` / `sed` / `grep -Fxc` / `grep -F` / `sort`，无提前退出面）。

## 2. 两向判据与实测退出码

| 判据 | 输入 | 实测 | 日志 |
|---|---|---|---|
| 守卫非空转（基线） | `git show 5925310:…` | 命中 **10** 行（剔除注释行） | `guard-hits.log` |
| 守卫清零（现行） | 现行 `scripts/check-ios-shell.sh` | 命中 **0** 行 | `guard-hits.log` |
| 旧形态伪红 | 首行即命中 + 1,180,100 字节尾巴 | 单跑管道 **exit=141**（SIGPIPE） | `old-form.log` |
| 旧形态两行（含 `problems=` 捕获） | 同一 block | exit 0 但写出 `Token 缺少 Motion.durationState;` → **假红** | `old-form.log` |
| 新形态（here-string） | 同一 block | 单跑 **exit=0**；两行 `problems=[]` | `new-form.log` |
| 仍红：缺 token | 删掉 `static let durationState` 的 block | 单跑 **exit=1**；两行打印 `Token 缺少 Motion.durationState;` | `negative-still-red.log` |
| 仍红：可读 label（sed 切片） | 合成 root ±4 行窗口 | 有 `L10n` → **0**；无 `L10n` → **1**（断言未写空） | `negative-still-red.log` |
| 仍红：相机回写（sed 切片） | 真实 `TrackMapView.swift` / 注入副本 | 真实 → `problems=[]`（无回写）；注入 `cameraPosition =` → `problems=[ onMapCameraChange 内回写了 cameraPosition;]` | `negative-still-red.log` |

旧形态与 sed / here-string 原文都是**运行时从 commit 与现行脚本逐字抽取**的，不手抄：
基线行 = `git show $OLD_REF:scripts/check-ios-shell.sh`（`OLD_REF` 默认 `5925310`）；
新形态行 / 函数体 / 相机块 = 现行 `scripts/check-ios-shell.sh` 的行号切片（行号运行时按固定串定位）。
单跑旧管道时只去掉行尾续行符 `\`，其余字形逐字不变（`old-form.log` 已打印来源原文与说明）。

## 3. 两条显式命令的结果

| 命令 | 退出码 | 结果 | 日志 |
|---|---|---|---|
| `bash scripts/check-ios-shell.sh` | `0` | `32 项断言，0 项失败`，含 `[PASS] ac-design-tokens (…; identifier: 49（冻结 33 + 新增 16）；demo/示例入口: 0)` 与 `ios shell OK`；`[PASS]` 32 / `[FAIL]` 0 | `check-ios-shell.log` |
| `bash scripts/check-ios-shell.sh --self-test` | `0` | `102 项断言，0 项失败`，末行 `self-test OK` | `check-ios-shell-self-test.log` |

`--self-test` 不在 22 门矩阵内（门 `lint-ios-shell` 只跑默认模式），故本项单独显式跑并留原始输出。

## 4. 门禁口径

- `.munk/code-gates.json` 零改动（`git diff -- .munk/code-gates.json` 为空）；矩阵为仓内既有 23 个 gate 条目
  （`lint` / `test` / … / `check-shell-expansion`），id 与 `command` 未增删改，无 `continue-on-error`、无删腿。
- 本项改动后本地已复跑并全绿（退出码均 `0`）的 18 门：`lint`、`lint-baseline`、`lint-ios-core`、`lint-ios-scripts`、
  `lint-ios-release`（49 断言）、`lint-ios-shell`（32 断言 0 失败）、`lint-ios-workflow`、`lint-ios-run-core`、
  `test`（`check-baseline` 29 断言）、`check-shared`（13 断言）、`check-gpx-export`（12 断言）、
  `check-shell-expansion`（7 断言）、`build-ios-core`、`build-ios-run-core`、`test-ios-core`、`test-ios-run-core`、
  `lint-android`（34 断言）、`lint-android-workflow`。
- 未在本目录复跑的 5 条重腿：`build-ios`、`test-ios`、`build-android`、`test-android`、`package-android`
  （xcodebuild / gradle 真构建与出包）。本项 diff 不触碰 `ios/**`、`android/**`、`shared/**`，
  这 5 条由下一阶段 Host 全量复跑仲裁；本目录**不写**「CI 通过」「22 门全绿」类未经本机实测的结论。

## 5. 重跑本证据

```bash
# 在仓库根目录；只读仓，产物只写本目录
bash docs/evidence/wi_intake_27d00c5366cf423a/verify-sigpipe-redgreen.sh
# 末行应为 `evidence: OK（两向判据全部成立）`，退出码 0
```

- 脚本 `set -euo pipefail`、幂等、无网络；临时目录在 `${TMPDIR:-/tmp}` 下并 `trap ... EXIT` 清理，日志里以 `<tmp>` 代指。
- 不修改工作树：读 `git show` 与现行脚本，合成夹具全部落在临时目录；唯一写入是本目录下的日志
  （`old-form.log` / `new-form.log` / `negative-still-red.log` / `guard-hits.log` / `summary.log` /
  `check-ios-shell.log` / `check-ios-shell-self-test.log`）。
- `OLD_REF` 取不到时脚本退回内联旧形态字面量（与基线 670-671 行同字形），并在 `old-form.log` 的
  「旧形态真源」处写明来源；此时 `guard-hits.log` 仍会对现行脚本计数，基线计数口径改用该字面量。
- 伪红复现必须用「首行即命中 + 后续大块」（本脚本 1,180,100 字节）；小 block 只是竞态，不作证据。
