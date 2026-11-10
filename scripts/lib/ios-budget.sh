#!/usr/bin/env bash
# iOS 预算记账纯逻辑 + 进程级看门狗，供 scripts/test-ios.sh 与 scripts/tests/*.sh source。
# 本文件刻意不加 set -euo pipefail、不产生主流程副作用：计时取时与预算算术都必须可被
# 单测直接替换/调用（scripts/tests/test-ios-budget.sh 用伪造时钟保持确定性）。

# 墙钟取时的唯一入口（epoch 秒）。测试通过重定义本函数注入伪造时钟。
ios_now_epoch() {
  date +%s
}

# 非负整数秒；空值/非法值回落默认值（CI 注入的 env 不做弱校验）。
ios_seconds_or_default() {
  local raw="${1:-}"
  local fallback="$2"
  case "${raw}" in
    ""|*[!0-9]*) printf '%s' "${fallback}" ;;
    *) printf '%s' "${raw}" ;;
  esac
}

# 本次 attempt 预算：step 预算 − 重试余量。已是重试 attempt（step 剩余 ≤ 首次预算）时
# 取 step 剩余，不再扣第二次余量。
#   $1 step_budget  $2 retry_reserve  $3 attempt 起点的 step 剩余（空串 = 无 step 约束）
ios_attempt_budget() {
  local step_budget="$1"
  local retry_reserve="$2"
  local step_remaining="${3:-}"
  local attempt
  attempt=$((step_budget - retry_reserve))
  if [ "${attempt}" -lt 0 ]; then
    attempt=0
  fi
  case "${step_remaining}" in
    ""|*[!0-9]*) ;;
    *)
      if [ "${step_remaining}" -le "${attempt}" ]; then
        attempt="${step_remaining}"
      fi
      ;;
  esac
  printf '%s' "${attempt}"
}

# 腿预算：min(单腿上界, 本次 attempt 剩余秒数)。
ios_leg_budget() {
  local leg_cap="$1"
  local attempt_remaining="$2"
  if [ "${attempt_remaining}" -lt "${leg_cap}" ]; then
    printf '%s' "${attempt_remaining}"
  else
    printf '%s' "${leg_cap}"
  fi
}

# 预算是否不足：可用秒数 < 阈值时返回 0（不足），否则返回 1。
ios_budget_short() {
  local available="$1"
  local threshold="$2"
  [ "${available}" -lt "${threshold}" ]
}

# 承载层预算不足口径（124 路径专用；只用承载层措辞，不含产品断言失败措辞）。
ios_budget_message() {
  local scope="$1"
  local available="$2"
  local threshold="$3"
  local step_budget="$4"
  local retry_reserve="$5"
  printf 'test-ios: 承载层预算不足：%s 可用 %ss < 阈值 %ss（来源：step 预算 %ss − 重试余量 %ss，归口承载层预算）\n' \
    "${scope}" "${available}" "${threshold}" "${step_budget}" "${retry_reserve}" >&2
}

# 进程级硬超时看门狗（macOS bash 3.2 无 GNU timeout）：超时判定只看墙钟差额，
# sleep 仅作轮询粒度（IOS_WATCHDOG_POLL_SECONDS，默认 1s）；超时先 TERM 再 KILL，
# 打印超时阶段与已执行测试摘要后返回 124；正常退出时透传子进程退出码。
run_with_watchdog() {
  local timeout_seconds="$1"
  local out_log="$2"
  shift 2
  local command_pid=""
  local started_at=0
  local elapsed=0
  local wait_status=0
  local poll_seconds="${IOS_WATCHDOG_POLL_SECONDS:-1}"
  "$@" >"${out_log}" 2>&1 &
  command_pid=$!
  started_at="$(ios_now_epoch)"
  while kill -0 "${command_pid}" 2>/dev/null; do
    elapsed=$(( $(ios_now_epoch) - started_at ))
    if [ "${elapsed}" -ge "${timeout_seconds}" ]; then
      echo "test-ios: 阶段 xcodebuild-test 硬超时（${timeout_seconds}s），强制终止 PID ${command_pid}" >&2
      kill -TERM "${command_pid}" >/dev/null 2>&1 || true
      sleep 2
      kill -KILL "${command_pid}" >/dev/null 2>&1 || true
      wait "${command_pid}" >/dev/null 2>&1 || true
      echo "test-ios: runner bootstrap 挂起：xcodebuild test 在 ${timeout_seconds}s 硬超时前未完成（未进入产品断言）" >&2
      echo "test-ios: 承载层硬超时：墙钟已用 ${elapsed}s ≥ 腿预算 ${timeout_seconds}s，归口承载层预算/硬超时" >&2
      echo "test-ios: 超时前已执行的测试摘要：" >&2
      grep -E "Test Case .*(started|passed|failed)|Executed [0-9]+ tests" "${out_log}" 2>/dev/null | tail -n 40 >&2 || true
      cat "${out_log}" 2>/dev/null || true
      return 124
    fi
    sleep "${poll_seconds}"
  done
  wait "${command_pid}" || wait_status=$?
  return "${wait_status}"
}
