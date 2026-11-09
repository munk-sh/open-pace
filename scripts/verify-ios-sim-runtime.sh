#!/usr/bin/env bash
# 在 iPhone 16 / iOS 18.6 模拟器上真实驱动三条运行链路（direct / corelocation / terminate→relaunch），
# 由本脚本独立复算 status.rawSamples，按写死阈值判定并产出机读报告。
# 真机项（后台锁屏连续定位、音乐不打断、TTS 实听）一律 pending: 待人现场，本脚本不产出真机结论。
set -euo pipefail

usage() {
  cat <<'EOF'
用法: scripts/verify-ios-sim-runtime.sh [--help]

在 iPhone 16 / iOS 18.6 模拟器上真实执行三条链路并写出机读报告：
  1. direct：脚本生成 3 km、1 Hz、5:00–7:00/km 的 JSONL 直接流（真实写入 App 容器），
     以 --harness direct 启动 App，独立 Haversine 复算距离/配速/分段/播报。
  2. corelocation：grant 定位授权后按 1 Hz 用 xcrun simctl location set 逐点推进约 250 m 路线
     （每 tick 3.0 m，按 status 实际采集距离确认推进，停滞 5 s 用当前进度重推，最多 2 轮），
     以 --harness corelocation 采集，独立复算捕获距离、覆盖率与配速。
  3. terminate→relaunch：direct 结束后 xcrun simctl terminate 杀进程，再以 --harness resume
     relaunch，比对真实 checkpoint 与恢复快照。

产物与报告只落 .build/verify-ios-sim-runtime/（report.json 为机读报告）。
任一链路或阈值失败、status 缺失、工具/模拟器缺失、App 安装或启动失败，均以非零退出。

选项:
  -h, --help   显示本帮助并退出 0

退出码:
  0  三条链路全部通过
  1  任一链路/阈值/环境失败（stderr 与报告 links[].failureReason 写明失败指标）
  2  参数非法
EOF
}

if [ "$#" -gt 1 ]; then
  echo "verify-ios-sim-runtime: 只接受一个参数（使用 --help 查看用法）" >&2
  exit 2
fi

case "${1:-}" in
  -h|--help)
    usage
    exit 0
    ;;
  "")
    ;;
  *)
    echo "verify-ios-sim-runtime: 未知参数 '${1}'（使用 --help 查看用法）" >&2
    exit 2
    ;;
esac

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
cd "${repo_root}"

# 同机跨 worktree iOS 门串行化锁：固定目录 /tmp/purepace-ios-gate.lock。
# mkdir 原子取锁；PUREPACE_IOS_GATE_LOCK_HELD=1 表示会话层已持锁，本脚本直接重入不重复加锁。
# 有界等待 1200s、每 30s 重试；锁目录无 pid 且 mtime >900s 视为陈旧可删；trap 保证退出释放。
ios_gate_lock_dir="/tmp/purepace-ios-gate.lock"
ios_gate_lock_held=0

ios_gate_lock_release() {
  if [ "${ios_gate_lock_held}" = "1" ] && [ "$(cat "${ios_gate_lock_dir}/pid" 2>/dev/null || true)" = "$$" ]; then
    rm -rf "${ios_gate_lock_dir}"
    echo "[lock] released pid=$$ dir=${ios_gate_lock_dir}"
  fi
}

ios_gate_lock_acquire() {
  if [ "${PUREPACE_IOS_GATE_LOCK_HELD:-0}" = "1" ]; then
    echo "[lock] reentrant pid=$$ (PUREPACE_IOS_GATE_LOCK_HELD=1)"
    return 0
  fi
  local waited=0 holder now mtime age stale
  while :; do
    if mkdir "${ios_gate_lock_dir}" 2>/dev/null; then
      printf '%s\n' "$$" > "${ios_gate_lock_dir}/pid"
      ios_gate_lock_held=1
      export PUREPACE_IOS_GATE_LOCK_HELD=1
      trap ios_gate_lock_release EXIT
      echo "[lock] acquired pid=$$ waited=${waited}s dir=${ios_gate_lock_dir}"
      return 0
    fi
    holder="$(cat "${ios_gate_lock_dir}/pid" 2>/dev/null || true)"
    now="$(date +%s)"
    mtime="$(stat -f %m "${ios_gate_lock_dir}" 2>/dev/null || stat -c %Y "${ios_gate_lock_dir}" 2>/dev/null || echo "${now}")"
    age=$((now - mtime))
    stale=0
    if [ -z "${holder}" ]; then
      stale=1
    elif ! kill -0 "${holder}" 2>/dev/null; then
      stale=1
    fi
    if [ "${stale}" = "1" ] && [ "${age}" -gt 900 ]; then
      echo "[lock] stale pid=${holder:-<none>} age=${age}s, removing dir=${ios_gate_lock_dir}"
      rm -rf "${ios_gate_lock_dir}"
      continue
    fi
    if [ "${waited}" -ge 1200 ]; then
      echo "[lock] timeout pid=$$ waited=${waited}s holder=${holder:-<none>}" >&2
      return 3
    fi
    if [ "${waited}" -eq 0 ]; then
      echo "[lock] waiting pid=$$ holder=${holder:-<none>}"
    fi
    sleep 30
    waited=$((waited + 30))
  done
}

# 取锁后先有界等待其它 worktree 的 xcodebuild/simctl 归零；有并发时禁止 shutdown/erase。
ios_gate_lock_wait_quiescent() {
  local waited=0 others
  while :; do
    others="$(pgrep -fl 'xcodebuild|simctl' 2>/dev/null | grep -v -e 'purepace-ios-gate' -e "^$$ " -e "^${PPID} " || true)"
    if [ -z "${others}" ]; then
      echo "[lock] quiescent pid=$$ waited=${waited}s"
      return 0
    fi
    if [ "${waited}" -ge 600 ]; then
      echo "[lock] timeout-quiescent pid=$$ waited=${waited}s" >&2
      printf '%s\n' "${others}" >&2
      return 4
    fi
    if [ "${waited}" -eq 0 ]; then
      echo "[lock] waiting-quiescent pid=$$"
    fi
    sleep 10
    waited=$((waited + 10))
  done
}

ios_gate_lock_prepare_simulator() {
  ios_gate_lock_wait_quiescent || return $?
  xcrun simctl shutdown all >/dev/null 2>&1 || true
  return 0
}

ios_gate_lock_acquire || exit $?
ios_gate_lock_prepare_simulator || exit $?

