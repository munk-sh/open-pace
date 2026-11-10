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
fake_release_file="${work_dir}/fake-release"
# 第 N 次取时放行子进程（0 = 不放行）：把「读次数下界」变成测试侧确定性事实。
fake_release_after=0
reset_fake_clock() { # 模式 起始值 [第 N 次取时放行]
  fake_mode="$1"
  printf '%s' "$2" > "${fake_clock_file}"
  : > "${fake_reads_file}"
  rm -f "${fake_release_file}"
  fake_release_after="${3:-0}"
}
fake_reads() { wc -l < "${fake_reads_file}" | tr -d ' '; }
ios_now_epoch() {
  printf 'r\n' >> "${fake_reads_file}"
  if [ "${fake_release_after}" -gt 0 ] \
    && [ "$(fake_reads)" -ge "${fake_release_after}" ]; then
    : > "${fake_release_file}"
  fi
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

# ------------------------- ac-timeout-product-failure：同日志有 failed 用例 → 产品失败归口
failed_seed="${work_dir}/failed-case-seed.log"
empty_log="${work_dir}/empty.log"
: > "${empty_log}"
printf "Test Case '-[PurePaceUITests.RunFlowUITests testX]' started.\nTest Case '-[PurePaceUITests.RunFlowUITests testX]' failed (0.1 seconds).\nExecuted 1 test, with 1 failure (0 failures expected) in 0.2 (0.2) seconds\n" > "${failed_seed}"
if ios_log_has_failed_test_case "${failed_seed}"; then
  pass "ac-timeout-product-failure (判定：Test Case failed 命中)"
else
  fail "ac-timeout-product-failure" "ios_log_has_failed_test_case 未命中 Test Case failed 样例"
fi
if ios_log_has_failed_test_case "${empty_log}"; then
  fail "ac-timeout-product-failure" "空日志被误判为含 failed 用例"
else
  pass "ac-timeout-product-failure (判定：空日志不含 failed)"
fi
zero_failure_log="${work_dir}/zero-failure.log"
printf "Executed 3 tests, with 0 failures (0 unexpected) in 1.0 (1.0) seconds\n" > "${zero_failure_log}"
if ios_log_has_failed_test_case "${zero_failure_log}"; then
  fail "ac-timeout-product-failure" "「with 0 failures」被误判为失败用例"
else
  pass "ac-timeout-product-failure (判定：with 0 failures 不命中)"
fi
executed_failure_log="${work_dir}/executed-failure.log"
printf "Executed 2 tests, with 1 failure (0 unexpected) in 1.0 (1.0) seconds\n" > "${executed_failure_log}"
if ios_log_has_failed_test_case "${executed_failure_log}"; then
  pass "ac-timeout-product-failure (判定：Executed N tests, with 1 failure 命中)"
else
  fail "ac-timeout-product-failure" "ios_log_has_failed_test_case 未命中 Executed 失败样例"
fi
# 走真实 run_with_watchdog 超时分支（伪造时钟）：子进程把 failed 样例写进被看守日志后挂起。
failed_watch_log="${work_dir}/failed-watch.log"
reset_fake_clock fake 0
failed_watch_rc=0
run_with_watchdog 10 "${failed_watch_log}" \
  bash -c 'cat "$1" >> "$2"; sleep 30' _ "${failed_seed}" "${failed_watch_log}" \
  2>"${work_dir}/failed-watch.err" || failed_watch_rc=$?
assert_eq "ac-timeout-product-failure (rc=124)" 124 "${failed_watch_rc}"
failed_watch_err="$(cat "${work_dir}/failed-watch.err" 2>/dev/null || true)"
if grep -Fq -- "未进入产品断言" <<<"${failed_watch_err}"; then
  fail "ac-timeout-product-failure" "含 failed 用例时仍输出 infra 触发措辞「未进入产品断言」"
else
  pass "ac-timeout-product-failure (不含「未进入产品断言」)"
fi
if grep -Fq -- "产品用例失败" <<<"${failed_watch_err}" \
  && grep -Fq -- "testX" <<<"${failed_watch_err}" \
  && grep -Fq -- "with 1 failure" <<<"${failed_watch_err}"; then
  pass "ac-timeout-product-failure (点名 failed 用例与失败数)"
else
  fail "ac-timeout-product-failure" "产品失败归口未点名 failed 用例/失败数：${failed_watch_err}"
fi
if grep -Fq -- "阶段 xcodebuild-test 硬超时" <<<"${failed_watch_err}" \
  && grep -Fq -- "超时前已执行的测试摘要" <<<"${failed_watch_err}"; then
  pass "ac-timeout-product-failure (保留硬超时与摘要行)"
else
  fail "ac-timeout-product-failure" "产品失败归口缺少硬超时/摘要行：${failed_watch_err}"
fi

# ------------------------- ac-classification-reused-by-caller：124 文案复用同一分类
cls_infra="$(ios_timeout_classification_message "UI 腿" "${empty_log}" 601 600 "attempt 预算 1800s" 2>&1)"
cls_product="$(ios_timeout_classification_message "UI 腿" "${failed_seed}" 601 600 "attempt 预算 1800s" 2>&1)"
if grep -Fq -- "承载层硬超时" <<<"${cls_infra}" && grep -Fq -- "归口承载层预算" <<<"${cls_infra}"; then
  pass "ac-classification-reused-by-caller (无 failed → 承载层预算)"
else
  fail "ac-classification-reused-by-caller" "无 failed 的 124 文案未归口承载层预算：${cls_infra}"
fi
if grep -Fq -- "产品用例失败" <<<"${cls_product}" && ! grep -Fq -- "归口承载层预算" <<<"${cls_product}"; then
  pass "ac-classification-reused-by-caller (有 failed → 产品用例失败)"
else
  fail "ac-classification-reused-by-caller" "有 failed 的 124 文案未归口产品用例失败：${cls_product}"
fi
caller_reuse_count="$(grep -Fc -- "ios_timeout_classification_message" scripts/test-ios.sh 2>/dev/null || true)"
[ -n "${caller_reuse_count}" ] || caller_reuse_count=0
if [ "${caller_reuse_count}" -ge 2 ]; then
  pass "ac-classification-reused-by-caller (test-ios.sh 两处 124 分支复用，count=${caller_reuse_count})"
else
  fail "ac-classification-reused-by-caller" "scripts/test-ios.sh 复用 ios_timeout_classification_message ${caller_reuse_count} 次（期望 ≥2）"
fi

# ---------------- ac-watchdog-not-iteration-counted：时钟冻结不按轮询次数判超时
# 读次数下界由测试侧确定性放行驱动：冻结时钟在第 N 次取时时创建 release 文件，
# 子进程见到后正常退出；run_with_watchdog 每轮先取时再 sleep，故 reads ≥ N 必然成立，
# 与子进程墙钟时长/机器速度无关（N 固定且 > 原「>5 次轮询」意图）。
frozen_release_after=8
reset_fake_clock frozen 1000 "${frozen_release_after}"
poll_rc=0
IOS_WATCHDOG_POLL_SECONDS=0.02 run_with_watchdog 5 "${work_dir}/frozen.log" \
  bash -c 'while [ ! -f "$1" ]; do sleep 0.01; done' _ "${fake_release_file}" \
  2>"${work_dir}/frozen.err" || poll_rc=$?
assert_eq "ac-watchdog-not-iteration-counted (rc=0)" 0 "${poll_rc}"
frozen_reads="$(fake_reads)"
if [ "${frozen_reads}" -ge "${frozen_release_after}" ]; then
  pass "ac-watchdog-not-iteration-counted (确定性放行 reads=${frozen_reads} ≥ ${frozen_release_after}，未误判超时)"
else
  fail "ac-watchdog-not-iteration-counted" "取时 ${frozen_reads} 次（期望 ≥${frozen_release_after}：第 N 次取时确定性放行的下界）"
fi

# --------------------------------------- ac-watchdog-passthrough-exit：退出码透传
fake_mode="real"
fake_release_after=0
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
