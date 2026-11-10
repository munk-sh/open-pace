#!/usr/bin/env bash
# GPX 1.1 导出外部校验（.munk/code-gates.json 的 check-gpx-export 门真实执行体，也是
# `.github/workflows/ios.yml` lint 腿的独立一行）。
# 构建 PurePaceGpxTool，把共享夹具真实写入临时 .gpx，再用 xmllint 与 python3
# 逐点比对 lat/lon/ele/time/hr/cad。任何工具缺失或字段不一致都必须失败，禁止 skip。
#
# 反例自证：本脚本还会对同一夹具造两个反例副本（删 `<ele>`、换成 GPX 1.0 命名空间），
# 断言逐字段比对必须判红。CI 与本地跑的是同一 runner 镜像（macOS + swift/xmllint/python3
# 全部预装），所以这两个反例在 CI 的 lint 腿里同样真实执行，不需要另起 job。
#
# 阈值先定后测（写进实现在前，跑测试在后；全部有推导依据，禁止看红再调）：
#   - 坐标/高程数值容差 1e-6：夹具写 6 位小数（≈0.11 m/格）；GPX 文本往返是十进制字符串，
#     Double→文本→Double 在 6 位小数下误差 < 1e-9；1e-6 是同坐标判定上界，远小于 GPS 噪声
#     （~1 m），足以判出任何真实字段漂移而对纯格式往返保持放行。
#   - trkpt 数量必须恰为 4：共享夹具冻结 4 点，导出器对该输入必须不丢点也不补点；
#     因此不设数量容差（任何 ±N 容差都会让丢点反例漏判）。
#   - time 必须同一瞬间（不设时间容差）：GPX 1.1 xs:dateTime 秒级精度，夹具与导出同精度，
#     秒以下无合法误差来源，任何时间差都是真实缺陷。
#   - hr/cad 整数精确相等：整数生命体征无浮点往返，容差会让 112 vs 113 漏判。
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
  - 反例自证：删某个 trkpt 的 <ele>、或把默认命名空间改成 GPX 1.0 后，逐字段比对必须判红
    （CI 与本地同一 runner 镜像，反例在 lint 腿里同样真实执行）

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
# 阈值先定后测：夹具 6 位小数（≈0.11 m/格），十进制文本往返误差 < 1e-9，
# 故 1e-6 是「同一坐标」判定上界；远小于 GPS 噪声（~1 m），能判出真实漂移又不误杀格式往返。
TOLERANCE = 1e-6
# 夹具冻结 4 个 trkpt，导出器对该输入必须不丢点不补点：数量不设容差。
EXPECTED_POINT_COUNT = 4


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
    if len(output_points) != EXPECTED_POINT_COUNT:
        record(
            errors,
            "输出 trkpt 数量应为 %d，实际 %d" % (EXPECTED_POINT_COUNT, len(output_points)),
        )
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

# ------------------------------------------------------- 反例自证（CI 实跑一次）
# 对同一夹具造反例副本（仓库夹具零改动），断言逐字段比对真能判红且指向被破坏字段。
red_ele="$tmp_dir/red-missing-ele.gpx"
if python3 - "$fixture" "$red_ele" <<'PY'
import re
import sys

source, target = sys.argv[1], sys.argv[2]
text = open(source, encoding="utf-8").read()
text, removed = re.subn(r"\n[ \t]*<ele>[^<]*</ele>", "", text, count=1)
if removed != 1:
    raise SystemExit("反例构造失败：没有找到可删除的 <ele>")
open(target, "w", encoding="utf-8").write(text)
PY
then
  red_ele_log="$tmp_dir/red-missing-ele.log"
  if python3 "$tmp_dir/compare.py" "$fixture" "$red_ele" >"$red_ele_log" 2>&1; then
    fail "red-proof-missing-ele" "删掉 <ele> 的反例仍判定一致，逐字段比对无法判红"
  elif grep -q 'trkpt\[0\]\.ele' "$red_ele_log"; then
    pass "red-proof-missing-ele"
  else
    fail "red-proof-missing-ele" "反例判红但未定位到 ele 字段: $(tr '\n' ' ' < "$red_ele_log")"
  fi
else
  fail "red-proof-missing-ele" "反例夹具构造失败（删除 <ele>）"
fi

red_ns="$tmp_dir/red-gpx10.gpx"
if python3 - "$fixture" "$red_ns" <<'PY'
import sys

source, target = sys.argv[1], sys.argv[2]
text = open(source, encoding="utf-8").read()
replaced = text.replace(
    "http://www.topografix.com/GPX/1/1", "http://www.topografix.com/GPX/1/0", 1
)
if replaced == text:
    raise SystemExit("反例构造失败：没有找到 GPX 1.1 默认命名空间")
open(target, "w", encoding="utf-8").write(replaced)
PY
then
  red_ns_log="$tmp_dir/red-gpx10.log"
  if python3 "$tmp_dir/compare.py" "$fixture" "$red_ns" >"$red_ns_log" 2>&1; then
    fail "red-proof-namespace" "GPX 1.0 命名空间反例仍判定一致，逐字段比对无法判红"
  elif grep -q 'GPX 1.1 gpx' "$red_ns_log"; then
    pass "red-proof-namespace"
  else
    fail "red-proof-namespace" "反例判红但未定位到命名空间: $(tr '\n' ' ' < "$red_ns_log")"
  fi
else
  fail "red-proof-namespace" "反例夹具构造失败（改成 GPX 1.0 命名空间）"
fi

summary_and_exit
