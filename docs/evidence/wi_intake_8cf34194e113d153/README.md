# Android 出包目录覆盖硬化 + sha256 口径纠偏（wi_intake_8cf34194e113d153）

本项只修口径漂移，不重出包、不改包、不改版本：

1. `scripts/package-android.sh` 在目标 `<versionName>-<versionCode>/` 已存在时**自动改用递增兄弟目录**（`…-b<N>`），
   绝不覆盖 / 删除 / 改名既有目录，零参数即可通过（不引入任何开关）。
2. sha256 判据收口到**同一产物目录内自校验**：Android APK 构建跨环境不可复现（CI 已实测两个不同 sha256），
   因此不再拿任何跨构建 / 跨机器的 sha256 互相比对。
3. 证据与手册把验收键固定为「sha256 + 版本 + APK 字节」，`manifest.commit` = **构建时工作树 commit**
   （盘上 `48b3e5c`，与 `2873ae2` 代码路径零差异），并给出仓外持久交付目录。

| 事实 | 实测值 | 证据文件 |
|---|---|---|
| 干净现场（无既有版本目录） | 用固定名 `<versionName>-<versionCode>/`，退出码 `0` | `package-existing-new.log` |
| 既有版本目录现场 + 零参数（新脚本） | 退出码 `0`；打印「本次实际输出目录」并落到 `0.1.0-1-b2`；既有目录三个文件 sha256 逐字不变 | `package-existing-dir-red-green.log` 第 2 节 |
| 再跑一次（序号单调） | 退出码 `0`，落到 `0.1.0-1-b3`（已存在最大序号 2 + 1）；基名目录与 `-b2` 均未被改写 | `package-existing-dir-red-green.log` 第 3 节 |
| 旧脚本对照（`707da7f:scripts/package-android.sh`） | 退出码 `0` 却就地把既有目录覆盖掉（哨兵消失、sha256 变化）→ 红由守卫消除 | `package-existing-dir-red-green.log` 第 1 节 |
| 去守卫副本自检（`check-android.sh` 内实跑） | 删掉 `guard-begin/guard-end: preserve-existing-dist` 区间后同一现场退出 `0` 且覆盖既有目录 → 红由守卫触发 | `check-android-full.log` 中 `ac-package-existing-dir-red-proof` |
| 跨构建 sha256 差异的判据归属 | 旧「跨构建 sha 必须相等」副本：sha 变化时退出 `1`（红）；新判据同场景退出 `0` 且新目录自校验 `OK`（绿） | `package-sha-judgement-red-green.log` |
| 真实零参数出包（盘上既有 `0.1.0-1/`） | 每次均 `exit=0`，依次落 `-b2…-b5`（去重后末次落 `-b2`），APK sha256 全为 `8b80c8e2…990e0` | `package-real-run-summary.log`、`package-real-run-1.log`、`package-real-run-2.log` |
| 同机重跑 / 跨机构建 | 本机 5 个目录 sha256 全同（`8b80c8e2…`），字节均 `11760611`；CI run 43634680117 → `11f3adce…`、43636713531 → `66576b94…` | `android-artifact-sha-scope.log` |
| 仓外持久交付目录 | `/Users/zhutao/purepace-dist/android/0.1.0-1/` 三件：APK `8b80c8e2…990e0`（`11760611` 字节）、`manifest.json` `9153dd0c…bedc`、`checksums.txt` `d93413e2…f7b1`；逐件与出包现场 `cmp` identical，目录内自校验 `OK` | `android-artifact-sha-scope.log` 第 2–3 节、`android-apk-bytes-untouched.log` 第 3 节 |
| 多余副本处置 | 方案 a：`-b2…-b5` 逐条记录「目录名 + sha256 + 字节数」后删除（持久目录已留存同等字节）；清理策略仍是本项非目标 | `android-artifact-sha-scope.log` 第 5–6 节 |
| CLI 契约 | `--help` → `0`（帮助含「兄弟目录」与 `-b<N>`）、未知参数 → `2`、`PUREPACE_DIST_ROOT` 指向仓库内仍被拒 | `check-android-full.log` 中 `ac-package-cli-contract-preserved` |
| 代码路径零差异依据 | `git diff --name-only 2873ae2 707da7f \| grep -E '^(android\|ios\|shared\|scripts)/'` 输出为空、grep 退出码 `1` | `android-two-build-zero-diff.log` |
| 盘上 APK 字节 | 出包现场基名目录文件名与 sha256 仍为 `purepace-0.1.0-1-debug.apk` / `8b80c8e2…990e0`，自校验 `OK`，mtime 仍 `Nov 15 04:17` | `android-apk-bytes-untouched.log` |
| 四条门禁 | `check-baseline` 29 项 / `check-android` 34 项 / `check-ios-release` 49 项 / `check-privacy-policy` 全绿，退出码均 `0` | `gates.log`（改动后）、`gates-before.log`（改动前 `check-android` 30 项对照） |
| 手册禁词与人耳 | 禁词零命中（grep 退出码 `1`）；三条人耳结论仍逐条 `pending: 待人现场`；第 3 节新增「机器前置」只写做法与判据 | `guide-zero-release-claims.log` |

