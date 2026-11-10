#!/usr/bin/env bash
# 真机自动化取证（需真机连接）：一条脚本、四种模式 --phase=audit|audio|background|tcc；
# `--list` 无需真机即可列出阶段与用例（exit 0）。
#
# 目标设备：公司给定 UDID 00008101-001C701E0A68001E（可用 --device 或 PUREPACE_DEVICE_UDID 覆盖）；
# 不假设模拟器可用，不做桌面端自研驱动，不装 mobilecli agent。
#
# 背景语义（公司裁决 owe_573178ee739c4d74）：测试期间设备已关闭自动锁屏，本版只验
# 「切后台连续记录」，不是「锁屏连续记录」。唯一前后台动作是 press(.home)，不驱动锁屏/解锁。
# 6 分钟等待放 Mac 侧（宿主 sleep + devicectl 只读读容器），不在测试进程内 sleep 断言后台连续性。
#
# 驱动方式：xcodegen 生成工程 → xcodebuild build-for-testing + test-without-building（设备端 XCUITest）
# → xcresulttool 导出截图/可及树/结果 JSON → devicectl 只读取 App 数据容器 → 汇总 report.md。
# 证据落盘：artifacts/device-audit/<UTC 时间戳>/（截图、*.ax.json、run-*.json、announcements-*.json、
# *.gpx、sha256.txt、report.md）；中间产物只留 .build/device-flow/。
#
# 硬约束：不修改 ios/PurePace/** 业务源码；不驱动锁屏/解锁；不在 run 内要求人按任何步骤；
# 未自动化到的人手点只写「pending: 待人现场（needs-you 单点）」。
set -euo pipefail

usage() {
  cat <<'EOF'
用法: scripts/verify-ios-device-flow.sh --phase=audit|audio|background|tcc [选项]
      scripts/verify-ios-device-flow.sh --list

真机自动化取证（需真机连接，目标 UDID 00008101-001C701E0A68001E）：

  --phase=audit       候选包首屏审计：五个读数位 / 三 Tab / 详情导出入口；产出截图、
                      *.ax.json、audit-result.json 与 report.md。
  --phase=audio       Debug 构建 + -uiTestLocation 确定性源：跨一次公里边界并起系统 Music，
                      机器读回 telemetry.announcements[] 的 km 触发 / duck 应用与恢复 /
                      isOtherAudioPlaying；落盘截图序列、跑次 JSON、announcements 抽取。
  --phase=background  Release 构建：开跑 → 起 Music → press(.home) → Mac 侧等 5–6 分钟后
                      回前台结束保存、历史、导出 GPX；读回 checkpoint/跑次/GPX 并实算 sha256。
                      设备不锁屏前提下可随时读容器；结论只写「切后台后进程存活 + 持续采样」。
  --phase=tcc         Debug 构建 + 真实 CoreLocation：可复用 TCC 授权步骤（SpringBoard 应用
                      查询 + addUIInterruptionMonitor 兜底 + 精确 label 匹配）打通新装首启
                      → 首次弹窗 → Always 升级，最后以跑次 JSON 的 App 自报为准
                      （telemetry.authorizationStatus.name==authorizedAlways / rawValue==3）。

选项:
  --phase <mode>            等价于 --phase=<mode>
  --device <udid>           覆盖目标设备（默认 00008101-001C701E0A68001E）
  --candidate <zip>         候选包 zip 路径（默认匹配 artifacts/candidates/PurePace-Release-*.zip）
  --list                    列出全部阶段与用例后退出 0（无真机也可运行，不做 preflight）
  -h, --help                显示本帮助并退出 0

环境变量:
  PUREPACE_DEVICE_UDID      覆盖目标设备 UDID
  PUREPACE_BUNDLE_ID        被测 App bundle id（默认 sh.munk.purepace）
  PUREPACE_DEVELOPMENT_TEAM 签名团队（默认 3X4J53U6RY，仅命令行临时传入）
  PUREPACE_BACKGROUND_SECONDS  background 阶段后台窗口秒数（默认 330，允许 300–360）
  PUREPACE_CANDIDATE_ZIP    候选包 zip 路径（同 --candidate）

退出码:
  0  该阶段全部机器断言通过
  1  任一步骤/断言失败（证据与 report.md 已落盘，失败原因写明）
  2  参数非法（缺 phase、未知参数、非法 phase）
EOF
}

phase=""
list_mode=0
candidate_path="${PUREPACE_CANDIDATE_ZIP:-}"
device_udid="${PUREPACE_DEVICE_UDID:-00008101-001C701E0A68001E}"
bundle_id="${PUREPACE_BUNDLE_ID:-sh.munk.purepace}"
team_id="${PUREPACE_DEVELOPMENT_TEAM:-3X4J53U6RY}"
background_seconds="${PUREPACE_BACKGROUND_SECONDS:-330}"

while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --list)
      list_mode=1
      ;;
    --phase=*)
      phase="${1#--phase=}"
      ;;
    --phase)
      shift
      phase="${1:-}"
      ;;
    --device=*)
      device_udid="${1#--device=}"
      ;;
    --device)
      shift
      device_udid="${1:-}"
      ;;
    --candidate=*)
      candidate_path="${1#--candidate=}"
      ;;
    --candidate)
      shift
      candidate_path="${1:-}"
      ;;
    *)
      echo "verify-ios-device-flow: 未知参数 '$1'（使用 --help 查看用法）" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

if [ "$list_mode" -eq 1 ]; then
  cat <<'EOF'
verify-ios-device-flow: 阶段与用例（--list，无需真机；默认模拟器 UI 腿已排除本套件）

  audit       Release  PurePaceUITests/DeviceFlowUITests/testAuditFirstScreenAndTabs
  audio       Debug    PurePaceUITests/DeviceFlowUITests/testAudioKilometerBoundaryWithMusic
  background  Release  PurePaceUITests/DeviceFlowUITests/testBackgroundStartAndPressHome
                       PurePaceUITests/DeviceFlowUITests/testBackgroundFinishSaveAndExport
  tcc         Debug    PurePaceUITests/TCCAuthorizationUITests/testTCCFreshInstallReachesAuthorizedAlways
EOF
  exit 0
fi

case "$phase" in
  audit|audio|background|tcc) ;;
  *)
    echo "verify-ios-device-flow: 缺少或非法的 --phase（只接受 audit|audio|background|tcc；用 --list 查看）" >&2
    usage >&2
    exit 2
    ;;
esac

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
cd "$repo_root"

project_path="ios/PurePace.xcodeproj"
spec_path="ios/project.yml"
scheme="PurePace"
derived_data=".build/device-flow/DerivedData"
phase_dir=".build/device-flow/${phase}"
utc_stamp="$(date -u +%Y%m%dT%H%M%SZ)"
evidence_dir="artifacts/device-audit/${utc_stamp}"
failures_file="${phase_dir}/failures.txt"
meta_json="${phase_dir}/meta.json"
analysis_json="${evidence_dir}/analysis.json"