bundle_id="sh.munk.purepace"
device_name="iPhone 16"
runtime_id="com.apple.CoreSimulator.SimRuntime.iOS-18-6"
derived_data=".build/ios"
work_dir="${repo_root}/.build/verify-ios-sim-runtime"
report_path="${work_dir}/report.json"
failures_file="${work_dir}/failures.txt"
phases_file="${work_dir}/phases.tsv"

mkdir -p "${work_dir}"
: > "${failures_file}"
: > "${phases_file}"

current_link=""

fail_all() {
  local reason="$1"
  local link
  for link in direct corelocation terminate-relaunch; do
    printf '%s: %s\n' "${link}" "${reason}" >> "${failures_file}"
  done
  printf 'verify-ios-sim-runtime: %s\n' "${reason}" >&2
}

link_fail() {
  local reason="$1"
  printf '%s: %s\n' "${current_link}" "${reason}" >> "${failures_file}"
  printf 'verify-ios-sim-runtime: %s 链路失败: %s\n' "${current_link}" "${reason}" >&2
  exit 1
}

require_command() {
  local name
  for name in "$@"; do
    if ! command -v "${name}" >/dev/null 2>&1; then
      fail_all "缺少必需命令 ${name}"
      return 1
    fi
  done
}

run_phase() {
  local link="$1"
  local phase_fn="$2"
  local start end rc=0
  current_link="${link}"
  start="$(date +%s)"
  set +e
  ( set -euo pipefail; "${phase_fn}" )
  rc=$?
  set -e
  end="$(date +%s)"
  printf '%s\t%s\t%s\n' "${link}" "${rc}" "$((end - start))" >> "${phases_file}"
  if [ "${rc}" -ne 0 ] && ! grep -q "^${link}:" "${failures_file}" 2>/dev/null; then
    printf '%s: 链路执行异常（退出码 %s）\n' "${link}" "${rc}" >> "${failures_file}"
  fi
  return 0
}

wait_for_status() {
  local status_path="$1"
  local want_state="$2"
  local timeout_seconds="$3"
  python3 - "${status_path}" "${want_state}" "${timeout_seconds}" <<'PY'
import json
import sys
import time

path, want, timeout = sys.argv[1], sys.argv[2], float(sys.argv[3])
deadline = time.time() + timeout
last = "missing"
while time.time() < deadline:
    try:
        with open(path, "r", encoding="utf-8") as handle:
            doc = json.load(handle)
        state = doc.get("state")
        if state == want:
            sys.exit(0)
        last = str(state)
    except FileNotFoundError:
        last = "missing"
    except Exception as exc:  # noqa: BLE001 - 报告里保留原始错误即可
        last = "unreadable: %s" % exc
    time.sleep(0.2)
print("等待 status state=%s 超时（最后状态: %s）" % (want, last), file=sys.stderr)
sys.exit(1)
PY
}

wait_for_corelocation_ready() {
  local status_path="$1"
  local timeout_seconds="$2"
  python3 - "${status_path}" "${timeout_seconds}" <<'PY'
import json
import sys
import time

path, timeout = sys.argv[1], float(sys.argv[2])
deadline = time.time() + timeout
last = "missing"
authorized = {"authorizedWhenInUse", "authorizedAlways"}
while time.time() < deadline:
    try:
        with open(path, "r", encoding="utf-8") as handle:
            doc = json.load(handle)
        last = str(doc.get("locationAuthorization"))
        if doc.get("locationAuthorization") in authorized:
            sys.exit(0)
    except FileNotFoundError:
        last = "missing"
    except Exception as exc:  # noqa: BLE001
        last = "unreadable: %s" % exc
    time.sleep(0.1)
print("等待定位授权就绪超时（最后 locationAuthorization: %s）" % last, file=sys.stderr)
sys.exit(1)
PY
}

wait_for_first_location_sample() {
  local status_path="$1"
  local timeout_seconds="$2"
  python3 - "${status_path}" "${timeout_seconds}" <<'PY'
import json
import sys
import time

path, timeout = sys.argv[1], float(sys.argv[2])
deadline = time.time() + timeout
while time.time() < deadline:
    try:
        with open(path, "r", encoding="utf-8") as handle:
            doc = json.load(handle)
        if len(doc.get("rawSamples") or []) > 0:
            sys.exit(0)
    except FileNotFoundError:
        pass
    except Exception:  # noqa: BLE001 - 原子写瞬间可能读不到，重试即可
        pass
    time.sleep(0.05)
print("等待首个定位样本超时（rawSamples 仍为空）", file=sys.stderr)
sys.exit(1)
PY
}

