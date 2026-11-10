#!/usr/bin/env bash
# PurePace 真机取证单一入口（P0-2）。
# 十个 phase 固定顺序：preflight → wda → install → launch → tcc → audio → record → lock → collect → evidence。
# 证据固定落 artifacts/device-run/<candidateKey>/；中间解包 / xctestrun / probe 只进 .build/device-run/<candidateKey>/。
# --phase=plan 无设备自证；真实设备连跑两次归 Owner 的设备 ops task，不在本脚本内宣称设备已验证。
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"

DEFAULT_DEVICE_UDID="00008101-001C701E0A68001E"
PHASES="preflight wda install launch tcc audio record lock collect evidence"
VALID_PHASES="plan all preflight wda install launch tcc audio record lock collect evidence"
AUTOSTART_FLAG="-autoStartRecording"
WDA_BASE="http://127.0.0.1:8100"
DEFAULT_TCC_WAIT_SECONDS=120
DEFAULT_WDA_TIMEOUT_SECONDS=240
DEFAULT_LOCK_WAIT_SECONDS=60
DEFAULT_UNLOCK_WAIT_SECONDS=120
DEFAULT_FIRST_SCREEN_TIMEOUT_SECONDS=90
DEFAULT_RECORD_CONFIRM_TIMEOUT_SECONDS=90
usage() {
  cat <<'EOF'
用法: scripts/device-run.sh [--phase=...] [选项]

真机取证单一入口：把 devicectl / xcodebuild / iproxy / WDA HTTP 收敛为幂等脚本，
证据固定落 artifacts/device-run/<candidateKey>/。十个 phase 固定顺序：
  preflight  wda  install  launch  tcc  audio  record  lock  collect  evidence

选项:
  --phase=<值>               取值 plan|all|<单个 phase>；缺省 all
  --dry-run                  等价于 --phase=plan（不碰设备、不跑 devicectl/xcodebuild/iproxy）
  --device=<udid>            目标真机 UDID；缺省 00008101-001C701E0A68001E
  --candidate=<zip>          候选包 zip；缺省唯一匹配 artifacts/candidates/PurePace-Release-*.zip
  --expect-zip-sha256=<hex>  期望候选 zip 的 sha256，不匹配 fail-closed
  --expect-exec-sha256=<hex> 期望 App 可执行文件的 sha256，不匹配 fail-closed
  --wda-xctestrun=<path>     WebDriverAgentRunner 的 .xctestrun
  --tcc=<模式>               auto|preset|manual；缺省 auto
  --tcc-wait-seconds=<n>     manual 授权等待上限；缺省 120
  --self-check               对 scripts/device-*.sh 逐个 bash -n（有 shellcheck 时 -S error），
                             并自证 --phase=plan 的幂等与 step 顺序，退出 0
  -h, --help                 显示本帮助并退出 0

环境变量（选项优先；未给选项时作为缺省）:
  PUREPACE_DEVICE_UDID / PUREPACE_CANDIDATE_ZIP
  PUREPACE_EXPECT_ZIP_SHA256 / PUREPACE_EXPECT_EXEC_SHA256
  PUREPACE_WDA_XCTESTRUN / PUREPACE_TCC_HELPER
  PUREPACE_WDA_TIMEOUT_SECONDS / PUREPACE_LOCK_WAIT_SECONDS
  PUREPACE_UNLOCK_WAIT_SECONDS / PUREPACE_FIRST_SCREEN_TIMEOUT_SECONDS
  PUREPACE_RECORD_CONFIRM_TIMEOUT_SECONDS

产物（同一候选包路径稳定，重复运行覆盖写同一证据根）:
  artifacts/device-run/<candidateKey>/summary.json
  artifacts/device-run/<candidateKey>/manifest-sha256.txt
  artifacts/device-run/<candidateKey>/logs/<phase>.log
  artifacts/device-run/<candidateKey>/container/{runs,exports,telemetry,diagnostics}/
  artifacts/device-run/<candidateKey>/wda/{status.json,lock.json,locked.json}
  candidateKey = zip-<候选 zip sha256 前 16 位>

退出码:
  0  本次请求的 phase 全部 ok（plan 模式为自证通过）
  1  任一步失败（fail-closed），summary.json 与失败 step 日志仍落盘
  2  参数非法（未知参数 / 非法 phase / 非法 tcc 模式 / 非整数等待秒数）
EOF
}

die_usage() {
  printf 'device-run: %s（使用 --help 查看用法）\n' "$1" >&2
  exit 2
}

require_uint() {
  case "${1:-}" in
    ''|*[!0-9]*) die_usage "$2 必须是整数（收到 '${1:-}'）" ;;
  esac
}
# ------------------------------------------------------------------ 参数解析
phase_request=""
dry_run=0
self_check=0
device_udid="${PUREPACE_DEVICE_UDID:-$DEFAULT_DEVICE_UDID}"
candidate_input="${PUREPACE_CANDIDATE_ZIP:-}"
expect_zip_sha="${PUREPACE_EXPECT_ZIP_SHA256:-}"
expect_exec_sha="${PUREPACE_EXPECT_EXEC_SHA256:-}"
wda_xctestrun_input="${PUREPACE_WDA_XCTESTRUN:-}"
tcc_mode="auto"
tcc_wait_seconds="$DEFAULT_TCC_WAIT_SECONDS"
wda_timeout_seconds="${PUREPACE_WDA_TIMEOUT_SECONDS:-$DEFAULT_WDA_TIMEOUT_SECONDS}"
lock_wait_seconds="${PUREPACE_LOCK_WAIT_SECONDS:-$DEFAULT_LOCK_WAIT_SECONDS}"
unlock_wait_seconds="${PUREPACE_UNLOCK_WAIT_SECONDS:-$DEFAULT_UNLOCK_WAIT_SECONDS}"
first_screen_timeout="${PUREPACE_FIRST_SCREEN_TIMEOUT_SECONDS:-$DEFAULT_FIRST_SCREEN_TIMEOUT_SECONDS}"
record_confirm_timeout="${PUREPACE_RECORD_CONFIRM_TIMEOUT_SECONDS:-$DEFAULT_RECORD_CONFIRM_TIMEOUT_SECONDS}"

while [ "$#" -gt 0 ]; do
  arg="$1"
  shift
  case "$arg" in
    -h|--help)
      usage
      exit 0
      ;;
    --self-check)
      self_check=1
      ;;
    --dry-run)
      dry_run=1
      ;;
    --phase=*)
      phase_request="${arg#--phase=}"
      ;;
    --phase)
      [ "$#" -gt 0 ] || die_usage '--phase 缺少取值'
      phase_request="$1"
      shift
      ;;
    --device=*)
      device_udid="${arg#--device=}"
      ;;
    --device)
      [ "$#" -gt 0 ] || die_usage '--device 缺少取值'
      device_udid="$1"
      shift
      ;;
    --candidate=*)
      candidate_input="${arg#--candidate=}"
      ;;
    --candidate)
      [ "$#" -gt 0 ] || die_usage '--candidate 缺少取值'
      candidate_input="$1"
      shift
      ;;
    --expect-zip-sha256=*)
      expect_zip_sha="${arg#--expect-zip-sha256=}"
      ;;
    --expect-zip-sha256)
      [ "$#" -gt 0 ] || die_usage '--expect-zip-sha256 缺少取值'
      expect_zip_sha="$1"
      shift
      ;;
    --expect-exec-sha256=*)
      expect_exec_sha="${arg#--expect-exec-sha256=}"
      ;;
    --expect-exec-sha256)
      [ "$#" -gt 0 ] || die_usage '--expect-exec-sha256 缺少取值'
      expect_exec_sha="$1"
      shift
      ;;
    --wda-xctestrun=*)
      wda_xctestrun_input="${arg#--wda-xctestrun=}"
      ;;
    --wda-xctestrun)
      [ "$#" -gt 0 ] || die_usage '--wda-xctestrun 缺少取值'
      wda_xctestrun_input="$1"
      shift
      ;;
    --tcc=*)
      tcc_mode="${arg#--tcc=}"
      ;;
    --tcc)
      [ "$#" -gt 0 ] || die_usage '--tcc 缺少取值'
      tcc_mode="$1"
      shift
      ;;
    --tcc-wait-seconds=*)
      tcc_wait_seconds="${arg#--tcc-wait-seconds=}"
      ;;
    --tcc-wait-seconds)
      [ "$#" -gt 0 ] || die_usage '--tcc-wait-seconds 缺少取值'
      tcc_wait_seconds="$1"
      shift
      ;;
    *)
      die_usage "未知参数 '${arg}'"
      ;;
  esac
done

if [ "$dry_run" -eq 1 ]; then
  phase_request="plan"
fi
if [ -z "$phase_request" ]; then
  phase_request="all"
fi

phase_ok=0
for known in $VALID_PHASES; do
  if [ "$known" = "$phase_request" ]; then
    phase_ok=1
  fi
done
if [ "$phase_ok" -ne 1 ]; then
  printf "device-run: 非法 phase '%s'，合法取值: %s\n" "$phase_request" "$VALID_PHASES" >&2
  exit 2
fi

case "$tcc_mode" in
  auto|preset|manual) ;;
  *) die_usage "非法 tcc 模式 '${tcc_mode}'（合法取值: auto|preset|manual）" ;;
esac

require_uint "$tcc_wait_seconds" '--tcc-wait-seconds'
require_uint "$wda_timeout_seconds" 'PUREPACE_WDA_TIMEOUT_SECONDS'
require_uint "$lock_wait_seconds" 'PUREPACE_LOCK_WAIT_SECONDS'
require_uint "$unlock_wait_seconds" 'PUREPACE_UNLOCK_WAIT_SECONDS'
require_uint "$first_screen_timeout" 'PUREPACE_FIRST_SCREEN_TIMEOUT_SECONDS'
require_uint "$record_confirm_timeout" 'PUREPACE_RECORD_CONFIRM_TIMEOUT_SECONDS'
# ------------------------------------------------------------------ 通用工具
now_utc() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

now_epoch() {
  python3 -c 'import time;print("%.3f" % time.time())'
}

elapsed_seconds() {
  python3 -c 'import sys;print("%.3f" % (float(sys.argv[2]) - float(sys.argv[1])))' "$1" "$2"
}