case "$phase" in
  audit) test_suite="DeviceFlowUITests"; test_case="testAuditFirstScreenAndTabs"; build_configuration="Release" ;;
  audio) test_suite="DeviceFlowUITests"; test_case="testAudioKilometerBoundaryWithMusic"; build_configuration="Debug" ;;
  background) test_suite="DeviceFlowUITests"; test_case="testBackgroundStartAndPressHome"; build_configuration="Release" ;;
  tcc) test_suite="TCCAuthorizationUITests"; test_case="testTCCFreshInstallReachesAuthorizedAlways"; build_configuration="Debug" ;;
esac

if [ "$phase" = "background" ]; then
  case "$background_seconds" in
    ''|*[!0-9]*)
      echo "verify-ios-device-flow: PUREPACE_BACKGROUND_SECONDS 必须是整数" >&2
      exit 2
      ;;
  esac
  if [ "$background_seconds" -lt 300 ] || [ "$background_seconds" -gt 360 ]; then
    echo "verify-ios-device-flow: PUREPACE_BACKGROUND_SECONDS 必须在 300–360 秒" >&2
    exit 2
  fi
fi

fail_step() {
  local name="$1" reason="$2"
  printf '%s: %s\n' "$name" "$reason" >> "$failures_file"
  printf 'verify-ios-device-flow: %s 失败: %s\n' "$name" "$reason" >&2
}

info() {
  printf 'verify-ios-device-flow: %s\n' "$*"
}

# 可重复执行：每次从干净的 .build 阶段目录开始；证据目录按 UTC 时间戳独立，不覆盖历史。
rm -rf -- "$phase_dir"
mkdir -p "$phase_dir" "$evidence_dir"
: > "$failures_file"

python3 - "$meta_json" "$phase" "$device_udid" "$bundle_id" "$build_configuration" <<'PY'
import json
import subprocess
import sys
import datetime

path, phase, udid, bundle_id, configuration = sys.argv[1:6]
meta = {
    "phase": phase,
    "udid": udid,
    "bundleId": bundle_id,
    "configuration": configuration,
    "startedAt": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "script": "scripts/verify-ios-device-flow.sh",
}
try:
    meta["commit"] = subprocess.run(
        ["git", "rev-parse", "--short=12", "HEAD"], capture_output=True, text=True, check=True
    ).stdout.strip()
    meta["commitFull"] = subprocess.run(
        ["git", "rev-parse", "HEAD"], capture_output=True, text=True, check=True
    ).stdout.strip()
except Exception:
    meta["commit"] = None
    meta["commitFull"] = None
