# Shared GPX/TCX 夹具、字符串占位与 SQLite schema

> 本文件只覆盖 WorkSet 子项 `key: shared-fixtures`。WorkSet 级叙事以 `.munk/work-set/overview.md` 为准，此处不复制。

## 范围

在仓库根新建 `shared/`，交付四类**纯静态数据契约**（不含任何解析/持久化实现）：

1. **GPX 1.1 夹具** `shared/fixtures/sample-run.gpx`：合成小样例（≥3 个轨迹点），含 `trk/trkseg/trkpt`、每点 `ele` 与 `time`（ISO 8601 UTC），并含 Garmin `TrackPointExtension` 命名空间（`gpxtpx:hr`、`gpxtpx:cad`）。
2. **TCX 夹具** `shared/fixtures/sample-run.tcx`：合成小样例，Garmin `TrainingCenterDatabase/v2` 命名空间，含 `Activities/Activity[@Sport='Running']`、`Lap`（`TotalTimeSeconds`、`DistanceMeters`）、`Track/Trackpoint`（`Time`、`Position/LatitudeDegrees`、`Position/LongitudeDegrees`、`AltitudeMeters`、`HeartRateBpm/Value`、`Cadence`）。
3. **夹具说明** `shared/fixtures/README.md`：逐份列出**期望解析结果**（点位数、首末点坐标 / ele / time、hr / cad 取值、可派生总时长与总距离），并说明各字段与 `schema.sql` 列的映射。
4. **字符串占位** `shared/strings/` 下至少 1 个扁平 key→string 的 UTF-8 JSON（含 `app_name` / `tagline` / 四个 Tab 标题等基础键），以及 **`shared/schema.sql`**：按 `docs/evidence/mobile-stack-spike.md` §4 定义 `run` / `run_point` / `food_log` / `food_cache` 四表。

同时新增可执行契约断言脚本 `scripts/check-shared.sh`，并在 `.munk/code-gates.json` 追加一门独立门禁。

## 验收标准

- ac-shared-tree: `shared/` 下存在 `fixtures/sample-run.gpx`、`fixtures/sample-run.tcx`、`fixtures/README.md`、至少 1 个 `strings/*.json`、`schema.sql`；`shared/` 内不存在 `.swift` / `.kt` / `.java` / `.ts` 等源码文件。
- ac-gpx-wellformed: `xmllint --noout shared/fixtures/sample-run.gpx` 退出码 0；根元素为 `gpx` 且 `version="1.1"`，默认命名空间为 `http://www.topografix.com/GPX/1/1`。
- ac-gpx-trackpoints: `trk/trkseg` 下至少 3 个 `trkpt`，每个都有 `lat` 与 `lon` 属性（数值、在合法经纬度范围内），且每个都含非空 `<ele>` 与 `<time>`（ISO 8601 UTC，以 `Z` 结尾）；`trkpt` 的 `time` 严格递增。
- ac-gpx-garmin-extension: 根元素声明 `xmlns:gpxtpx="http://www.garmin.com/xmlschemas/TrackPointExtension/v1"`；每个 `trkpt` 含 `<extensions><gpxtpx:TrackPointExtension>`，其中 `gpxtpx:hr` 与 `gpxtpx:cad` 均为数值且心率落在合理区间（40–220）。
- ac-tcx-wellformed: `xmllint --noout shared/fixtures/sample-run.tcx` 退出码 0；根元素为 `TrainingCenterDatabase`，默认命名空间为 `http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2`；含且仅含 1 个 `Activities/Activity`，其 `Sport="Running"`。
- ac-tcx-trackpoints: `Activity` 下 `Lap` 含数值 `TotalTimeSeconds`（>0）与 `DistanceMeters`（>0）；`Lap/Track` 下至少 3 个 `Trackpoint`，每个含 `Time`、`Position/LatitudeDegrees`、`Position/LongitudeDegrees`、`AltitudeMeters`，且至少 1 个含 `HeartRateBpm/Value` 与 `Cadence`。
- ac-fixtures-readme: `shared/fixtures/README.md` 对两份夹具各给出期望解析结果，其中声明的轨迹点数与文件实际点数相等（GPX `trkpt` 数、TCX `Trackpoint` 数），声明的首末点 `time` / `ele` 与文件实际值逐项一致；并给出 GPX↔TCX↔`schema.sql` 列映射（`t`←`time`、`lat`/`lon`←`trkpt@lat/lon` 或 `LatitudeDegrees`/`LongitudeDegrees`、`ele`←`ele`/`AltitudeMeters`、`hr`←`gpxtpx:hr`/`HeartRateBpm/Value`、`cad`←`gpxtpx:cad`/`Cadence`）。
- ac-schema-four-tables: `shared/schema.sql` 恰好定义 4 张表，表名与列名/顺序严格为 `run(id, started_at, ended_at, distance_m, duration_s, avg_pace, source, gpx_path)`、`run_point(run_id, t, lat, lon, ele, hr, cad)`、`food_log(id, logged_at, barcode, name, kcal, source)`、`food_cache(barcode, json, fetched_at)`；不得多出第 5 张表或重命名任何列。
- ac-schema-applies-clean: 用 `python3` 标准库 `sqlite3`（或 `sqlite3` CLI）在空临时库上执行 `shared/schema.sql` 退出码 0，重复执行第二次仍退出码 0（幂等，`CREATE TABLE IF NOT EXISTS`）；`PRAGMA table_info(<表>)` 返回的列名与顺序与 ac-schema-four-tables 完全一致。
- ac-schema-keys-and-types: `run.id`、`food_log.id`、`food_cache.barcode` 为主键（或唯一约束），`run_point` 以 (`run_id`, `t`) 为主键或唯一约束；`run_point.run_id` 有外键指向 `run.id`；`lat`/`lon`/`ele`/`distance_m`/`duration_s`/`kcal` 等度量列为 `INTEGER` 或 `REAL`，时间列（`started_at`/`ended_at`/`t`/`logged_at`/`fetched_at`）在全库统一采用同一口径，并在 `schema.sql` 注释中写明（epoch 秒 `INTEGER` 或 ISO 8601 `TEXT`，二选一）。
- ac-strings-json: `shared/strings/` 下 JSON 文件为扁平 `key → string` 对象，UTF-8、可被 `python3 -m json.tool` 解析，key 不重复、值非空，且至少包含 `app_name`、`tagline`、`tab_run`、`tab_history`、`tab_log`、`tab_settings` 六个键；不生成 `.strings` / `strings.xml` 等平台本地化产物，不引入多语言框架。
- ac-no-parser-code-and-no-seed: `shared/` 内无 GPX/TCX 解析、SQLite 访问或缓存实现；`ios/` 与 `android/` 下 grep `shared/fixtures`、`sample-run.gpx`、`sample-run.tcx` 结果为 0 命中；夹具未进入任何 app bundle / assets / 首屏，仓库中不存在引用夹具的样例数据路径。
- ac-check-shared-gate: 新增 `scripts/check-shared.sh`（`set -euo pipefail`、支持 `--help` 退出 0、幂等、路径以仓库根为基准）真实断言上述各条并逐条打印 PASS/FAIL；`.munk/code-gates.json` 追加一门 `check-shared`（`command` 为单一 argv，无 `&&`/`|`/`;`/重定向），既有门（尤其 `test` → `scripts/check-baseline.sh`）保持不变；本机 `bash scripts/check-shared.sh` 退出码 0，人为改坏（删一个 `trkpt` 的 `time`、改一个列名）后非零退出。

