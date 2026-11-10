#!/usr/bin/env bash
# iOS 预算记账确定性单测：墙钟看门狗 + attempt/腿预算算术。
# 不依赖模拟器 / Xcode / 网络；用伪造时钟保持确定性，单次运行 <10s。
set -euo pipefail

usage() {
  cat <<'EOF'
用法: scripts/tests/test-ios-budget.sh [--help]

对 scripts/lib/ios-budget.sh 做确定性单测（纯 bash，无需模拟器/Xcode/网络）：
  - run_with_watchdog 按墙钟差额判定超时（sleep 只作轮询粒度），透传子进程退出码；
  - attempt 预算 = step 预算 − 重试余量（默认 2700 − 900 = 1800，严格小于 step 超时）；
  - 重试 attempt 不重复扣余量，腿预算取 min(单腿上界, attempt 剩余)；
  - 承载层预算不足/硬超时口径点名「承载层预算」，不写成产品断言失败；
  - 脚本与库中不再出现以轮询计数参与预算判定的写法。

本脚本由 scripts/check-ios-scripts.sh（lint-ios-scripts 门）调用，也可独立运行。

选项:
  -h, --help   显示本帮助并退出 0
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
    echo "test-ios-budget: 未知参数 '$1'（使用 --help 查看用法）" >&2
    exit 2
    ;;
esac

if [ "$#" -gt 1 ]; then
  echo "test-ios-budget: 只接受一个参数（使用 --help 查看用法）" >&2
  exit 2
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../.." && pwd)"
cd "${repo_root}"

lib_path="scripts/lib/ios-budget.sh"
# shellcheck source=../lib/ios-budget.sh
. "${script_dir}/../lib/ios-budget.sh"

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
assert_eq() { # 名称 期望 实际
  if [ "$2" = "$3" ]; then
    pass "$1"
  else
    fail "$1" "期望 '$2'，实际 '$3'"
  fi
}

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/purepace-ios-budget.XXXXXX")"
cleanup() { rm -rf "${work_dir}"; }
trap cleanup EXIT

# -------------------------------------------- 伪造时钟（重定义 ios_now_epoch）
# 计时取时发生在命令替换的子 shell 里，故伪造时钟的状态落在文件上，跨子 shell 生效。
fake_mode="real"
fake_step=5
fake_clock_file="${work_dir}/fake-clock"
fake_reads_file="${work_dir}/fake-reads"
reset_fake_clock() { # 模式 起始值
  fake_mode="$1"
  printf '%s' "$2" > "${fake_clock_file}"
  : > "${fake_reads_file}"
}
fake_reads() { wc -l < "${fake_reads_file}" | tr -d ' '; }
ios_now_epoch() {
  printf 'r\n' >> "${fake_reads_file}"
  case "${fake_mode}" in
    fake)
      local next
      next=$(( $(cat "${fake_clock_file}") + fake_step ))
      printf '%s' "${next}" > "${fake_clock_file}"
      printf '%s' "${next}"
      ;;
    frozen)
      printf '%s' "$(cat "${fake_clock_file}")"
      ;;
    *)
      date +%s
      ;;
  esac
}

# ------------------------------- ac-watchdog-wall-clock-budget：墙钟差额驱动超时
reset_fake_clock fake 0
watch_log="${work_dir}/wall-clock.log"
watch_rc=0
run_with_watchdog 10 "${watch_log}" bash -c 'sleep 30' 2>"${work_dir}/wall-clock.err" || watch_rc=$?
assert_eq "ac-watchdog-wall-clock-budget (rc=124)" 124 "${watch_rc}"
# 起点 1 次 + 每轮 1 次取时：预算 10s / 每次前进 5s → ≤3 次轮询内必须判定超时。
wall_reads="$(fake_reads)"
if [ "${wall_reads}" -le 4 ]; then
  pass "ac-watchdog-wall-clock-budget (poll<=3 reads=${wall_reads})"
else
  fail "ac-watchdog-wall-clock-budget" "取时 ${wall_reads} 次（期望 ≤4：起点 + ≤3 次轮询）"
fi
wall_err="$(cat "${work_dir}/wall-clock.err" 2>/dev/null || true)"
if grep -Fq -- "阶段 xcodebuild-test 硬超时" <<<"${wall_err}" \
  && grep -Fq -- "runner bootstrap 挂起" <<<"${wall_err}"; then
  pass "ac-timeout-message-preserved (infra_pattern 原文)"
