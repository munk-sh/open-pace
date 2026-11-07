#!/usr/bin/env bash
# shared/ 数据契约断言（.munk/code-gates.json 的 check-shared 门真实执行体）。
# 逐条校验 shared/ 下 GPX / TCX 夹具、fixtures README、字符串占位与 SQLite schema，
# 以及 code-gates 中 check-shared 门的形状；任一条失败即非零退出，不静默跳过、不用 true 冒充。
set -euo pipefail

usage() {
  cat <<'EOF'
用法: scripts/check-shared.sh [--help]

对 shared/ 静态数据契约做断言并按 ac-* 逐条打印 PASS/FAIL：
  - ac-shared-tree          shared/ 目录树齐全且不含任何源码文件
  - ac-gpx-wellformed       xmllint 通过、根 gpx@version=1.1、GPX 1.1 默认命名空间
  - ac-gpx-trackpoints      >=3 个 trkpt，lat/lon/ele/time 合法且 time 严格递增
  - ac-gpx-garmin-extension gpxtpx 命名空间与 hr/cad 扩展齐全（hr 40-220）
  - ac-tcx-wellformed       xmllint 通过、TrainingCenterDatabase v2、唯一 Running Activity
  - ac-tcx-trackpoints      Lap 时长/距离 > 0，>=3 个 Trackpoint 含 Position/Altitude/HR/Cadence
  - ac-fixtures-readme      README 声明的点位数/首末值/派生量与实际夹具逐项一致，含列映射
  - ac-schema-four-tables   恰好 4 张表，表名与列名顺序与 spike §4 完全一致
  - ac-schema-applies-clean schema.sql 在空库上可执行且重复执行幂等，列顺序稳定
  - ac-schema-keys-and-types 主键/唯一约束、run_point 外键、度量与时间列类型口径
  - ac-strings-json         strings/*.json 为扁平 key→非空 string，必备键齐全
  - ac-no-parser-code-and-no-seed shared/ 无解析/持久化实现，ios/ 与 android/ 零引用夹具
  - ac-check-shared-gate    scripts/check-shared.sh 存在可执行，本门为单一 argv，既有 test 门未改

选项:
  -h, --help   显示本帮助并退出 0

退出码:
  0  全部断言通过
  1  存在失败断言
  2  参数非法
EOF
}

case "${1:-}" in
  -h|--help)
    usage
    exit 0
    ;;
  "")
    ;;
  *)
    echo "check-shared: 未知参数 '$1'（使用 --help 查看用法）" >&2
    exit 2
    ;;
esac

if [ "$#" -gt 1 ]; then
  echo "check-shared: 只接受一个参数（使用 --help 查看用法）" >&2
  exit 2
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
cd "$repo_root"

CHECKS=0
FAILURES=0

pass() {
  CHECKS=$((CHECKS + 1))
  printf '[PASS] %s\n' "$1"
}

fail() {
  CHECKS=$((CHECKS + 1))
  FAILURES=$((FAILURES + 1))
  printf '[FAIL] %s: %s\n' "$1" "$2"
}

# ------------------------------------------------------------ 依赖工具
missing_tools=""
if ! command -v python3 >/dev/null 2>&1; then
  missing_tools="$missing_tools python3"
fi
if ! command -v xmllint >/dev/null 2>&1; then
  missing_tools="$missing_tools xmllint"
fi
if [ -n "$missing_tools" ]; then
  fail "ac-tools-available" "缺少依赖工具:${missing_tools}（xmllint: xcode-select --install；python3: 安装 CPython 3，不得静默跳过）"
fi

# ------------------------------------------------------------ 数据契约断言
if command -v python3 >/dev/null 2>&1; then
  check_py="$(mktemp "${TMPDIR:-/tmp}/purepace-check-shared.XXXXXX")"
  trap 'rm -f "$check_py"' EXIT
  cat > "$check_py" <<'PYCHECK'
import contextlib
import datetime
import json
import math
import os
import re
import shutil
import sqlite3
import subprocess
import tempfile
import xml.etree.ElementTree as ET

GPX = "shared/fixtures/sample-run.gpx"
TCX = "shared/fixtures/sample-run.tcx"
FIX_README = "shared/fixtures/README.md"
STRINGS_DIR = "shared/strings"
SCHEMA = "shared/schema.sql"
GATES = ".munk/code-gates.json"
CHECK_SCRIPT = "scripts/check-shared.sh"

GPX_NS = "http://www.topografix.com/GPX/1/1"
TPX_NS = "http://www.garmin.com/xmlschemas/TrackPointExtension/v1"
TCX_NS = "http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2"

G = "{%s}" % GPX_NS
X = "{%s}" % TPX_NS
T = "{%s}" % TCX_NS

ISO_UTC = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?Z$")
SOURCE_EXT = {
    ".swift", ".kt", ".kts", ".java", ".ts", ".tsx", ".js", ".m", ".mm",
    ".py", ".rb", ".go", ".cs", ".dart", ".c", ".cc", ".cpp", ".h", ".hpp",
}
EXPECTED_COLUMNS = {
    "run": ["id", "started_at", "ended_at", "distance_m", "duration_s", "avg_pace", "source", "gpx_path"],
    "run_point": ["run_id", "t", "lat", "lon", "ele", "hr", "cad"],
    "food_log": ["id", "logged_at", "barcode", "name", "kcal", "source"],
    "food_cache": ["barcode", "json", "fetched_at"],
}
TIME_COLUMNS = [
    ("run", "started_at"),
    ("run", "ended_at"),
    ("run_point", "t"),
    ("food_log", "logged_at"),
    ("food_cache", "fetched_at"),
]

RESULTS = []


def emit(ac, ok, message=""):
    RESULTS.append(("PASS" if ok else "FAIL", ac, re.sub(r"[\t\r\n]+", " ", str(message))))


def run(ac, fn):
    try:
        fn()
        emit(ac, True)
    except AssertionError as exc:
        emit(ac, False, str(exc) or "断言失败")
    except Exception as exc:  # noqa: BLE001 - 任何异常都必须显式 FAIL
        emit(ac, False, "%s: %s" % (type(exc).__name__, exc))


def read_text(path):
    with open(path, "r", encoding="utf-8") as handle:
        return handle.read()


def parse_xml(path):
    return ET.parse(path).getroot()


def fmt_time(value):
    return value.astimezone(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def parse_iso(value):
    return datetime.datetime.strptime(value[:19], "%Y-%m-%dT%H:%M:%S").replace(
        tzinfo=datetime.timezone.utc
    )


def haversine(a, b):
    lat1, lon1 = a
    lat2, lon2 = b
    dlat = math.radians(lat2 - lat1)
    dlon = math.radians(lon2 - lon1)
    h = math.sin(dlat / 2) ** 2 + math.cos(math.radians(lat1)) * math.cos(
        math.radians(lat2)
    ) * math.sin(dlon / 2) ** 2
    return 2 * 6371000.0 * math.asin(math.sqrt(h))


def gpx_points():
    root = parse_xml(GPX)
    points = []
    for trkpt in root.findall("./%strk/%strkseg/%strkpt" % (G, G, G)):
        ele = trkpt.find("./%sele" % G)
        tm = trkpt.find("./%stime" % G)
        tpx = trkpt.find("./%sextensions/%sTrackPointExtension" % (G, X))
        hr = tpx.find("./%shr" % X) if tpx is not None else None
        cad = tpx.find("./%scad" % X) if tpx is not None else None
        points.append({
            "lat": trkpt.get("lat"),
            "lon": trkpt.get("lon"),
            "ele": ele.text.strip() if ele is not None and ele.text else None,
            "time": tm.text.strip() if tm is not None and tm.text else None,
            "hr": hr.text.strip() if hr is not None and hr.text else None,
            "cad": cad.text.strip() if cad is not None and cad.text else None,
        })
    return points


def tcx_lap():
    root = parse_xml(TCX)
    activities = root.findall("./%sActivities/%sActivity" % (T, T))
    assert len(activities) == 1, "Activity 数量应为 1，实际 %d" % len(activities)
    laps = activities[0].findall("./%sLap" % T)
    assert laps, "Activity 下缺少 Lap"
    return root, activities[0], laps[0]


def tcx_points():
    _, _, lap = tcx_lap()
    points = []
    for tp in lap.findall("./%sTrack/%sTrackpoint" % (T, T)):
        tm = tp.find("./%sTime" % T)
        pos = tp.find("./%sPosition" % T)
        lat = pos.find("./%sLatitudeDegrees" % T) if pos is not None else None
        lon = pos.find("./%sLongitudeDegrees" % T) if pos is not None else None
        alt = tp.find("./%sAltitudeMeters" % T)
        hrv = tp.find("./%sHeartRateBpm/%sValue" % (T, T))
        cad = tp.find("./%sCadence" % T)
        points.append({
            "time": tm.text.strip() if tm is not None and tm.text else None,
            "lat": lat.text.strip() if lat is not None and lat.text else None,
            "lon": lon.text.strip() if lon is not None and lon.text else None,
            "ele": alt.text.strip() if alt is not None and alt.text else None,
            "hr": hrv.text.strip() if hrv is not None and hrv.text else None,
            "cad": cad.text.strip() if cad is not None and cad.text else None,
        })
    return points


def clean_float(value, label):
    assert value is not None and value != "", "缺少 %s" % label
    try:
        return float(value)
    except ValueError:
        raise AssertionError("%s 不是数值: %r" % (label, value))


def clean_int(value, label):
    number = clean_float(value, label)
    assert number == int(number), "%s 不是整数: %r" % (label, value)
    return int(number)


@contextlib.contextmanager
def temp_db():
    tmpdir = tempfile.mkdtemp(prefix="purepace-shared-")
    conn = sqlite3.connect(os.path.join(tmpdir, "check.sqlite"))
    try:
        yield conn
    finally:
        conn.close()
        shutil.rmtree(tmpdir, ignore_errors=True)


def table_names(conn):
    rows = conn.execute(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name"
    )
    return [row[0] for row in rows]


def column_map(conn, table):
    return [(row[1], (row[2] or "").upper(), row[5]) for row in conn.execute("PRAGMA table_info(%s)" % table)]


def apply_schema(conn):
    sql = read_text(SCHEMA)
    conn.executescript(sql)
    return sql


# ---------------------------------------------------------------- ac-shared-tree
def check_shared_tree():
    required = [GPX, TCX, FIX_README, SCHEMA, CHECK_SCRIPT]
    missing = [path for path in required if not os.path.isfile(path)]
    assert not missing, "缺少文件: %s" % ", ".join(missing)
    assert os.path.isdir(STRINGS_DIR), "缺少 %s" % STRINGS_DIR
    strings = [name for name in os.listdir(STRINGS_DIR) if name.endswith(".json")]
    assert strings, "%s 下至少需要 1 个 JSON 字符串文件" % STRINGS_DIR
    banned = []
    for base, _dirs, files in os.walk("shared"):
        for name in files:
            if os.path.splitext(name)[1].lower() in SOURCE_EXT:
                banned.append(os.path.join(base, name))
    assert not banned, "shared/ 内不得出现源码文件: %s" % ", ".join(sorted(banned))


# ----------------------------------------------------------- ac-gpx-wellformed
def check_gpx_wellformed():
    assert shutil.which("xmllint"), "缺少 xmllint（macOS: xcode-select --install）"
    proc = subprocess.run(["xmllint", "--noout", GPX], capture_output=True, text=True)
    assert proc.returncode == 0, "xmllint 失败: %s" % (proc.stderr.strip() or "exit %d" % proc.returncode)
    body = read_text(GPX)
    assert 'xmlns="%s"' % GPX_NS in body, "根元素未声明 GPX 1.1 默认命名空间"
    root = parse_xml(GPX)
    assert root.tag == G + "gpx", "根元素不是 gpx，实际 %s" % root.tag
    assert (root.get("version") or "") == "1.1", "根元素 version 必须是 1.1，实际 %r" % root.get("version")


# ---------------------------------------------------------- ac-gpx-trackpoints
def check_gpx_trackpoints():
    points = gpx_points()
    assert len(points) >= 3, "trkpt 数量必须 >= 3，实际 %d" % len(points)
    previous = None
    for index, point in enumerate(points, start=1):
        lat = clean_float(point["lat"], "trkpt#%d@lat" % index)
        lon = clean_float(point["lon"], "trkpt#%d@lon" % index)
        assert -90.0 <= lat <= 90.0, "trkpt#%d@lat 超出范围: %s" % (index, lat)
        assert -180.0 <= lon <= 180.0, "trkpt#%d@lon 超出范围: %s" % (index, lon)
        clean_float(point["ele"], "trkpt#%d/ele" % index)
        time_value = point["time"]
        assert time_value and ISO_UTC.match(time_value), "trkpt#%d/time 不是 ISO 8601 UTC: %r" % (index, time_value)
        current = parse_iso(time_value)
        assert previous is None or current > previous, "trkpt 的 time 未严格递增（第 %d 点）" % index
        previous = current


# ---------------------------------------------------- ac-gpx-garmin-extension
def check_gpx_garmin_extension():
    body = read_text(GPX)
    assert 'gpxtpx="%s"' % TPX_NS in body, "根元素未声明 gpxtpx TrackPointExtension 命名空间"
    points = gpx_points()
    assert points, "缺少 trkpt，无法校验扩展"
    for index, point in enumerate(points, start=1):
        assert point["hr"] is not None, "trkpt#%d 缺少 gpxtpx:hr" % index
        assert point["cad"] is not None, "trkpt#%d 缺少 gpxtpx:cad" % index
        hr = clean_float(point["hr"], "trkpt#%d/gpxtpx:hr" % index)
        assert 40.0 <= hr <= 220.0, "trkpt#%d 心率超出 40-220: %s" % (index, hr)
        clean_float(point["cad"], "trkpt#%d/gpxtpx:cad" % index)


# ----------------------------------------------------------- ac-tcx-wellformed
def check_tcx_wellformed():
    assert shutil.which("xmllint"), "缺少 xmllint（macOS: xcode-select --install）"
    proc = subprocess.run(["xmllint", "--noout", TCX], capture_output=True, text=True)
    assert proc.returncode == 0, "xmllint 失败: %s" % (proc.stderr.strip() or "exit %d" % proc.returncode)
    body = read_text(TCX)
    assert 'xmlns="%s"' % TCX_NS in body, "根元素未声明 TrainingCenterDatabase v2 默认命名空间"
    root = parse_xml(TCX)
    assert root.tag == T + "TrainingCenterDatabase", "根元素不是 TrainingCenterDatabase，实际 %s" % root.tag
    activities = root.findall("./%sActivities/%sActivity" % (T, T))
    assert len(activities) == 1, "Activities 下必须恰好 1 个 Activity，实际 %d" % len(activities)
    assert activities[0].get("Sport") == "Running", "Activity@Sport 必须是 Running，实际 %r" % activities[0].get("Sport")


# ---------------------------------------------------------- ac-tcx-trackpoints
def check_tcx_trackpoints():
    _, _, lap = tcx_lap()
    total_time = lap.find("./%sTotalTimeSeconds" % T)
    distance = lap.find("./%sDistanceMeters" % T)
    seconds = clean_float(total_time.text if total_time is not None else None, "Lap/TotalTimeSeconds")
    meters = clean_float(distance.text if distance is not None else None, "Lap/DistanceMeters")
    assert seconds > 0, "TotalTimeSeconds 必须 > 0，实际 %s" % seconds
    assert meters > 0, "DistanceMeters 必须 > 0，实际 %s" % meters
    points = tcx_points()
    assert len(points) >= 3, "Trackpoint 数量必须 >= 3，实际 %d" % len(points)
    previous = None
    with_vitals = 0
    for index, point in enumerate(points, start=1):
        time_value = point["time"]
        assert time_value and ISO_UTC.match(time_value), "Trackpoint#%d/Time 不是 ISO 8601 UTC: %r" % (index, time_value)
        current = parse_iso(time_value)
        assert previous is None or current > previous, "Trackpoint 的 Time 未严格递增（第 %d 点）" % index
        previous = current
        lat = clean_float(point["lat"], "Trackpoint#%d/LatitudeDegrees" % index)
        lon = clean_float(point["lon"], "Trackpoint#%d/LongitudeDegrees" % index)
        assert -90.0 <= lat <= 90.0, "Trackpoint#%d 纬度超出范围: %s" % (index, lat)
        assert -180.0 <= lon <= 180.0, "Trackpoint#%d 经度超出范围: %s" % (index, lon)
        clean_float(point["ele"], "Trackpoint#%d/AltitudeMeters" % index)
        if point["hr"] is not None and point["cad"] is not None:
            clean_float(point["hr"], "Trackpoint#%d/HeartRateBpm/Value" % index)
            clean_float(point["cad"], "Trackpoint#%d/Cadence" % index)
            with_vitals += 1
    assert with_vitals >= 1, "至少 1 个 Trackpoint 必须同时含 HeartRateBpm/Value 与 Cadence"


# ------------------------------------------------------------ ac-fixtures-readme
def check_fixtures_readme():
    body = read_text(FIX_README)
    declared = {}
    for match in re.finditer(r"^([a-z][a-z0-9_]*):[ \t]*(\S+)[ \t]*$", body, re.MULTILINE):
        key, value = match.group(1), match.group(2)
        assert key not in declared, "README 声明键重复: %s" % key
        declared[key] = value
    need = [
        "gpx_points", "gpx_first_time", "gpx_last_time", "gpx_first_ele", "gpx_last_ele",
        "gpx_first_hr", "gpx_last_hr", "gpx_first_cad", "gpx_last_cad",
        "tcx_points", "tcx_first_time", "tcx_last_time", "tcx_first_ele", "tcx_last_ele",
        "tcx_first_hr", "tcx_last_hr", "tcx_first_cad", "tcx_last_cad",
        "derived_duration_s", "derived_distance_m",
    ]
    missing = [key for key in need if key not in declared]
    assert not missing, "README 缺少期望解析结果键: %s" % ", ".join(missing)

    gpx = gpx_points()
    tcx = tcx_points()
    assert declared["gpx_points"] == str(len(gpx)), "README gpx_points=%s 与实际 %d 不符" % (declared["gpx_points"], len(gpx))
    assert declared["tcx_points"] == str(len(tcx)), "README tcx_points=%s 与实际 %d 不符" % (declared["tcx_points"], len(tcx))

    pairs = [
        ("gpx_first_time", gpx[0]["time"]), ("gpx_last_time", gpx[-1]["time"]),
        ("tcx_first_time", tcx[0]["time"]), ("tcx_last_time", tcx[-1]["time"]),
        ("gpx_first_hr", gpx[0]["hr"]), ("gpx_last_hr", gpx[-1]["hr"]),
        ("gpx_first_cad", gpx[0]["cad"]), ("gpx_last_cad", gpx[-1]["cad"]),
        ("tcx_first_hr", tcx[0]["hr"]), ("tcx_last_hr", tcx[-1]["hr"]),
        ("tcx_first_cad", tcx[0]["cad"]), ("tcx_last_cad", tcx[-1]["cad"]),
    ]
    for key, actual in pairs:
        assert declared[key] == actual, "README %s=%s 与实际 %s 不符" % (key, declared[key], actual)

    float_pairs = [
        ("gpx_first_ele", gpx[0]["ele"]), ("gpx_last_ele", gpx[-1]["ele"]),
        ("tcx_first_ele", tcx[0]["ele"]), ("tcx_last_ele", tcx[-1]["ele"]),
    ]
    for key, actual in float_pairs:
        assert abs(float(declared[key]) - float(actual)) < 1e-6, "README %s=%s 与实际 %s 不符" % (key, declared[key], actual)

    _, _, lap = tcx_lap()
    lap_seconds = float(lap.find("./%sTotalTimeSeconds" % T).text)
    lap_meters = float(lap.find("./%sDistanceMeters" % T).text)
    start = parse_iso(gpx[0]["time"])
    end = parse_iso(gpx[-1]["time"])
    actual_duration = (end - start).total_seconds()
    assert abs(actual_duration - int(declared["derived_duration_s"])) < 1e-6, \
        "README derived_duration_s=%s 与夹具实际 %s 不符" % (declared["derived_duration_s"], actual_duration)
    assert abs(actual_duration - lap_seconds) < 1e-6, "derived 时长与 TCX TotalTimeSeconds 不一致"
    actual_distance = sum(
        haversine(
            (float(gpx[i - 1]["lat"]), float(gpx[i - 1]["lon"])),
            (float(gpx[i]["lat"]), float(gpx[i]["lon"])),
        )
        for i in range(1, len(gpx))
    )
    declared_distance = float(declared["derived_distance_m"])
    assert abs(declared_distance - lap_meters) <= 0.05, \
        "README derived_distance_m=%s 与 TCX DistanceMeters=%s 不符" % (declared_distance, lap_meters)
    assert abs(declared_distance - actual_distance) <= 5.0, \
        "README derived_distance_m=%s 与坐标 Haversine 累加 %.2f m 偏差过大" % (declared_distance, actual_distance)

    mapping_tokens = [
        "run_point.t", "run_point.lat", "run_point.lon", "run_point.ele",
        "run_point.hr", "run_point.cad",
        "run.started_at", "run.ended_at", "run.duration_s", "run.distance_m", "run.gpx_path",
        "LatitudeDegrees", "LongitudeDegrees", "AltitudeMeters", "HeartRateBpm", "Cadence",
        "gpxtpx:hr", "gpxtpx:cad", "trkpt@lat", "trkpt@lon",
    ]
    missing_tokens = [token for token in mapping_tokens if token not in body]
    assert not missing_tokens, "README 缺少列映射标记: %s" % ", ".join(missing_tokens)
    assert "synthetic" in body.lower() or "合成" in body, "README 必须标注夹具为 synthetic/合成数据"


# --------------------------------------------------------- ac-schema-four-tables
def check_schema_four_tables():
    with temp_db() as conn:
        apply_schema(conn)
        tables = table_names(conn)
        assert len(tables) == 4, "schema.sql 必须恰好定义 4 张表，实际 %d 张: %s" % (len(tables), ", ".join(tables))
        expected = set(EXPECTED_COLUMNS)
        assert set(tables) == expected, "表名不符，期望 %s，实际 %s" % (sorted(expected), tables)
        for table, columns in EXPECTED_COLUMNS.items():
            actual = [name for name, _type, _pk in column_map(conn, table)]
            assert actual == columns, "%s 列名/顺序不符，期望 %s，实际 %s" % (table, columns, actual)


# ------------------------------------------------------ ac-schema-applies-clean
def check_schema_applies_clean():
    with temp_db() as conn:
        try:
            apply_schema(conn)
            apply_schema(conn)
        except sqlite3.Error as exc:
            raise AssertionError("schema.sql 在空库上执行失败或非幂等: %s" % exc)
        tables = table_names(conn)
        assert sorted(tables) == sorted(EXPECTED_COLUMNS), "重复执行后表集合异常: %s" % tables
        for table, columns in EXPECTED_COLUMNS.items():
            actual = [name for name, _type, _pk in column_map(conn, table)]
            assert actual == columns, "重复执行后 %s 列名/顺序异常: %s" % (table, actual)


# ------------------------------------------------------ ac-schema-keys-and-types
def check_schema_keys_and_types():
    with temp_db() as conn:
        sql = apply_schema(conn)
        for table in EXPECTED_COLUMNS:
            rows = column_map(conn, table)
            pk = [name for name, _type, pk_pos in sorted(
                [row for row in rows if row[2] > 0], key=lambda row: row[2]
            )]
            if table == "run_point":
                assert pk == ["run_id", "t"], "run_point 主键应为 (run_id, t)，实际 %s" % pk
            elif table == "food_cache":
                assert pk == ["barcode"], "food_cache 主键应为 barcode，实际 %s" % pk
            else:
                assert pk == ["id"], "%s 主键应为 id，实际 %s" % (table, pk)

        fks = list(conn.execute("PRAGMA foreign_key_list(run_point)"))
        assert any(
            row[2] == "run" and row[3] == "run_id" and row[4] == "id" for row in fks
        ), "run_point.run_id 缺少指向 run.id 的外键"

        types = {table: {name: ctype for name, ctype, _pk in column_map(conn, table)} for table in EXPECTED_COLUMNS}
        for table, column in [
            ("run", "distance_m"), ("run", "duration_s"), ("run_point", "lat"), ("run_point", "lon"),
            ("run_point", "ele"), ("run_point", "hr"), ("run_point", "cad"), ("food_log", "kcal"),
        ]:
            assert types[table][column] in ("INTEGER", "REAL"), \
                "%s.%s 必须是 INTEGER 或 REAL，实际 %r" % (table, column, types[table][column])
        for table, column in TIME_COLUMNS:
            assert types[table][column] == "INTEGER", \
                "时间列 %s.%s 必须统一为 epoch 秒 INTEGER，实际 %r" % (table, column, types[table][column])
        assert "epoch" in sql.lower(), "schema.sql 注释必须写明 epoch 秒时间口径"


# ------------------------------------------------------------ ac-strings-json
def check_strings_json():
    assert os.path.isdir(STRINGS_DIR), "缺少 %s" % STRINGS_DIR
    files = sorted(name for name in os.listdir(STRINGS_DIR) if name.endswith(".json"))
    assert files, "%s 下至少需要 1 个 .json 字符串文件" % STRINGS_DIR
    banned = [name for name in os.listdir(STRINGS_DIR) if name.endswith(".strings") or name.endswith(".xml")]
    assert not banned, "不得生成平台本地化产物: %s" % ", ".join(banned)
    required_keys = {"app_name", "tagline", "tab_run", "tab_history", "tab_log", "tab_settings"}
    for name in files:
        path = os.path.join(STRINGS_DIR, name)
        pairs = json.loads(read_text(path), object_pairs_hook=lambda items: items)
        assert isinstance(pairs, list), "%s 顶层必须是扁平 JSON 对象" % name
        keys = [key for key, _value in pairs]
        assert len(keys) == len(set(keys)), "%s 存在重复 key" % name
        for key, value in pairs:
            assert isinstance(value, str) and value.strip(), "%s 的 %s 必须是非空字符串" % (name, key)
        missing = required_keys - set(keys)
        assert not missing, "%s 缺少必备键: %s" % (name, ", ".join(sorted(missing)))


# ------------------------------------------- ac-no-parser-code-and-no-seed
def check_no_parser_code_and_no_seed():
    banned = []
    for base, _dirs, files in os.walk("shared"):
        for name in files:
            if os.path.splitext(name)[1].lower() in SOURCE_EXT:
                banned.append(os.path.join(base, name))
    assert not banned, "shared/ 内存在解析/持久化实现源码: %s" % ", ".join(sorted(banned))

    tokens = ["shared/fixtures", "sample-run.gpx", "sample-run.tcx"]
    hits = []
    for base in ("ios", "android"):
        if not os.path.isdir(base):
            continue
        for root, dirs, files in os.walk(base):
            dirs[:] = [entry for entry in dirs if entry not in {".build", ".git", "DerivedData", "build", "Pods"}]
            for name in files:
                path = os.path.join(root, name)
                if name in {"sample-run.gpx", "sample-run.tcx"}:
                    hits.append(path)
                    continue
                if os.path.getsize(path) > 2 * 1024 * 1024:
                    continue
                try:
                    content = open(path, "r", encoding="utf-8", errors="ignore").read()
                except OSError:
                    continue
                for token in tokens:
                    if token in content:
                        hits.append("%s: %s" % (path, token))
    assert not hits, "ios/ 或 android/ 引用了 shared 夹具: %s" % "; ".join(sorted(hits))


# -------------------------------------------------------- ac-check-shared-gate
def check_check_shared_gate():
    assert os.path.isfile(CHECK_SCRIPT), "缺少 %s" % CHECK_SCRIPT
    assert os.access(CHECK_SCRIPT, os.X_OK), "%s 必须可执行（chmod +x）" % CHECK_SCRIPT
    script = read_text(CHECK_SCRIPT)
    assert "set -euo pipefail" in script, "%s 必须 set -euo pipefail" % CHECK_SCRIPT
    assert "--help" in script, "%s 必须支持 --help" % CHECK_SCRIPT

    config = json.loads(read_text(GATES))
    assert config.get("version") == 1, "%s version 必须为 1" % GATES
    gates = config.get("gates")
    assert isinstance(gates, list) and gates, "%s gates 必须是非空数组" % GATES
    by_id = {gate.get("id"): gate for gate in gates}
    assert "check-shared" in by_id, "%s 缺少 check-shared 门" % GATES
    command = by_id["check-shared"].get("command") or ""
    assert command == "bash scripts/check-shared.sh", \
        "check-shared 门必须是单一 argv 'bash scripts/check-shared.sh'，实际 %r" % command
    test_command = (by_id.get("test") or {}).get("command") or ""
    assert "scripts/check-baseline.sh" in test_command, "既有 test 门必须仍执行 scripts/check-baseline.sh，实际 %r" % test_command
    for gate in gates:
        gate_command = gate.get("command") or ""
        assert gate_command.strip(), "门 %s 的 command 为空" % gate.get("id")
        assert not re.search(r"[&|;<>`\n]", gate_command), \
            "门 %s 的 command 含 shell 分隔符或重定向: %r" % (gate.get("id"), gate_command)
        assert not re.match(r"^\s*(echo|true|:)\b", gate_command), \
            "门 %s 是占位/空转命令: %r" % (gate.get("id"), gate_command)


run("ac-shared-tree", check_shared_tree)
run("ac-gpx-wellformed", check_gpx_wellformed)
run("ac-gpx-trackpoints", check_gpx_trackpoints)
run("ac-gpx-garmin-extension", check_gpx_garmin_extension)
run("ac-tcx-wellformed", check_tcx_wellformed)
run("ac-tcx-trackpoints", check_tcx_trackpoints)
run("ac-fixtures-readme", check_fixtures_readme)
run("ac-schema-four-tables", check_schema_four_tables)
run("ac-schema-applies-clean", check_schema_applies_clean)
run("ac-schema-keys-and-types", check_schema_keys_and_types)
run("ac-strings-json", check_strings_json)
run("ac-no-parser-code-and-no-seed", check_no_parser_code_and_no_seed)
run("ac-check-shared-gate", check_check_shared_gate)

for status, ac_id, message in RESULTS:
    print("%s\t%s\t%s" % (status, ac_id, message))
PYCHECK

  set +e
  results="$(python3 "$check_py")"
  py_status=$?
  set -e

  if [ "$py_status" -ne 0 ]; then
    fail "ac-checker-runtime" "python3 断言脚本异常退出（exit ${py_status}），结果不可信"
  elif [ -z "$results" ]; then
    fail "ac-checker-runtime" "python3 断言脚本未输出任何结果"
  else
    while IFS=$'\t' read -r status ac_id message; do
      [ -n "${ac_id:-}" ] || continue
      if [ "$status" = "PASS" ]; then
        pass "$ac_id"
      else
        fail "$ac_id" "${message:-断言失败}"
      fi
    done <<< "$results"
  fi
fi

printf '\ncheck-shared: 共 %d 项断言，失败 %d 项\n' "$CHECKS" "$FAILURES"
if [ "$FAILURES" -ne 0 ]; then
  exit 1
fi
exit 0