## 非目标

- 不实现任何 GPX/TCX 解析器、SQLite DAO、迁移 runner、缓存读写或 OFF 查询逻辑（属阶段 2/3）。
- 不把夹具、字符串或 schema 接进 iOS/Android 首屏、Tab、业务流程或 app bundle；不新增 iOS/Android 测试 target 去读夹具。
- 不新增 FIT 或其它格式夹具，不做真实轨迹采集（夹具为合成数据，坐标虚构）。
- 不搭建多语言框架 / 本地化流水线，只放一份占位 JSON。
- 不做导出功能、不做 schema 版本升级机制、不做数据迁移脚本。
- 不改 `ios/**`、`android/**`、`.github/**`、Host 托管文件；不新建/修改 git remote；不声称 CI 绿或真机验证。
- 不重写 `scripts/check-baseline.sh` 既有断言，不放宽任何既有门禁。

## 实现约束

- **上游依据**：`docs/evidence/mobile-stack-spike.md` §4「数据所有权」是 `schema.sql` 列名与顺序的唯一权威（spike 原文：`run(id, started_at, ended_at, distance_m, duration_s, avg_pace, source, gpx_path)`、`run_point(run_id, t, lat, lon, ele, hr, cad)`、`food_log(id, logged_at, barcode, name, kcal, source)`、`food_cache(barcode, json, fetched_at)`）。不得自行增删列或改表名。
- **目录口径**：`AGENTS.md`「目录约定」已冻结 `shared/` = `fixtures/`（gpx/tcx）、`strings/`、`schema.sql`、`fixtures/README.md`；本项按此落位，不新增 `shared/` 子目录层级。
- **前置 skill**：`repo-bootstrap` 已在 `wi_ws_6035fb0cde33a0a3` 完成（AGENTS.md 四节 + 官方 skill 路由已在位，`.agents/skills/swiftui-pro`、`.agents/skills/android-cli`），本项**不重复执行 repo 初始化**，也不涉及 `ui-baseline`。
- **命名空间硬约束**：GPX `xmlns:gpxtpx="http://www.garmin.com/xmlschemas/TrackPointExtension/v1"`；TCX 默认命名空间 `http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2`。GPX 须同时声明默认命名空间 `http://www.topografix.com/GPX/1/1`。
- **数据规模**：每份夹具 3–6 个轨迹点即可，够断言 `ele`/`time`/`hr`/`cad` 与首末值；总时长 ~3 分钟、总距离 ~600–900 m 量级，便于 README 写可交叉核对的派生量。
- **隐私**：坐标虚构（非真实用户轨迹），README 中标注 synthetic fixture；不写入任何真实健康数据。
- **工具可用性（本机已实测）**：`xmllint` 在 `/usr/bin/xmllint`；`python3` 可用（stdlib `sqlite3` / `xml.etree` 足以完成全部断言）；`sqlite3` CLI 本机来自 Android platform-tools，**不要把它作为唯一依赖**，断言优先用 `python3`，缺工具时显式 FAIL 并提示安装方式，不得静默跳过或降级为 `true`。
- **门禁口径**：只允许在 `.munk/code-gates.json` **追加**一门 `check-shared`；`command` 必须是单一 argv（`bash scripts/check-shared.sh`），不得用 `echo` / `true` 冒充；既有 10 门不得删改。
- **红线**：不改 Host 托管文件（`goal.md`、`handoff.md`、`now.md`、`product.json`、`close-proposal.json`）；不出现任何跑步/计时/播报等业务实现；首屏不得出现夹具样例数据。