else
  fail "ac-timeout-message-preserved" "超时路径缺少 ios.yml infra_pattern 依赖的原文特征串"
fi
if grep -Fq -- "承载层硬超时" <<<"${wall_err}"; then
  pass "ac-timeout-message-preserved (承载层口径追加)"
else
  fail "ac-timeout-message-preserved" "超时路径未追加承载层预算/硬超时口径"
fi

# ---------------- ac-watchdog-not-iteration-counted：时钟冻结不按轮询次数判超时
reset_fake_clock frozen 1000
poll_rc=0
IOS_WATCHDOG_POLL_SECONDS=0.02 run_with_watchdog 5 "${work_dir}/frozen.log" bash -c 'sleep 0.3' \
  2>"${work_dir}/frozen.err" || poll_rc=$?
assert_eq "ac-watchdog-not-iteration-counted (rc=0)" 0 "${poll_rc}"
frozen_reads="$(fake_reads)"
if [ "${frozen_reads}" -gt 6 ]; then
  pass "ac-watchdog-not-iteration-counted (轮询 >5 次未误判超时，reads=${frozen_reads})"
else
  fail "ac-watchdog-not-iteration-counted" "轮询取时 ${frozen_reads} 次（期望 >6，样本不足以证伪轮询计数）"
fi

# --------------------------------------- ac-watchdog-passthrough-exit：退出码透传
fake_mode="real"
exit_rc=0
run_with_watchdog 5 "${work_dir}/passthrough.log" bash -c 'exit 65' 2>/dev/null || exit_rc=$?
assert_eq "ac-watchdog-passthrough-exit (65 原样返回)" 65 "${exit_rc}"

# ------------------------- ac-step-budget-strictly-less：attempt = step − 重试余量
step_budget="$(ios_seconds_or_default "" 2700)"
retry_reserve="$(ios_seconds_or_default "" 900)"
ui_min=300
attempt_default="$(ios_attempt_budget "${step_budget}" "${retry_reserve}" "")"
assert_eq "ac-step-budget-strictly-less (默认 attempt)" 1800 "${attempt_default}"
if [ "${attempt_default}" -lt "${step_budget}" ]; then
  pass "ac-step-budget-strictly-less (1800 < 2700)"
else
  fail "ac-step-budget-strictly-less" "attempt ${attempt_default}s 未严格小于 step ${step_budget}s"
fi

# -------------------------------- ac-retry-margin-determinable：余量可判定且够起跑
if [ "${retry_reserve}" -ge 900 ] && [ "${retry_reserve}" -ge "${ui_min}" ]; then
  pass "ac-retry-margin-determinable (reserve=${retry_reserve} ≥ 门槛 900 且 ≥ UI 最小 ${ui_min})"
else
  fail "ac-retry-margin-determinable" "reserve ${retry_reserve}s 不足门槛 900 或 UI 最小 ${ui_min}s"
fi
if [ "${attempt_default}" -ge "${retry_reserve}" ]; then
  pass "ac-retry-margin-determinable (attempt=${attempt_default} ≥ reserve=${retry_reserve})"
else
  fail "ac-retry-margin-determinable" "attempt ${attempt_default}s < reserve ${retry_reserve}s"
fi

# --------------------------- ac-retry-attempt-no-double-reserve：重试不扣第二次余量
retry_attempt="$(ios_attempt_budget 2700 900 900)"
assert_eq "ac-retry-attempt-no-double-reserve (step 剩余 900 → attempt 900)" 900 "${retry_attempt}"
retry_ui_leg="$(ios_leg_budget 600 "${retry_attempt}")"
assert_eq "ac-retry-attempt-no-double-reserve (UI 腿 600)" 600 "${retry_ui_leg}"
if [ "${retry_attempt}" -lt 2700 ]; then
  pass "ac-retry-attempt-no-double-reserve (900 < 2700)"
else
  fail "ac-retry-attempt-no-double-reserve" "重试 attempt ${retry_attempt}s 未严格小于 step 2700s"
fi