with open(path, "w", encoding="utf-8") as handle:
    json.dump(meta, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
PY

merge_meta() {
  python3 - "$meta_json" "$@" <<'PY'
import json
import sys

path = sys.argv[1]
pairs = sys.argv[2:]
with open(path, "r", encoding="utf-8") as handle:
    meta = json.load(handle)
for index in range(0, len(pairs), 2):
    key = pairs[index]
    raw = pairs[index + 1]
    try:
        value = json.loads(raw)
    except Exception:
        value = raw
    meta[key] = value
with open(path, "w", encoding="utf-8") as handle:
    json.dump(meta, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
PY
}

merge_meta testSuite "$test_suite"

# ---------------------------------------------------------------- 预检
preflight() {
  local missing=""
  for command in xcrun xcodebuild xcodegen python3 git; do
    if ! command -v "$command" >/dev/null 2>&1; then
      missing="${missing} ${command}"
    fi
  done
  if [ -n "$missing" ]; then
    fail_step "environment" "缺少必需命令:${missing}"
    return 1
  fi

  if ! xcrun devicectl device info details \
    --device "$device_udid" \
    --json-output "${phase_dir}/device-details.json" >/dev/null 2>&1; then
    fail_step "device" "目标真机不可达或不可用（xcrun devicectl device info details --device ${device_udid} 失败）"
    return 1
  fi
  python3 - "$meta_json" "${phase_dir}/device-details.json" <<'PY'
import json
import sys

meta_path, details_path = sys.argv[1], sys.argv[2]
with open(meta_path, "r", encoding="utf-8") as handle:
    meta = json.load(handle)
try:
    with open(details_path, "r", encoding="utf-8") as handle:
        result = json.load(handle).get("result", {})
    hardware = result.get("hardwareProperties", {})
    device = result.get("deviceProperties", {})
    meta["deviceModel"] = hardware.get("marketingName")
    meta["productType"] = hardware.get("productType")
    meta["iosVersion"] = device.get("osVersionNumber")
    meta["osBuild"] = device.get("osBuildUpdate")
    meta["deviceName"] = device.get("name")
except Exception as exc:  # noqa: BLE001
    meta["deviceDetailsError"] = str(exc)
with open(meta_path, "w", encoding="utf-8") as handle:
    json.dump(meta, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
PY
  info "目标真机 ${device_udid} 可达（${build_configuration} 构建，用例 ${test_case}）"
}

observe_lock_state() {
  local label="$1"
  local out="${phase_dir}/lockstate-${label}.json"
  if xcrun devicectl device info lockState --device "$device_udid" --json-output "$out" >/dev/null 2>&1; then
    python3 - "$meta_json" "$label" "$out" <<'PY'
import json
import sys

meta_path, label, path = sys.argv[1], sys.argv[2], sys.argv[3]
with open(meta_path, "r", encoding="utf-8") as handle:
    meta = json.load(handle)
try:
    with open(path, "r", encoding="utf-8") as handle:
        result = json.load(handle).get("result", {})
    meta["lockState_" + label] = {
        "passcodeRequired": result.get("passcodeRequired"),
        "unlockedSinceBoot": result.get("unlockedSinceBoot"),
    }
except Exception as exc:  # noqa: BLE001
    meta["lockState_" + label] = {"error": str(exc)}
with open(meta_path, "w", encoding="utf-8") as handle:
    json.dump(meta, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
PY
  fi
}

collect_candidate_identity() {
  if [ -z "$candidate_path" ]; then
    for candidate in artifacts/candidates/PurePace-Release-*.zip; do
      if [ -e "$candidate" ]; then
        candidate_path="$candidate"
        break
      fi
    done
  fi
  if [ -n "$candidate_path" ] && [ -f "$candidate_path" ]; then
    candidate_sha="$(shasum -a 256 "$candidate_path" | cut -d' ' -f1)"
    merge_meta candidatePath "$candidate_path" candidateSha256 "$candidate_sha" \
      candidateBytes "$(wc -c < "$candidate_path" | tr -d ' ')"
    info "候选包 ${candidate_path}（sha256 ${candidate_sha}）"
  else
    merge_meta candidatePath "" candidateSha256 "" candidateBytes 0
    info "未提供候选包 zip：报告将只记录实际驱动构建身份"
  fi
}

generate_project() {
  if ! xcodegen generate --spec "$spec_path" --project ios >"${phase_dir}/xcodegen.log" 2>&1; then
    fail_step "generate-project" "xcodegen 从 ${spec_path} 生成工程失败（日志 ${phase_dir}/xcodegen.log）"
    return 1
  fi
  info "xcodegen 已按 ${spec_path} 生成 ${project_path}"
}

build_for_testing() {
  local log="${phase_dir}/build-for-testing.log"
  # Release 下 PurePaceTests 的 @testable import 需要 ENABLE_TESTABILITY；仅命令行临时覆盖，
  # 不落入工程文件。构建身份在 report.md 中如实记录。
  set +e
  xcodebuild build-for-testing \
    -project "$project_path" \
    -scheme "$scheme" \
    -destination "id=${device_udid}" \
    -configuration "$build_configuration" \
    -derivedDataPath "$derived_data" \
    -only-testing:"PurePaceUITests/${test_suite}/${test_case}" \
    -allowProvisioningUpdates \
    DEVELOPMENT_TEAM="$team_id" \
    CODE_SIGNING_ALLOWED=YES \
    CODE_SIGN_STYLE=Automatic \
    ENABLE_TESTABILITY=YES >"$log" 2>&1
  local status=$?
  set -e
  if [ "$status" -ne 0 ]; then
    fail_step "build-for-testing" "xcodebuild build-for-testing 退出 ${status}（日志 ${log}）"
    return 1
  fi
  info "build-for-testing 完成（${build_configuration}）"
}

run_case() {
  local case_name="$1" result_bundle="$2" log="$3"
  set +e
  xcodebuild test-without-building \
    -project "$project_path" \
    -scheme "$scheme" \
    -destination "id=${device_udid}" \
    -configuration "$build_configuration" \
    -derivedDataPath "$derived_data" \
    -only-testing:"PurePaceUITests/${test_suite}/${case_name}" \
    -resultBundlePath "$result_bundle" \
    -allowProvisioningUpdates \
    DEVELOPMENT_TEAM="$team_id" \
    CODE_SIGNING_ALLOWED=YES \
    CODE_SIGN_STYLE=Automatic >"$log" 2>&1
  local status=$?
  set -e
  return "$status"
}

export_attachments() {
  local result_bundle="$1" out="$2"
  mkdir -p "$out"
  if ! xcrun xcresulttool export attachments --path "$result_bundle" --output-path "$out" >/dev/null 2>&1; then
    fail_step "attachments" "xcresulttool export attachments 失败（${result_bundle}）"
    return 1
  fi
  python3 - "$out" "$evidence_dir" <<'PY'
import json
import os
import re
import shutil
import sys

attachments_dir, evidence_dir = sys.argv[1], sys.argv[2]
manifest_path = os.path.join(attachments_dir, "manifest.json")


def normalize(suggested, exported):
    stem, ext = os.path.splitext(suggested)
    # XCTest 附件名会被追加 `_<index>_<UUID>`；去掉后恢复用例显式命名的稳定文件名。
    stem = re.sub(r"_\d+_[0-9A-Fa-f-]{36}$", "", stem)
    if not ext:
        ext = os.path.splitext(exported)[1]
    return stem + ext


entries = []
try:
    with open(manifest_path, "r", encoding="utf-8") as handle:
        manifest = json.load(handle)
except Exception:
    manifest = []
problems = []
for test in manifest if isinstance(manifest, list) else []:
    for attachment in test.get("attachments", []) or []:
        exported = attachment.get("exportedFileName")
        suggested = attachment.get("suggestedHumanReadableName") or exported or ""
        if not exported:
            continue
        source = os.path.join(attachments_dir, exported)
        if not os.path.isfile(source) or os.path.getsize(source) <= 0:
            problems.append("附件为空或不存在: %s" % suggested)
            continue
        target_name = normalize(suggested, exported)
        shutil.copyfile(source, os.path.join(evidence_dir, target_name))
        entries.append({"name": target_name, "bytes": os.path.getsize(source)})
with open(os.path.join(evidence_dir, "attachments-manifest.json"), "w", encoding="utf-8") as handle:
    json.dump({"entries": entries, "problems": problems}, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
if problems:
    sys.stderr.write("\n".join(problems) + "\n")
    sys.exit(1)
PY
}

copy_directory_from_container() {
  local source="$1" dest="$2" label="$3"
  mkdir -p "$dest"
  if xcrun devicectl device copy from \
    --device "$device_udid" \
    --domain-type appDataContainer \
    --domain-identifier "$bundle_id" \
    --source "$source" \
    --destination "$dest" >>"${phase_dir}/container-copy.log" 2>&1; then
    return 0
  fi
  info "容器只读复制 ${label} 无内容或不可用（${source}）"
  return 1
}

copy_container() {
  local dest="$1"
  mkdir -p "$dest/Runs" "$dest/Exports"
  copy_directory_from_container "Documents/Runs" "$dest/Runs" "Documents/Runs" || true
  copy_directory_from_container "Documents/Exports" "$dest/Exports" "Documents/Exports" || true
  if xcrun devicectl device copy from \
    --device "$device_udid" \
    --domain-type appDataContainer \
    --domain-identifier "$bundle_id" \
    --source "Library/Caches/active-run.jsonl" \
    --destination "$dest/active-run.jsonl" >>"${phase_dir}/container-copy.log" 2>&1; then
    info "已只读复制 checkpoint（Library/Caches/active-run.jsonl）"
  else
    info "当前无运行中 checkpoint（Library/Caches/active-run.jsonl 不存在）"
  fi
  info "容器证据只读复制到 ${dest}"
}

# ---------------------------------------------------------------- 分析 + 报告
analyze_and_report() {
  local staging_before="${phase_dir}/container-window"
  local staging_after="${phase_dir}/container-after"
  python3 - "$phase" "$evidence_dir" "$meta_json" "$failures_file" "$analysis_json" \
    "$staging_before" "$staging_after" <<'PY'
import datetime
import glob
import hashlib
import json
import os
import re
import shutil
import sys
import xml.etree.ElementTree as ET

phase, evidence_dir, meta_path, failures_path, analysis_path, before_dir, after_dir = sys.argv[1:8]
gpx_ns = "http://www.topografix.com/GPX/1/1"

with open(meta_path, "r", encoding="utf-8") as handle:
    meta = json.load(handle)

failures = []
if os.path.exists(failures_path):
    with open(failures_path, "r", encoding="utf-8") as handle:
        for raw in handle:
            line = raw.strip()
            if not line:
                continue
            step, _, reason = line.partition(": ")
            failures.append({"step": step, "reason": reason or line})

checks = []


def check(name, ok, detail, evidence=None):
    entry = {"name": name, "ok": bool(ok), "detail": detail}
    if evidence:
        entry["evidence"] = evidence
    checks.append(entry)
    return entry


def read_json(path, default=None):
    try:
        with open(path, "r", encoding="utf-8") as handle:
            return json.load(handle)
    except Exception:
        return default


def nonempty(path):
    return os.path.isfile(path) and os.path.getsize(path) > 0


def pick_newest_runs(directories, since_epoch):
    candidates = []
    for directory in directories:
        for path in glob.glob(os.path.join(directory, "Runs", "*.json")):
            doc = read_json(path)
            if not isinstance(doc, dict):
                continue
            started = doc.get("startedAt")
            if not isinstance(started, (int, float)):
                continue
            if since_epoch is not None and started < since_epoch - 60:
                continue
            candidates.append((started, path, doc))
    candidates.sort(key=lambda item: item[0])
    return candidates


def copy_evidence_file(source, dest_dir, prefix):
    if not source or not os.path.isfile(source):
        return None
    target = os.path.join(dest_dir, prefix + os.path.basename(source))
    shutil.copyfile(source, target)
    return os.path.basename(target)


def sha256_of(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def parse_gpx(path):
    root = ET.parse(path).getroot()
    trkpts = []
    for node in root.iter("{%s}trkpt" % gpx_ns):
        time_node = node.find("{%s}time" % gpx_ns)
        text = time_node.text.strip() if time_node is not None and time_node.text else None
        trkpts.append({"lat": float(node.get("lat")), "lon": float(node.get("lon")), "time": text})
    return trkpts


def epoch_seconds(text):
    if not text:
        raise ValueError("缺失 <time>")
    value = text.strip()
    if value.endswith("Z"):
        value = value[:-1] + "+00:00"
    return datetime.datetime.fromisoformat(value).timestamp()


def announce_checks(announcements):
    if not announcements:
        check("announcements-present", False, "telemetry.announcements[] 为空", "run JSON")
        return
    km = [a for a in announcements if a.get("splitIndex") == 1]
    km_text = [a for a in km if "第 1 公里" in str(a.get("text", ""))]
    check(
        "announcements-km-trigger",
        bool(km_text),
        "announcements=%d，splitIndex==1 且 text 含「第 1 公里」的条目=%d（telemetry 无独立 trigger 字段，"
        "公里触发由 splitIndex/text 推得）" % (len(announcements), len(km_text)),
        "announcements-*.json",
    )
    entry = (km_text or km or [announcements[0]])[0]
    check(
        "announcements-audio-session",
        bool(entry.get("category")) and bool(entry.get("mode")) and isinstance(entry.get("categoryOptions"), list),
        "category=%r mode=%r options=%r"
        % (entry.get("category"), entry.get("mode"), entry.get("categoryOptions")),
        "announcements-*.json",
    )
    options = entry.get("categoryOptions") or []
    check(
        "announcements-duck-applied-and-restored",
        "duckOthers" in options and entry.get("duckRevoked") is True,
        "categoryOptions 含 duckOthers=%s，duckRevoked=%r，sessionActivated=%r，sessionDeactivated=%r"
        % ("duckOthers" in options, entry.get("duckRevoked"), entry.get("sessionActivated"), entry.get("sessionDeactivated")),
        "announcements-*.json",
    )
    check(
        "announcements-other-audio-playing",
        isinstance(entry.get("isOtherAudioPlaying"), bool),
        "isOtherAudioPlaying=%r（原样记录，不伪造 true）" % (entry.get("isOtherAudioPlaying"),),
        "announcements-*.json",
    )


def checkpoint_continuity(path, pressed_home, window_seconds):
    if not os.path.isfile(path):
        check("background-checkpoint", False, "未读到 Library/Caches/active-run.jsonl（checkpoint）", None)
        return
    records = []
    with open(path, "r", encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            try:
                records.append(json.loads(line))
            except Exception:
                continue
    if not records:
        check("background-checkpoint", False, "checkpoint 无有效记录", "active-run.jsonl")
        return
    times = [float(r.get("recordedAt", 0)) for r in records]
    monotonic = all(times[i] >= times[i - 1] for i in range(1, len(times)))
    gaps = [times[i] - times[i - 1] for i in range(1, len(times))]
    max_gap = max(gaps) if gaps else 0.0
    first, last = times[0], times[-1]
    window_end = pressed_home + window_seconds
    check(
        "background-first-before-home",
        first < pressed_home,
        "首条 checkpoint 早于 press(.home)：%.1fs vs %.1fs" % (first, pressed_home),
        "active-run.jsonl",
    )
    check(
        "background-last-after-window",
        last >= window_end - 60,
        "末条 checkpoint 晚于后台窗口结束（允许 60s 容差）：%.1fs vs %.1fs" % (last, window_end),
        "active-run.jsonl",
    )
    check(
        "background-max-gap",
        max_gap <= 60,
        "相邻 checkpoint 最大空洞 %.1fs（上限 60s）" % max_gap,
        "active-run.jsonl",
    )
    check("background-monotonic", monotonic, "recordedAt 时间序列%s" % ("单调不减" if monotonic else "出现回退"),
          "active-run.jsonl")
    if len(records) >= 2:
        check(
            "background-window-observed",
            last - first >= window_seconds - 120,
            "checkpoint 观测跨度 %.1fs（后台窗口 %ss）" % (last - first, window_seconds),
            "active-run.jsonl",
        )


def build_identity_lines():
    candidate_sha = meta.get("candidateSha256") or ""
    actual = "bundle %s / version %s / build %s / 配置 %s / commit %s" % (
        meta.get("bundleId"),
        meta.get("appVersion") or "?",
        meta.get("appBundleVersion") or "?",
        meta.get("configuration"),
        meta.get("commit") or "?",
    )
    lines = ["- 实际驱动构建：" + actual]
    if candidate_sha:
        lines.append(
            "- 候选包 zip：%s（sha256 `%s`，%s 字节）"
            % (meta.get("candidatePath"), candidate_sha, meta.get("candidateBytes"))
        )
        lines.append(
            "- 二进制一致性：实际驱动构建 = 当前 worktree commit `%s` 的 %s 构建；本脚本未解包比对候选 zip 内 `.app`，"
            "故一律标注「实际驱动构建 ≠ 候选包二进制」，不宣称「候选包已验证」；"
            "差异原因：候选 zip 由交付侧独立构建，本脚本只按同一 %s 配置复现，未做二进制等价证明。"
            % (meta.get("commit") or "?", meta.get("configuration"), meta.get("configuration"))
        )
    else:
        lines.append("- 候选包 zip：未提供（本报告不宣称任何候选包已验证）")
    return lines


def render_report(ok):
    lines = []
    lines.append("# 真机取证报告（%s）" % phase)
    lines.append("")
    lines.append("- 口径：真机自动化取证（需真机连接）")
    lines.append("- 阶段：`%s`，构建配置：`%s`" % (phase, meta.get("configuration")))
    lines.append("- 目标设备：%s（UDID `%s`，%s / iOS %s build %s）"
                 % (meta.get("deviceModel") or "?", meta.get("udid"),
                    meta.get("productType") or "?", meta.get("iosVersion") or "?",
                    meta.get("osBuild") or "?"))
    lines.append("- 起止时间：%s → %s"
                 % (meta.get("startedAt"), meta.get("finishedAt") or "?"))
    lines.append("- 用例：`PurePaceUITests/%s/%s`"
                 % (meta.get("testSuite") or "DeviceFlowUITests", meta.get("testCase")))
    lines.append("- 结论：%s" % ("机器断言通过" if ok else "存在失败项"))
    lines.append("")
    lines.extend(build_identity_lines())
    lines.append("")
    lines.append("## 断言逐项")
    lines.append("")
    lines.append("| 断言项 | 结果 | 证据 / 说明 |")
    lines.append("|---|---|---|")
    for entry in checks:
        lines.append("| `%s` | %s | %s |"
                     % (entry["name"], "PASS" if entry["ok"] else "FAIL", entry["detail"]))
    lines.append("")
    lines.append("## 失败项")
    lines.append("")
    if failures:
        for failure in failures:
            lines.append("- `%s`: %s" % (failure["step"], failure["reason"]))
    else:
        lines.append("- 无")
    lines.append("")
    lines.append("## 证据文件")
    lines.append("")
    for name in sorted(os.listdir(evidence_dir)):
        if name == "report.md":
            continue
        lines.append("- `%s`（%d 字节）" % (name, os.path.getsize(os.path.join(evidence_dir, name))))
    lines.append("")
    lines.append("## pending: 待人现场（needs-you 单点）")
    lines.append("")
    lines.append("- 锁屏态本版不验；如公司要求补，只由人在最终候选包上做一次「电源键 + 解锁」（≤ 30 秒），"
                 "由公司另排，产品侧不得自行加进脚本或窗口。")
    lines.append("- 人耳判定（≤ 2 条）随机器证据一次性交回公司负责人：播报是否听清；音乐 duck 后听感是否恢复。")
    lines.append("- 断言清单确认：`docs/device-assertion-matrix.md` 待 PO 转公司确认（`pending: 待公司确认`）；"
                 "确认后才跑 `--phase=audio` / `--phase=background` 正式场。")
    if not ok:
        lines.append("- 本阶段存在机器失败项，需公司确认后另行安排。")
    lines.append("")
    with open(os.path.join(evidence_dir, "report.md"), "w", encoding="utf-8") as handle:
        handle.write("\n".join(lines))


phase_started_epoch = None
started_text = meta.get("startedAt")
if started_text:
    try:
        phase_started_epoch = datetime.datetime.strptime(
            started_text, "%Y-%m-%dT%H:%M:%SZ"
        ).replace(tzinfo=datetime.timezone.utc).timestamp()
    except Exception:
        phase_started_epoch = None

# 以实际驱动构建的设备信息补全身份。
apps_json = read_json(os.path.join(os.path.dirname(meta_path), "installed-app.json"), {})
try:
    app_entry = (apps_json.get("result", {}).get("apps") or [{}])[0]
    if app_entry:
        meta["appVersion"] = app_entry.get("version")
        meta["appBundleVersion"] = app_entry.get("bundleVersion")
except Exception:
    pass

if phase == "audit":
    result = read_json(os.path.join(evidence_dir, "audit-result.json"), {})
    for name in ["audit-runview.png", "audit-run-tab.png", "audit-history.png", "audit-settings.png"]:
        check("audit-screenshot-%s" % name, nonempty(os.path.join(evidence_dir, name)),
              "截图 %s %s" % (name, "存在且非空" if nonempty(os.path.join(evidence_dir, name)) else "缺失或为空"),
              name)
    for name in ["audit-runview.ax.json", "audit-run-tab.ax.json", "audit-history.ax.json",
                 "audit-settings.ax.json", "audit-detail.ax.json"]:
        check("audit-ax-%s" % name, nonempty(os.path.join(evidence_dir, name)),
              "可及树 %s %s" % (name, "存在且非空" if nonempty(os.path.join(evidence_dir, name)) else "缺失或为空"),
              name)

    metrics = (result or {}).get("fiveMetrics") or {}
    expected_metrics = ["run.distance", "run.elapsed", "run.currentPace", "run.averagePace", "run.splits"]
    ax_text = ""
    ax_path = os.path.join(evidence_dir, "audit-runview.ax.json")
    ax_doc = read_json(ax_path, {})
    if isinstance(ax_doc, dict):
        ax_text = str(ax_doc.get("dump", ""))
    missing = [identifier for identifier in expected_metrics
               if not ((metrics.get(identifier) or {}).get("exists") is True or identifier in ax_text)]
    check(
        "audit-runview-five-metrics",
        not missing,
        "五读数位: " + ", ".join(
            "%s=%s" % (identifier, "PASS" if identifier not in missing else "MISSING")
            for identifier in expected_metrics
        ) + (("；缺失: " + ", ".join(missing)) if missing else ""),
        "audit-runview.png / audit-runview.ax.json",
    )

    tabs = (result or {}).get("tabs") or {}
    tabs_ok = all((tabs.get(key) or {}).get("ok") is True for key in ["run", "history", "settings"])
    check(
        "audit-three-tabs",
        tabs_ok,
        "Run/History/Settings 逐项: " + ", ".join(
            "%s=%s" % (key, "PASS" if (tabs.get(key) or {}).get("ok") is True else "FAIL")
            for key in ["run", "history", "settings"]
        ),
        "audit-run-tab.png / audit-history.png / audit-settings.png",
    )

    detail = (result or {}).get("detailExport") or {}
    detail_ok = detail.get("archiveAvailable") is True and detail.get("exists") is True and detail.get("hittable") is True
    detail_reason = detail.get("reason") or ""
    check(
        "audit-detail-gpx-entry",
        detail_ok,
        "runDetail.export exists=%r hittable=%r 归档可用=%r%s"
        % (detail.get("exists"), detail.get("hittable"), detail.get("archiveAvailable"),
           ("；原因: " + detail_reason) if detail_reason else ""),
        "audit-detail.png / audit-detail.ax.json / audit-result.json",
    )

    check(
        "audit-build-identity",
        bool(meta.get("commit")),
        "实际驱动构建 bundle %s / 配置 %s / commit %s；与候选 zip 的同一性未解包比对，按口径显式标注"
        % (meta.get("bundleId"), meta.get("configuration"), meta.get("commit")),
        "report.md",
    )

elif phase == "audio":
    audio_result = read_json(os.path.join(evidence_dir, "audio-result.json"), {})
    for name in ["audio-start.png", "audio-km.png", "audio-finish.png"]:
        check("audio-screenshot-%s" % name, nonempty(os.path.join(evidence_dir, name)),
              "截图 %s %s" % (name, "存在且非空" if nonempty(os.path.join(evidence_dir, name)) else "缺失或为空"),
              name)
    check(
        "audio-music-playing-confirmed",
        (audio_result or {}).get("musicPlayingConfirmed") is True,
        "系统 Music 启动/在播确认: musicRunning=%r musicPlayingConfirmed=%r（确认不了即 FAIL，不伪造）"
        % ((audio_result or {}).get("musicRunning"), (audio_result or {}).get("musicPlayingConfirmed")),
        "audio-music.png / audio-result.json",
    )

    runs = pick_newest_runs([os.path.join(os.path.dirname(meta_path), "container-after")],
                            phase_started_epoch)
    run = runs[-1][2] if runs else None
    if run is None:
        check("audio-run-json", False, "未读到本次跑次 JSON（Documents/Runs）", None)
        announcements = []
    else:
        copied_run = copy_evidence_file(runs[-1][1], evidence_dir, "run-")
        check("audio-run-json", bool(copied_run), "跑次 JSON 已复制: %s" % copied_run, copied_run)
        telemetry = run.get("telemetry") or {}
        announcements = telemetry.get("announcements") or []
        announce_path = os.path.join(evidence_dir, "announcements-%s.json" % run.get("id", "unknown"))
        with open(announce_path, "w", encoding="utf-8") as handle:
            json.dump(announcements, handle, ensure_ascii=False, indent=2)
            handle.write("\n")
        announce_checks(announcements)
        duration = run.get("activeDuration")
        check(
            "audio-single-run-bounded",
            isinstance(duration, (int, float)) and 60 <= duration <= 90,
            "activeDuration=%.1fs（验收窗口 60–90s；-uiTestLocation 默认节奏约 10 m/s，跨 1 km 约 100s）"
            % duration if isinstance(duration, (int, float)) else "activeDuration 缺失",
            "run JSON",
        )
        samples = run.get("samples") or []
        check("audio-sample-count", len(samples) > 1, "samples=%d" % len(samples), "run JSON")
        sources = sorted({str(sample.get("source")) for sample in samples})
        check("audio-sample-source-simulated", sources == ["simulated"],
              "samples[].source=%r（-uiTestLocation 确定性路径）" % sources, "run JSON")

    gpx_files = sorted(glob.glob(os.path.join(os.path.dirname(meta_path), "container-after", "Exports", "*.gpx")))
    if gpx_files:
        gpx_path = gpx_files[-1]
        target = copy_evidence_file(gpx_path, evidence_dir, "")
        check("audio-gpx-artifact", bool(target), "导出 GPX: %s" % target, target)
        if target:
            digest = sha256_of(os.path.join(evidence_dir, target))
            with open(os.path.join(evidence_dir, "sha256.txt"), "w", encoding="utf-8") as handle:
                handle.write("%s  %s\n" % (digest, target))
            check("audio-gpx-sha256", re.fullmatch(r"[0-9a-f]{64}", digest) is not None,
                  "sha256=%s（%d 字节）" % (digest, os.path.getsize(os.path.join(evidence_dir, target))),
                  "sha256.txt")

elif phase == "tcc":
    tcc = read_json(os.path.join(evidence_dir, "tcc-result.json"), {}) or {}
    check(
        "tcc-result-json",
        bool(tcc),
        "tcc-result.json %s" % ("已落盘" if tcc else "缺失：TCC 授权步骤未产出诊断附件"),
        "tcc-result.json",
    )
    mode = tcc.get("authorizationMode")
    first_handled = tcc.get("firstPromptHandled")
    check(
        "tcc-authorization-mode",
        mode in ("grantedThisRun", "preAuthorized"),
        "authorizationMode=%r（只接受 grantedThisRun / preAuthorized）" % mode,
        "tcc-result.json",
    )
    check(
        "tcc-first-prompt-consistency",
        (mode == "grantedThisRun" and first_handled is True)
        or (mode == "preAuthorized" and first_handled is False),
        "authorizationMode=%r firstPromptHandled=%r（grantedThisRun 必须 true；preAuthorized 必须 false）"
        % (mode, first_handled),
        "tcc-result.json",
    )

    failure_entries = tcc.get("failures") or []
    failure_details = []
    for entry in failure_entries:
        actual = entry.get("actualPromptButtons") or {}
        detail = (
            "阶段 `%s`：%s；期望 label=%s；实际弹窗按钮 SpringBoard=%s App=%s"
            % (
                entry.get("stage"),
                entry.get("reason"),
                entry.get("expectedLabels"),
                actual.get("springboard"),
                actual.get("app"),
            )
        )
        failure_details.append(detail)
        failures.append({"step": "tcc-%s" % entry.get("stage"), "reason": detail})
    check(
        "tcc-failure-stage",
        not failure_entries,
        "；".join(failure_details) if failure_details else "无失败阶段",
        "tcc-result.json",
    )

    runs = pick_newest_runs([os.path.join(os.path.dirname(meta_path), "container-after")],
                            phase_started_epoch)
    run = runs[-1][2] if runs else None
    if run is None:
        check("tcc-run-json", False, "未读到本次跑次 JSON（Documents/Runs）", None)
        check("tcc-self-report-authorized-always", False, "无跑次 JSON，无法以 App 自报判定授权", None)
    else:
        copied_run = copy_evidence_file(runs[-1][1], evidence_dir, "run-")
        check("tcc-run-json", bool(copied_run), "跑次 JSON 已复制: %s" % copied_run, copied_run)
        telemetry = run.get("telemetry") or {}
        auth = telemetry.get("authorizationStatus") or {}
        check(
            "tcc-self-report-authorized-always",
            auth.get("name") == "authorizedAlways" and auth.get("rawValue") == 3,
            "telemetry.authorizationStatus={name=%r, rawValue=%r}（以 App 自报为准，不以「弹窗点到了」代替）"
            % (auth.get("name"), auth.get("rawValue")),
            copied_run or "run JSON",
        )

elif phase == "background":
    stage1 = read_json(os.path.join(evidence_dir, "background-stage1.json"), {}) or {}
    stage2 = read_json(os.path.join(evidence_dir, "background-result.json"), {}) or {}
    pressed_home = stage1.get("pressedHomeAt")
    window_seconds = int(float(meta.get("backgroundSeconds") or 330))
    if isinstance(pressed_home, (int, float)):
        check("background-pressed-home", True, "press(.home) 时刻 %.0f" % pressed_home,
              "background-stage1.json")
        checkpoint_continuity(os.path.join(before_dir, "active-run.jsonl"), float(pressed_home), window_seconds)
    else:
        check("background-pressed-home", False, "未读到 background-stage1.json 的 pressedHomeAt", None)

    check(
        "background-finish-saved",
        stage2.get("sessionStillActive") is True and stage2.get("saved") is True,
        "回前台后会话仍活跃=%r，结束保存=%r%s"
        % (stage2.get("sessionStillActive"), stage2.get("saved"),
           ("；原因: " + str(stage2.get("reason"))) if stage2.get("reason") else ""),
        "background-finish.png / background-result.json",
    )
    check(
        "background-exported",
        stage2.get("exported") is True and str(stage2.get("exportedLabel", "")).endswith(".gpx"),
        "导出完成态=%r label=%r" % (stage2.get("exported"), stage2.get("exportedLabel")),
        "background-export.png",
    )

    runs = pick_newest_runs([after_dir, before_dir], phase_started_epoch)
    run = runs[-1][2] if runs else None
    if run is None:
        check("background-run-json", False, "未读到本次跑次 JSON（Documents/Runs）", None)
        announcements = []
        samples = []
    else:
        copied_run = copy_evidence_file(runs[-1][1], evidence_dir, "run-")
        check("background-run-json", bool(copied_run), "跑次 JSON 已复制: %s" % copied_run, copied_run)
        telemetry = run.get("telemetry") or {}
        announcements = telemetry.get("announcements") or []
        samples = run.get("samples") or []
        announce_path = os.path.join(evidence_dir, "announcements-%s.json" % run.get("id", "unknown"))
        with open(announce_path, "w", encoding="utf-8") as handle:
            json.dump(announcements, handle, ensure_ascii=False, indent=2)
            handle.write("\n")
        announce_checks(announcements)

        if isinstance(pressed_home, (int, float)) and samples:
            times = [float(s["timestamp"]) for s in samples if isinstance(s.get("timestamp"), (int, float))]
            if times:
                check("background-first-sample-before-home", times[0] < float(pressed_home),
                      "首样本 %.1fs 早于 press(.home) %.1fs" % (times[0], float(pressed_home)), "run JSON")
                check("background-last-sample-after-window",
                      times[-1] >= float(pressed_home) + window_seconds - 60,
                      "末样本 %.1fs 晚于后台窗口结束（容差 60s）%.1fs"
                      % (times[-1], float(pressed_home) + window_seconds), "run JSON")
                gaps = [times[i] - times[i - 1] for i in range(1, len(times))]
                check("background-sample-max-gap", max(gaps) <= 60 if gaps else False,
                      "相邻样本最大空洞 %.1fs（上限 60s）" % (max(gaps) if gaps else 0), "run JSON")
                check("background-sample-monotonic", all(g >= 0 for g in gaps),
                      "samples[].timestamp %s" % ("单调不减" if all(g >= 0 for g in gaps) else "出现回退"), "run JSON")
                active = run.get("activeDuration")
                wall = times[-1] - times[0]
                if isinstance(active, (int, float)) and wall > 0:
                    delta_ratio = abs(active - wall) / wall
                    check("background-active-duration", delta_ratio <= 0.05,
                          "activeDuration=%.1fs 与样本墙钟 %.1fs 相对差 %.2f%%（上限 5%%）"
                          % (active, wall, delta_ratio * 100), "run JSON")
                else:
                    check("background-active-duration", False, "activeDuration 或样本墙钟不可用", "run JSON")

    auth = ((run or {}).get("telemetry") or {}).get("authorizationStatus") or {}
    accuracy = ((run or {}).get("telemetry") or {}).get("accuracyAuthorization") or {}
    background_allowed = ((run or {}).get("telemetry") or {}).get("allowsBackgroundLocationUpdates")
    check(
        "background-auth-honest",
        bool(auth.get("name")) and bool(accuracy.get("name")) and isinstance(background_allowed, bool),
        "authorizationStatus=%r accuracyAuthorization=%r allowsBackgroundLocationUpdates=%r%s"
        % (auth.get("name"), accuracy.get("name"), background_allowed,
           "；WhenInUse 时后台会被系统掐断，结论标 pending: 待人现场（needs-you 单点）"
           if auth.get("name") == "authorizedWhenInUse" else ""),
        "run JSON telemetry",
    )

    gpx_files = sorted(glob.glob(os.path.join(after_dir, "Exports", "*.gpx")))
    if not gpx_files:
        gpx_files = sorted(glob.glob(os.path.join(before_dir, "Exports", "*.gpx")))
    if gpx_files:
        gpx_path = gpx_files[-1]
        target = copy_evidence_file(gpx_path, evidence_dir, "")
        digest = sha256_of(os.path.join(evidence_dir, target)) if target else None
        if target:
            with open(os.path.join(evidence_dir, "sha256.txt"), "w", encoding="utf-8") as handle:
                handle.write("%s  %s\n" % (digest, target))
        check("background-gpx-exists",
              bool(target) and os.path.getsize(os.path.join(evidence_dir, target)) > 0,
              "导出 GPX: %s（%s 字节）"
              % (target, os.path.getsize(os.path.join(evidence_dir, target)) if target else 0), target)
        check("background-gpx-sha256", bool(digest) and re.fullmatch(r"[0-9a-f]{64}", digest) is not None,
              "实算 sha256=%s 已写入 sha256.txt" % digest, "sha256.txt")
        if target:
            try:
                trkpts = parse_gpx(os.path.join(evidence_dir, target))
                sample_count = len(samples)
                check("background-gpx-trkpt-count", abs(len(trkpts) - sample_count) <= 1,
                      "trkpt=%d samples=%d（差值 ≤ 1）" % (len(trkpts), sample_count), target)
                if trkpts and samples:
                    gpx_span = epoch_seconds(trkpts[-1]["time"]) - epoch_seconds(trkpts[0]["time"])
                    sample_times = [float(s["timestamp"]) for s in samples if isinstance(s.get("timestamp"), (int, float))]
                    if sample_times:
                        sample_span = sample_times[-1] - sample_times[0]
                        check("background-gpx-time-span", abs(gpx_span - sample_span) <= 1.0,
                              "GPX 时间跨度 %.1fs vs 记录区间 %.1fs（绝对差 ≤ 1s）" % (gpx_span, sample_span),
                              target)
            except Exception as exc:  # noqa: BLE001
                check("background-gpx-parse", False, "GPX 解析失败: %s" % exc, target)
    else:
        check("background-gpx-exists", False, "Documents/Exports 未读到 .gpx", None)
        check("background-gpx-sha256", False, "无 .gpx 可实算 sha256", None)

    lock_observation = {
        "lockState_before": meta.get("lockState_before"),
        "lockState_after": meta.get("lockState_after"),
    }
    check(
        "background-lock-state-observation-only",
        True,
        "只读观测 %r；本项不宣称锁屏后连续采样，结论仅「切后台后进程存活 + 持续采样」" % lock_observation,
        "report.md",
    )

ok = not failures and all(entry["ok"] for entry in checks)
finished = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
meta["finishedAt"] = finished
meta["ok"] = ok
with open(meta_path, "w", encoding="utf-8") as handle:
    json.dump(meta, handle, ensure_ascii=False, indent=2)
    handle.write("\n")

payload = {
    "ok": ok,
    "phase": phase,
    "meta": meta,
    "checks": checks,
    "failures": failures,
}
with open(analysis_path, "w", encoding="utf-8") as handle:
    json.dump(payload, handle, ensure_ascii=False, indent=2)
    handle.write("\n")

render_report(ok)
sys.exit(0 if ok else 1)
PY
  local status=$?
  return "$status"
}

# ---------------------------------------------------------------- 阶段实现
run_audit() {
  build_for_testing || return 1
  local result_bundle="${phase_dir}/DeviceFlow-audit.xcresult"
  if ! run_case "testAuditFirstScreenAndTabs" "$result_bundle" "${phase_dir}/xcodebuild-audit.log"; then
    fail_step "xcodebuild-audit" "test-without-building 退出非零（日志 ${phase_dir}/xcodebuild-audit.log）"
  fi
  export_attachments "$result_bundle" "${phase_dir}/attachments" || true
  xcrun devicectl device info apps --device "$device_udid" --bundle-id "$bundle_id" \
    --json-output "${phase_dir}/installed-app.json" >/dev/null 2>&1 || true
  merge_meta testCase "$test_case"
}

run_audio() {
  build_for_testing || return 1
  local result_bundle="${phase_dir}/DeviceFlow-audio.xcresult"
  if ! run_case "testAudioKilometerBoundaryWithMusic" "$result_bundle" "${phase_dir}/xcodebuild-audio.log"; then
    fail_step "xcodebuild-audio" "test-without-building 退出非零（日志 ${phase_dir}/xcodebuild-audio.log）"
  fi
  export_attachments "$result_bundle" "${phase_dir}/attachments" || true
  copy_container "${phase_dir}/container-after"
  xcrun devicectl device info apps --device "$device_udid" --bundle-id "$bundle_id" \
    --json-output "${phase_dir}/installed-app.json" >/dev/null 2>&1 || true
  merge_meta testCase "$test_case"
}

run_background() {
  build_for_testing || return 1
  observe_lock_state "before"
  merge_meta testCase "$test_case" backgroundSeconds "$background_seconds"

  local stage1_bundle="${phase_dir}/DeviceFlow-background-stage1.xcresult"
  if ! run_case "testBackgroundStartAndPressHome" "$stage1_bundle" "${phase_dir}/xcodebuild-background-stage1.log"; then
    fail_step "xcodebuild-background-stage1" "阶段一 test-without-building 退出非零（日志 ${phase_dir}/xcodebuild-background-stage1.log）"
  fi
  export_attachments "$stage1_bundle" "${phase_dir}/attachments-stage1" || true

  local pressed_home
  pressed_home="$(python3 - "${evidence_dir}/background-stage1.json" <<'PY'
import json
import sys

try:
    with open(sys.argv[1], "r", encoding="utf-8") as handle:
        print("%.0f" % float(json.load(handle)["pressedHomeAt"]))
except Exception:
    print("0")
PY
)"
  if [ "$pressed_home" = "0" ]; then
    fail_step "background-pressed-home" "未读到 press(.home) 时刻（${evidence_dir}/background-stage1.json）"
    # 没有可信起点就不空等，直接用窗口秒数兜底等待。
    pressed_home="$(date +%s)"
  fi
  merge_meta pressedHomeAt "$pressed_home"

  # 6 分钟等待放 Mac 侧：宿主 sleep，不在测试进程内 sleep 断言后台连续性。
  local wait_deadline=$((pressed_home + background_seconds))
  info "Mac 侧等待后台窗口 ${background_seconds}s（到 $(date -r "$wait_deadline" -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "$wait_deadline")）"
  while :; do
    local now
    now="$(date +%s)"
    if [ "$now" -ge "$wait_deadline" ]; then
      break
    fi
    local remaining=$((wait_deadline - now))
    if [ "$remaining" -gt 60 ]; then
      sleep 60
    else
      sleep "$remaining"
    fi
  done

  copy_container "${phase_dir}/container-window"
  observe_lock_state "after"

  local stage2_bundle="${phase_dir}/DeviceFlow-background-stage2.xcresult"
  if ! run_case "testBackgroundFinishSaveAndExport" "$stage2_bundle" "${phase_dir}/xcodebuild-background-stage2.log"; then
    fail_step "xcodebuild-background-stage2" "阶段二 test-without-building 退出非零（日志 ${phase_dir}/xcodebuild-background-stage2.log）"
  fi
  export_attachments "$stage2_bundle" "${phase_dir}/attachments-stage2" || true
  copy_container "${phase_dir}/container-after"
  xcrun devicectl device info apps --device "$device_udid" --bundle-id "$bundle_id" \
    --json-output "${phase_dir}/installed-app.json" >/dev/null 2>&1 || true
}

# tcc 阶段：Debug 构建 + 真实 CoreLocation（不传 -uiTestLocation）；授权结果以跑次 JSON 自报为准。
run_tcc() {
  build_for_testing || return 1
  local result_bundle="${phase_dir}/TCC-tcc.xcresult"
  if ! run_case "testTCCFreshInstallReachesAuthorizedAlways" "$result_bundle" "${phase_dir}/xcodebuild-tcc.log"; then
    fail_step "xcodebuild-tcc" "test-without-building 退出非零（日志 ${phase_dir}/xcodebuild-tcc.log）"
  fi
  export_attachments "$result_bundle" "${phase_dir}/attachments" || true
  copy_container "${phase_dir}/container-after"
  xcrun devicectl device info apps --device "$device_udid" --bundle-id "$bundle_id" \
    --json-output "${phase_dir}/installed-app.json" >/dev/null 2>&1 || true
  merge_meta testCase "$test_case"
}

main() {
  info "阶段 ${phase}（${build_configuration} 构建）→ 证据目录 ${evidence_dir}"
  preflight || return 1
  collect_candidate_identity
  generate_project || return 1
  case "$phase" in
    audit) run_audit || true ;;
    audio) run_audio || true ;;
    background) run_background || true ;;
    tcc) run_tcc || true ;;
  esac
  return 0
}

set +e
main
main_status=$?
analyze_and_report
report_status=$?
set -e

if [ "$report_status" -ne 0 ]; then
  printf 'verify-ios-device-flow: 阶段 %s 存在失败项，详见 %s\n' "$phase" "$evidence_dir/report.md" >&2
  exit 1
fi
printf 'verify-ios-device-flow: 阶段 %s 机器断言通过\n' "$phase"
printf 'verify-ios-device-flow: 证据目录 %s\n' "$evidence_dir"
printf 'verify-ios-device-flow: 报告 %s\n' "$evidence_dir/report.md"
exit 0
