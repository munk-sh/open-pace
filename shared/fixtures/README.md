# shared/fixtures

两份**合成**夹具，用于冻结 GPX 1.1 与 TCX v2 的解析契约。坐标、海拔、心率、步频全部虚构，
不含任何真实用户轨迹或健康数据；夹具不进入 App bundle，也不被 `ios/`、`android/` 引用。

- `sample-run.gpx` — GPX 1.1，`trk/trkseg/trkpt` + `ele` + `time`，Garmin `TrackPointExtension`（`gpxtpx:hr`、`gpxtpx:cad`）
- `sample-run.tcx` — Garmin `TrainingCenterDatabase/v2`，`Activities/Activity[@Sport='Running']` + `Lap` + `Track/Trackpoint`

## 期望解析结果（机器可校验块）

下列 `key: value` 为断言脚本（`scripts/check-shared.sh`）逐项比对的目标，改动夹具时必须同步更新。

```text
gpx_points: 4
gpx_first_time: 2026-01-01T08:00:00Z
gpx_last_time: 2026-01-01T08:03:00Z
gpx_first_ele: 12.0
gpx_last_ele: 13.8
gpx_first_hr: 112
gpx_last_hr: 147
gpx_first_cad: 82
gpx_last_cad: 85
tcx_points: 4
tcx_first_time: 2026-01-01T08:00:00Z
tcx_last_time: 2026-01-01T08:03:00Z
tcx_first_ele: 12.0
tcx_last_ele: 13.8
tcx_first_hr: 112
tcx_last_hr: 147
tcx_first_cad: 82
tcx_last_cad: 85
derived_duration_s: 180
derived_distance_m: 691.2
```

- 两份夹具是同一段 4 点、3 分钟的合成跑步：采样间隔 60 s，`trkpt` 与 `Trackpoint` 一一对应。
- 逐点数值（首→末）：`ele` 12.0 → 12.5 → 13.2 → 13.8；`hr` 112 → 128 → 141 → 147；`cad` 82 → 84 → 86 → 85。
- 可派生总时长 = 末点 time − 首点 time = 180 s（等于 TCX `Lap/TotalTimeSeconds`）。
- 可派生总距离 ≈ 691.2 m（Haversine 对 4 个坐标累加，等于 TCX `Lap/DistanceMeters`；实测 691.16 m，夹具取 691.2）。
- 平均配速 ≈ 260 s/km（180 s / 0.691 km），对应 `run.avg_pace`。

## 字段 → `shared/schema.sql` 列映射

| schema 列 | GPX 1.1 取值 | TCX v2 取值 |
|---|---|---|
| `run_point.t` | `trkpt/time`（epoch 秒，解析后统一口径） | `Trackpoint/Time` |
| `run_point.lat` | `trkpt@lat` | `Trackpoint/Position/LatitudeDegrees` |
| `run_point.lon` | `trkpt@lon` | `Trackpoint/Position/LongitudeDegrees` |
| `run_point.ele` | `trkpt/ele` | `Trackpoint/AltitudeMeters` |
| `run_point.hr` | `trkpt/extensions/gpxtpx:TrackPointExtension/gpxtpx:hr` | `Trackpoint/HeartRateBpm/Value` |
| `run_point.cad` | `trkpt/extensions/gpxtpx:TrackPointExtension/gpxtpx:cad` | `Trackpoint/Cadence` |
| `run.duration_s` | 末点 `time` − 首点 `time` | `Lap/TotalTimeSeconds` |
| `run.distance_m` | 相邻 `trkpt` 坐标 Haversine 累加 | `Lap/DistanceMeters` |
| `run.started_at` | 首点 `time` | `Lap@StartTime` / 首点 `Time` |
| `run.ended_at` | 末点 `time` | `Lap@StartTime` + `TotalTimeSeconds` |
| `run.source` | `gpx` | `tcx` |
| `run.gpx_path` | 导入/导出后的本地 GPX 文件路径 | 导出后生成的 GPX 路径 |

命名空间（解析时必须精确匹配）：

- GPX 默认命名空间 `http://www.topografix.com/GPX/1/1`，扩展命名空间 `xmlns:gpxtpx="http://www.garmin.com/xmlschemas/TrackPointExtension/v1"`。
- TCX 默认命名空间 `http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2`。
