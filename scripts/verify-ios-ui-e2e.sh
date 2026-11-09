#!/usr/bin/env bash
# 模拟器端到端取证：版本同步 → XcodeGen/现有工程 → 构建安装 → iPhone 16 / iOS 18.6
# 模拟器 boot → uninstall 保证空容器 → 定向 UI 用例（由 launch-arg 门控的 DEBUG 确定性
# 测试源驱动，不依赖 simulator 定位投递）→ 读取真实 App 容器断言跑次 JSON 与导出 GPX →
# 独立 python 标准库解析 → report.json 与截图证据（默认只写 .build/）。
# 口径：只写「模拟器 + 代码层」，不产出真机结论；不读任何夹具或样例数据，
# 不用假流或内存字符串冒充导出与跑次。真实 CoreLocation 覆盖由 verify-ios-sim-runtime.sh 承担。
set -euo pipefail

usage() {
  cat <<'EOF'
用法: scripts/verify-ios-ui-e2e.sh [--help] [--refresh-evidence]

在 iPhone 16 / iOS 18.6 模拟器上跑一条真实端到端链路并产出机读报告与截图：
  1. 由根 VERSION 同步版本；工程缺失且本机有 xcodegen 时从 ios/project.yml 生成工程
     （复用 scripts/build-ios.sh 的判定口径，禁止手写 project.pbxproj）。
  2. xcodebuild 构建并安装到 iPhone 16 / iOS 18.6 模拟器（bundle id com.chaxiu.purepace）。
  3. xcrun simctl uninstall 清空容器并断言 Documents/Runs 无跑次文件。
  4. 定位由启动参数 -uiTestLocation 门控的 DEBUG 确定性测试源覆盖（UI/导出对齐）；
     真实 CoreLocation 由 scripts/verify-ios-sim-runtime.sh 的门禁覆盖。
  5. 只跑 PurePaceUITests/RunFlowUITests/testRunPauseResumeFinishAndHistory 真实流程用例，
     result bundle 写入 .build/verify-ios-ui-e2e/。
  6. xcrun simctl get_app_container 读取真实容器：Documents/Runs 恰 1 条跑次
     （formatVersion == 1、distance > 0、samples 非空、activeDuration > 0、startedAt < endedAt），
     Documents/Exports 至少 1 个 .gpx 且 xmllint --noout 通过、根节点为 GPX 1.1。
  7. 内嵌 python3（仅标准库、不 import App/RunCore 源码）独立解析 GPX 与跑次 JSON，
      核对 trkpt 数 == samples 数、首末时间差 ≤1 s、首末经纬度差 ≤1e-6。
  8. 生成 .build/verify-ios-ui-e2e/report.json 与同目录 evidence/ 证据副本；
      只有显式 --refresh-evidence 才覆盖仓库 docs/evidence/stage3-e2e/。

选项:
  -h, --help            显示本帮助并退出 0
  --refresh-evidence    额外把报告、解析结果与 4 张截图副本写入 docs/evidence/stage3-e2e/

退出码:
  0  端到端链路全部通过（模拟器 + 代码层）
  1  任一步骤或断言失败（stderr 与 report.json failures[].failureReason 写明原因）
  2  参数非法
EOF
}

refresh_evidence=0
case "${1:-}" in
  -h|--help)
    usage
    exit 0
    ;;
  "")
    ;;
  --refresh-evidence)
    refresh_evidence=1
    ;;
  *)
    echo "verify-ios-ui-e2e: 未知参数 '$1'（使用 --help 查看用法）" >&2
    exit 2
    ;;
esac

if [ "$#" -gt 1 ]; then
  echo "verify-ios-ui-e2e: 只接受一个参数（使用 --help 查看用法）" >&2
  exit 2
fi

# 以脚本自身位置推导仓库根，保证在任意 cwd 下运行结果一致。
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
cd "$repo_root"

device_name="iPhone 16"
runtime_id="com.apple.CoreSimulator.SimRuntime.iOS-18-6"
runtime_name="iOS 18.6"
destination="platform=iOS Simulator,name=iPhone 16,OS=18.6"
bundle_id="com.chaxiu.purepace"
scheme="PurePace"
project_path="ios/PurePace.xcodeproj"
spec_path="ios/project.yml"
derived_data=".build/ios"
work_dir=".build/verify-ios-ui-e2e"
# 默认只写 .build/，避免每次门禁都重写仓库证据目录；显式 --refresh-evidence 才覆盖仓库证据。
evidence_dir="${work_dir}/evidence"
if [ "$refresh_evidence" -eq 1 ]; then
  evidence_dir="docs/evidence/stage3-e2e"