# 确定性推点：以 1 Hz 用 simctl location set 逐点推进注入路线（每 tick 3.0 m），
# 每 tick 读 status 的实际采集距离确认推进；停滞超过 5 s 用当前进度重算剩余点并重推（最多 2 轮）。
# 进度型超时：总预算 300 s，不依赖模拟器 location start 的播放时长。
push_location_route() {
  local status_path="$1"
  local plan_path="$2"
  local total_budget="$3"
  python3 - "${status_path}" "${plan_path}" "${udid}" "${total_budget}" <<'PY'
import json
import math
import subprocess
import sys
import time

status_path, plan_path, udid, total_budget = sys.argv[1], sys.argv[2], sys.argv[3], float(sys.argv[4])

with open(plan_path, "r", encoding="utf-8") as handle:
    plan = json.load(handle)

speed = float(plan["speedMetersPerSecond"])
injected = float(plan["injectedMeters"])
target = injected * float(plan["coverageMin"])
start_latitude = float(plan["startLatitude"])
start_longitude = float(plan["startLongitude"])
meters_per_degree_latitude = 6371000.0 * math.pi / 180.0
interval = 1.0
stall_seconds = 5.0
max_repush_rounds = 2


def point_at(distance_meters):
    return start_latitude + distance_meters / meters_per_degree_latitude, start_longitude


def push(distance_meters):
    latitude, longitude = point_at(distance_meters)
    completed = subprocess.run(
        ["xcrun", "simctl", "location", udid, "set", "%.7f,%.7f" % (latitude, longitude)],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
    )
    if completed.returncode != 0:
        message = completed.stderr.decode("utf-8", "replace").strip()
        raise RuntimeError("simctl location set 失败: %s" % message)


def read_distance():
    try:
        with open(status_path, "r", encoding="utf-8") as handle:
            doc = json.load(handle)
    except FileNotFoundError:
        return None
    except Exception:  # noqa: BLE001 - 原子写瞬间可能读不到，重试即可
        return None
    return float((doc.get("actual") or {}).get("distanceMeters") or 0.0)


started = time.time()
try:
    push(0.0)
except RuntimeError as exc:
    print(str(exc), file=sys.stderr)
    sys.exit(1)

anchor_deadline = time.time() + 30.0
while time.time() < anchor_deadline:
    if read_distance() is not None:
        break
    time.sleep(0.05)
else:
    print("App 未在 30 s 内写出 status（首个定位样本缺失）", file=sys.stderr)
    sys.exit(1)

distance = read_distance() or 0.0
cursor = 0.0
last_distance = distance
last_progress_at = time.time()
next_tick = time.time() + interval
repush_rounds = 0

while distance < target:
    now = time.time()
    measured = read_distance()
    if measured is not None:
        distance = measured
    if distance >= target:
        break
    if now - started >= total_budget:
        print(
            "推点在总预算 %.0f s 内未达到 %.1f m（最后 %.1f m，重推 %d 轮）"
            % (total_budget, target, distance, repush_rounds),
            file=sys.stderr,
        )
        sys.exit(1)
    if distance > last_distance + 0.05:
        last_distance = distance
        last_progress_at = now
    elif now - last_progress_at >= stall_seconds:
        repush_rounds += 1
        if repush_rounds > max_repush_rounds:
            print(
                "注入停滞超过 %.0f s 且已重推 %d 轮仍未推进（最后 %.1f m）"
                % (stall_seconds, max_repush_rounds, distance),
                file=sys.stderr,
            )
            sys.exit(1)
        cursor = distance
        last_distance = distance
        last_progress_at = now
        next_tick = now + interval
        continue
    if now < next_tick:
        time.sleep(min(0.05, next_tick - now))
        continue
    cursor = min(cursor + speed * interval, injected)
    if cursor <= distance:
        cursor = min(distance + speed * interval, injected)
    try:
        push(cursor)
    except RuntimeError as exc:
        print(str(exc), file=sys.stderr)
        sys.exit(1)
    next_tick += interval

print(
    "注入完成：target=%.1f m collected=%.1f m repush=%d elapsed=%.1f s"
    % (target, distance, repush_rounds, time.time() - started),
    file=sys.stderr,
)
PY
}

select_device() {
  xcrun simctl list devices available --json | python3 -c '
import json
import sys

runtime = sys.argv[1]
name = sys.argv[2]
doc = json.load(sys.stdin)
for runtime_id, devices in doc.get("devices", {}).items():
    if runtime_id != runtime:
        continue
    for device in devices:
        if device.get("name") == name and device.get("isAvailable", True):
            print(device["udid"])
            sys.exit(0)
sys.exit(1)
' "${runtime_id}" "${device_name}"
}

runtime_display_name() {
  xcrun simctl list runtimes --json | python3 -c '
import json
import sys

runtime = sys.argv[1]
doc = json.load(sys.stdin)
for item in doc.get("runtimes", []):
    if item.get("identifier") == runtime:
        print(item.get("name") or item.get("version") or runtime)
        sys.exit(0)
print(runtime)
' "${runtime_id}"
}

app_container_path() {
  xcrun simctl get_app_container "${udid}" "${bundle_id}" data
}

setup_environment() {
  require_command python3 xcrun xcodebuild || return 1

  udid="$(select_device)" || {
    fail_all "未找到可用的 ${device_name} / iOS 18.6 模拟器（xcrun simctl list devices available）"
    return 1
  }
  runtime_name="$(runtime_display_name)"

  python3 - "${work_dir}/device.json" "${device_name}" "${udid}" "${runtime_name}" <<'PY'
import json
import sys

path, name, udid, runtime = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
with open(path, "w", encoding="utf-8") as handle:
    json.dump({"name": name, "udid": udid, "runtime": runtime}, handle, ensure_ascii=False)
    handle.write("\n")
PY
  printf 'udid=%q\nruntime_name=%q\n' "${udid}" "${runtime_name}" > "${work_dir}/device.env"

  bash scripts/build-ios.sh || {
    fail_all "iOS 构建失败（scripts/build-ios.sh 非零退出）"
    return 1
  }
  app_path="$(find "${derived_data}/Build/Products" -type d -name 'PurePace.app' -print -quit 2>/dev/null || true)"
  if [ -z "${app_path}" ] || [ ! -d "${app_path}" ]; then
    fail_all "构建成功但未找到 PurePace.app 产物"
    return 1
  fi
  printf 'app_path=%q\n' "${app_path}" >> "${work_dir}/device.env"

  xcrun simctl terminate "${udid}" "${bundle_id}" >/dev/null 2>&1 || true
  xcrun simctl shutdown "${udid}" >/dev/null 2>&1 || true
  xcrun simctl boot "${udid}" >/dev/null 2>&1 || true
  xcrun simctl bootstatus "${udid}" -b >/dev/null || {
    fail_all "模拟器启动失败（simctl bootstatus）"
    return 1
  }
  xcrun simctl uninstall "${udid}" "${bundle_id}" >/dev/null 2>&1 || true
  xcrun simctl install "${udid}" "${app_path}" || {
    fail_all "App 安装失败（simctl install ${app_path}）"
    return 1
  }
  xcrun simctl privacy "${udid}" grant location "${bundle_id}" || {
    fail_all "定位授权 grant 失败（simctl privacy grant location）"
    return 1
  }
  xcrun simctl location "${udid}" clear >/dev/null 2>&1 || true
}