say() {
  printf '%s\n' "$*"
}

log() {
  if [ -n "${CURRENT_LOG:-}" ] && [ -f "${CURRENT_LOG}" ]; then
    printf '%s\n' "$*" >> "$CURRENT_LOG"
  fi
}

sha256_of() {
  local line
  line="$(shasum -a 256 "$1")"
  printf '%s' "${line%% *}"
}

step_set() {
  printf '%s' "$3" > "${state_dir}/steps/${1}.${2}"
}

step_get() {
  local file="${state_dir}/steps/${1}.${2}"
  if [ -f "$file" ]; then
    cat "$file"
  else
    printf ''
  fi
}

record_timing() {
  printf '%s' "$2" > "${state_dir}/timings/${1}"
}

add_pending() {
  printf '%s\n' "$1" >> "${state_dir}/pending.txt"
}

read_timing() {
  local file="${state_dir}/timings/${1}"
  if [ -f "$file" ]; then
    cat "$file"
  else
    printf '0'
  fi
}

dir_nonempty() {
  python3 - "$1" <<'PY'
import os
import sys
try:
    entries = os.listdir(sys.argv[1])
except OSError:
    entries = []
raise SystemExit(0 if entries else 1)
PY
}

print_log_tail() {
  local file="$1"
  if [ -s "$file" ]; then
    printf '%s\n' '--- last 40 log lines ---' >&2
    tail -n 40 "$file" >&2
  fi
}

begin_step() {
  STEP_ID="$1"
  mkdir -p "${evidence_dir}/logs"
  CURRENT_LOG="${evidence_dir}/logs/${1}.log"
  : > "$CURRENT_LOG"
  printf 'START %s %s\n' "$1" "$(now_utc)" >> "$CURRENT_LOG"
  step_set "$1" status running
  step_set "$1" startedAt "$(now_utc)"
  step_set "$1" finishedAt ''
  step_set "$1" error ''
  say "[${1}] start"
}

end_step() {
  local status="$1"
  local error="${2:-}"
  step_set "$STEP_ID" status "$status"
  step_set "$STEP_ID" finishedAt "$(now_utc)"
  step_set "$STEP_ID" error "$error"
  printf 'END %s %s status=%s\n' "$STEP_ID" "$(now_utc)" "$status" >> "$CURRENT_LOG"
  say "[${STEP_ID}] ${status}"
  return 0
}

finalize_step_failure() {
  local id="$1"
  local status="$2"
  local message="$3"
  local file="${evidence_dir}/logs/${id}.log"
  if [ -f "$file" ]; then
    # 先抹掉该 step 可能已写入的 END 行（例如 tcc 先 ok 后被授权自报校验改判 failed），
    # 保证每个日志只剩一条、且位于末行的 END。
    python3 - "$file" "$id" <<'PY'
import sys

path, sid = sys.argv[1], sys.argv[2]
with open(path, "r", encoding="utf-8", errors="replace") as handle:
    lines = handle.readlines()
while lines and lines[-1].rstrip("\n").startswith("END %s " % sid):
    lines.pop()
with open(path, "w", encoding="utf-8") as handle:
    handle.writelines(lines)
PY
    printf 'FAIL %s: %s\n' "$id" "$message" >> "$file"
    printf 'END %s %s status=%s\n' "$id" "$(now_utc)" "$status" >> "$file"
  fi
  step_set "$id" status "$status"
  step_set "$id" finishedAt "$(now_utc)"
  step_set "$id" error "$message"
  printf 'failedStep=%s\n' "$id" >&2
  printf 'reason: %s\n' "$message" >&2
  if [ -f "$file" ]; then
    printf 'log: %s\n' "${file#"${repo_root}/"}" >&2
    print_log_tail "$file"
  fi
  exit 1
}

fail_step() {
  finalize_step_failure "$STEP_ID" failed "$1"
}

mark_step_failed() {
  finalize_step_failure "$1" failed "$2"
}

mark_step_pending() {
  add_pending "${1}: ${2}"
  finalize_step_failure "$1" pending "$2"
}
# ------------------------------------------------- 候选包定位与 candidateKey
candidate_path=""
candidate_matches=0

resolve_candidate_loose() {
  candidate_path=""
  candidate_matches=0
  if [ -n "$candidate_input" ]; then
    candidate_path="$candidate_input"
    if [ -f "$candidate_input" ]; then
      candidate_matches=1
    fi
    return 0
  fi
  local file
  local only=""
  for file in "${repo_root}"/artifacts/candidates/PurePace-Release-*.zip; do
    if [ -e "$file" ]; then
      candidate_matches=$((candidate_matches + 1))
      only="$file"
    fi
  done
  if [ "$candidate_matches" -eq 1 ]; then
    candidate_path="$only"
  fi
  return 0
}

candidate_key_for() {
  local path="$1"
  local digest
  if [ -n "$path" ] && [ -f "$path" ]; then
    digest="$(sha256_of "$path")"
  else
    digest="$(printf '%s' 'no-candidate' | shasum -a 256)"
    digest="${digest%% *}"
  fi
  printf 'zip-%s' "${digest:0:16}"
}

resolve_candidate_loose
candidate_key="$(candidate_key_for "$candidate_path")"
evidence_dir="${repo_root}/artifacts/device-run/${candidate_key}"
state_dir="${repo_root}/.build/device-run/${candidate_key}"
wda_dir="${evidence_dir}/wda"
container_dir="${evidence_dir}/container"

# --------------------------------------------------------------- plan 自证输出
print_plan() {
  printf 'mode=plan\n'
  printf 'phase=%s\n' "$phase_request"
  printf 'candidateKey=%s\n' "$candidate_key"
  if [ -n "$candidate_path" ]; then
    printf 'candidate=%s\n' "$candidate_path"
  else
    printf 'candidate=<none>\n'
  fi
  printf 'device.udid=%s\n' "$device_udid"
  printf 'tcc.mode=%s\n' "$tcc_mode"
  printf 'evidence.root=artifacts/device-run/%s\n' "$candidate_key"
  printf 'state.root=.build/device-run/%s\n' "$candidate_key"

  printf 'step=preflight\n'
  printf '  command: xcrun devicectl list devices --json-output .build/device-run/%s/device-list.json\n' "$candidate_key"
  printf '  command: unzip -q -o <candidate.zip> -d .build/device-run/%s/unpack\n' "$candidate_key"
  printf '  command: plutil -extract CFBundleIdentifier raw -o - <app>/Info.plist\n'
  printf '  command: shasum -a 256 <candidate.zip> <app-exec>\n'
  printf '  evidence: logs/preflight.log\n'

  printf 'step=wda\n'
  printf '  command: xcodebuild test-without-building -xctestrun <WebDriverAgentRunner.xctestrun> -destination id=%s -only-testing:WebDriverAgentRunner/UITestingUITests\n' "$device_udid"
  printf '  command: iproxy -u %s 8100:8100 (LOCAL:DEVICE)\n' "$device_udid"
  printf '  command: curl -sS -o wda/status.json %s/status   # WDA HTTP 200 为就绪\n' "$WDA_BASE"
  printf '  command: curl -sS -X POST -d {"capabilities":{}} %s/session\n' "$WDA_BASE"
  printf '  evidence: logs/wda.log logs/wda.xcodebuild.log logs/iproxy.log wda/status.json\n'

  printf 'step=install\n'
  printf '  command: xcrun devicectl device info apps --device %s --json-output .build/device-run/%s/apps-before.json\n' "$device_udid" "$candidate_key"
  printf '  command: xcrun devicectl device uninstall app --device %s <bundle-id>   # 仅已安装时\n' "$device_udid"
  printf '  command: xcrun devicectl device install app --device %s <unpacked .app>\n' "$device_udid"
  printf '  evidence: logs/install.log\n'

  printf 'step=launch\n'
  printf '  command: xcrun devicectl device process launch --terminate-existing --device %s <bundle-id>\n' "$device_udid"
  printf '  evidence: logs/launch.log\n'

  printf 'step=tcc\n'
  printf '  command: ${PUREPACE_TCC_HELPER:-<unset>} --device %s --bundle <bundle-id>   # auto 时有则调用\n' "$device_udid"
  printf '  command: sleep 5   # manual/preset 只做提示 + 有界等待，不点坐标、不识别文案\n'
  printf '  evidence: logs/tcc.log\n'

  printf 'step=audio\n'
  printf '  command: bash scripts/verify-ios-device-flow.sh --phase=audio --configuration=Release --candidate <candidate.zip> --device %s\n' "$device_udid"
  printf '  command: audio 固定三遍 app（系统 Music 本地曲目）→ runner（正例）→ none（负对照），只经 verify 脚本\n'
  printf '  evidence: audio/{meta.json,analysis.json,report.md,candidate-identity.json,duck-evidence.json}\n'
  printf '  evidence: audio/audio-app/{music-source.json,track-metadata.json,announcements-*.json,audio-result.json}\n'
  printf '  evidence: audio/audio-runner/ audio/audio-none/ audio/audio-step.json\n'

  printf 'step=record\n'
  printf '  command: xcrun devicectl device process launch --terminate-existing --device %s <bundle-id> -- %s\n' "$device_udid" "$AUTOSTART_FLAG"
  printf '  evidence: logs/record.log\n'

  printf 'step=lock\n'
  printf '  command: curl -sS -X POST -d {} %s/session/<id>/wda/lock\n' "$WDA_BASE"
  printf '  command: curl -sS %s/session/<id>/wda/locked   # 双证: lock.json + locked.json\n' "$WDA_BASE"
  printf '  evidence: logs/lock.log wda/lock.json wda/locked.json\n'

  printf 'step=collect\n'
  printf '  command: xcrun devicectl device copy from --device %s --domain-type appDataContainer --domain-identifier <bundle-id> --source Documents/Runs --destination container/runs\n' "$device_udid"
  printf '  command: xcrun devicectl device copy from --device %s --domain-type appDataContainer --domain-identifier <bundle-id> --source Documents/Exports --destination container/exports\n' "$device_udid"
  printf '  command: xcrun devicectl device copy from --device %s --domain-type appDataContainer --domain-identifier <bundle-id> --source Library/Caches/active-run.jsonl --destination container/diagnostics/active-run.jsonl\n' "$device_udid"
  printf '  evidence: logs/collect.log container/{runs,exports,telemetry,diagnostics}/\n'

  printf 'step=evidence\n'
  printf '  command: python3 写 summary.json 后按路径排序写 manifest-sha256.txt\n'
  printf '  evidence: summary.json manifest-sha256.txt logs/evidence.log\n'

  printf 'artifact: summary.json\n'
  printf 'artifact: manifest-sha256.txt\n'
  printf 'artifact: logs/preflight.log\n'
  printf 'artifact: logs/wda.log\n'
  printf 'artifact: logs/install.log\n'
  printf 'artifact: logs/launch.log\n'
  printf 'artifact: logs/tcc.log\n'
  printf 'artifact: logs/audio.log\n'
  printf 'artifact: audio/\n'
  printf 'artifact: logs/record.log\n'
  printf 'artifact: logs/lock.log\n'
  printf 'artifact: logs/collect.log\n'
  printf 'artifact: logs/evidence.log\n'
  printf 'artifact: container/runs/\n'
  printf 'artifact: container/exports/\n'
  printf 'artifact: container/telemetry/\n'
  printf 'artifact: container/diagnostics/\n'
  printf 'artifact: wda/status.json\n'
  printf 'artifact: wda/lock.json\n'
  printf 'artifact: wda/locked.json\n'
}