# ----------------------- ac-leg-budget-bounded-by-attempt：腿预算受 attempt 剩余约束
short_left=200
unit_leg="$(ios_leg_budget 600 "${short_left}")"
ui_leg="$(ios_leg_budget 600 "${short_left}")"
assert_eq "ac-leg-budget-bounded-by-attempt (单测腿 200)" 200 "${unit_leg}"
assert_eq "ac-leg-budget-bounded-by-attempt (UI 腿 200)" 200 "${ui_leg}"
if ios_budget_short "${ui_leg}" "${ui_min}"; then
  pass "ac-leg-budget-bounded-by-attempt (200 < ${ui_min} 判预算不足)"
else
  fail "ac-leg-budget-bounded-by-attempt" "UI 腿 ${ui_leg}s 未判为低于阈值 ${ui_min}s"
fi
if ios_budget_short "${ui_min}" "${ui_min}"; then
  fail "ac-leg-budget-bounded-by-attempt" "阈值等于可用值被误判为不足（边界恒假错误）"
else
  pass "ac-leg-budget-bounded-by-attempt (300 = 阈值 不判不足)"
fi

# ------------------------- ac-budget-exhausted-names-carrier：124 口径点名承载层预算
budget_msg="$(ios_budget_message "UI 腿" 200 300 2700 900 2>&1)"
if grep -Fq -- "承载层预算" <<<"${budget_msg}"; then
  pass "ac-budget-exhausted-names-carrier (含「承载层预算」)"
else
  fail "ac-budget-exhausted-names-carrier" "预算不足消息未点名承载层预算：${budget_msg}"
fi
if grep -Fq -- "断言失败" <<<"${budget_msg}"; then
  fail "ac-budget-exhausted-names-carrier" "预算不足消息混入产品断言失败措辞：${budget_msg}"
else
  pass "ac-budget-exhausted-names-carrier (不含「断言失败」)"
fi
if grep -Fq -- "step 预算" <<<"${budget_msg}" && grep -Fq -- "重试余量" <<<"${budget_msg}"; then
  pass "ac-budget-exhausted-names-carrier (含 step/重试余量来源)"
else
  fail "ac-budget-exhausted-names-carrier" "预算不足消息缺少 step/重试余量来源：${budget_msg}"
fi

# --------------------------------------- ac-env-overridable：两个 env 可覆盖且非法回落
override_step="$(ios_seconds_or_default "3600" 2700)"
override_reserve="$(ios_seconds_or_default "1200" 900)"
assert_eq "ac-env-overridable (step=3600/reserve=1200 → attempt 2400)" 2400 \
  "$(ios_attempt_budget "${override_step}" "${override_reserve}" "")"
assert_eq "ac-env-overridable (非法 step 回落 2700)" 2700 "$(ios_seconds_or_default "abc" 2700)"
assert_eq "ac-env-overridable (非法 reserve 回落 900)" 900 "$(ios_seconds_or_default "12x" 900)"
assert_eq "ac-env-overridable (空值回落默认)" 900 "$(ios_seconds_or_default "" 900)"

# ------------------ ac-watchdog-not-iteration-counted：库/脚本不再按轮询计数记账
if grep -Fq -- 'waited=$((waited' scripts/test-ios.sh "${lib_path}"; then
  fail "ac-watchdog-not-iteration-counted (无 waited 计数)" "scripts/test-ios.sh 或 ${lib_path} 仍以轮询计数记账"
else
  pass "ac-watchdog-not-iteration-counted (无 waited 计数)"
fi
if grep -Fq -- 'lib/ios-budget.sh' scripts/test-ios.sh; then
  pass "ac-tests-runnable-deterministic (test-ios.sh source 纯逻辑库)"
else
  fail "ac-tests-runnable-deterministic" "scripts/test-ios.sh 未 source ${lib_path}"
fi
if grep -Fq -- 'ios_attempt_budget' scripts/test-ios.sh \
  && grep -Fq -- 'PUREPACE_IOS_RETRY_RESERVE_SECONDS' scripts/test-ios.sh; then
  pass "ac-retry-margin-determinable (脚本使用 attempt 预算与新 env)"
else
  fail "ac-retry-margin-determinable" "scripts/test-ios.sh 未使用 ios_attempt_budget / PUREPACE_IOS_RETRY_RESERVE_SECONDS"
fi

printf '\n%d 项断言，%d 项失败\n' "${CHECKS}" "${FAILURES}"
if [ "${FAILURES}" -ne 0 ]; then
  exit 1
fi
printf 'ios budget tests OK\n'
