# Domain: shared

`shared/` 只承载跨端数据契约与静态样例（GPX 1.1 / TCX 夹具、字符串占位、SQLite `schema.sql`），不含任何解析、持久化或缓存实现。

## 范围

- `shared/fixtures/`：合成 GPX 1.1 与 TCX（Garmin TrainingCenterDatabase/v2）小样例，各 3–6 个轨迹点，含 `ele`/`time`/`hr`/`cad` 等可断言字段；坐标虚构，标注 synthetic fixture。
- `shared/fixtures/README.md`：逐份夹具的期望解析结果（点位数、首末点坐标 / `ele` / `time`、`hr` / `cad`、可派生总时长与总距离）以及与 `schema.sql` 列的映射。
- `shared/strings/*.json`：至少一份扁平 `key → string` 的 UTF-8 JSON 占位，含 `app_name` / `tagline` / 四个 Tab 标题。
- `shared/schema.sql`：`run` / `run_point` / `food_log` / `food_cache` 四表的唯一定义（列名与顺序由 `docs/evidence/mobile-stack-spike.md` §4 冻结）。
- `scripts/check-shared.sh` + `.munk/code-gates.json` 的 `check-shared` 门：把上述契约做成可执行断言。

## 验收

- ac-shared-tree：五类产物齐全（`fixtures/sample-run.gpx`、`fixtures/sample-run.tcx`、`fixtures/README.md`、至少 1 个 `strings/*.json`、`schema.sql`）；`shared/` 内无 `.swift` / `.kt` / `.java` / `.ts` 等源码。
- ac-gpx-wellformed：`xmllint --noout` 退出 0；根元素 `gpx`、`version="1.1"`、默认命名空间 `http://www.topografix.com/GPX/1/1`。
- ac-gpx-trackpoints：`trk/trkseg` 下 ≥3 个 `trkpt`，均含合法 `lat`/`lon` 与非空 `<ele>`、ISO 8601 UTC `<time>`（`Z` 结尾），`time` 严格递增。
- ac-gpx-garmin-extension：声明 `xmlns:gpxtpx="http://www.garmin.com/xmlschemas/TrackPointExtension/v1"`；每个 `trkpt` 的 `extensions` 内 `gpxtpx:hr` 与 `gpxtpx:cad` 为数值，心率落在 40–220。
- ac-tcx-wellformed：`xmllint --noout` 退出 0；根元素 `TrainingCenterDatabase`、默认命名空间 `http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2`；含且仅含 1 个 `Activities/Activity[@Sport='Running']`。
- ac-tcx-trackpoints：`Lap` 的 `TotalTimeSeconds` / `DistanceMeters` > 0；`Lap/Track` 下 ≥3 个 `Trackpoint`，各含 `Time`、`Position/LatitudeDegrees`、`Position/LongitudeDegrees`、`AltitudeMeters`，至少 1 个含 `HeartRateBpm/Value` 与 `Cadence`。
- ac-fixtures-readme：README 声明的点数与文件实际点数相等，首末点 `time`/`ele` 逐项一致；给出 `t`←`time`、`lat`/`lon`←`trkpt@lat/lon` 或 `LatitudeDegrees`/`LongitudeDegrees`、`ele`←`ele`/`AltitudeMeters`、`hr`←`gpxtpx:hr`/`HeartRateBpm/Value`、`cad`←`gpxtpx:cad`/`Cadence` 映射。
- ac-schema-four-tables：恰好 4 张表，表名与列名/顺序严格为 `run(id, started_at, ended_at, distance_m, duration_s, avg_pace, source, gpx_path)`、`run_point(run_id, t, lat, lon, ele, hr, cad)`、`food_log(id, logged_at, barcode, name, kcal, source)`、`food_cache(barcode, json, fetched_at)`。
- ac-schema-applies-clean：空临时库执行 `schema.sql` 退出 0，重复执行仍退出 0（幂等，`CREATE TABLE IF NOT EXISTS`）；`PRAGMA table_info` 列名与顺序与上条一致。
- ac-schema-keys-and-types：`run.id`、`food_log.id`、`food_cache.barcode` 为主键或唯一约束；`run_point` 以 (`run_id`,`t`) 为主键或唯一约束且 `run_id` 外键指向 `run.id`；度量列为 `INTEGER`/`REAL`；时间列全库统一口径（epoch 秒 `INTEGER` 或 ISO 8601 `TEXT`）并在注释中写明。
- ac-strings-json：JSON 为扁平 `key → string`、UTF-8、`python3 -m json.tool` 可解析、key 不重复、值非空，至少含 `app_name`、`tagline`、`tab_run`、`tab_history`、`tab_log`、`tab_settings`；不产出 `.strings` / `strings.xml` 等平台本地化产物。
- ac-no-parser-code-and-no-seed：`shared/` 内无解析/DB/缓存实现；`ios/` 与 `android/` grep `shared/fixtures`、`sample-run.gpx`、`sample-run.tcx` 均 0 命中；夹具不进 app bundle / assets / 首屏。
- ac-check-shared-gate：`scripts/check-shared.sh`（`set -euo pipefail`、`--help` 退出 0、幂等、以仓库根为基准）逐条打印 PASS/FAIL；`.munk/code-gates.json` 追加单一 argv 的 `check-shared` 门，既有门保持不变；人为改坏夹具或列名后必须非零退出。

