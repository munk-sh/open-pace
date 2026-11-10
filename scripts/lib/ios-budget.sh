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

# 日志里是否已出现失败用例（超时归口的唯一判定，纯函数、无输出）：
# 命中 `Test Case ... failed` 或 `Executed N tests, with M failures`（M ≥ 1）返回 0；
# `with 0 failures` 与空日志均返回 1（只能归口承载层，不能吞掉真失败）。
ios_log_has_failed_test_case() {
  local log="$1"
  if grep -Eq "Test Case .*failed" "${log}" 2>/dev/null; then
    return 0
  fi
  grep -Eq "Executed [0-9]+ tests?, with [1-9][0-9]* failures?" "${log}" 2>/dev/null
}

# 超时归口的最终文案（看门狗与 scripts/test-ios.sh 的 124 分支共用同一判定）：
# 有 failed 用例 → 产品用例失败；无 failed 用例 → 承载层预算/硬超时。
#   $1 范围（如「UI 腿」）  $2 日志路径  $3 已用秒数  $4 腿预算秒数  $5 预算来源说明
ios_timeout_classification_message() {
  local scope="$1"
  local log="$2"
  local elapsed="$3"
  local budget="$4"
  local source="${5:-}"
  if [ -n "${elapsed}" ]; then
    elapsed="，墙钟已用 ${elapsed}s"
  fi
  if [ -n "${source}" ]; then
    source="（来源：${source}；"
  else
    source="（"
  fi
  if ios_log_has_failed_test_case "${log}"; then
    printf 'test-ios: 产品用例失败：%s 在 %ss 腿预算内硬超时前已出现失败用例%s %s归口产品用例失败，不计为承载层预算）\n' \
      "${scope}" "${budget}" "${elapsed}" "${source}" >&2
  else
    printf 'test-ios: 承载层硬超时：%s 在 %ss 腿预算内未完成%s %s归口承载层预算，不计为产品用例）\n' \
      "${scope}" "${budget}" "${elapsed}" "${source}" >&2
  fi
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
      if ios_log_has_failed_test_case "${out_log}"; then
        # 同日志已出现 failed 用例：归口产品用例失败，不输出 infra_pattern 触发措辞（否则会误重试）。
        echo "test-ios: 产品用例失败：硬超时前已执行用例中已有 failed（摘要见下），归口产品用例失败，不计为承载层预算" >&2
        grep -E "Test Case .*failed|Executed [0-9]+ tests?, with [1-9][0-9]* failures?" "${out_log}" 2>/dev/null | tail -n 20 >&2 || true
        echo "test-ios: 硬超时：墙钟已用 ${elapsed}s ≥ 腿预算 ${timeout_seconds}s（硬超时归因于已出现的失败用例）" >&2
      else
        echo "test-ios: runner bootstrap 挂起：xcodebuild test 在 ${timeout_seconds}s 硬超时前未完成（未进入产品断言）" >&2
        echo "test-ios: 承载层硬超时：墙钟已用 ${elapsed}s ≥ 腿预算 ${timeout_seconds}s，归口承载层预算/硬超时" >&2
      fi
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
