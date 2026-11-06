-- PurePace 本地存储 schema（数据契约，不含任何访问/迁移实现）。
-- 时间口径：全库时间列统一为 epoch 秒（UTC），类型 INTEGER。
--   覆盖 run.started_at / run.ended_at / run_point.t / food_log.logged_at / food_cache.fetched_at。
-- 幂等：全部使用 CREATE TABLE IF NOT EXISTS，可重复执行。
-- 权威来源：docs/evidence/mobile-stack-spike.md §4「数据所有权」。

CREATE TABLE IF NOT EXISTS run (
  id INTEGER PRIMARY KEY,
  started_at INTEGER NOT NULL,
  ended_at INTEGER NOT NULL,
  distance_m REAL NOT NULL,
  duration_s INTEGER NOT NULL,
  avg_pace REAL,
  source TEXT NOT NULL,
  gpx_path TEXT
);

CREATE TABLE IF NOT EXISTS run_point (
  run_id INTEGER NOT NULL,
  t INTEGER NOT NULL,
  lat REAL NOT NULL,
  lon REAL NOT NULL,
  ele REAL,
  hr INTEGER,
  cad INTEGER,
  PRIMARY KEY (run_id, t),
  FOREIGN KEY (run_id) REFERENCES run (id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS food_log (
  id INTEGER PRIMARY KEY,
  logged_at INTEGER NOT NULL,
  barcode TEXT,
  name TEXT NOT NULL,
  kcal REAL,
  source TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS food_cache (
  barcode TEXT PRIMARY KEY,
  json TEXT NOT NULL,
  fetched_at INTEGER NOT NULL
);