## 非目标

- 不实现 GPX/TCX 解析器、SQLite DAO、迁移 runner、缓存读写或 OFF 查询逻辑。
- 不把夹具、字符串或 schema 接入 iOS/Android 首屏、Tab、业务流程或 app bundle；不新增跨端测试 target 去读夹具。
- 不新增 FIT 或其它格式夹具；不做真实轨迹采集。
- 不搭多语言框架 / 本地化流水线；不做导出、schema 版本升级机制或数据迁移脚本。
- 不改 `ios/**`、`android/**`、`.github/**`、Host 托管文件；不放宽任何既有门禁。

## 实现约束

- 列名与顺序的唯一权威是 `docs/evidence/mobile-stack-spike.md` §4，不得增删列或改表名。
- 目录口径沿用 `AGENTS.md`「目录约定」：`shared/` 只含 `fixtures/`、`strings/`、`schema.sql`，不新增子目录层级。
- 命名空间硬约束：GPX 同时声明默认 `http://www.topografix.com/GPX/1/1` 与 `gpxtpx` TrackPointExtension v1；TCX 默认 `TrainingCenterDatabase/v2`。
- 夹具规模 3–6 点、总时长 ~3 分钟、总距离 ~600–900 m，便于 README 写可交叉核对的派生量。
- 断言优先用 `python3` 标准库（`sqlite3` / `xml.etree`）+ `xmllint`；`sqlite3` CLI 非唯一依赖；缺工具须显式 FAIL 并提示安装方式，不得静默跳过或降级为 `true`。
- 门禁口径：只允许在 `.munk/code-gates.json` 追加 `check-shared`（`command` 为单一 argv），禁止 `echo`/`true` 冒充，多步断言放进脚本。
- 隐私：坐标虚构、无真实健康数据；夹具不得作为任何样例数据路径进入产品。

## 最近交付证明

- workItemId: wi_ws_277fcc37f239e039（2026-11-07，pass）
- 交付：`shared/fixtures/sample-run.gpx`（GPX 1.1 + gpxtpx hr/cad）、`shared/fixtures/sample-run.tcx`（TrainingCenterDatabase/v2，Running 单 Activity）、`shared/fixtures/README.md`（期望解析结果 + 三向列映射）、`shared/strings/en.json`（六个基础键）、`shared/schema.sql`（四表冻结列序、幂等、时间列统一口径）、`scripts/check-shared.sh` 与 `.munk/code-gates.json` 新增 `check-shared` 门。
- 验证：`code_gates` 全门通过，含 `check-shared` 真实断言（XML/schema/JSON/无解析代码/无夹具引用）与 `scripts/check-baseline.sh`；未改动 `ios/**`、`android/**` 与既有门禁。
