# Android 出包目录覆盖硬化 + manifest commit 口径纠偏（wi_intake_8cf34194e113d153）

本项只修口径漂移，不重出包、不改包、不改版本：`scripts/package-android.sh` 增加「目标目录已存在默认拒绝覆盖」的
守卫（显式 `--force` 才覆盖），`scripts/check-android.sh` 补红绿两态行为反例，证据与手册把 commit 口径改成
「验收键 = sha256 + 版本 + APK 字节，`manifest.commit` = 构建时工作树 commit」。

| 事实 | 实测值 | 证据文件 |
|---|---|---|
| 目标目录已存在、不带参数（旧脚本 `707da7f:scripts/package-android.sh`） | 退出码 `0`（该拦未拦，红态） | `package-guard-red-green.log` 第 1 节 |
| 目标目录已存在、不带参数（改后脚本） | 退出码 `1`，错误含「已存在」与 `--force`，并回显既有 manifest 的 `commit=0000…0000` / `buildTime=1970-01-01T00:00:00Z`；预置哨兵文件与旧 checksums / manifest 字节不变 | `package-guard-red-green.log` 第 2 节 |
| 目标目录已存在、显式 `--force` | 退出码 `0`，APK / manifest.json / checksums.txt 为新产物，哨兵已消失 | `package-guard-red-green.log` 第 3 节 |
| 去守卫副本自检（`check-android.sh` 内实跑） | 删掉 `guard-begin/guard-end: refuse-existing-dist` 区间后同一场景退出 `0` → 红由守卫触发 | `gates.log` 中 `ac-package-guard-red-proof` |
| 同 commit 幂等（`--force` 下） | 连跑两次 `SHA256=` 相同、分发目录仍为 1 个；切 sha 变化模式仍非零退出并命中「幂等」 | `gates.log` 中 `ac-package-idempotent-under-force` |
| 代码路径零差异依据 | `git diff --name-only 2873ae2 707da7f \| grep -E '^(android\|ios\|shared\|scripts)/'` 输出为空、grep 退出码 `1` | `android-two-build-zero-diff.log` |
| 盘上 APK 字节 | 文件名与 sha256 仍为 `purepace-0.1.0-1-debug.apk` / `8b80c8e2252fbbd20ccacadfad67bf2b49410b7976926ae507282d9b242990e0`，自校验 `OK` | `android-apk-bytes-untouched.log` |
| 四条门禁 | `check-baseline` 29 项 / `check-android` 35 项 / `check-ios-release` 49 项 / `check-privacy-policy` 全绿，退出码均 `0` | `gates.log`（改动后）、`gates-before.log`（改动前 30 项对照） |
| 手册禁词与人耳 | 禁词零命中（grep 退出码 `1`）；三条人耳结论仍逐条 `pending: 待人现场` | `guide-zero-release-claims.log` |

## 1. 两轮构建与 commit 口径

| 轮次 | 构建时工作树 commit（manifest.commit） | buildTime | sha256 | 字节 |
|---|---|---|---|---|
| 第一轮 | `2873ae21ee05c890980be28a63dda1d7da573bcf` | `2026-11-14T19:59:46Z` | `8b80c8e2252fbbd20ccacadfad67bf2b49410b7976926ae507282d9b242990e0` | 与第二轮字节一致 |
| 第二轮（盘上现行产物） | `48b3e5c82c7988df8bc1a1e0c5cf949006c45602` | `2026-11-14T20:17:29Z` | `8b80c8e2252fbbd20ccacadfad67bf2b49410b7976926ae507282d9b242990e0` | 与第一轮字节一致 |

两轮 manifest 快照：`docs/evidence/wi_intake_9dc4d2c5af703568/android-manifest.json`（第一轮）与同目录
`android-manifest-ondisk-48b3e5c.json`（盘上第二轮）。`manifest.commit` 只记构建时工作树 HEAD，
不是交付 commit 的等号；两次构建在 `android/ ios/ shared/ scripts/` 上零差异（见 `android-two-build-zero-diff.log`），
因此 APK 字节一致。

## 2. 脚本行为边界

- 目标目录 `${PUREPACE_DIST_ROOT:-${TMPDIR:-/tmp}}/purepace-dist/android/<versionName>-<versionCode>/` 已存在 →
  默认 `exit 1`，回显既有 `manifest.json` 的 commit / buildTime，提示改 `PUREPACE_DIST_ROOT` 或显式 `--force`。
- `--force` 只解除「目录已存在」这一层；同 commit + sha256 变化仍非零退出（幂等断言未放宽）。
- CLI 契约不变：`--help` → 0（帮助文本含 `--force` 与「拒绝覆盖」）、未知参数 → 2、`PUREPACE_DIST_ROOT`
  指向仓库内仍被拒（「仓库外」断言保留）。

## 3. 边界

- 未改产品代码（`ios/`、`android/`、`shared/`）、未改 `VERSION`、未改 UI 与 design tokens、未改
  `.github/workflows/`、未新增 CI 腿、未改 `.munk/code-gates.json` 门定义、未改 `docs/verification-matrix.md`。
- 未执行真实出包：盘上 APK 未改名 / 未删除 / 未搬迁 / 未覆盖；新产物只出现在 `mktemp` 沙箱目录（已清理）。
