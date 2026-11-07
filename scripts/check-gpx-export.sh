#!/usr/bin/env bash
# GPX 1.1 导出外部校验（.munk/code-gates.json 的 check-gpx-export 门真实执行体）。
# 构建 PurePaceGpxTool，把共享夹具真实写入临时 .gpx，再用 xmllint 与 python3
# 逐点比对 lat/lon/ele/time/hr/cad。任何工具缺失或字段不一致都必须失败，禁止 skip。
set -euo pipefail

usage() {
  cat <<'EOF'
用法: scripts/check-gpx-export.sh [--help]

对 ios/RunCore 的 PurePaceGpxTool 做真实导出校验并打印逐条结果：
  - swift / xmllint / python3 均可用（缺任何一个即失败，不跳过）
  - swift build --package-path ios/RunCore --product PurePaceGpxTool 成功
  - 以 shared/fixtures/sample-run.gpx 为 --input 真实运行工具写出临时 .gpx
  - 输出文件存在且非空，xmllint --noout 解析通过
  - 输出根元素为 GPX 1.1 gpx，creator 非空，默认命名空间与 gpxtpx 命名空间精确匹配
  - trkpt 恰好 4 个，逐点 lat/lon/ele 数值差 <= 1e-6、time 按同一瞬间、hr/cad 整数相等

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
    echo "check-gpx-export: 未知参数 '$1'（使用 --help 查看用法）" >&2
    exit 2
    ;;
esac

if [ "$#" -gt 1 ]; then
  echo "check-gpx-export: 只接受一个参数（使用 --help 查看用法）" >&2
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

summary_and_exit() {
  printf '\n%d 项断言，%d 项失败\n' "$CHECKS" "$FAILURES"
  if [ "$FAILURES" -ne 0 ]; then
    exit 1
  fi
  printf 'check-gpx-export OK\n'
  exit 0
}

# --------------------------------------------------------------- 工具依赖
missing_tools=0
for tool in swift xmllint python3; do
  if command -v "$tool" >/dev/null 2>&1; then
    pass "tool-${tool}"
  else
    fail "tool-${tool}" "缺少 ${tool}（本门禁禁止 skip 或降级）"
    missing_tools=1
  fi
done
if [ "$missing_tools" -ne 0 ]; then
  summary_and_exit
fi

# ------------------------------------------------------------------ 夹具
fixture="shared/fixtures/sample-run.gpx"
if [ -s "$fixture" ]; then
  pass "fixture-present"
else
  fail "fixture-present" "缺少或为空: ${fixture}"
  summary_and_exit
fi

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/check-gpx-export.XXXXXX")"
# shellcheck disable=SC2064
trap "rm -rf '${tmp_dir}'" EXIT

output="$tmp_dir/export.gpx"
build_log="$tmp_dir/build.log"

# ------------------------------------------------------------------ 构建
if swift build --package-path ios/RunCore --product PurePaceGpxTool >"$build_log" 2>&1; then
  pass "build-PurePaceGpxTool"
else
  fail "build-PurePaceGpxTool" "$(tr '\n' ' ' < "$build_log")"
  summary_and_exit
fi

bin_dir="$(swift build --package-path ios/RunCore --show-bin-path 2>/dev/null)"
tool_path="${bin_dir}/PurePaceGpxTool"
if [ -x "$tool_path" ]; then
  pass "tool-binary-present"
else
  fail "tool-binary-present" "未找到可执行文件: ${tool_path}"
  summary_and_exit
fi

# ------------------------------------------------------------- 真实导出
tool_log="$tmp_dir/tool.log"
if "$tool_path" --input "$fixture" --output "$output" >"$tool_log" 2>&1; then
  pass "tool-exit-0"
else
  fail "tool-exit-0" "$(tr '\n' ' ' < "$tool_log")"
  summary_and_exit
fi

if [ -s "$output" ]; then
  pass "output-nonempty"
else
  fail "output-nonempty" "输出文件缺失或为空: ${output}"
  summary_and_exit
fi

# -------------------------------------------------------------- xmllint
xmllint_log="$tmp_dir/xmllint.log"
if xmllint --noout "$output" >"$xmllint_log" 2>&1; then
  pass "xmllint-noout"
else
  fail "xmllint-noout" "$(tr '\n' ' ' < "$xmllint_log")"
fi

# ------------------------------------------------------------ 逐字段比对
cat > "$tmp_dir/compare.py" <<'PY'
import sys
import xml.etree.ElementTree as ET
from datetime import datetime, timezone

GPX = "http://www.topografix.com/GPX/1/1"
TPX = "http://www.garmin.com/xmlschemas/TrackPointExtension/v1"
TOLERANCE = 1e-6


def record(errors, message):
    errors.append(message)


def track_points(root):
    return root.findall("./{%s}trk/{%s}trkseg/{%s}trkpt" % (GPX, GPX, GPX))


def text_of(element, tag):
    child = element.find("{%s}%s" % (GPX, tag))
    if child is None or child.text is None:
        return None
    return child.text.strip()


def vital_of(point, tag):
    child = point.find(
        "{%s}extensions/{%s}TrackPointExtension/{%s}%s" % (GPX, TPX, TPX, tag)
    )
    if child is None or child.text is None:
        return None
    return child.text.strip()


def parse_timestamp(value):
    if value is None:
        return None
    return datetime.fromisoformat(value.replace("Z", "+00:00")).astimezone(timezone.utc)


def compare_number(errors, index, field, expected, actual):
    if expected is None or actual is None:
        record(errors, "trkpt[%d].%s 缺失: fixture=%r output=%r" % (index, field, expected, actual))
        return
    try:
        expected_value = float(expected)
        actual_value = float(actual)
    except ValueError:
        record(errors, "trkpt[%d].%s 不是数值: fixture=%r output=%r" % (index, field, expected, actual))
        return
    if abs(expected_value - actual_value) > TOLERANCE:
        record(
            errors,
            "trkpt[%d].%s 不一致: fixture=%.9f output=%.9f" % (index, field, expected_value, actual_value),
        )


def compare_integer(errors, index, field, expected, actual):
    if expected is None or actual is None:
        record(errors, "trkpt[%d].%s 缺失: fixture=%r output=%r" % (index, field, expected, actual))
        return
    try:
        if int(expected) != int(actual):
            record(errors, "trkpt[%d].%s 不一致: fixture=%r output=%r" % (index, field, expected, actual))
    except ValueError:
        record(errors, "trkpt[%d].%s 不是整数: fixture=%r output=%r" % (index, field, expected, actual))


def main():
    fixture_path, output_path = sys.argv[1], sys.argv[2]
    errors = []
    try:
        fixture_root = ET.parse(fixture_path).getroot()
        output_root = ET.parse(output_path).getroot()
    except ET.ParseError as error:
        print("XML 解析失败: %s" % error, file=sys.stderr)
        return 1

    if output_root.tag != "{%s}gpx" % GPX:
        record(errors, "输出根元素不是 GPX 1.1 gpx: %s" % output_root.tag)
    if output_root.get("version") != "1.1":
        record(errors, "输出 gpx@version 不是 1.1: %r" % output_root.get("version"))
    if not output_root.get("creator"):
        record(errors, "输出 gpx@creator 为空")

    fixture_points = track_points(fixture_root)
    output_points = track_points(output_root)
    if len(output_points) != 4:
        record(errors, "输出 trkpt 数量应为 4，实际 %d" % len(output_points))
    if len(fixture_points) != len(output_points):
        record(
            errors,
            "trkpt 数量不一致: fixture=%d output=%d" % (len(fixture_points), len(output_points)),
        )

    for index, (expected, actual) in enumerate(zip(fixture_points, output_points)):
        compare_number(errors, index, "lat", expected.get("lat"), actual.get("lat"))
        compare_number(errors, index, "lon", expected.get("lon"), actual.get("lon"))
        compare_number(errors, index, "ele", text_of(expected, "ele"), text_of(actual, "ele"))

        try:
            expected_time = parse_timestamp(text_of(expected, "time"))
        except ValueError:
            expected_time = None
        try:
            actual_time = parse_timestamp(text_of(actual, "time"))
        except ValueError:
            actual_time = None
        if expected_time is None or actual_time is None or expected_time != actual_time:
            record(
                errors,
                "trkpt[%d].time 不一致: fixture=%r output=%r"
                % (index, text_of(expected, "time"), text_of(actual, "time")),
            )

        for tag in ("hr", "cad"):
            compare_integer(errors, index, tag, vital_of(expected, tag), vital_of(actual, tag))

    if errors:
        for error in errors:
            print(error, file=sys.stderr)
        return 1
    print("4 个 trkpt 的 lat/lon/ele/time/hr/cad 与夹具逐点一致")
    return 0


if __name__ == "__main__":
    sys.exit(main())
PY

compare_log="$tmp_dir/compare.log"
if python3 "$tmp_dir/compare.py" "$fixture" "$output" >"$compare_log" 2>&1; then
  pass "fixture-fields-match"
else
  fail "fixture-fields-match" "$(tr '\n' ' ' < "$compare_log")"
fi

summary_and_exit