fi
result_bundle="${work_dir}/PurePaceE2E.xcresult"
attachments_dir="${work_dir}/attachments"
screenshots_dir="${work_dir}/screenshots"
evidence_screenshots="${evidence_dir}/screenshots"
report_path="${work_dir}/report.json"
device_json="${work_dir}/device.json"
steps_json="${work_dir}/steps.json"
container_json="${work_dir}/container.json"
parse_json="${work_dir}/parse.json"
screenshots_json="${work_dir}/screenshots.json"
failures_file="${work_dir}/failures.txt"
xcode_log="${work_dir}/xcodebuild-test.log"

# 可重复执行：每次从干净的产物目录开始（幂等）；仅在 --refresh-evidence 时覆盖仓库证据目录。
rm -rf "$work_dir"
if [ "$refresh_evidence" -eq 1 ]; then
  rm -rf "$evidence_dir"
fi
mkdir -p "$work_dir" "$screenshots_dir" "$attachments_dir" "$evidence_dir" "$evidence_screenshots"
: > "$failures_file"

sim_udid=""

record_step() {
  local name="$1" ok="$2" detail="$3"
  python3 - "$steps_json" "$name" "$ok" "$detail" <<'PY'
import json
import os
import sys

path, name, ok, detail = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
steps = []
if os.path.exists(path):
    try:
        with open(path, "r", encoding="utf-8") as handle:
            steps = json.load(handle)
    except Exception:
        steps = []
steps.append({"name": name, "ok": ok == "true", "detail": detail})
with open(path, "w", encoding="utf-8") as handle:
    json.dump(steps, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
PY
}

fail_step() {
  local name="$1" reason="$2"
  printf '%s: %s\n' "$name" "$reason" >> "$failures_file"
  record_step "$name" false "$reason"
  printf 'verify-ios-ui-e2e: %s 失败: %s\n' "$name" "$reason" >&2
}

select_simulator() {
  xcrun simctl list devices available --json 2>/dev/null | python3 -c '
import json
import sys

runtime, name = sys.argv[1], sys.argv[2]
data = json.load(sys.stdin).get("devices", {})
for key, devices in data.items():
    if key != runtime:
        continue
    for device in devices:
        if device.get("name") == name and device.get("isAvailable", True):
            print(device["udid"])
            sys.exit(0)
sys.exit(1)
' "$runtime_id" "$device_name"
}

assert_empty_container() {
  local container count
  if container="$(xcrun simctl get_app_container "$sim_udid" "$bundle_id" data 2>/dev/null)"; then
    count="$(python3 - "$container" <<'PY'
import glob
import os
import sys

container = sys.argv[1]
runs = glob.glob(os.path.join(container, "Documents", "Runs", "*.json"))
print(len(runs))
PY
)"
    if [ "$count" -ne 0 ]; then
      fail_step "empty-container" "uninstall 后 Documents/Runs 仍有 $count 个跑次文件（容器 ${container}）"
      return 1
    fi
    record_step "empty-container" true "uninstall 后容器存在但 Documents/Runs 无跑次文件（${container}）"
  else
    record_step "empty-container" true "uninstall 后容器不存在，测试前为空"
  fi
}