## 1. 两轮构建与 commit 口径

| 轮次 | 构建时工作树 commit（manifest.commit） | buildTime | sha256 | 字节 |
|---|---|---|---|---|
| 第一轮 | `2873ae21ee05c890980be28a63dda1d7da573bcf` | `2026-11-14T19:59:46Z` | `8b80c8e2252fbbd20ccacadfad67bf2b49410b7976926ae507282d9b242990e0` | 与第二轮字节一致（本地两次构建恰好相同） |
| 第二轮（盘上现行产物） | `48b3e5c82c7988df8bc1a1e0c5cf949006c45602` | `2026-11-14T20:17:29Z` | `8b80c8e2252fbbd20ccacadfad67bf2b49410b7976926ae507282d9b242990e0` | 与第一轮字节一致（同上） |

两轮 manifest 快照：`docs/evidence/wi_intake_9dc4d2c5af703568/android-manifest.json`（第一轮）与同目录
`android-manifest-ondisk-48b3e5c.json`（盘上第二轮）。`manifest.commit` 只记构建时工作树 HEAD，
不是交付 commit 的等号；两次构建在 `android/ ios/ shared/ scripts/` 上零差异（见 `android-two-build-zero-diff.log`）。
验收键是 sha256 + 版本 + APK 字节三者，不以 `manifest.commit` 等号判真伪；上表 sha256 只对应本机交付的这一个文件，
跨机构建实测就是不同 sha256（见「同机重跑 / 跨机构建」行），不得据此推断「重跑必得同一 sha」或「重跑必得新 sha」。

## 2. 脚本行为边界

- 目标目录 `${PUREPACE_DIST_ROOT:-${TMPDIR:-/tmp}}/purepace-dist/android/<versionName>-<versionCode>/` **不存在** → 用固定名。
- 该目录**已存在** → 选 `<versionName>-<versionCode>-b<N>`（基名视为序号 1，`N` = 已存在最大序号 + 1），
  绝不覆盖 / 删除 / 改名既有目录；stdout 打印「info: 本次实际输出目录: …」与 `DIST_DIR=<实际目录>`，调用方以 `DIST_DIR=` 为准。
- 序号竞争（同一时刻别的进程已建同名兄弟目录）→ `[ -e ]` 判据拒绝，脚本非零退出，不写半截产物。
- sha256 判据只在本次产物目录内：写完 `checksums.txt` 立即 `shasum -a 256 -c` 自校验，与本次 APK 字节不一致即非零退出；
  跨构建 / 跨环境的 sha256 差异**不比对**（旧判据红态见 `package-sha-judgement-red-green.log`）。
- CLI 契约不变：`--help` → `0`（帮助含「兄弟目录」与 `-b<N>`）、未知参数 → `2`、`PUREPACE_DIST_ROOT`
  指向仓库内仍被拒（「仓库外」断言保留）。

## 3. 交付文件位置

- 仓外持久目录（收货用，不随 `$TMPDIR` 清理）：`/Users/zhutao/purepace-dist/android/0.1.0-1/`
  —— APK `8b80c8e2…990e0` / `11760611` 字节、`manifest.json`、`checksums.txt`；复算与 `cmp` 逐件 identical。
- 出包现场（`${TMPDIR}/purepace-dist/android/0.1.0-1/`）只作复原对照；它存在同名要求时脚本会自动改用 `-b<N>` 兄弟目录。
- 验收只需在产物目录内执行 `shasum -a 256 -c checksums.txt`（输出 `…: OK`，退出码 0）。

## 4. 边界

- 未改产品代码（`ios/`、`android/`、`shared/`）、未改 `VERSION`、未改 UI 与 design tokens、未改
  `.github/workflows/`、未新增 CI 腿、未改 `.munk/code-gates.json` 门定义、未改 `docs/verification-matrix.md`。
- 未重出交付包：盘上基名目录 `0.1.0-1/` 未改名 / 未删除 / 未搬迁 / 未覆盖，APK sha256 保持 `8b80c8e2…990e0`；
  后续零参数出包只写进 `0.1.0-1-b<N>` 兄弟目录，字节与之一致。
- 未把覆盖硬化扩成保留 / 清理策略：不自动删旧目录、不加归档逻辑；本项只按方案 a 一次性清理同名同 sha 的历史副本。