phase_direct() {
  local container run_dir stream status checkpoint line_count
  container="$(app_container_path)" || link_fail "无法获取 App 容器路径"
  run_dir="${container}/Library/Caches/verify-ios-sim-runtime"
  mkdir -p "${run_dir}"
  stream="${run_dir}/direct-stream.jsonl"
  status="${run_dir}/direct-status.json"
  checkpoint="${run_dir}/direct-checkpoint.jsonl"
  rm -f "${stream}" "${status}" "${checkpoint}"

  python3 - "${stream}" "${work_dir}/direct-plan.json" <<'PY'
import json
import math
import sys

stream_path, plan_path = sys.argv[1], sys.argv[2]
base = 1_700_000_000.0
meters_per_degree = 6371000.0 * math.pi / 180.0
step = 2.8
pace = 1000.0 / step
delta_latitude = step / meters_per_degree
latitude = 37.0
longitude = -122.0
phase_a_samples = 730
paused_samples = 1924
phase_b_samples = 345

lines = []
expected_split_indexes = []
accepted_count = 0
accumulated = 0.0
next_split = 1
previous_latitude = latitude
previous_longitude = longitude
skip_next_distance = False


def haversine(lat1, lon1, lat2, lon2):
    phi1 = lat1 * math.pi / 180.0
    phi2 = lat2 * math.pi / 180.0
    delta_phi = (lat2 - lat1) * math.pi / 180.0
    delta_lambda = (lon2 - lon1) * math.pi / 180.0
    sin_half_phi = math.sin(delta_phi / 2.0)
    sin_half_lambda = math.sin(delta_lambda / 2.0)
    h = sin_half_phi * sin_half_phi + math.cos(phi1) * math.cos(phi2) * sin_half_lambda * sin_half_lambda
    return 2.0 * 6371000.0 * math.asin(min(1.0, math.sqrt(max(0.0, h))))


def emit(payload):
    lines.append(json.dumps(payload, ensure_ascii=False, separators=(",", ":")))


def moving_sample(offset_seconds):
    global latitude, accumulated, accepted_count, next_split, previous_latitude, previous_longitude, skip_next_distance
    latitude += delta_latitude
    rounded_latitude = round(latitude, 9)
    rounded_longitude = round(longitude, 9)
    if skip_next_distance:
        skip_next_distance = False
    else:
        accumulated += haversine(previous_latitude, previous_longitude, rounded_latitude, rounded_longitude)
    previous_latitude = rounded_latitude
    previous_longitude = rounded_longitude
    accepted_count += 1
    while accumulated >= next_split * 1000.0:
        expected_split_indexes.append(accepted_count)
        next_split += 1
    emit({
        "type": "sample",
        "lat": rounded_latitude,
        "lon": rounded_longitude,
        "timestamp": base + offset_seconds,
    })


emit({"type": "start", "timestamp": base})
emit({"type": "sample", "lat": latitude, "lon": longitude, "timestamp": base})
accepted_count = 1

for index in range(1, phase_a_samples + 1):
    moving_sample(index)

pause_at = base + phase_a_samples + 1.0
emit({"type": "pause", "timestamp": pause_at})

frozen_latitude = round(latitude, 9)
frozen_longitude = round(longitude, 9)
for index in range(1, paused_samples + 1):
    accepted_count += 1
    emit({
        "type": "sample",
        "lat": frozen_latitude,
        "lon": frozen_longitude,
        "timestamp": pause_at + index,
    })

resume_at = pause_at + paused_samples + 1.0
emit({"type": "resume", "timestamp": resume_at})
skip_next_distance = True

for index in range(1, phase_b_samples + 1):
    moving_sample(paused_samples + phase_a_samples + 2.0 + index)

emit({"type": "finish", "timestamp": resume_at + phase_b_samples + 1.0})

with open(stream_path, "w", encoding="utf-8") as handle:
    handle.write("\n".join(lines))
    handle.write("\n")

plan = {
    "baseTimestamp": base,
    "sampleRateHz": 1,
    "paceSecondsPerKilometer": pace,
    "stepMeters": step,
    "expectedDistanceMeters": 3000.0,
    "pauseWindowSamples": paused_samples,
    "expectedCompletedKilometers": 3,
    "expectedSplitSampleIndexes": expected_split_indexes,
    "expectedRecomputedDistanceMeters": accumulated,
    "totalSampleLines": accepted_count,
    "totalLines": len(lines),
}
with open(plan_path, "w", encoding="utf-8") as handle:
    json.dump(plan, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
PY

  line_count="$(wc -l < "${stream}" | tr -d ' ')"
  if [ "${line_count}" -lt 3000 ]; then
    link_fail "direct 直接流行数 ${line_count} < 3000"
  fi

  python3 - "${work_dir}/direct-plan.json" "${line_count}" <<'PY'
import json
import sys

plan_path, on_disk = sys.argv[1], int(sys.argv[2])
with open(plan_path, "r", encoding="utf-8") as handle:
    plan = json.load(handle)
plan["onDiskLineCount"] = on_disk
with open(plan_path, "w", encoding="utf-8") as handle:
    json.dump(plan, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
PY

  xcrun simctl terminate "${udid}" "${bundle_id}" >/dev/null 2>&1 || true
  xcrun simctl launch "${udid}" "${bundle_id}" \
    --harness direct \
    --status "${status}" \
    --checkpoint "${checkpoint}" \
    --stream "${stream}" >/dev/null || link_fail "direct 模式 App 启动失败"

  wait_for_status "${status}" finished 300 || link_fail "direct status 未在超时内达到 finished"

  cp "${status}" "${work_dir}/direct-status.json"
  # finished 后静置再取一次快照，用于断言 status 不再新增 announcement。
  sleep 1
  cp "${status}" "${work_dir}/direct-status-after.json"
}

phase_corelocation() {
  local container run_dir status checkpoint plan
  container="$(app_container_path)" || link_fail "无法获取 App 容器路径"
  run_dir="${container}/Library/Caches/verify-ios-sim-runtime"
  mkdir -p "${run_dir}"
  status="${run_dir}/corelocation-status.json"
  checkpoint="${run_dir}/corelocation-checkpoint.jsonl"
  plan="${work_dir}/corelocation-plan.json"
  rm -f "${status}" "${checkpoint}"

  python3 - "${plan}" <<'PY'
import json
import math
import sys

plan_path = sys.argv[1]
speed = 3.0
injected_meters = 250.0
latitude = 37.0
longitude = -122.0
delta_latitude = injected_meters / (6371000.0 * math.pi / 180.0)
plan = {
    "injectedMeters": injected_meters,
    "speedMetersPerSecond": speed,
    "expectedPaceSecondsPerKilometer": 1000.0 / speed,
    "startLatitude": latitude,
    "startLongitude": longitude,
    "endLatitude": latitude + delta_latitude,
    "endLongitude": longitude,
    "coverageMin": 0.99,
    "distanceRelativeErrorMax": 0.005,
    "paceErrorMaxSecondsPerKilometer": 2.0,
}
with open(plan_path, "w", encoding="utf-8") as handle:
    json.dump(plan, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
PY

  trap 'xcrun simctl location "${udid}" clear >/dev/null 2>&1 || true' EXIT

  xcrun simctl location "${udid}" clear >/dev/null 2>&1 || true
  xcrun simctl terminate "${udid}" "${bundle_id}" >/dev/null 2>&1 || true
  xcrun simctl launch "${udid}" "${bundle_id}" \
    --harness corelocation \
    --status "${status}" \
    --checkpoint "${checkpoint}" \
    --max-duration 200 >/dev/null || link_fail "corelocation 模式 App 启动失败"

  wait_for_corelocation_ready "${status}" 30 || link_fail "corelocation 定位授权未就绪"

  push_location_route "${status}" "${plan}" 300 || link_fail "注入路线未在进度预算内被采集到 99% 距离"

  xcrun simctl location "${udid}" clear >/dev/null 2>&1 || true

  wait_for_status "${status}" finished 120 || link_fail "corelocation status 未在超时内达到 finished"

  cp "${status}" "${work_dir}/corelocation-status.json"
}

phase_resume() {
  local container run_dir checkpoint resume_status
  container="$(app_container_path)" || link_fail "无法获取 App 容器路径"
  run_dir="${container}/Library/Caches/verify-ios-sim-runtime"
  checkpoint="${run_dir}/direct-checkpoint.jsonl"
  resume_status="${run_dir}/resume-status.json"

  xcrun simctl terminate "${udid}" "${bundle_id}" >/dev/null 2>&1 || true

  if [ ! -s "${checkpoint}" ]; then
    link_fail "杀进程后 App 容器内缺少非空 checkpoint 文件"
  fi
  cp "${checkpoint}" "${work_dir}/direct-checkpoint.jsonl"

  rm -f "${resume_status}"
  xcrun simctl launch "${udid}" "${bundle_id}" \
    --harness resume \
    --status "${resume_status}" \
    --checkpoint "${checkpoint}" >/dev/null || link_fail "resume 模式 App 启动失败"

  if ! python3 - "${resume_status}" 60 <<'PY'
import json
import sys
import time

path, timeout = sys.argv[1], float(sys.argv[2])
deadline = time.time() + timeout
last = "missing"
while time.time() < deadline:
    try:
        with open(path, "r", encoding="utf-8") as handle:
            doc = json.load(handle)
        last = "resumed=%s" % doc.get("resumed")
        if doc.get("resumed") is True:
            sys.exit(0)
    except FileNotFoundError:
        last = "missing"
    except Exception as exc:  # noqa: BLE001
        last = "unreadable: %s" % exc
    time.sleep(0.1)
print("等待 resume status 超时（最后 %s）" % last, file=sys.stderr)
sys.exit(1)
PY
  then
    link_fail "resume status 未在超时内出现 resumed=true"
  fi

  cp "${resume_status}" "${work_dir}/resume-status.json"
}

setup_failed=0
set +e
( set -euo pipefail; setup_environment )
setup_rc=$?
set -e
if [ "${setup_rc}" -ne 0 ]; then
  setup_failed=1
fi

if [ "${setup_failed}" -eq 0 ]; then
  # shellcheck disable=SC1091
  source "${work_dir}/device.env"
fi

if [ "${setup_failed}" -eq 0 ]; then
  run_phase direct phase_direct
  run_phase terminate-relaunch phase_resume
  run_phase corelocation phase_corelocation
  xcrun simctl location "${udid}" clear >/dev/null 2>&1 || true
fi

set +e
python3 - "${work_dir}" "${report_path}" <<'PY'
import json
import math
import os
import sys

work_dir, report_path = sys.argv[1], sys.argv[2]

failures = {}
failures_path = os.path.join(work_dir, "failures.txt")
if os.path.exists(failures_path):
    with open(failures_path, "r", encoding="utf-8") as handle:
        for raw_line in handle:
            line = raw_line.strip()
            if not line:
                continue
            link, _, reason = line.partition(": ")
            failures.setdefault(link, []).append(reason)

durations = {}
phases_path = os.path.join(work_dir, "phases.tsv")
if os.path.exists(phases_path):
    with open(phases_path, "r", encoding="utf-8") as handle:
        for raw_line in handle:
            parts = raw_line.strip().split("\t")
            if len(parts) == 3:
                durations[parts[0]] = int(parts[2])


def load(name):
    path = os.path.join(work_dir, name)
    with open(path, "r", encoding="utf-8") as handle:
        return json.load(handle)


def load_device():
    path = os.path.join(work_dir, "device.json")
    try:
        return load("device.json")
    except Exception:
        return {"name": "iPhone 16", "udid": "unavailable", "runtime": "iOS 18.6"}


def haversine(first, second):
    radius = 6371000.0
    lat1 = math.radians(float(first["latitude"]))
    lon1 = math.radians(float(first["longitude"]))
    lat2 = math.radians(float(second["latitude"]))
    lon2 = math.radians(float(second["longitude"]))
    delta_lat = lat2 - lat1
    delta_lon = lon2 - lon1
    value = math.sin(delta_lat / 2.0) ** 2 + math.cos(lat1) * math.cos(lat2) * math.sin(delta_lon / 2.0) ** 2
    return 2.0 * radius * math.asin(min(1.0, math.sqrt(value)))


def recompute_distance(raw_samples, anchor_reason=None):
    previous = None
    total = 0.0
    for sample in raw_samples:
        if anchor_reason is not None and sample.get("rejectedReason") == anchor_reason:
            previous = sample
            continue
        if not sample.get("accepted"):
            continue
        if previous is not None:
            total += haversine(previous, sample)
        previous = sample
    return total


def build_link(link_id, thresholds, actual, checks):
    reasons = list(failures.get(link_id, []))
    check_records = []
    for name, ok, detail in checks:
        check_records.append({"id": name, "ok": bool(ok), "detail": detail})
        if not ok:
            reasons.append("%s: %s" % (name, detail))
    verdict = "pass" if not reasons else "fail"
    result = {
        "id": link_id,
        "status": "passed" if verdict == "pass" else "failed",
        "thresholds": thresholds,
        "actual": actual,
        "checks": check_records,
        "verdict": verdict,
        "durationSeconds": durations.get(link_id, 0),
    }
    if reasons:
        result["failureReason"] = "; ".join(reasons)
    return result


def direct_link():
    plan = load("direct-plan.json")
    status = load("direct-status.json")
    raw = status.get("rawSamples", [])
    accepted = [sample for sample in raw if sample.get("accepted")]
    recomputed = recompute_distance(raw)
    actual = status.get("actual", {})
    distance = float(actual.get("distanceMeters") or 0.0)
    elapsed = float(actual.get("elapsedSeconds") or 0.0)
    average_pace = actual.get("averagePaceSecondsPerKilometer")
    current_pace = actual.get("currentPaceSecondsPerKilometer")
    completed = int(actual.get("completedKilometers") or 0)
    split_indexes = list(actual.get("splitSampleIndexes") or [])
    expected_indexes = list(plan.get("expectedSplitSampleIndexes") or [])
    splits = status.get("splits", [])
    announcements = status.get("announcements", [])
    kilometer_announcements = [item for item in announcements if item.get("trigger") == "kilometerCompleted"]
    announced_indexes = [int(item.get("splitIndex") or 0) for item in kilometer_announcements]
    finished_announcements = [item for item in announcements if item.get("trigger") == "finished"]
    trigger_counts = {}
    for item in announcements:
        key = str(item.get("trigger"))
        trigger_counts[key] = trigger_counts.get(key, 0) + 1
    unexpected_triggers = sorted(set(trigger_counts) - {"kilometerCompleted", "finished"})
    try:
        after = load("direct-status-after.json")
    except Exception:
        after = {}
    after_announcements = after.get("announcements", [])
    on_disk_lines = int(plan.get("onDiskLineCount") or plan.get("totalLines") or 0)

    distance_error = abs(distance - recomputed) / recomputed if recomputed > 0 else 1.0
    expected_distance_error = abs(recomputed - 3000.0) / 3000.0
    recomputed_pace = elapsed / (recomputed / 1000.0) if recomputed > 0 else 0.0
    pace_error = abs(float(average_pace) - recomputed_pace) if average_pace is not None else 1.0e9
    boundary_deltas = [
        abs(actual_index - expected_index)
        for actual_index, expected_index in zip(split_indexes, expected_indexes)
    ]
    split_distances = [float(item.get("distanceMeters") or 0.0) for item in splits]
    split_distance_ok = all(abs(value - 1000.0) / 1000.0 <= 0.01 for value in split_distances)
    monotonic_ok = all(
        split_distances[index] <= split_distances[index + 1] + 1.0e-9
        for index in range(len(split_distances) - 1)
    )

    checks = [
        ("schemaVersion", status.get("schemaVersion") == 1, "schemaVersion=%s" % status.get("schemaVersion")),
        ("mode", status.get("mode") == "direct", "mode=%s" % status.get("mode")),
        ("state", status.get("state") == "finished", "state=%s" % status.get("state")),
        ("rawSamplesNonEmpty", len(raw) > 0, "rawSamples=%d" % len(raw)),
        (
            "sampleCountsReceived",
            int(status.get("sampleCounts", {}).get("received", -1)) == len(raw),
            "received=%s rawSamples=%d" % (status.get("sampleCounts", {}).get("received"), len(raw)),
        ),
        (
            "streamLineCount",
            on_disk_lines >= 3000,
            "onDiskLineCount=%d" % on_disk_lines,
        ),
        ("distanceRelativeError", distance_error <= 0.005, "relativeError=%.6f" % distance_error),
        ("expectedDistanceRelativeError", expected_distance_error <= 0.01, "relativeError=%.6f" % expected_distance_error),
        ("averagePaceError", pace_error <= 2.0, "paceError=%.6f" % pace_error),
        (
            "currentPaceRange",
            current_pace is not None and 300.0 <= float(current_pace) <= 420.0,
            "currentPace=%s" % current_pace,
        ),
        ("completedKilometers", completed == 3, "completedKilometers=%d" % completed),
        ("splitIndexCount", len(split_indexes) == 3, "splitSampleIndexes=%s" % split_indexes),
        (
            "splitBoundaryTolerance",
            len(split_indexes) == len(expected_indexes) and all(delta <= 1 for delta in boundary_deltas),
            "actual=%s expected=%s deltas=%s" % (split_indexes, expected_indexes, boundary_deltas),
        ),
        (
            "splitDistances",
            len(split_distances) == 3 and split_distance_ok and monotonic_ok,
            "splits=%s" % split_distances,
        ),
        (
            "kilometerAnnouncementsExactlyOnce",
            len(kilometer_announcements) == completed and announced_indexes == list(range(1, completed + 1)),
            "count=%d indexes=%s completed=%d" % (len(kilometer_announcements), announced_indexes, completed),
        ),
        (
            "finishAnnouncement",
            len(finished_announcements) <= 1,
            "finishCount=%d" % len(finished_announcements),
        ),
        (
            "announcementTriggers",
            not unexpected_triggers
            and len(announcements) == len(kilometer_announcements) + len(finished_announcements),
            "triggerCounts=%s unexpected=%s" % (trigger_counts, unexpected_triggers),
        ),
        (
            "noAnnouncementAfterFinish",
            after.get("state") == "finished" and len(after_announcements) == len(announcements),
            "stateAfter=%s announcementsAfter=%d announcementsAtFinish=%d"
            % (after.get("state"), len(after_announcements), len(announcements)),
        ),
        ("error", status.get("error") is None, "error=%s" % status.get("error")),
    ]

    thresholds = {
        "distanceRelativeErrorMax": 0.005,
        "paceErrorMaxSecondsPerKilometer": 2.0,
        "splitBoundaryToleranceSamples": 1,
        "expectedDistanceMeters": 3000.0,
        "currentPaceMinSecondsPerKilometer": 300.0,
        "currentPaceMaxSecondsPerKilometer": 420.0,
        "streamMinimumLines": 3000,
    }
    actual_record = {
        "distanceMeters": distance,
        "recomputedDistanceMeters": recomputed,
        "distanceRelativeError": distance_error,
        "expectedDistanceRelativeError": expected_distance_error,
        "averagePaceSecondsPerKilometer": average_pace,
        "recomputedAveragePaceSecondsPerKilometer": recomputed_pace,
        "paceErrorSecondsPerKilometer": pace_error,
        "currentPaceSecondsPerKilometer": current_pace,
        "completedKilometers": completed,
        "splitCount": int(actual.get("splitCount") or 0),
        "splitSampleIndexes": split_indexes,
        "expectedSplitSampleIndexes": expected_indexes,
        "streamLineCount": on_disk_lines,
        "acceptedSampleCount": len(accepted),
        "announcementCount": len(announcements),
        "kilometerAnnouncementCount": len(kilometer_announcements),
        "announcementTriggerCounts": trigger_counts,
    }
    return build_link("direct", thresholds, actual_record, checks)


def corelocation_link():
    plan = load("corelocation-plan.json")
    status = load("corelocation-status.json")
    raw = status.get("rawSamples", [])
    recomputed = recompute_distance(raw, anchor_reason="firstPoint")
    if recomputed == 0.0:
        recomputed = recompute_distance(raw)
    actual = status.get("actual", {})
    distance = float(actual.get("distanceMeters") or 0.0)
    average_pace = actual.get("averagePaceSecondsPerKilometer")
    elapsed = float(actual.get("elapsedSeconds") or 0.0)
    injected = float(plan.get("injectedMeters") or 250.0)
    expected_pace = float(plan.get("expectedPaceSecondsPerKilometer") or (1000.0 / 3.0))
    distance_error = abs(distance - recomputed) / recomputed if recomputed > 0 else 1.0
    injected_error = abs(recomputed - injected) / injected
    coverage = recomputed / injected if injected > 0 else 0.0
    recomputed_pace = elapsed / (recomputed / 1000.0) if recomputed > 0 else 0.0
    pace_error = abs(float(average_pace) - expected_pace) if average_pace is not None else 1.0e9
    recomputed_pace_error = abs(float(average_pace) - recomputed_pace) if average_pace is not None else 1.0e9
    authorization = status.get("locationAuthorization")
    authorized = authorization in ("authorizedWhenInUse", "authorizedAlways")

    checks = [
        ("schemaVersion", status.get("schemaVersion") == 1, "schemaVersion=%s" % status.get("schemaVersion")),
        ("mode", status.get("mode") == "corelocation", "mode=%s" % status.get("mode")),
        ("locationAuthorization", authorized, "locationAuthorization=%s" % authorization),
        ("error", status.get("error") is None, "error=%s" % status.get("error")),
        ("rawSamplesNonEmpty", len(raw) > 0, "rawSamples=%d" % len(raw)),
        (
            "sampleCountsReceived",
            int(status.get("sampleCounts", {}).get("received", -1)) == len(raw),
            "received=%s rawSamples=%d" % (status.get("sampleCounts", {}).get("received"), len(raw)),
        ),
        ("distanceRelativeError", distance_error <= 0.005, "relativeError=%.6f" % distance_error),
        ("injectedDistanceError", injected_error <= 0.01, "relativeError=%.6f" % injected_error),
        ("captureCoverage", coverage >= 0.99, "coverage=%.6f" % coverage),
        ("averagePaceError", pace_error <= 2.0, "paceError=%.6f" % pace_error),
        ("recomputedPaceError", recomputed_pace_error <= 2.0, "paceError=%.6f" % recomputed_pace_error),
        ("state", status.get("state") == "finished", "state=%s" % status.get("state")),
    ]

    thresholds = {
        "distanceRelativeErrorMax": 0.005,
        "paceErrorMaxSecondsPerKilometer": 2.0,
        "coverageMin": 0.99,
        "injectedRouteMeters": injected,
        "injectedSpeedMetersPerSecond": float(plan.get("speedMetersPerSecond") or 3.0),
        "expectedPaceSecondsPerKilometer": expected_pace,
    }
    actual_record = {
        "distanceMeters": distance,
        "recomputedDistanceMeters": recomputed,
        "distanceRelativeError": distance_error,
        "injectedMeters": injected,
        "capturedMeters": recomputed,
        "injectedDistanceRelativeError": injected_error,
        "coverage": coverage,
        "averagePaceSecondsPerKilometer": average_pace,
        "recomputedAveragePaceSecondsPerKilometer": recomputed_pace,
        "expectedPaceSecondsPerKilometer": expected_pace,
        "paceErrorSecondsPerKilometer": pace_error,
        "locationAuthorization": authorization,
        "rawSampleCount": len(raw),
        "rejectedByFirstPoint": int(status.get("sampleCounts", {}).get("rejectedByFirstPoint") or 0),
    }
    return build_link("corelocation", thresholds, actual_record, checks)


def resume_link():
    resume = load("resume-status.json")
    restored = resume.get("restored") or {}
    checkpoint_lines = []
    with open(os.path.join(work_dir, "direct-checkpoint.jsonl"), "r", encoding="utf-8") as handle:
        for raw_line in handle:
            line = raw_line.strip()
            if line:
                checkpoint_lines.append(json.loads(line))
    last = checkpoint_lines[-1] if checkpoint_lines else {}
    direct_status = load("direct-status.json")
    direct_completed = int((direct_status.get("actual") or {}).get("completedKilometers") or 0)
    max_announced = 0
    for item in direct_status.get("announcements", []):
        if item.get("trigger") == "kilometerCompleted":
            max_announced = max(max_announced, int(item.get("splitIndex") or 0))
    restored_announced = int(restored.get("announcedSplitIndex") or 0)
    checkpoint_announced = int(last.get("announcedSplitIndex") or 0)
    duplicate = [
        item for item in resume.get("announcements", [])
        if int(item.get("splitIndex") or 0) <= restored_announced
    ]
    last_distance = float(last.get("completedDistance") or 0.0)
    last_split_count = len(last.get("splits") or [])
    restored_distance = float(restored.get("completedDistanceMeters") or 0.0)
    restored_split_count = int(restored.get("splitCount") or 0)
    checkpoint_split_indexes = [int(item.get("index") or 0) for item in (last.get("splits") or [])]
    checkpoint_semantics_ok = (
        int(last.get("formatVersion") or 0) == 1
        and checkpoint_split_indexes == list(range(1, last_split_count + 1))
        and last_distance >= 0.0
        and isinstance(last.get("state"), str)
        and bool(last.get("state"))
    )

    checks = [
        ("resumed", resume.get("resumed") is True, "resumed=%s" % resume.get("resumed")),
        ("error", resume.get("error") is None, "error=%s" % resume.get("error")),
        ("restoredPresent", bool(restored), "restored=%s" % bool(restored)),
        (
            "directCompletedKilometersAtLeastTwo",
            direct_completed >= 2,
            "completedKilometers=%d" % direct_completed,
        ),
        (
            "checkpointLineCount",
            len(checkpoint_lines) >= 2,
            "lines=%d" % len(checkpoint_lines),
        ),
        (
            "checkpointSemantics",
            checkpoint_semantics_ok,
            "formatVersion=%s indexes=%s state=%s distance=%.6f"
            % (last.get("formatVersion"), checkpoint_split_indexes, last.get("state"), last_distance),
        ),
        (
            "restoredDistance",
            restored_distance >= last_distance - 1.0e-6,
            "restored=%.6f checkpoint=%.6f" % (restored_distance, last_distance),
        ),
        (
            "restoredSplitCount",
            restored_split_count >= last_split_count,
            "restored=%d checkpoint=%d" % (restored_split_count, last_split_count),
        ),
        (
            "restoredAnnouncedSplitIndex",
            restored_announced >= max_announced,
            "restored=%d announcedBeforeKill=%d" % (restored_announced, max_announced),
        ),
        (
            "restoredAnnouncedSplitIndexMatchesCheckpoint",
            restored_announced == checkpoint_announced,
            "restored=%d checkpoint=%d" % (restored_announced, checkpoint_announced),
        ),
        (
            "checkpointMatchesRestored",
            abs(restored_distance - last_distance) <= 1.0e-6 and restored_split_count == last_split_count,
            "distanceDelta=%.9f splitDelta=%d" % (restored_distance - last_distance, restored_split_count - last_split_count),
        ),
        (
            "noDuplicateAnnouncement",
            len(duplicate) == 0,
            "duplicateCount=%d" % len(duplicate),
        ),
    ]

    thresholds = {
        "checkpointMinimumLines": 2,
        "checkpointFormatVersion": 1,
        "directCompletedKilometersMinimum": 2,
        "restoredDistanceMinimumMeters": last_distance,
        "restoredSplitCountMinimum": last_split_count,
        "restoredAnnouncedSplitIndexMinimum": max_announced,
        "distanceToleranceMeters": 1.0e-6,
    }
    actual_record = {
        "resumed": resume.get("resumed"),
        "restoredCompletedDistanceMeters": restored_distance,
        "restoredSplitCount": restored_split_count,
        "restoredAnnouncedSplitIndex": restored_announced,
        "checkpointLineCount": len(checkpoint_lines),
        "checkpointFormatVersion": last.get("formatVersion"),
        "checkpointState": last.get("state"),
        "checkpointLastCompletedDistanceMeters": last_distance,
        "checkpointLastSplitCount": last_split_count,
        "checkpointAnnouncedSplitIndex": checkpoint_announced,
        "directCompletedKilometers": direct_completed,
        "announcedSplitIndexBeforeKill": max_announced,
        "duplicateAnnouncementCount": len(duplicate),
        "error": resume.get("error"),
    }
    return build_link("terminate-relaunch", thresholds, actual_record, checks)


link_builders = [
    ("direct", direct_link),
    ("corelocation", corelocation_link),
    ("terminate-relaunch", resume_link),
]


def fallback_thresholds(link_id):
    if link_id == "direct":
        return {
            "distanceRelativeErrorMax": 0.005,
            "paceErrorMaxSecondsPerKilometer": 2.0,
            "splitBoundaryToleranceSamples": 1,
            "expectedDistanceMeters": 3000.0,
            "currentPaceMinSecondsPerKilometer": 300.0,
            "currentPaceMaxSecondsPerKilometer": 420.0,
            "streamMinimumLines": 3000,
        }
    if link_id == "corelocation":
        try:
            plan = load("corelocation-plan.json")
        except Exception:
            plan = {}
        return {
            "distanceRelativeErrorMax": 0.005,
            "paceErrorMaxSecondsPerKilometer": 2.0,
            "coverageMin": float(plan.get("coverageMin") or 0.99),
            "injectedRouteMeters": float(plan.get("injectedMeters") or 250.0),
            "injectedSpeedMetersPerSecond": float(plan.get("speedMetersPerSecond") or 3.0),
            "expectedPaceSecondsPerKilometer": float(plan.get("expectedPaceSecondsPerKilometer") or (1000.0 / 3.0)),
        }
    return {
        "checkpointMinimumLines": 2,
        "checkpointFormatVersion": 1,
        "directCompletedKilometersMinimum": 2,
        "distanceToleranceMeters": 1.0e-6,
    }


def fallback_actual(link_id):
    status_files = {
        "direct": "direct-status.json",
        "corelocation": "corelocation-status.json",
        "terminate-relaunch": "resume-status.json",
    }
    try:
        doc = load(status_files[link_id])
    except Exception:
        return {}
    actual = doc.get("actual") or {}
    return {
        "state": doc.get("state"),
        "distanceMeters": actual.get("distanceMeters"),
        "averagePaceSecondsPerKilometer": actual.get("averagePaceSecondsPerKilometer"),
        "rawSampleCount": len(doc.get("rawSamples") or []),
    }


links = []
for link_id, builder in link_builders:
    try:
        links.append(builder())
    except Exception as exc:  # noqa: BLE001 - 缺产物时仍要写出机读报告
        links.append({
            "id": link_id,
            "status": "failed",
            "thresholds": fallback_thresholds(link_id),
            "actual": fallback_actual(link_id),
            "checks": [],
            "verdict": "fail",
            "durationSeconds": durations.get(link_id, 0),
            "failureReason": "; ".join(failures.get(link_id, []) + ["产物缺失或无法解析: %s" % exc]),
        })

verdict = "pass" if all(link["verdict"] == "pass" for link in links) else "fail"
report = {
    "schemaVersion": 1,
    "generatedAt": __import__("time").time(),
    "device": load_device(),
    "links": links,
    "deviceVerification": {
        "backgroundLocationContinuous": "pending: 待人现场",
        "audioNotInterrupted": "pending: 待人现场",
        "ttsLiveListen": "pending: 待人现场",
    },
    "notes": [
        "direct 直接流为脚本生成的 3 km、1 Hz、5:00–7:00/km JSONL，真实写入 App 容器；独立 Haversine 复算不信任 actual 自证。",
        "corelocation 以 1 Hz 的 xcrun simctl location set 确定性逐点推进 250 m 路线（每 tick 3.0 m），不依赖 simctl location start 的播放时长；按 3.0 m/s 独立换算的期望配速为 333.33 s/km（阈值仍为 ±2 s/km），PRD 文案写作 5:00/km 与 3.0 m/s 不等价。",
        "真机项（后台锁屏连续定位、音乐不打断与 duck 恢复、TTS 实听）保持 pending: 待人现场。",
    ],
    "verdict": verdict,
}
with open(report_path, "w", encoding="utf-8") as handle:
    json.dump(report, handle, ensure_ascii=False, indent=2)
    handle.write("\n")

if verdict != "pass":
    for link in links:
        if link["verdict"] != "pass":
            print("verify-ios-sim-runtime: %s 判定失败: %s" % (link["id"], link.get("failureReason", "")), file=sys.stderr)
    sys.exit(1)
sys.exit(0)
PY
report_rc=$?
set -e

if [ "${report_rc}" -ne 0 ]; then
  echo "verify-ios-sim-runtime: 机读报告判定失败（${report_path}）" >&2
  exit 1
fi

echo "verify-ios-sim-runtime: 三条链路通过，机读报告 ${report_path}"