# ------------------------------------------- 解包内 App bundle 布局 resolver
# 候选 zip 有两种合法布局：Payload/*.app（优先）与根级 *.app（部分候选为 .app 直接打包）。
# 成功：CANDIDATE_APP_LAYOUT_PATH=<app 路径>，返回 0。
# 失败：CANDIDATE_APP_LAYOUT_ERROR=<含候选 zip 路径与 unpack 顶层条目的原因>，返回 1。
# 同一被选层内多个 .app 立即 fail-closed；Payload/ 命中时不再看根级。
CANDIDATE_APP_LAYOUT_PATH=""
CANDIDATE_APP_LAYOUT_ERROR=""

unpack_top_entries() {
  local unpack="$1"
  local entries
  entries="$(ls -A "$unpack" | tr '\n' ' ')"
  entries="${entries% }"
  if [ -z "$entries" ]; then
    entries="<empty>"
  fi
  printf '%s' "$entries"
}

resolve_unpacked_app_layout() {
  local unpack="$1"
  local zip_path="${2:-<candidate.zip>}"
  CANDIDATE_APP_LAYOUT_PATH=""
  CANDIDATE_APP_LAYOUT_ERROR=""
  local layer layer_dir candidate_app found
  for layer in payload root; do
    if [ "$layer" = "payload" ]; then
      layer_dir="${unpack}/Payload"
      if [ ! -d "$layer_dir" ]; then
        continue
      fi
    else
      layer_dir="$unpack"
    fi
    found=""
    for candidate_app in "$layer_dir"/*.app; do
      if [ ! -d "$candidate_app" ]; then
        continue
      fi
      if [ -n "$found" ]; then
        CANDIDATE_APP_LAYOUT_ERROR="候选 zip 内含多个 .app: ${found} / ${candidate_app}"
        return 1
      fi
      found="$candidate_app"
    done
    if [ -n "$found" ]; then
      CANDIDATE_APP_LAYOUT_PATH="$found"
      return 0
    fi
  done
  CANDIDATE_APP_LAYOUT_ERROR="解包后缺少 .app（既无 Payload/*.app 也无根级 *.app）: ${zip_path}; unpack 顶层条目: $(unpack_top_entries "$unpack")"
  return 1
}

# --------------------------------------------------------------- --self-check
run_self_check() {
  local rc=0
  local file
  for file in "${repo_root}"/scripts/device-*.sh; do
    if [ ! -f "$file" ]; then
      continue
    fi
    if ! bash -n "$file"; then
      printf 'self-check: bash -n 失败 %s\n' "$file" >&2
      rc=1
    fi
    if command -v shellcheck >/dev/null 2>&1; then
      if ! shellcheck -S error "$file"; then
        printf 'self-check: shellcheck 失败 %s\n' "$file" >&2
        rc=1
      fi
    fi
  done

  local plan_a=""
  local plan_b=""
  if ! plan_a="$(bash "${script_dir}/device-run.sh" --phase=plan 2>&1)"; then
    printf 'self-check: --phase=plan 失败\n' >&2
    rc=1
  fi
  if ! plan_b="$(bash "${script_dir}/device-run.sh" --phase=plan 2>&1)"; then
    printf 'self-check: --phase=plan 第二次失败\n' >&2
    rc=1
  fi
  if [ "$plan_a" != "$plan_b" ]; then
    printf 'self-check: 同一候选包两次 plan 输出不一致\n' >&2
    rc=1
  fi
  local id
  for id in $PHASES; do
    if ! grep -Fq -- "step=${id}" <<<"$plan_a"; then
      printf 'self-check: plan 缺少 step=%s\n' "$id" >&2
      rc=1
    fi
  done
  local needle
  for needle in 'devicectl' 'xcodebuild test-without-building' 'iproxy' "${WDA_BASE}/status"; do
    if ! grep -Fq -- "$needle" <<<"$plan_a"; then
      printf 'self-check: plan 缺少 %s\n' "$needle" >&2
      rc=1
    fi
  done

  local rc_probe=0
  bash "${script_dir}/device-run.sh" --phase=definitely-invalid >/dev/null 2>&1 || rc_probe=$?
  if [ "$rc_probe" -ne 2 ]; then
    printf 'self-check: 非法 phase 退出 %s（期望 2）\n' "$rc_probe" >&2
    rc=1
  fi
  rc_probe=0
  bash "${script_dir}/device-run.sh" --definitely-invalid >/dev/null 2>&1 || rc_probe=$?
  if [ "$rc_probe" -ne 2 ]; then
    printf 'self-check: 未知参数退出 %s（期望 2）\n' "$rc_probe" >&2
    rc=1
  fi

  # 候选包布局 resolver 夹具：临时目录现造（不入库、结束清理），断言的就是 preflight 生产入口。
  local layout_root
  layout_root="$(mktemp -d "${TMPDIR:-/tmp}/purepace-device-layout.XXXXXX")"
  local layout_dir

  layout_dir="${layout_root}/payload-only"
  mkdir -p "${layout_dir}/Payload/PurePace.app"
  if resolve_unpacked_app_layout "$layout_dir" "${layout_dir}/candidate.zip" \
    && [ "$CANDIDATE_APP_LAYOUT_PATH" = "${layout_dir}/Payload/PurePace.app" ]; then
    printf 'self-check: layout[1] payload-only → %s\n' "$CANDIDATE_APP_LAYOUT_PATH"
  else
    printf 'self-check: layout[1] payload-only 解析失败\n  path=%s\n  error=%s\n' \
      "$CANDIDATE_APP_LAYOUT_PATH" "$CANDIDATE_APP_LAYOUT_ERROR" >&2
    rc=1
  fi

  layout_dir="${layout_root}/root-only"
  mkdir -p "${layout_dir}/PurePace.app"
  if resolve_unpacked_app_layout "$layout_dir" "${layout_dir}/candidate.zip" \
    && [ "$CANDIDATE_APP_LAYOUT_PATH" = "${layout_dir}/PurePace.app" ]; then
    printf 'self-check: layout[2] root-only → %s\n' "$CANDIDATE_APP_LAYOUT_PATH"
  else
    printf 'self-check: layout[2] root-only 解析失败\n  path=%s\n  error=%s\n' \
      "$CANDIDATE_APP_LAYOUT_PATH" "$CANDIDATE_APP_LAYOUT_ERROR" >&2
    rc=1
  fi

  layout_dir="${layout_root}/both"
  mkdir -p "${layout_dir}/Payload/PurePace.app" "${layout_dir}/Decoy.app"
  if resolve_unpacked_app_layout "$layout_dir" "${layout_dir}/candidate.zip" \
    && [ "$CANDIDATE_APP_LAYOUT_PATH" = "${layout_dir}/Payload/PurePace.app" ]; then
    printf 'self-check: layout[3] payload+root 取 Payload → %s\n' "$CANDIDATE_APP_LAYOUT_PATH"
  else
    printf 'self-check: layout[3] payload+root 未按 Payload 优先解析\n  path=%s\n  error=%s\n' \
      "$CANDIDATE_APP_LAYOUT_PATH" "$CANDIDATE_APP_LAYOUT_ERROR" >&2
    rc=1
  fi

  layout_dir="${layout_root}/missing"
  mkdir -p "${layout_dir}/Payload" "${layout_dir}/__MACOSX"
  if resolve_unpacked_app_layout "$layout_dir" "${layout_dir}/candidate.zip"; then
    printf 'self-check: layout[4] missing 应 fail-closed 却返回 %s\n' "$CANDIDATE_APP_LAYOUT_PATH" >&2
    rc=1
  elif ! grep -Fq -- "__MACOSX" <<<"$CANDIDATE_APP_LAYOUT_ERROR" \
    || ! grep -Fq -- "Payload" <<<"$CANDIDATE_APP_LAYOUT_ERROR" \
    || ! grep -Fq -- "${layout_dir}/candidate.zip" <<<"$CANDIDATE_APP_LAYOUT_ERROR"; then
    printf 'self-check: layout[4] missing 失败文案缺少顶层条目或候选路径: %s\n' \
      "$CANDIDATE_APP_LAYOUT_ERROR" >&2
    rc=1
  else
    printf 'self-check: layout[4] missing fail-closed → %s\n' "$CANDIDATE_APP_LAYOUT_ERROR"
  fi

  layout_dir="${layout_root}/multi"
  mkdir -p "${layout_dir}/Payload/One.app" "${layout_dir}/Payload/Two.app"
  if resolve_unpacked_app_layout "$layout_dir" "${layout_dir}/candidate.zip"; then
    printf 'self-check: layout[5] 同一层多 .app 应 fail-closed 却返回 %s\n' "$CANDIDATE_APP_LAYOUT_PATH" >&2
    rc=1
  elif ! grep -Fq -- "One.app" <<<"$CANDIDATE_APP_LAYOUT_ERROR" \
    || ! grep -Fq -- "Two.app" <<<"$CANDIDATE_APP_LAYOUT_ERROR"; then
    printf 'self-check: layout[5] 多 .app 失败文案未列出冲突路径: %s\n' "$CANDIDATE_APP_LAYOUT_ERROR" >&2
    rc=1
  else
    printf 'self-check: layout[5] multi-app fail-closed → %s\n' "$CANDIDATE_APP_LAYOUT_ERROR"
  fi
  rm -rf "$layout_root"

  if [ "$rc" -ne 0 ]; then
    printf 'device-run: self-check 失败\n' >&2
    exit 1
  fi
  printf 'device-run: self-check OK\n'
  exit 0
}

if [ "$self_check" -eq 1 ]; then
  run_self_check
fi

if [ "$phase_request" = "plan" ]; then
  print_plan
  exit 0
fi
# --------------------------------------------------------- 真机运行的现场准备
mode_started_at="$(now_utc)"
mode_started_epoch="$(now_epoch)"
summary_done=0
cleanup_done=0
wda_session_id=""
wda_http_reachable=0
wda_xcodebuild_pid=""
iproxy_pid=""
CURRENT_LOG=""
STEP_ID=""

rm -rf "$state_dir"
mkdir -p "${state_dir}/steps" "${state_dir}/timings"
rm -rf "$evidence_dir"
mkdir -p "${evidence_dir}/logs" "$wda_dir" "${container_dir}/runs" "${container_dir}/exports" \
  "${container_dir}/telemetry" "${container_dir}/diagnostics"
printf '%s' "$candidate_key" > "${state_dir}/candidateKey"

initial_status="skipped"
if [ "$phase_request" = "all" ]; then
  initial_status="pending"
fi
for step_id in $PHASES; do
  step_set "$step_id" status "$initial_status"
  step_set "$step_id" startedAt ''
  step_set "$step_id" finishedAt ''
  step_set "$step_id" error ''
done

stop_own_pid() {
  local pid="$1"
  local label="$2"
  local target_log="$3"
  if [ -z "$pid" ]; then
    return 0
  fi
  if ! kill -0 "$pid" 2>/dev/null; then
    printf 'not-running %s pid=%s\n' "$label" "$pid" >> "$target_log"
    return 0
  fi
  if kill "$pid" 2>/dev/null; then
    printf 'killed %s pid=%s\n' "$label" "$pid" >> "$target_log"
  else
    printf 'kill-failed %s pid=%s\n' "$label" "$pid" >> "$target_log"
  fi
  local waited=0
  while [ "$waited" -lt 10 ]; do
    if ! kill -0 "$pid" 2>/dev/null; then
      break
    fi
    sleep 0.5
    waited=$((waited + 1))
  done
  if kill -0 "$pid" 2>/dev/null; then
    if kill -9 "$pid" 2>/dev/null; then
      printf 'killed -9 %s pid=%s\n' "$label" "$pid" >> "$target_log"
    else
      printf 'kill -9 failed %s pid=%s\n' "$label" "$pid" >> "$target_log"
    fi
  fi
  return 0
}

cleanup_processes() {
  local cleanup_log="${evidence_dir}/logs/cleanup.log"
  mkdir -p "${evidence_dir}/logs"
  : > "$cleanup_log"
  printf 'cleanup %s\n' "$(now_utc)" >> "$cleanup_log"
  if [ -n "$wda_session_id" ] && [ "$wda_http_reachable" -eq 1 ]; then
    if curl -sS -X DELETE -o /dev/null --max-time 5 "${WDA_BASE}/session/${wda_session_id}" >> "$cleanup_log" 2>&1; then
      printf 'wda session delete ok session=%s\n' "$wda_session_id" >> "$cleanup_log"
    else
      printf 'wda session delete failed session=%s\n' "$wda_session_id" >> "$cleanup_log"
    fi
  fi
  stop_own_pid "$iproxy_pid" 'iproxy' "$cleanup_log"
  stop_own_pid "$wda_xcodebuild_pid" 'xcodebuild' "$cleanup_log"
  iproxy_pid=""
  wda_xcodebuild_pid=""
  local residue_pids=""
  if residue_pids="$(pgrep -f "iproxy -u ${device_udid} 8100:8100" 2>/dev/null)"; then
    printf 'notice: 其他 iproxy 实例仍在运行 pids=%s（非本脚本启动，未处理）\n' "$residue_pids" >> "$cleanup_log"
  else
    printf 'residue: iproxy 无残留\n' >> "$cleanup_log"
  fi
  if residue_pids="$(pgrep -f "xcodebuild test-without-building .*id=${device_udid}" 2>/dev/null)"; then
    printf 'notice: 其他 xcodebuild 实例仍在运行 pids=%s（非本脚本启动，未处理）\n' "$residue_pids" >> "$cleanup_log"
  else
    printf 'residue: xcodebuild 无残留\n' >> "$cleanup_log"
  fi
  if curl -sS --max-time 2 -o /dev/null "${WDA_BASE}/status" >> "$cleanup_log" 2>&1; then
    printf 'notice: 端口 8100 仍有 WDA 响应（非本脚本启动）\n' >> "$cleanup_log"
  else
    printf 'residue: 端口 8100 已释放\n' >> "$cleanup_log"
  fi
  return 0
}

write_summary() {
  local status="$1"
  export SUMMARY_STATUS="$status"
  export SUMMARY_PHASE="$phase_request"
  export SUMMARY_TCC_MODE="$tcc_mode"
  export SUMMARY_STARTED_AT="$mode_started_at"
  export SUMMARY_FINISHED_AT="$(now_utc)"
  export SUMMARY_TOTAL_SECONDS="$(elapsed_seconds "$mode_started_epoch" "$(now_epoch)")"
  export SUMMARY_WDA_WARMUP="$(read_timing wdaWarmupSeconds)"
  export SUMMARY_RUN_SECONDS="$(read_timing runSeconds)"
  export SUMMARY_EVIDENCE_DIR="$evidence_dir"
  export SUMMARY_STATE_DIR="$state_dir"
  export SUMMARY_DEVICE_UDID="$device_udid"
  python3 - <<'PY'
import datetime
import hashlib
import json
import os

evidence = os.environ["SUMMARY_EVIDENCE_DIR"]
state = os.environ["SUMMARY_STATE_DIR"]
order = ["preflight", "wda", "install", "launch", "tcc", "audio", "record", "lock", "collect", "evidence"]


def read(path, default=""):
    try:
        with open(path, "r", encoding="utf-8") as handle:
            return handle.read().strip()
    except OSError:
        return default


def parse_ts(value):
    if not value:
        return None
    try:
        return datetime.datetime.strptime(value, "%Y-%m-%dT%H:%M:%SZ")
    except ValueError:
        return None


def as_float(value):
    try:
        return round(float(value), 3)
    except (TypeError, ValueError):
        return 0


steps = []
for step_id in order:
    status = read(os.path.join(state, "steps", step_id + ".status"), "skipped")
    started = read(os.path.join(state, "steps", step_id + ".startedAt"))
    finished = read(os.path.join(state, "steps", step_id + ".finishedAt"))
    error = read(os.path.join(state, "steps", step_id + ".error"))
    if status == "running":
        status = "failed"
    if status not in ("ok", "skipped", "failed", "pending", "planned"):
        status = "skipped"
    start_dt = parse_ts(started)
    finish_dt = parse_ts(finished)
    duration = 0
    if start_dt is not None and finish_dt is not None:
        duration = round((finish_dt - start_dt).total_seconds(), 3)
        if duration < 0:
            duration = 0
    steps.append({
        "id": step_id,
        "status": status,
        "startedAt": started,
        "finishedAt": finished,
        "durationSeconds": duration,
        "log": "logs/%s.log" % step_id,
        "exitCode": 0 if status in ("ok", "skipped") else 1,
        "error": error,
    })

candidate = {
    "path": "",
    "zipSha256": "",
    "execSha256": "",
    "bundleId": "",
    "version": "",
    "build": "",
    "pinned": False,
    "expectedZipSha256": None,
    "expectedExecSha256": None,
}
candidate_file = os.path.join(state, "candidate.json")
if os.path.isfile(candidate_file):
    try:
        with open(candidate_file, "r", encoding="utf-8") as handle:
            loaded = json.load(handle)
        if isinstance(loaded, dict):
            candidate.update(loaded)
    except (OSError, ValueError):
        pass
candidate["pinned"] = bool(candidate.get("pinned"))

device = {"udid": os.environ["SUMMARY_DEVICE_UDID"], "name": "", "iosVersion": ""}
device_file = os.path.join(state, "device.json")
if os.path.isfile(device_file):
    try:
        with open(device_file, "r", encoding="utf-8") as handle:
            loaded = json.load(handle)
        if isinstance(loaded, dict):
            device.update(loaded)
    except (OSError, ValueError):
        pass

authorization = {"status": "", "accuracy": "", "source": ""}
auth_file = os.path.join(state, "authorization.json")
if os.path.isfile(auth_file):
    try:
        with open(auth_file, "r", encoding="utf-8") as handle:
            loaded = json.load(handle)
        if isinstance(loaded, dict):
            authorization.update(loaded)
    except (OSError, ValueError):
        pass

artifacts = []
for base, dirs, files in os.walk(evidence):
    dirs.sort()
    for name in sorted(files):
        full = os.path.join(base, name)
        rel = os.path.relpath(full, evidence)
        if rel in ("summary.json", "manifest-sha256.txt"):
            continue
        digest = hashlib.sha256()
        with open(full, "rb") as handle:
            for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                digest.update(chunk)
        artifacts.append({"path": rel, "sha256": digest.hexdigest(), "bytes": os.path.getsize(full)})
artifacts.sort(key=lambda item: item["path"])

pending = []
pending_file = os.path.join(state, "pending.txt")
if os.path.isfile(pending_file):
    with open(pending_file, "r", encoding="utf-8") as handle:
        pending = [line.strip() for line in handle if line.strip()]

summary = {
    "schemaVersion": 1,
    "candidateKey": read(os.path.join(state, "candidateKey"), "zip-0000000000000000"),
    "candidate": candidate,
    "device": device,
    "mode": {
        "phase": os.environ["SUMMARY_PHASE"],
        "tcc": os.environ["SUMMARY_TCC_MODE"],
        "status": os.environ["SUMMARY_STATUS"],
        "startedAt": os.environ["SUMMARY_STARTED_AT"],
        "finishedAt": os.environ["SUMMARY_FINISHED_AT"],
    },
    "timings": {
        "wdaWarmupSeconds": as_float(os.environ["SUMMARY_WDA_WARMUP"]),
        "runSeconds": as_float(os.environ["SUMMARY_RUN_SECONDS"]),
        "totalSeconds": as_float(os.environ["SUMMARY_TOTAL_SECONDS"]),
    },
    "steps": steps,
    "authorization": {
        "status": authorization.get("status") or "",
        "accuracy": authorization.get("accuracy") or "",
        "source": authorization.get("source") or "",
    },
    "artifacts": artifacts,
    "pending": pending,
}

with open(os.path.join(evidence, "summary.json"), "w", encoding="utf-8") as handle:
    json.dump(summary, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
print("summary.json written status=%s" % os.environ["SUMMARY_STATUS"])
PY
  return 0
}

write_manifest() {
  if [ ! -d "$evidence_dir" ]; then
    return 0
  fi
  python3 - "$evidence_dir" <<'PY'
import hashlib
import os
import sys

root = sys.argv[1]
entries = []
for base, dirs, files in os.walk(root):
    dirs.sort()
    for name in sorted(files):
        full = os.path.join(base, name)
        rel = os.path.relpath(full, root)
        if rel == "manifest-sha256.txt":
            continue
        digest = hashlib.sha256()
        with open(full, "rb") as handle:
            for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                digest.update(chunk)
        entries.append((rel, digest.hexdigest()))
entries.sort()
with open(os.path.join(root, "manifest-sha256.txt"), "w", encoding="utf-8") as handle:
    for rel, digest in entries:
        handle.write("%s  %s\n" % (digest, rel))
PY
  return 0
}

on_exit() {
  local rc=$?
  trap - EXIT
  if [ -n "${STEP_ID:-}" ] && [ "$(step_get "$STEP_ID" status)" = "running" ]; then
    # 失败可能发生在别的 step 判定里（如 tcc 自报校验中断 collect），
    # 给被打断的当前 step 补一条 END，保证每个已开始的日志都以 END 收尾。
    step_set "$STEP_ID" status failed
    step_set "$STEP_ID" finishedAt "$(now_utc)"
    printf 'END %s %s status=failed\n' "$STEP_ID" "$(now_utc)" >> "$CURRENT_LOG"
  fi
  if [ "$cleanup_done" -eq 0 ]; then
    cleanup_processes
    cleanup_done=1
  fi
  if [ "$summary_done" -eq 0 ]; then
    local status="failed"
    if [ "$rc" -eq 0 ]; then
      status="ok"
    fi
    if write_summary "$status"; then
      printf '[exit] summary 已落盘\n' >&2
    else
      printf 'device-run: summary 写入失败\n' >&2
    fi
    if write_manifest; then
      printf '[exit] manifest 已落盘\n' >&2
    else
      printf 'device-run: manifest 写入失败\n' >&2
    fi
  fi
  exit "$rc"
}

trap on_exit EXIT
trap 'exit 130' INT TERM
# ----------------------------------------------------------- preflight 子步骤
write_candidate_json() {
  local pinned="$1"
  export CAND_PATH="$candidate_path"
  export CAND_ZIP_SHA="${zip_sha:-}"
  export CAND_EXEC_SHA="${exec_sha:-}"
  export CAND_BUNDLE_ID="${bundle_id:-}"
  export CAND_VERSION="${app_version:-}"
  export CAND_BUILD="${app_build:-}"
  export CAND_PINNED="$pinned"
  export CAND_EXPECT_ZIP="$expect_zip_sha"
  export CAND_EXPECT_EXEC="$expect_exec_sha"
  python3 - "$state_dir/candidate.json" <<'PY'
import json
import os
import sys

data = {
    "path": os.environ["CAND_PATH"],
    "zipSha256": os.environ["CAND_ZIP_SHA"],
    "execSha256": os.environ["CAND_EXEC_SHA"],
    "bundleId": os.environ["CAND_BUNDLE_ID"],
    "version": os.environ["CAND_VERSION"],
    "build": os.environ["CAND_BUILD"],
    "pinned": os.environ["CAND_PINNED"] == "true",
    "expectedZipSha256": os.environ.get("CAND_EXPECT_ZIP") or None,
    "expectedExecSha256": os.environ.get("CAND_EXPECT_EXEC") or None,
}
with open(sys.argv[1], "w", encoding="utf-8") as handle:
    json.dump(data, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
PY
  return 0
}

resolve_candidate_strict() {
  if [ -n "$candidate_input" ]; then
    if [ ! -f "$candidate_input" ]; then
      log "候选包不存在: ${candidate_input}"
      fail_step "候选包不存在: ${candidate_input}"
    fi
    candidate_path="$candidate_input"
    return 0
  fi
  candidate_path=""
  local count=0
  local only=""
  local file
  for file in "${repo_root}"/artifacts/candidates/PurePace-Release-*.zip; do
    if [ -e "$file" ]; then
      count=$((count + 1))
      only="$file"
      log "候选: ${file}"
    fi
  done
  if [ "$count" -eq 0 ]; then
    log "候选目录: artifacts/candidates/PurePace-Release-*.zip 无匹配"
    fail_step "未找到候选包（需 --candidate 或唯一的 artifacts/candidates/PurePace-Release-*.zip）"
  fi
  if [ "$count" -gt 1 ]; then
    fail_step "候选包多义（${count} 个），请用 --candidate 指定唯一路径"
  fi
  candidate_path="$only"
  return 0
}

phase_preflight() {
  begin_step preflight
  local device_file="${state_dir}/device-list.json"
  local device_info="${state_dir}/device.json"

  log "CMD: xcrun devicectl list devices --json-output ${device_file}"
  if ! xcrun devicectl list devices --json-output "$device_file" >> "$CURRENT_LOG" 2>&1; then
    fail_step "xcrun devicectl list devices 失败"
  fi
  if ! python3 - "$device_file" "$device_udid" "$device_info" <<'PY' >> "$CURRENT_LOG" 2>&1
import json
import sys

listing_path, target, out_path = sys.argv[1], sys.argv[2], sys.argv[3]
with open(listing_path, "r", encoding="utf-8") as handle:
    listing = json.load(handle)
result = listing.get("result")
if isinstance(result, dict):
    devices = result.get("devices") or []
else:
    devices = listing.get("devices") or []
match = None
for device in devices:
    hardware = device.get("hardwareProperties") or {}
    props = device.get("deviceProperties") or {}
    conn = device.get("connectionProperties") or {}
    if hardware.get("udid") == target or props.get("udid") == target:
        match = (hardware, props, conn)
        break
if match is None:
    print("目标 UDID %s 不在 devicectl 设备列表中" % target)
    raise SystemExit(1)
hardware, props, conn = match
reality = hardware.get("reality") or props.get("reality") or ""
pairing = conn.get("pairingState") or props.get("pairingState") or ""
problems = []
if reality != "physical":
    problems.append("reality=%r（期望 physical）" % reality)
if pairing != "paired":
    problems.append("pairingState=%r（期望 paired）" % pairing)
if problems:
    print("目标设备不可用: " + "; ".join(problems))
    raise SystemExit(1)
info = {
    "udid": target,
    "name": props.get("name") or "",
    "iosVersion": str(props.get("osVersionNumber") or ""),
}
with open(out_path, "w", encoding="utf-8") as handle:
    json.dump(info, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
print("device %s name=%s ios=%s" % (target, info["name"], info["iosVersion"]))
PY
  then
    fail_step "preflight: 目标 UDID 缺失 / 非物理机 / 未配对（详见日志）"
  fi

  resolve_candidate_strict
  log "candidate: ${candidate_path}"
  log "evidence.root=${evidence_dir#"${repo_root}/"}"
  log "candidateKey=${candidate_key}"

  if ! unzip -q -o "$candidate_path" -d "${state_dir}/unpack" >> "$CURRENT_LOG" 2>&1; then
    fail_step "候选 zip 解包失败: ${candidate_path}"
  fi
  local app_path=""
  if ! resolve_unpacked_app_layout "${state_dir}/unpack" "$candidate_path"; then
    fail_step "$CANDIDATE_APP_LAYOUT_ERROR"
  fi
  app_path="$CANDIDATE_APP_LAYOUT_PATH"

  local plist="${app_path}/Info.plist"
  if [ ! -f "$plist" ]; then
    fail_step "App 缺少 Info.plist: ${app_path}"
  fi
  if ! bundle_id="$(plutil -extract CFBundleIdentifier raw -o - "$plist" 2>> "$CURRENT_LOG")"; then
    fail_step "读取 CFBundleIdentifier 失败"
  fi
  if ! app_version="$(plutil -extract CFBundleShortVersionString raw -o - "$plist" 2>> "$CURRENT_LOG")"; then
    fail_step "读取 CFBundleShortVersionString 失败"
  fi
  if ! app_build="$(plutil -extract CFBundleVersion raw -o - "$plist" 2>> "$CURRENT_LOG")"; then
    fail_step "读取 CFBundleVersion 失败"
  fi
  if ! app_exec_name="$(plutil -extract CFBundleExecutable raw -o - "$plist" 2>> "$CURRENT_LOG")"; then
    fail_step "读取 CFBundleExecutable 失败"
  fi
  local exec_path="${app_path}/${app_exec_name}"
  if [ ! -f "$exec_path" ]; then
    fail_step "App 可执行文件不存在: ${exec_path}"
  fi

  zip_sha="$(sha256_of "$candidate_path")"
  exec_sha="$(sha256_of "$exec_path")"
  local computed_key
  computed_key="$(candidate_key_for "$candidate_path")"
  log "zip sha256=${zip_sha}"
  log "exec sha256=${exec_sha}"
  log "candidateKey=${computed_key}"

  if [ "$computed_key" != "$candidate_key" ]; then
    fail_step "candidateKey 不一致（当前 ${candidate_key}，按 zip sha 计算 ${computed_key}）"
  fi

  printf '%s' "$app_path" > "${state_dir}/app.path"
  printf '%s' "$bundle_id" > "${state_dir}/bundle.id"
  printf '%s' "$app_version" > "${state_dir}/app.version"
  printf '%s' "$app_build" > "${state_dir}/app.build"

  local mismatch=""
  if [ -n "$expect_zip_sha" ] && [ "$expect_zip_sha" != "$zip_sha" ]; then
    mismatch="zip expected=${expect_zip_sha} actual=${zip_sha}"
  fi
  if [ -n "$expect_exec_sha" ] && [ "$expect_exec_sha" != "$exec_sha" ]; then
    mismatch="${mismatch} exec expected=${expect_exec_sha} actual=${exec_sha}"
  fi
  if [ -n "$mismatch" ]; then
    log "expect mismatch: ${mismatch}"
    write_candidate_json false
    fail_step "候选包 sha256 与期望不一致: ${mismatch}"
  fi

  local pinned="false"
  if [ -n "$expect_zip_sha" ] || [ -n "$expect_exec_sha" ]; then
    pinned="true"
  fi
  write_candidate_json "$pinned"

  log "bundleId=${bundle_id} version=${app_version} build=${app_build} exec=${app_exec_name}"
  log "pinned=${pinned}"
  end_step ok
}

ensure_preflight() {
  if [ "$(step_get preflight status)" = "ok" ]; then
    return 0
  fi
  phase_preflight
}
# --------------------------------------------------------------- WDA / 设备探针
load_bundle_id() {
  bundle_id="$(cat "${state_dir}/bundle.id")"
}

wda_status_ok() {
  local code
  if ! code="$(curl -sS -o "${wda_dir}/status.json" -w '%{http_code}' --max-time 5 "${WDA_BASE}/status" 2>> "$CURRENT_LOG")"; then
    return 1
  fi
  [ "$code" = "200" ]
}

ensure_wda_session() {
  if [ -n "$wda_session_id" ]; then
    return 0
  fi
  local body="${state_dir}/wda-session.json"
  local code
  log "WDA HTTP: POST ${WDA_BASE}/session"
  if ! code="$(curl -sS -o "$body" -w '%{http_code}' -X POST \
      -H 'Content-Type: application/json' -d '{"capabilities":{},"desiredCapabilities":{}}' \
      --max-time 10 "${WDA_BASE}/session" 2>> "$CURRENT_LOG")"; then
    return 1
  fi
  if [ "$code" != "200" ] && [ "$code" != "201" ]; then
    log "WDA session HTTP ${code}"
    return 1
  fi
  wda_session_id="$(python3 - "$body" <<'PY'
import json
import sys
try:
    with open(sys.argv[1], "r", encoding="utf-8") as handle:
        data = json.load(handle)
except Exception:
    print("")
    raise SystemExit(0)
value = data.get("sessionId")
if not value:
    inner = data.get("value")
    if isinstance(inner, dict):
        value = inner.get("sessionId")
print(value or "")
PY
)"
  if [ -z "$wda_session_id" ]; then
    log "WDA session 响应缺少 sessionId"
    return 1
  fi
  log "WDA session id=${wda_session_id}"
  return 0
}

wda_source_ok() {
  if [ -z "$wda_session_id" ]; then
    return 1
  fi
  local code
  if ! code="$(curl -sS -o "${state_dir}/wda-source.json" -w '%{http_code}' --max-time 5 \
      "${WDA_BASE}/session/${wda_session_id}/source" 2>> "$CURRENT_LOG")"; then
    return 1
  fi
  if [ "$code" != "200" ]; then
    return 1
  fi
  [ -s "${state_dir}/wda-source.json" ]
}

container_runs_present() {
  local dest="${state_dir}/probe/Runs"
  rm -rf "$dest"
  mkdir -p "$dest"
  if xcrun devicectl device copy from \
      --device "$device_udid" \
      --domain-type appDataContainer \
      --domain-identifier "$bundle_id" \
      --source 'Documents/Runs' \
      --destination "$dest" >> "$CURRENT_LOG" 2>&1; then
    if dir_nonempty "$dest"; then
      return 0
    fi
  fi
  return 1
}

first_screen_ready() {
  if wda_source_ok; then
    log "首屏就绪: WDA source 可读"
    return 0
  fi
  if container_runs_present; then
    log "首屏就绪: 容器 Documents/Runs 已出现"
    return 0
  fi
  return 1
}

# ------------------------------------------------------------------- wda phase
phase_wda() {
  begin_step wda
  local xctestrun="$wda_xctestrun_input"
  if [ -z "$xctestrun" ]; then
    fail_step "缺少 --wda-xctestrun / PUREPACE_WDA_XCTESTRUN（WebDriverAgentRunner 的 .xctestrun）"
  fi
  if [ ! -f "$xctestrun" ]; then
    fail_step "xctestrun 不存在: ${xctestrun}"
  fi
  local warmup_started
  warmup_started="$(now_epoch)"

  log "CMD: xcodebuild test-without-building -xctestrun ${xctestrun} -destination id=${device_udid} -only-testing:WebDriverAgentRunner/UITestingUITests"
  xcodebuild test-without-building \
    -xctestrun "$xctestrun" \
    -destination "id=${device_udid}" \
    -only-testing:WebDriverAgentRunner/UITestingUITests \
    > "${evidence_dir}/logs/wda.xcodebuild.log" 2>&1 &
  wda_xcodebuild_pid="$!"
  log "xcodebuild pid=${wda_xcodebuild_pid}"

  log "CMD: iproxy -u ${device_udid} 8100:8100 (LOCAL:DEVICE)"
  iproxy -u "$device_udid" 8100:8100 > "${evidence_dir}/logs/iproxy.log" 2>&1 &
  iproxy_pid="$!"
  log "iproxy pid=${iproxy_pid}"

  local deadline=$(( $(date +%s) + wda_timeout_seconds ))
  local ready=0
  while [ "$(date +%s)" -lt "$deadline" ]; do
    if wda_status_ok; then
      ready=1
      break
    fi
    if ! kill -0 "$wda_xcodebuild_pid" 2>/dev/null; then
      fail_step "xcodebuild 在 WDA 就绪前退出（见 logs/wda.xcodebuild.log）"
    fi
    if ! kill -0 "$iproxy_pid" 2>/dev/null; then
      fail_step "iproxy 在 WDA 就绪前退出（见 logs/iproxy.log）"
    fi
    sleep 2
  done
  if [ "$ready" -ne 1 ]; then
    fail_step "有界轮询 ${WDA_BASE}/status 超时（${wda_timeout_seconds}s）"
  fi
  wda_http_reachable=1
  record_timing wdaWarmupSeconds "$(elapsed_seconds "$warmup_started" "$(now_epoch)")"
  log "WDA /status 200，warmup=$(read_timing wdaWarmupSeconds)s"
  if ! ensure_wda_session; then
    fail_step "WDA session 创建失败"
  fi
  end_step ok
}

# --------------------------------------------------------------- install phase
app_installed() {
  local listing="$1"
  python3 - "$listing" "$bundle_id" <<'PY'
import json
import sys
try:
    with open(sys.argv[1], "r", encoding="utf-8") as handle:
        data = json.load(handle)
except Exception:
    raise SystemExit(2)
apps = None
result = data.get("result")
if isinstance(result, dict):
    apps = result.get("apps")
if apps is None:
    apps = data.get("apps")
for app in apps or []:
    ident = app.get("bundleIdentifier") or app.get("identifier") or ""
    if ident == sys.argv[2]:
        raise SystemExit(0)
raise SystemExit(1)
PY
}

phase_install() {
  begin_step install
  ensure_preflight
  load_bundle_id
  local app_path
  app_path="$(cat "${state_dir}/app.path")"
  local apps_before="${state_dir}/apps-before.json"

  log "CMD: xcrun devicectl device info apps --device ${device_udid} --json-output ${apps_before}"
  if xcrun devicectl device info apps --device "$device_udid" --json-output "$apps_before" >> "$CURRENT_LOG" 2>&1; then
    if app_installed "$apps_before"; then
      log "已安装: ${bundle_id}，先卸载"
      log "CMD: xcrun devicectl device uninstall app --device ${device_udid} ${bundle_id}"
      if ! xcrun devicectl device uninstall app --device "$device_udid" "$bundle_id" >> "$CURRENT_LOG" 2>&1; then
        fail_step "卸载既有安装失败: ${bundle_id}"
      fi
    else
      log "未安装: ${bundle_id}，直接安装"
    fi
  else
    log "安装状态查询失败（按未安装处理）"
  fi

  log "CMD: xcrun devicectl device install app --device ${device_udid} ${app_path}"
  if ! xcrun devicectl device install app --device "$device_udid" "$app_path" \
      --json-output "${state_dir}/install.json" >> "$CURRENT_LOG" 2>&1; then
    fail_step "安装失败: ${app_path}"
  fi
  if [ -f "${state_dir}/install.json" ]; then
    python3 - "${state_dir}/install.json" "$bundle_id" <<'PY' >> "$CURRENT_LOG" 2>&1
import json
import sys
try:
    with open(sys.argv[1], "r", encoding="utf-8") as handle:
        data = json.load(handle)
except Exception:
    print("install.json 不可解析")
    raise SystemExit(0)


def pick(data, *names):
    stack = [data]
    while stack:
        node = stack.pop()
        if isinstance(node, dict):
            for name in names:
                value = node.get(name)
                if isinstance(value, (str, int)) and str(value):
                    return str(value)
            stack.extend(node.values())
        elif isinstance(node, list):
            stack.extend(node)
    return ""


print("installed bundleId=%s version=%s build=%s"
      % (sys.argv[2], pick(data, "version"), pick(data, "bundleVersion", "build")))
PY
  fi
  log "bundleId=${bundle_id} version=$(cat "${state_dir}/app.version") build=$(cat "${state_dir}/app.build")"
  end_step ok
}

# ---------------------------------------------------------------- launch phase
phase_launch() {
  begin_step launch
  ensure_preflight
  load_bundle_id
  log "CMD: xcrun devicectl device process launch --terminate-existing --device ${device_udid} ${bundle_id}"
  if ! xcrun devicectl device process launch --terminate-existing --device "$device_udid" "$bundle_id" >> "$CURRENT_LOG" 2>&1; then
    fail_step "App 启动失败: ${bundle_id}"
  fi
  local deadline=$(( $(date +%s) + first_screen_timeout ))
  local ready=0
  while [ "$(date +%s)" -lt "$deadline" ]; do
    if first_screen_ready; then
      ready=1
      break
    fi
    sleep 3
  done
  if [ "$ready" -ne 1 ]; then
    log "等待判据: WDA source 可读 或 容器 Documents/Runs 出现"
    log "最后轮询: WDA session=${wda_session_id:-<none>}"
    fail_step "首屏就绪等待超时（${first_screen_timeout}s）"
  fi
  end_step ok
}
# ------------------------------------------------------------------- tcc phase
tcc_manual_wait() {
  say "tcc: 请在设备上完成定位授权（脚本只提示 + 轮询，不点坐标、不识别文案），最长 ${tcc_wait_seconds}s"
  log "manual wait ${tcc_wait_seconds}s"
  local waited=0
  while [ "$waited" -lt "$tcc_wait_seconds" ]; do
    sleep 5
    waited=$((waited + 5))
    log "manual wait progress ${waited}/${tcc_wait_seconds}s"
  done
  end_step ok
}

phase_tcc() {
  begin_step tcc
  case "$tcc_mode" in
    preset)
      log "tcc=preset：假定已授权，只做校验不等待"
      end_step ok
      ;;
    auto)
      if [ -n "${PUREPACE_TCC_HELPER:-}" ] && [ -x "${PUREPACE_TCC_HELPER}" ]; then
        load_bundle_id
        log "CMD: ${PUREPACE_TCC_HELPER} --device ${device_udid} --bundle ${bundle_id}"
        if ! "${PUREPACE_TCC_HELPER}" --device "$device_udid" --bundle "$bundle_id" >> "$CURRENT_LOG" 2>&1; then
          fail_step "PUREPACE_TCC_HELPER 执行失败"
        fi
        end_step ok
      else
        log "tcc=auto：PUREPACE_TCC_HELPER 不可用，回退 manual 有界等待"
        tcc_manual_wait
      fi
      ;;
    manual)
      log "tcc=manual"
      tcc_manual_wait
      ;;
  esac
}

# ----------------------------------------------------------------- audio phase
# audio 必备产物清单：缺任一项 fail-closed（证据索引 audio-step.json 也按同一清单核对）。
audio_required_artifacts() {
  printf '%s\n' \
    "meta.json" \
    "analysis.json" \
    "report.md" \
    "candidate-identity.json" \
    "duck-evidence.json" \
    "audio-app/pass.json" \
    "audio-app/music-source.json" \
    "audio-app/track-metadata.json" \
    "audio-app/audio-result.json" \
    "audio-app/duck-evidence.json" \
    "audio-runner/pass.json" \
    "audio-runner/music-source.json" \
    "audio-runner/audio-result.json" \
    "audio-runner/duck-evidence.json" \
    "audio-none/pass.json" \
    "audio-none/music-source.json" \
    "audio-none/audio-result.json" \
    "audio-none/duck-evidence.json"
}

audio_announcement_gaps() {
  local root="$1" pass="" file="" found=""
  for pass in audio-app audio-runner audio-none; do
    found=""
    for file in "${root}/${pass}"/announcements-*.json; do
      if [ -s "$file" ]; then
        found="$file"
        break
      fi
    done
    if [ -z "$found" ]; then
      printf ' %s/announcements-*.json' "$pass"
    fi
  done
}

audio_evidence_gaps() {
  local root="$1" rel="" missing=""
  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    if [ ! -s "${root}/${rel}" ]; then
      missing="${missing} ${rel}"
    fi
  done <<EOF
$(audio_required_artifacts)
EOF
  missing="${missing}$(audio_announcement_gaps "$root")"
  printf '%s' "$missing"
}

write_audio_step_index() {
  local root="$1"
  local required=()
  local rel=""
  while IFS= read -r rel; do
    [ -n "$rel" ] && required+=("$rel")
  done <<EOF
$(audio_required_artifacts)
EOF
  python3 - "$root/audio-step.json" "$root" "$candidate_path" "${state_dir}/candidate.json" \
    "${required[@]}" <<'PY'
import glob
import json
import os
import sys

out_path, root, candidate_path, candidate_json = sys.argv[1:5]
required = sys.argv[5:]
try:
    with open(candidate_json, "r", encoding="utf-8") as handle:
        candidate = json.load(handle)
except Exception:
    candidate = {}
present = [rel for rel in required if os.path.isfile(os.path.join(root, rel)) and os.path.getsize(os.path.join(root, rel)) > 0]
announcements = sorted(
    os.path.relpath(path, root)
    for path in glob.glob(os.path.join(root, "audio-*", "announcements-*.json"))
)
payload = {
    "phase": "audio",
    "configuration": "Release",
    "grade": "release",
    "evidenceDir": root,
    "candidate": {
        "path": candidate_path,
        "zipSha256": candidate.get("zipSha256"),
        "execSha256": candidate.get("execSha256"),
    },
    "requiredArtifacts": required,
    "presentArtifacts": present,
    "missingArtifacts": [rel for rel in required if rel not in present],
    "announcementFiles": announcements,
    "passes": ["audio-app", "audio-runner", "audio-none"],
}
with open(out_path, "w", encoding="utf-8") as handle:
    json.dump(payload, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
print("audio-step.json missing=%d" % len(payload["missingArtifacts"]))
PY
}

phase_audio() {
  begin_step audio
  ensure_preflight
  load_bundle_id
  local audio_root="${evidence_dir}/audio"
  mkdir -p "$audio_root"
  log "CMD: bash scripts/verify-ios-device-flow.sh --phase=audio --configuration=Release --candidate ${candidate_path} --device ${device_udid}"
  log "evidence.root=${audio_root#"${repo_root}/"}"
  if ! PUREPACE_EVIDENCE_DIR="$audio_root" bash "${script_dir}/verify-ios-device-flow.sh" \
      --phase=audio \
      --configuration=Release \
      --candidate "$candidate_path" \
      --device "$device_udid" >> "$CURRENT_LOG" 2>&1; then
    local missing=""
    missing="$(audio_evidence_gaps "$audio_root")"
    log "audio 必备产物缺失:${missing:- <none>}"
    fail_step "verify-ios-device-flow.sh --phase=audio 失败（缺失产物:${missing:- <none>}，日志 logs/audio.log）"
  fi
  local missing=""
  missing="$(audio_evidence_gaps "$audio_root")"
  if [ -n "$missing" ]; then
    log "audio 必备产物缺失:${missing}"
    fail_step "audio 证据不完整，缺:${missing}"
  fi
  write_audio_step_index "$audio_root" >> "$CURRENT_LOG" 2>&1
  if [ ! -s "${audio_root}/audio-step.json" ]; then
    fail_step "audio-step.json 未生成（${audio_root}/audio-step.json）"
  fi
  end_step ok
  printf 'audio.evidence=%s\n' "${audio_root#"${repo_root}/"}"
}

# ---------------------------------------------------------------- record phase
record_active_present() {
  local checkpoint="${state_dir}/probe/active-run.jsonl"
  rm -f "$checkpoint"
  mkdir -p "${state_dir}/probe"
  if xcrun devicectl device copy from \
      --device "$device_udid" \
      --domain-type appDataContainer \
      --domain-identifier "$bundle_id" \
      --source 'Library/Caches/active-run.jsonl' \
      --destination "$checkpoint" >> "$CURRENT_LOG" 2>&1; then
    if [ -s "$checkpoint" ]; then
      log "记录态确认: Library/Caches/active-run.jsonl 非空"
      return 0
    fi
  fi
  if container_runs_present; then
    log "记录态确认: 容器 Documents/Runs 已有文件"
    return 0
  fi
  return 1
}

phase_record() {
  begin_step record
  ensure_preflight
  load_bundle_id
  now_epoch > "${state_dir}/timings/runStartEpoch"
  log "CMD: xcrun devicectl device process launch --terminate-existing --device ${device_udid} ${bundle_id} -- ${AUTOSTART_FLAG}"
  if ! xcrun devicectl device process launch --terminate-existing --device "$device_udid" "$bundle_id" \
      -- "$AUTOSTART_FLAG" >> "$CURRENT_LOG" 2>&1; then
    fail_step "带 ${AUTOSTART_FLAG} 的启动失败"
  fi
  local deadline=$(( $(date +%s) + record_confirm_timeout ))
  local recording=0
  while [ "$(date +%s)" -lt "$deadline" ]; do
    if record_active_present; then
      recording=1
      break
    fi
    sleep 3
  done
  if [ "$recording" -ne 1 ]; then
    fail_step "有界确认记录态失败（checkpoint 与 Documents/Runs 均未出现，${record_confirm_timeout}s）"
  fi
  end_step ok
}

# ------------------------------------------------------------------ lock phase
json_value_is_true() {
  python3 - "$1" <<'PY'
import json
import sys
try:
    with open(sys.argv[1], "r", encoding="utf-8") as handle:
        data = json.load(handle)
except Exception:
    raise SystemExit(1)
raise SystemExit(0 if data.get("value") is True else 1)
PY
}

wda_locked_state() {
  local code
  if ! code="$(curl -sS -o "${wda_dir}/locked.json" -w '%{http_code}' --max-time 5 \
      "${WDA_BASE}/session/${wda_session_id}/wda/locked" 2>> "$CURRENT_LOG")"; then
    return 1
  fi
  if [ "$code" != "200" ]; then
    return 1
  fi
  python3 - "${wda_dir}/locked.json" <<'PY'
import json
import sys
try:
    with open(sys.argv[1], "r", encoding="utf-8") as handle:
        value = json.load(handle).get("value")
except Exception:
    raise SystemExit(1)
print("true" if value is True else "false")
PY
}

wda_locked_is_true() {
  local state_value=""
  if ! state_value="$(wda_locked_state)"; then
    return 1
  fi
  [ "$state_value" = "true" ]
}

wda_locked_is_false() {
  local state_value=""
  if ! state_value="$(wda_locked_state)"; then
    return 1
  fi
  [ "$state_value" = "false" ]
}

poll_until() {
  local timeout="$1"
  shift
  local deadline=$(( $(date +%s) + timeout ))
  while [ "$(date +%s)" -lt "$deadline" ]; do
    if "$@"; then
      return 0
    fi
    sleep 2
  done
  return 1
}

phase_lock() {
  begin_step lock
  if ! ensure_wda_session; then
    fail_step "WDA session 不可用，无法执行 lock 双证"
  fi
  local lock_body="${wda_dir}/lock.json"
  local code
  log "WDA HTTP: POST ${WDA_BASE}/session/${wda_session_id}/wda/lock body={}"
  if ! code="$(curl -sS -o "$lock_body" -w '%{http_code}' -X POST \
      -H 'Content-Type: application/json' -d '{}' \
      --max-time 10 "${WDA_BASE}/session/${wda_session_id}/wda/lock" 2>> "$CURRENT_LOG")"; then
    fail_step "POST wda/lock 请求失败"
  fi
  log "wda/lock HTTP ${code}"
  if [ "$code" != "200" ]; then
    fail_step "POST wda/lock 返回 ${code}"
  fi
  if ! json_value_is_true "$lock_body"; then
    fail_step "wda/lock 响应不是 true（见 wda/lock.json）"
  fi
  if ! poll_until "$lock_wait_seconds" wda_locked_is_true; then
    fail_step "GET wda/locked 在 ${lock_wait_seconds}s 内未变 true"
  fi
  log "lock 双证齐备: wda/lock.json + wda/locked.json"

  say "lock: 请人工在设备上解锁（脚本不输入密码、不点坐标），最长 ${unlock_wait_seconds}s"
  log "manual unlock wait ${unlock_wait_seconds}s"
  if ! poll_until "$unlock_wait_seconds" wda_locked_is_false; then
    mark_step_pending lock "人工解锁等待超时（${unlock_wait_seconds}s），未伪造已解锁"
  fi
  log "unlock 确认: wda/locked.json value=false"
  end_step ok
}
# --------------------------------------------------------------- collect phase
copy_from_container() {
  local source="$1"
  local dest="$2"
  log "CMD: xcrun devicectl device copy from --device ${device_udid} --domain-type appDataContainer --domain-identifier ${bundle_id} --source ${source} --destination ${dest}"
  if xcrun devicectl device copy from \
      --device "$device_udid" \
      --domain-type appDataContainer \
      --domain-identifier "$bundle_id" \
      --source "$source" \
      --destination "$dest" >> "$CURRENT_LOG" 2>&1; then
    return 0
  fi
  return 1
}

extract_telemetry() {
  local run_file=""
  if ! run_file="$(python3 - "${container_dir}/runs" <<'PY'
import glob
import os
import sys
files = [p for p in glob.glob(os.path.join(sys.argv[1], "**", "*.json"), recursive=True) if os.path.isfile(p)]
files.sort(key=lambda path: os.path.getmtime(path))
print(files[-1] if files else "")
PY
)"; then
    return 1
  fi
  if [ -z "$run_file" ]; then
    return 1
  fi
  python3 - "$run_file" "${container_dir}/telemetry" "${state_dir}/authorization.json" <<'PY' >> "$CURRENT_LOG" 2>&1
import json
import os
import sys

run_path, telemetry_dir, auth_path = sys.argv[1], sys.argv[2], sys.argv[3]
with open(run_path, "r", encoding="utf-8") as handle:
    run = json.load(handle)
telemetry = run.get("telemetry") if isinstance(run, dict) else {}
if not isinstance(telemetry, dict):
    telemetry = {}
os.makedirs(telemetry_dir, exist_ok=True)
name = os.path.basename(run_path)
with open(os.path.join(telemetry_dir, name), "w", encoding="utf-8") as handle:
    json.dump(telemetry, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
status = (telemetry.get("authorizationStatus") or {}).get("name") or ""
accuracy = (telemetry.get("accuracyAuthorization") or {}).get("name") or ""
with open(auth_path, "w", encoding="utf-8") as handle:
    json.dump({"status": status, "accuracy": accuracy, "source": "run-json"}, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
print("telemetry from %s authorizationStatus=%r accuracyAuthorization=%r" % (name, status, accuracy))
PY
}

record_run_seconds() {
  local start_file="${state_dir}/timings/runStartEpoch"
  if [ ! -f "$start_file" ]; then
    return 0
  fi
  record_timing runSeconds "$(elapsed_seconds "$(cat "$start_file")" "$(now_epoch)")"
  return 0
}

enforce_authorization() {
  if [ "$(step_get tcc status)" != "ok" ]; then
    return 0
  fi
  local auth_line=""
  if ! auth_line="$(python3 - "${state_dir}/authorization.json" <<'PY'
import json
import sys
try:
    with open(sys.argv[1], "r", encoding="utf-8") as handle:
        data = json.load(handle)
except Exception:
    data = {}
print("%s|%s" % (data.get("status") or "", data.get("accuracy") or ""))
PY
)"; then
    mark_step_failed tcc "authorization 自报字段读取失败"
  fi
  local auth_status="${auth_line%%|*}"
  local auth_accuracy="${auth_line#*|}"
  case "$auth_status" in
    authorized*) ;;
    *) mark_step_failed tcc "App 自报 authorizationStatus='${auth_status}'（期望 authorized*，字段缺失也失败）" ;;
  esac
  case "$auth_accuracy" in
    fullAccuracy|reducedAccuracy) ;;
    *) mark_step_failed tcc "App 自报 accuracyAuthorization='${auth_accuracy}'（期望 fullAccuracy|reducedAccuracy）" ;;
  esac
  log "authorization 自报校验通过: status=${auth_status} accuracy=${auth_accuracy}"
  return 0
}

phase_collect() {
  begin_step collect
  ensure_preflight
  load_bundle_id
  rm -rf "${container_dir}/runs" "${container_dir}/exports" "${container_dir}/telemetry" "${container_dir}/diagnostics"
  mkdir -p "${container_dir}/runs" "${container_dir}/exports" "${container_dir}/telemetry" "${container_dir}/diagnostics"

  local missing=""
  if ! copy_from_container 'Documents/Runs' "${container_dir}/runs"; then
    missing="${missing} Documents/Runs"
  fi
  if ! copy_from_container 'Documents/Exports' "${container_dir}/exports"; then
    missing="${missing} Documents/Exports"
  fi
  if ! copy_from_container 'Library/Caches/active-run.jsonl' "${container_dir}/diagnostics/active-run.jsonl"; then
    missing="${missing} Library/Caches/active-run.jsonl"
  fi
  if [ -z "$missing" ]; then
    if ! dir_nonempty "${container_dir}/runs"; then
      missing="${missing} Documents/Runs(空)"
    fi
    if ! dir_nonempty "${container_dir}/exports"; then
      missing="${missing} Documents/Exports(空)"
    fi
    if [ ! -s "${container_dir}/diagnostics/active-run.jsonl" ]; then
      missing="${missing} Library/Caches/active-run.jsonl(空)"
    fi
  fi
  if [ -n "$missing" ]; then
    log "缺失:${missing}"
    fail_step "容器证据缺失:${missing}"
  fi
  if ! extract_telemetry; then
    fail_step "无法从 run JSON 抽取 telemetry（container/runs 无 JSON）"
  fi
  # 授权结论只认 App 自报字段；校验放在 END 之前，保证 collect 日志末行是自检后的 END。
  enforce_authorization
  record_run_seconds
  end_step ok
}

# -------------------------------------------------------------- evidence phase
phase_evidence() {
  begin_step evidence
  log "cleanup 本次启动的 xcodebuild / iproxy / WDA session"
  cleanup_processes
  cleanup_done=1
  end_step ok
  write_summary ok
  write_manifest
  summary_done=1
  printf 'evidence.root=%s\n' "${evidence_dir#"${repo_root}/"}"
  printf 'summary=%s\n' "${evidence_dir#"${repo_root}/"}/summary.json"
  printf 'manifest=%s\n' "${evidence_dir#"${repo_root}/"}/manifest-sha256.txt"
  local step_id
  for step_id in $PHASES; do
    printf 'step=%s status=%s log=logs/%s.log\n' "$step_id" "$(step_get "$step_id" status)" "$step_id"
  done
}

# ------------------------------------------------------------------- 主流程调度
run_real_phase() {
  local target="$1"
  case "$target" in
    preflight)
      phase_preflight
      ;;
    wda)
      ensure_preflight
      phase_wda
      ;;
    install)
      ensure_preflight
      phase_install
      ;;
    launch)
      ensure_preflight
      phase_launch
      ;;
    tcc)
      ensure_preflight
      phase_tcc
      ;;
    audio)
      ensure_preflight
      phase_audio
      ;;
    record)
      ensure_preflight
      phase_record
      ;;
    lock)
      ensure_preflight
      phase_lock
      ;;
    collect)
      ensure_preflight
      phase_collect
      ;;
    evidence)
      ensure_preflight
      phase_evidence
      ;;
    *)
      printf "device-run: 未知 phase '%s'\n" "$target" >&2
      exit 2
      ;;
  esac
}

if [ "$phase_request" = "all" ]; then
  for phase_name in $PHASES; do
    run_real_phase "$phase_name"
  done
else
  run_real_phase "$phase_request"
fi

if [ "$summary_done" -eq 0 ]; then
  # 单 phase 运行在此收尾：先清理本次启动的 xcodebuild/iproxy 与 WDA session，
  # 再写 summary/manifest，使 logs/cleanup.log 与清理后的产物一并进入证据。
  if [ "$cleanup_done" -eq 0 ]; then
    cleanup_processes
    cleanup_done=1
  fi
  write_summary ok
  write_manifest
  summary_done=1
  printf 'evidence.root=%s\n' "${evidence_dir#"${repo_root}/"}"
  printf 'summary=%s\n' "${evidence_dir#"${repo_root}/"}/summary.json"
  printf 'manifest=%s\n' "${evidence_dir#"${repo_root}/"}/manifest-sha256.txt"
fi

printf 'device-run OK phase=%s candidateKey=%s\n' "$phase_request" "$candidate_key"