probe_container() {
  local container
  if ! container="$(xcrun simctl get_app_container "$sim_udid" "$bundle_id" data 2>/dev/null)"; then
    fail_step "container" "无法读取 App 容器（xcrun simctl get_app_container 失败）"
    return 1
  fi
  record_step "container" true "读取真实容器 $container"
  python3 - "$container" "$container_json" <<'PY'
import glob
import json
import os
import subprocess
import sys
import xml.etree.ElementTree as ET

container, out_path = sys.argv[1], sys.argv[2]
gpx_namespace = "http://www.topografix.com/GPX/1/1"
problems = []

runs_dir = os.path.join(container, "Documents", "Runs")
exports_dir = os.path.join(container, "Documents", "Exports")
run_files = sorted(glob.glob(os.path.join(runs_dir, "*.json")))

run_summary = {
    "count": len(run_files),
    "files": [os.path.basename(path) for path in run_files],
}
if len(run_files) != 1:
    problems.append(
        "Documents/Runs 应恰 1 个 .json，实际 %d 个: %s"
        % (len(run_files), run_summary["files"])
    )

if run_files:
    run_path = run_files[0]
    try:
        with open(run_path, "r", encoding="utf-8") as handle:
            record = json.load(handle)
    except Exception as exc:  # noqa: BLE001
        problems.append("跑次 JSON 解析失败: %s" % exc)
        record = {}

    samples = record.get("samples") or []
    run_summary.update(
        {
            "formatVersion": record.get("formatVersion"),
            "distance": record.get("distance"),
            "activeDuration": record.get("activeDuration"),
            "startedAt": record.get("startedAt"),
            "endedAt": record.get("endedAt"),
            "sampleCount": len(samples),
        }
    )
    if record.get("formatVersion") != 1:
        problems.append("formatVersion 应为 1，实际 %r" % record.get("formatVersion"))
    distance = record.get("distance")
    if not isinstance(distance, (int, float)) or isinstance(distance, bool) or distance <= 0:
        problems.append("distance 应 > 0，实际 %r" % distance)
    if not samples:
        problems.append("samples 不得为空")
    active = record.get("activeDuration")
    if not isinstance(active, (int, float)) or isinstance(active, bool) or active <= 0:
        problems.append("activeDuration 应 > 0，实际 %r" % active)
    started, ended = record.get("startedAt"), record.get("endedAt")
    if not isinstance(started, (int, float)) or not isinstance(ended, (int, float)) or not started < ended:
        problems.append("startedAt 应 < endedAt，实际 %r / %r" % (started, ended))
    if samples:
        first, last = samples[0], samples[-1]
        run_summary["firstSample"] = {
            "latitude": first.get("latitude"),
            "longitude": first.get("longitude"),
            "timestamp": first.get("timestamp"),
        }
        run_summary["lastSample"] = {
            "latitude": last.get("latitude"),
            "longitude": last.get("longitude"),
            "timestamp": last.get("timestamp"),
        }

gpx_files = sorted(glob.glob(os.path.join(exports_dir, "*.gpx")))
exports = []
if not gpx_files:
    problems.append("Documents/Exports 至少应有 1 个 .gpx")
for path in gpx_files:
    entry = {"name": os.path.basename(path), "bytes": os.path.getsize(path)}
    if entry["bytes"] <= 0:
        problems.append("%s 字节数为 0" % entry["name"])
    linter = subprocess.run(["xmllint", "--noout", path], capture_output=True, text=True)
    entry["xmllintOk"] = linter.returncode == 0
    if linter.returncode != 0:
        problems.append(
            "xmllint --noout %s 退出 %d: %s"
            % (entry["name"], linter.returncode, (linter.stderr or "").strip())
        )
    try:
        root = ET.parse(path).getroot()
        entry["rootTag"] = root.tag
        entry["version"] = root.get("version")
        # ElementTree 把 xmlns 解析进 tag 的命名空间前缀，因此由 tag 反推实际命名空间。
        entry["xmlns"] = gpx_namespace if root.tag == "{%s}gpx" % gpx_namespace else None
        root_ok = (
            root.tag == "{%s}gpx" % gpx_namespace
            and root.get("version") == "1.1"
        )
        entry["rootOk"] = root_ok
        if not root_ok:
            problems.append(
                "%s 根节点/命名空间不合法（tag=%r version=%r）"
                % (entry["name"], root.tag, root.get("version"))
            )
    except Exception as exc:  # noqa: BLE001
        entry["rootOk"] = False
        problems.append("%s XML 解析失败: %s" % (entry["name"], exc))
    exports.append(entry)

payload = {
    "ok": not problems,
    "problems": problems,
    "containerPath": container,
    "runs": run_summary,
    "exports": {
        "count": len(gpx_files),
        "files": exports,
        "primary": os.path.basename(gpx_files[0]) if gpx_files else None,
    },
}
with open(out_path, "w", encoding="utf-8") as handle:
    json.dump(payload, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
sys.exit(0 if not problems else 1)
PY
  local status=$?
  if [ "$status" -ne 0 ]; then
    while IFS= read -r reason; do
      [ -n "$reason" ] || continue
      fail_step "container" "$reason"
    done < <(python3 -c '
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    doc = json.load(handle)
for problem in doc.get("problems", []):
    print(problem)
' "$container_json")
    return 1
  fi
  record_step "container-assertions" true "Runs 恰 1 条、Exports GPX 合法（见容器与导出解析数值）"
}

parse_export_consistency() {
  python3 - "$container_json" "$parse_json" <<'PY'
import datetime
import json
import os
import sys
import xml.etree.ElementTree as ET

container_path, out_path = sys.argv[1], sys.argv[2]
gpx_namespace = "http://www.topografix.com/GPX/1/1"
with open(container_path, "r", encoding="utf-8") as handle:
    container = json.load(handle)

runs = container.get("runs") or {}
exports = container.get("exports") or {}
container_dir = container.get("containerPath") or ""
primary = exports.get("primary")
problems = []

first_sample = runs.get("firstSample") or {}
last_sample = runs.get("lastSample") or {}
sample_count = runs.get("sampleCount")

trkpts = []
if not primary:
    problems.append("缺少可解析的导出 GPX")
else:
    gpx_path = os.path.join(container_dir, "Documents", "Exports", primary)
    try:
        root = ET.parse(gpx_path).getroot()
        for node in root.iter("{%s}trkpt" % gpx_namespace):
            time_node = node.find("{%s}time" % gpx_namespace)
            trkpts.append(
                {
                    "lat": float(node.get("lat")),
                    "lon": float(node.get("lon")),
                    "time": time_node.text.strip() if time_node is not None and time_node.text else None,
                }
            )
    except Exception as exc:  # noqa: BLE001
        problems.append("导出 GPX 解析失败: %s" % exc)


def epoch_seconds(text):
    if not text:
        raise ValueError("缺失 <time>")
    value = text.strip()
    if value.endswith("Z"):
        value = value[:-1] + "+00:00"
    return datetime.datetime.fromisoformat(value).timestamp()


result = {
    "gpxFile": primary,
    "trkptCount": len(trkpts),
    "sampleCount": sample_count,
    "firstTimeDeltaSeconds": None,
    "lastTimeDeltaSeconds": None,
    "firstCoordinateDelta": None,
    "lastCoordinateDelta": None,
    "problems": problems,
}

if sample_count != len(trkpts):
    problems.append("trkpt 数 %d != samples 数 %r" % (len(trkpts), sample_count))

if trkpts and first_sample and last_sample:
    try:
        first_delta = abs(epoch_seconds(trkpts[0]["time"]) - float(first_sample["timestamp"]))
        last_delta = abs(epoch_seconds(trkpts[-1]["time"]) - float(last_sample["timestamp"]))
        result["firstTimeDeltaSeconds"] = first_delta
        result["lastTimeDeltaSeconds"] = last_delta
        if first_delta > 1.0:
            problems.append("首个 trkpt 时间与 samples[0].timestamp 差 %.3f s > 1 s" % first_delta)
        if last_delta > 1.0:
            problems.append("末个 trkpt 时间与 samples[-1].timestamp 差 %.3f s > 1 s" % last_delta)
    except Exception as exc:  # noqa: BLE001
        problems.append("时间对齐解析失败: %s" % exc)

    first_coord = max(
        abs(trkpts[0]["lat"] - float(first_sample["latitude"])),
        abs(trkpts[0]["lon"] - float(first_sample["longitude"])),
    )
    last_coord = max(
        abs(trkpts[-1]["lat"] - float(last_sample["latitude"])),
        abs(trkpts[-1]["lon"] - float(last_sample["longitude"])),
    )
    result["firstCoordinateDelta"] = first_coord
    result["lastCoordinateDelta"] = last_coord
    if first_coord > 1e-6:
        problems.append("首个 trkpt 经纬度与 samples[0] 差 %.9f > 1e-6" % first_coord)
    if last_coord > 1e-6:
        problems.append("末个 trkpt 经纬度与 samples[-1] 差 %.9f > 1e-6" % last_coord)

result["ok"] = not problems
with open(out_path, "w", encoding="utf-8") as handle:
    json.dump(result, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
sys.exit(0 if not problems else 1)
PY
  local status=$?
  if [ "$status" -ne 0 ]; then
    while IFS= read -r reason; do
      [ -n "$reason" ] || continue
      fail_step "external-parse" "$reason"
    done < <(python3 -c '
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    doc = json.load(handle)
for problem in doc.get("problems", []):
    print(problem)
' "$parse_json")
    return 1
  fi
  record_step "external-parse" true "trkpt 数与采样数一致，首末时间与经纬度在容差内"
}

export_screenshots() {
  if ! xcrun xcresulttool export attachments \
    --path "$result_bundle" \
    --output-path "$attachments_dir" >/dev/null 2>&1; then
    fail_step "screenshots" "xcresulttool export attachments 失败（result bundle ${result_bundle}）"
    return 1
  fi
  python3 - "$attachments_dir" "$screenshots_dir" "$evidence_screenshots" "$screenshots_json" <<'PY'
import json
import os
import shutil
import sys

attachments_dir, screenshots_dir, evidence_dir, out_path = sys.argv[1:5]
expected = ["e2e-finish", "e2e-history", "e2e-detail", "e2e-share"]
manifest_path = os.path.join(attachments_dir, "manifest.json")
problems = []
entries = []

try:
    with open(manifest_path, "r", encoding="utf-8") as handle:
        manifest = json.load(handle)
except Exception as exc:  # noqa: BLE001
    manifest = []
    problems.append("读取附件 manifest.json 失败: %s" % exc)

available = []
for test in manifest if isinstance(manifest, list) else []:
    for attachment in test.get("attachments", []) or []:
        exported = attachment.get("exportedFileName")
        suggested = attachment.get("suggestedHumanReadableName") or ""
        if exported:
            available.append((suggested, exported))

for name in expected:
    match = None
    for suggested, exported in available:
        normalized = os.path.splitext(suggested)[0]
        if normalized == name or suggested.startswith(name) or name in suggested:
            match = exported
            break
    if not match:
        problems.append("缺少附件 %s（manifest 中未找到）" % name)
        entries.append({"name": name, "ok": False})
        continue
    src = os.path.join(attachments_dir, match)
    if not os.path.isfile(src) or os.path.getsize(src) <= 0:
        problems.append("附件 %s 导出文件为空或不存在（%s）" % (name, match))
        entries.append({"name": name, "ok": False})
        continue
    target_name = name + ".png"
    for directory in (screenshots_dir, evidence_dir):
        os.makedirs(directory, exist_ok=True)
        shutil.copyfile(src, os.path.join(directory, target_name))
    entries.append(
        {
            "name": name,
            "file": target_name,
            "bytes": os.path.getsize(src),
            "ok": True,
        }
    )

payload = {"ok": not problems, "problems": problems, "screenshots": entries}
with open(out_path, "w", encoding="utf-8") as handle:
    json.dump(payload, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
sys.exit(0 if not problems else 1)
PY
  local status=$?
  if [ "$status" -ne 0 ]; then
    while IFS= read -r reason; do
      [ -n "$reason" ] || continue
      fail_step "screenshots" "$reason"
    done < <(python3 -c '
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    doc = json.load(handle)
for problem in doc.get("problems", []):
    print(problem)
' "$screenshots_json")
    return 1
  fi
  record_step "screenshots" true "4 张固定名称截图已导出并复制到证据目录"
}

write_report() {
  python3 - "$work_dir" "$report_path" "$evidence_dir" <<'PY'
import datetime
import json
import os
import shutil
import sys

work_dir, report_path, evidence_dir = sys.argv[1], sys.argv[2], sys.argv[3]


def load(name, default):
    path = os.path.join(work_dir, name)
    try:
        with open(path, "r", encoding="utf-8") as handle:
            return json.load(handle)
    except Exception:
        return default


steps = load("steps.json", [])
device = load("device.json", {})
container = load("container.json", {})
external = load("parse.json", {})
screenshots = load("screenshots.json", {})

failures = []
failures_path = os.path.join(work_dir, "failures.txt")
if os.path.exists(failures_path):
    with open(failures_path, "r", encoding="utf-8") as handle:
        for raw_line in handle:
            line = raw_line.strip()
            if not line:
                continue
            step, _, reason = line.partition(": ")
            failures.append({"step": step, "failureReason": reason or line})

ok = (
    not failures
    and bool(steps)
    and all(step.get("ok") for step in steps)
    and container.get("ok", False)
    and external.get("ok", False)
    and screenshots.get("ok", False)
)

report = {
    "ok": ok,
    "caliber": "模拟器 + 代码层",
    "generatedAt": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "script": "scripts/verify-ios-ui-e2e.sh",
    "destination": device.get("destination", "platform=iOS Simulator,name=iPhone 16,OS=18.6"),
    "simulator": {
        "name": device.get("name", "iPhone 16"),
        "udid": device.get("udid", ""),
        "runtime": device.get("runtime", "iOS 18.6"),
        "bundleId": device.get("bundleId", "com.chaxiu.purepace"),
    },
    "steps": steps,
    "container": container,
    "externalParse": external,
    "screenshots": screenshots.get("screenshots", []),
    "failures": failures,
}

with open(report_path, "w", encoding="utf-8") as handle:
    json.dump(report, handle, ensure_ascii=False, indent=2)
    handle.write("\n")

# 证据副本：报告、独立解析结果与摘要（每次覆盖写入）。
os.makedirs(evidence_dir, exist_ok=True)
shutil.copyfile(report_path, os.path.join(evidence_dir, "report.json"))
if external:
    with open(os.path.join(evidence_dir, "external-parse.json"), "w", encoding="utf-8") as handle:
        json.dump(external, handle, ensure_ascii=False, indent=2)
        handle.write("\n")

summary_lines = [
    "# 阶段 3 端到端证据（模拟器 + 代码层）",
    "",
    "- 口径：模拟器 + 代码层",
    "- 定位口径：UI/导出对齐由确定性测试源（-uiTestLocation）覆盖；真实 CoreLocation 由 verify-ios-sim-runtime 覆盖",
    "- 结论：%s" % ("模拟器链路通过" if ok else "模拟器链路未通过"),
    "- 模拟器：%s / %s（%s）"
    % (report["simulator"]["name"], report["simulator"]["runtime"], report["simulator"]["udid"]),
    "- destination：%s" % report["destination"],
    "- 导出逐字段对齐：%s" % ("导出逐字段对齐通过" if external.get("ok") else "导出逐字段对齐未通过"),
    "- Runs 条数：%s" % container.get("runs", {}).get("count"),
    "- Exports 条数：%s" % container.get("exports", {}).get("count"),
    "- 截图：%s" % ", ".join(entry.get("file", "") for entry in report["screenshots"]),
    "",
    "## 失败项",
    "",
]
if failures:
    for failure in failures:
        summary_lines.append("- %s: %s" % (failure["step"], failure["failureReason"]))
else:
    summary_lines.append("- 无")
summary_lines.append("")
with open(os.path.join(evidence_dir, "summary.md"), "w", encoding="utf-8") as handle:
    handle.write("\n".join(summary_lines))

sys.exit(0 if ok else 1)
PY
}

main() {
  if ! command -v xcrun >/dev/null 2>&1 || ! command -v xcodebuild >/dev/null 2>&1 \
    || ! command -v python3 >/dev/null 2>&1 || ! command -v xmllint >/dev/null 2>&1; then
    fail_step "environment" "缺少必需命令（xcrun / xcodebuild / python3 / xmllint）"
    return 1
  fi

  # 版本真源：MARKETING_VERSION 只能来自根 VERSION。
  if ! bash scripts/sync-ios-version.sh >/dev/null; then
    fail_step "sync-version" "scripts/sync-ios-version.sh 非零退出"
    return 1
  fi
  record_step "sync-version" true "根 VERSION 已同步到 ios/Config/Version.xcconfig"

  # 工程：优先现有 XcodeGen 产物；缺失时从 project.yml 生成，绝不手写 pbxproj。
  if [ -d "$project_path" ]; then
    record_step "generate-project" true "使用现有 ${project_path}（XcodeGen 产物）"
  elif [ -f "$spec_path" ] && command -v xcodegen >/dev/null 2>&1; then
    if ! xcodegen generate --spec "$spec_path" --project ios >/dev/null; then
      fail_step "generate-project" "xcodegen 从 $spec_path 生成工程失败"
      return 1
    fi
    record_step "generate-project" true "xcodegen 从 $spec_path 生成 $project_path"
  else
    fail_step "generate-project" "缺 $project_path 且无法用 xcodegen 从 $spec_path 生成"
    return 1
  fi

  # 模拟器：固定 iPhone 16 / iOS 18.6；缺失或 boot 失败必须非零退出并在报告中写明。
  if ! sim_udid="$(select_simulator)"; then
    fail_step "simulator" "未找到可用的 $device_name / $runtime_name 模拟器（xcrun simctl list devices available）"
    return 1
  fi
  record_step "simulator" true "选中 $device_name / ${runtime_name}（${sim_udid}）"

  xcrun simctl boot "$sim_udid" >/dev/null 2>&1 || true
  if ! xcrun simctl bootstatus "$sim_udid" -b >/dev/null 2>&1; then
    fail_step "simulator-boot" "模拟器启动失败（xcrun simctl bootstatus $sim_udid -b）"
    return 1
  fi
  record_step "simulator-boot" true "模拟器已启动（${sim_udid}）"

  python3 - "$device_json" "$device_name" "$sim_udid" "$runtime_name" "$bundle_id" "$destination" <<'PY'
import json
import sys

path, name, udid, runtime, bundle_id, destination = sys.argv[1:7]
with open(path, "w", encoding="utf-8") as handle:
    json.dump(
        {
            "name": name,
            "udid": udid,
            "runtime": runtime,
            "bundleId": bundle_id,
            "destination": destination,
        },
        handle,
        ensure_ascii=False,
        indent=2,
    )
    handle.write("\n")
PY

  # 构建：复用 scripts/build-ios.sh 的判定口径；产物缺失视为失败，不降级为「通过」。
  if ! bash scripts/build-ios.sh >"$work_dir/build.log" 2>&1; then
    fail_step "build" "scripts/build-ios.sh 非零退出（日志 $work_dir/build.log）"
    return 1
  fi
  app_path="$(find "$derived_data/Build/Products" -type d -name 'PurePace.app' -print -quit 2>/dev/null || true)"
  if [ -z "$app_path" ] || [ ! -d "$app_path" ]; then
    fail_step "build" "构建脚本未产出 PurePace.app（$derived_data/Build/Products）"
    return 1
  fi
  record_step "build" true "构建产物 $app_path"

  if ! xcrun simctl install "$sim_udid" "$app_path" >/dev/null 2>&1; then
    fail_step "install" "simctl install 失败（${app_path}）"
    return 1
  fi
  record_step "install" true "已安装 $bundle_id 到 $sim_udid"

  # 空容器：先 uninstall，再断言 Documents/Runs 无跑次文件，保证「恰 1 条」来自本次。
  xcrun simctl terminate "$sim_udid" "$bundle_id" >/dev/null 2>&1 || true
  xcrun simctl uninstall "$sim_udid" "$bundle_id" >/dev/null 2>&1 || true
  assert_empty_container || return 1

  # UI 流由启动参数 -uiTestLocation 门控的 DEBUG 确定性测试源驱动，不依赖 simulator
  # 定位投递；真实 CoreLocation 覆盖由 scripts/verify-ios-sim-runtime.sh 的门禁承担。
  record_step "location-source" true "确定性测试源 -uiTestLocation（真实 CoreLocation 由 verify-ios-sim-runtime 覆盖）"

  # 只跑真实流程用例，避免播报开关用例的 terminate/relaunch 干扰「恰 1 条跑次」。
  xcodebuild test \
    -project "$project_path" \
    -scheme "$scheme" \
    -destination "$destination" \
    -derivedDataPath "$derived_data" \
    -only-testing:PurePaceUITests/RunFlowUITests/testRunPauseResumeFinishAndHistory \
    -resultBundlePath "$result_bundle" \
    CODE_SIGNING_ALLOWED=NO >"$xcode_log" 2>&1
  xcode_status=$?
  if [ "$xcode_status" -ne 0 ]; then
    tail_output="$(tail -n 40 "$xcode_log" 2>/dev/null || true)"
    printf '%s\n' "$tail_output" >&2
    fail_step "ui-test" "xcodebuild test 退出 ${xcode_status}（日志 ${xcode_log}）"
    return 1
  fi
  record_step "ui-test" true "RunFlowUITests/testRunPauseResumeFinishAndHistory 真实通过"

  probe_container || return 1
  parse_export_consistency || return 1
  export_screenshots || return 1
}

set +e
main
main_status=$?
write_report
report_status=$?
set -e

if [ "$report_status" -ne 0 ]; then
  printf 'verify-ios-ui-e2e: report.json 判定失败（%s）\n' "$report_path" >&2
  [ "$main_status" -ne 0 ] || main_status="$report_status"
fi

if [ "$main_status" -ne 0 ]; then
  printf 'verify-ios-ui-e2e: 存在失败项，详见 %s\n' "$report_path" >&2
  exit 1
fi
printf 'verify-ios-ui-e2e: 模拟器链路通过（模拟器 + 代码层），报告 %s\n' "$report_path"
