#!/usr/bin/env bash
# iOS 脚本静态/契约断言（.munk/code-gates.json 的 lint-ios-scripts 门真实执行体）。
# 校验 build-ios.sh / test-ios.sh / check-ios-scripts.sh / version.sh / verify-ios-ui-e2e.sh /
# verify-ios-sim-runtime.sh 的
# bash 严格模式、参数契约、xcodebuild 分支字面量、降级分支、无写死版本、无伪造成功行；任一条失败即非零退出。
set -euo pipefail

usage() {
  cat <<'EOF'
用法: scripts/check-ios-scripts.sh [--help]

对 iOS 构建/测试/版本/模拟器脚本做结构与契约断言并打印逐条结果：
  - 六个脚本 bash -n 通过、shebang 为 #!/usr/bin/env bash、正文含 set -euo pipefail
  - build-ios.sh / test-ios.sh / check-ios-scripts.sh / verify-ios-ui-e2e.sh /
    verify-ios-sim-runtime.sh 的 --help
    退出 0 且含「用法」，未知参数退出 2
  - build-ios.sh 含 xcodebuild build、-scheme、iPhone 16 destination（可带 OS/UDID）与 swift build 降级分支
  - test-ios.sh 含 xcodebuild test、-scheme、iPhone 16 destination（可带 OS/UDID）与 swift test 降级分支
  - test-ios.sh 先 bootstatus、再安装 → simctl privacy grant location → 先单测后 UI 四段 xcodebuild test，
    单测/各 UI 段日志分文件、各带测试预算参数，主脚本不含 simctl 定位注入，且带 bash 看门狗硬超时（≤600s）
  - ios/PurePaceUITests 下所有 XCTestCase 套件都必须进入 ui_call 的 -only-testing 枚举；
    本机-only 套件须写入 scripts/ios-ui-local-only-suites.txt 且带非空理由（含正负反例自检）
  - verify-ios-sim-runtime.sh 仍以 1 Hz simctl location set 真实驱动 CoreLocation，脚本契约仍在
  - verify-ios-ui-e2e.sh 默认只写 .build/，--refresh-evidence 才覆盖仓库证据目录
  - .munk/code-gates.json 保持 22 门：本地只留快而确定腿（重 UI 门不作本地阻断），
    test-ios 本地门固定为 --unit-only，全量单测+UI 权威落点为 .github/workflows/ios.yml
  - 分支判定基于 ios/PurePace.xcodeproj 存在性；工程缺失时由 ios/project.yml + xcodegen 生成，
    仍不可用才走降级分支输出 blocked: 且不输出伪造成功行
  - version.sh 无参输出等于根 VERSION，--tools 输出可核对且逐字节幂等
  - version.sh 不调用 gradlew，Gradle 版本离线取自 android/gradle/wrapper/gradle-wrapper.properties
  - 脚本与 README.md 不出现根 VERSION 字面值，不出现不实验收措辞

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
    echo "check-ios-scripts: 未知参数 '$1'（使用 --help 查看用法）" >&2
    exit 2
    ;;
esac

if [ "$#" -gt 1 ]; then
  echo "check-ios-scripts: 只接受一个参数（使用 --help 查看用法）" >&2
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

targets="build-ios.sh test-ios.sh check-ios-scripts.sh version.sh verify-ios-ui-e2e.sh verify-ios-sim-runtime.sh"
strict_targets="build-ios.sh test-ios.sh check-ios-scripts.sh verify-ios-ui-e2e.sh verify-ios-sim-runtime.sh"

# ------------------------------------------------- 脚本存在、语法与严格模式
problems=""
for name in $targets; do
  [ -f "scripts/$name" ] || problems="$problems 缺少 scripts/$name;"
done
if [ -z "$problems" ]; then
  pass "ac-ios-scripts-present"
else
  fail "ac-ios-scripts-present" "$problems"
fi

problems=""
for name in $targets; do
  [ -f "scripts/$name" ] || continue
  bash -n "scripts/$name" >/dev/null 2>&1 || problems="$problems scripts/$name bash -n 失败;"
done
if [ -z "$problems" ]; then
  pass "ac-ios-scripts-bash-strict (bash -n)"
else
  fail "ac-ios-scripts-bash-strict" "$problems"
fi

problems=""
for name in $strict_targets; do
  [ -f "scripts/$name" ] || continue
  first_line="$(sed -n '1p' "scripts/$name")"
  [ "$first_line" = "#!/usr/bin/env bash" ] || problems="$problems scripts/$name shebang 为 '$first_line';"
  grep -Fq -- 'set -euo pipefail' "scripts/$name" || problems="$problems scripts/$name 缺少 set -euo pipefail;"
  grep -Fq -- 'BASH_SOURCE' "scripts/$name" || problems="$problems scripts/$name 未以 BASH_SOURCE 推导仓库根;"
done
if [ -z "$problems" ]; then
  pass "ac-ios-scripts-bash-strict (shebang/set/BASH_SOURCE)"
else
  fail "ac-ios-scripts-bash-strict" "$problems"
fi

# --------------------------------------- --help 退出 0 且含「用法」，未知参数退出 2
problems=""
for name in $strict_targets; do
  [ -f "scripts/$name" ] || continue
  help_out="$(bash "scripts/$name" --help 2>&1)" && help_rc=0 || help_rc=$?
  if [ "$help_rc" -ne 0 ]; then
    problems="$problems scripts/$name --help 退出 $help_rc;"
  elif ! grep -Fq -- "用法" <<<"$help_out"; then
    problems="$problems scripts/$name --help 输出缺少「用法」;"
  fi
  bash "scripts/$name" --definitely-invalid >/dev/null 2>&1 && bad_rc=0 || bad_rc=$?
  [ "$bad_rc" -eq 2 ] || problems="$problems scripts/$name 未知参数退出 ${bad_rc}（期望 2）;"
done
if [ -z "$problems" ]; then
  pass "ac-ios-scripts-help"
else
  fail "ac-ios-scripts-help" "$problems"
fi


# --------------------------------------------------- build-ios.sh 契约字面量
problems=""
if [ ! -f scripts/build-ios.sh ]; then
  problems="$problems 缺少 scripts/build-ios.sh;"
else
  for needle in \
    "xcodebuild build" \
    "-scheme" \
    "ios/PurePace.xcodeproj" \
    "xcodegen generate" \
    "swift build --package-path ios/Core" \
    "blocked:"; do
    grep -Fq -- "$needle" scripts/build-ios.sh || problems="$problems 缺少 '$needle';"
  done
  # destination 必须钉住 iPhone 16；允许显式 OS 版本或 UDID 以消除 latest 歧义。
  grep -Eq -- "-destination ['\"]platform=iOS Simulator,name=iPhone 16(,OS=[0-9.]+|,id=[0-9A-Fa-f-]+)?['\"]" scripts/build-ios.sh \
    || problems="$problems 缺少 iPhone 16 destination;"
fi
if [ -z "$problems" ]; then
  pass "ac-build-ios-xcodebuild-path"
else
  fail "ac-build-ios-xcodebuild-path" "$problems"
fi

# ---------------------------------------------------- test-ios.sh 契约字面量
problems=""
if [ ! -f scripts/test-ios.sh ]; then
  problems="$problems 缺少 scripts/test-ios.sh;"
else
  for needle in \
    "xcodebuild test" \
    "-scheme" \
    "ios/PurePace.xcodeproj" \
    "xcodegen generate" \
    "swift test --package-path ios/Core" \
    "blocked:"; do
    grep -Fq -- "$needle" scripts/test-ios.sh || problems="$problems 缺少 '$needle';"
  done
  # destination 必须钉住 iPhone 16；允许显式 OS 版本或 UDID 以消除 latest 歧义。
  grep -Eq -- "-destination ['\"]platform=iOS Simulator,name=iPhone 16(,OS=[0-9.]+|,id=[0-9A-Fa-f-]+)?['\"]" scripts/test-ios.sh \
    || problems="$problems 缺少 iPhone 16 destination;"
fi
if [ -z "$problems" ]; then
  pass "ac-test-ios-xcodebuild-path"
else
  fail "ac-test-ios-xcodebuild-path" "$problems"
fi

# ------------- test-ios.sh 模拟器前置状态契约：bootstatus → 安装 → 授权 → 单测/UI 拆分执行 + 硬超时
test_ios_preparation_problems() {
  local file="$1" out="" install_line="" privacy_line="" unit_line="" ui_line=""
  if [ ! -f "$file" ]; then
    printf '缺少 %s;' "$file"
    return 0
  fi
  for needle in \
    "simctl bootstatus" \
    "simctl privacy" \
    "grant location" \
    "simctl install" \
    "simctl launch" \
    "simctl terminate" \
    "run_with_watchdog" \
    "IOS_XCODEBUILD_TIMEOUT" \
    "-only-testing:PurePaceTests" \
    "-only-testing:PurePaceUITests" \
    "-test-timeouts-enabled YES" \
    "-default-test-execution-time-allowance" \
    "-maximum-test-execution-time-allowance"; do
    grep -Fq -- "$needle" "$file" || out="$out 缺少 '$needle';"
  done
  # 安装 → 授权 → 首次 xcodebuild test 的顺序锚点。
  install_line="$(grep -nF -- 'xcrun simctl install' "$file" | head -n 1 | cut -d: -f1 || true)"
  privacy_line="$(grep -nF -- 'xcrun simctl privacy' "$file" | head -n 1 | cut -d: -f1 || true)"
  unit_line="$(grep -nE -- '^[[:space:]]*-only-testing:PurePaceTests[[:space:]]*\\?[[:space:]]*$' "$file" | head -n 1 | cut -d: -f1 || true)"
  # UI 腿由 ui_call 分段驱动（每段一次 xcodebuild，每次 ≤600s），顺序锚点取首个分段调用。
  ui_line="$(grep -nE -- '^[[:space:]]*ui_call "' "$file" | head -n 1 | cut -d: -f1 || true)"
  if [ -z "$install_line" ] || [ -z "$privacy_line" ] || [ -z "$unit_line" ] || [ -z "$ui_line" ]; then
    out="$out 缺少 install/privacy/-only-testing:PurePaceTests/-only-testing:PurePaceUITests 顺序锚点;"
  elif [ "$install_line" -ge "$privacy_line" ]; then
    out="$out simctl privacy 必须排在 simctl install 之后（install=${install_line} privacy=${privacy_line}）;"
  elif [ "$privacy_line" -ge "$unit_line" ]; then
    out="$out simctl privacy 必须排在单测调用之前（privacy=${privacy_line} unit=${unit_line}）;"
  elif [ "$unit_line" -ge "$ui_line" ]; then
    out="$out 单测调用必须先于 UI 调用（unit=${unit_line} ui=${ui_line}）;"
  fi
  # UI 测试不得再依赖 simctl 的隐藏式定位投递：脚本正文出现任何 simctl location 都判失败。
  if grep -Fq -- "simctl location" "$file"; then
    out="$out test-ios.sh 出现 simctl location（UI 测试应走 -uiTestLocation 确定性测试源）;"
  fi
  # 两次 xcodebuild test 调用都必须带三个测试执行预算参数。
  local budget_count=""
  for needle in \
    "-test-timeouts-enabled YES" \
    "-default-test-execution-time-allowance 300" \
    "-maximum-test-execution-time-allowance 540"; do
    budget_count="$(grep -Fc -- "$needle" "$file" 2>/dev/null || true)"
    [ -n "$budget_count" ] || budget_count=0
    [ "$budget_count" -ge 2 ] || out="$out '$needle' 出现 ${budget_count} 次（单测/UI 各需 1 次）;"
  done
  # 单测/UI 调用的日志必须分文件；UI 腿按 ≤600s 分段（见 AGENTS「测试稳定性约定」）。
  for needle in "xcodebuild-unit.log" "xcodebuild-ui.log" "xcodebuild-ui-2.log" \
    "xcodebuild-ui-3.log" "xcodebuild-ui-4.log"; do
    grep -Fq -- "$needle" "$file" || out="$out 缺少分文件日志 '$needle';"
  done
  # 分段执行契约（拆分≠放宽）：UI 腿必须由同一组预算参数模板驱动四次调用，
  # 且分段依据被显式记录；每次调用仍受 IOS_XCODEBUILD_TIMEOUT(≤600s) 上界。
  local ui_call_count=0
  ui_call_count="$(grep -cE '^[[:space:]]*ui_call "' "$file" 2>/dev/null || true)"
  [ -n "$ui_call_count" ] || ui_call_count=0
  [ "$ui_call_count" -eq 4 ] || out="$out ui_call 分段调用为 ${ui_call_count} 次（UI 腿需 4 段、每次 ≤600s）;"
  grep -Fq -- "拆分≠放宽" "$file" || out="$out 缺少「拆分≠放宽」分段依据说明;"
  # 固定顺序 runflow → evidence → screenshot-light → screenshot-dark（出现次序即执行次序）。
  local runflow_line="" evidence_line="" light_call_line="" dark_call_line="" dark_appearance_line="" restore_light_line=""
  runflow_line="$(grep -nE '^[[:space:]]*ui_call "runflow"' "$file" | head -n 1 | cut -d: -f1 || true)"
  evidence_line="$(grep -nE '^[[:space:]]*ui_call "evidence"' "$file" | head -n 1 | cut -d: -f1 || true)"
  light_call_line="$(grep -nE '^[[:space:]]*ui_call "screenshot-light"' "$file" | head -n 1 | cut -d: -f1 || true)"
  dark_call_line="$(grep -nE '^[[:space:]]*ui_call "screenshot-dark"' "$file" | head -n 1 | cut -d: -f1 || true)"
  if [ -z "$runflow_line" ] || [ -z "$evidence_line" ] || [ -z "$light_call_line" ] || [ -z "$dark_call_line" ]; then
    out="$out ui_call 缺少 runflow/evidence/screenshot-light/screenshot-dark 分段;"
  elif [ "$runflow_line" -ge "$evidence_line" ] || [ "$evidence_line" -ge "$light_call_line" ] \
    || [ "$light_call_line" -ge "$dark_call_line" ]; then
    out="$out ui_call 分段顺序必须为 runflow → evidence → screenshot-light → screenshot-dark;"
  fi
  # 深色段：调用前 appearance dark，调用后（成功或失败）appearance light。
  dark_appearance_line="$(grep -nF -- 'appearance dark' "$file" | head -n 1 | cut -d: -f1 || true)"
  restore_light_line="$(grep -nF -- 'appearance light' "$file" | tail -n 1 | cut -d: -f1 || true)"
  if [ -z "$dark_appearance_line" ] || [ -z "$dark_call_line" ] || [ "$dark_appearance_line" -ge "$dark_call_line" ]; then
    out="$out 深色段前缺少 simctl appearance dark;"
  fi
  if [ -z "$restore_light_line" ] || [ -z "$dark_call_line" ] || [ "$restore_light_line" -le "$dark_call_line" ]; then
    out="$out 深色段结束后缺少 simctl appearance light 恢复;"
  fi
  # 失败即停：非首段（evidence / screenshot-light / screenshot-dark）均须由 ui_status==0 门控。
  local guard_count=0 call_line="" guard_window="" window_start=""
  guard_count="$(grep -cE '^[[:space:]]*if \[ "\$ui_status" -eq 0 \]' "$file" 2>/dev/null || true)"
  [ -n "$guard_count" ] || guard_count=0
  [ "$guard_count" -ge 3 ] || out="$out ui_status==0 失败即停门控仅 ${guard_count} 处（非首段各需 1 处）;"
  for call_line in "$evidence_line" "$light_call_line" "$dark_call_line"; do
    [ -n "$call_line" ] || continue
    window_start=$((call_line - 6))
    [ "$window_start" -ge 1 ] || window_start=1
    guard_window="$(sed -n "${window_start},$((call_line - 1))p" "$file")"
    grep -Fq -- 'if [ "$ui_status" -eq 0 ]' <<< "$guard_window" \
      || out="$out ui_call 第 ${call_line} 行前缺少 ui_status==0 失败即停门控;"
  done
  # macOS runner 没有 GNU timeout：硬超时必须是 bash 看门狗（kill），不能用 timeout 命令。
  if grep -Eq '(^|[^[:alnum:]_])timeout[[:space:]]+[0-9]' "$file"; then
    out="$out test-ios.sh 依赖 GNU timeout（macOS runner 无该命令），应使用 bash 看门狗 + kill;"
  fi
  # 单次 attempt 聚合硬上限 ≤600s。
  local timeout_default=""
  timeout_default="$(sed -n 's/.*IOS_XCODEBUILD_TIMEOUT:-\([0-9][0-9]*\).*/\1/p' "$file" | head -n 1 || true)"
  if [ -z "$timeout_default" ]; then
    out="$out 未找到 IOS_XCODEBUILD_TIMEOUT 默认值;"
  elif [ "$timeout_default" -gt 600 ]; then
    out="$out 看门狗默认超时 ${timeout_default}s 超过 600s（AX 静默等待未被压住）;"
  fi
  printf '%s' "$out"
}

problems="$(test_ios_preparation_problems scripts/test-ios.sh)"
if [ -z "$problems" ]; then
  pass "ac-test-ios-simulator-preparation"
else
  fail "ac-test-ios-simulator-preparation" "$problems"
fi

# 反例自检：把授权命令挪到文件最前（先于安装），顺序断言必须报错。
prep_sandbox="$(mktemp -d "${TMPDIR:-/tmp}/purepace-check-ios-prep.XXXXXX")"
{
  printf '%s\n' '# xcrun simctl privacy simctl privacy grant location'
  cat scripts/test-ios.sh
} > "$prep_sandbox/test-ios.sh"
if [ -n "$(test_ios_preparation_problems "$prep_sandbox/test-ios.sh")" ]; then
  pass "ac-test-ios-simulator-preparation (self-test)"
else
  fail "ac-test-ios-simulator-preparation" "授权先于安装的违规样本未被识别"
fi
rm -rf "$prep_sandbox"

# 反例自检：UI 路径残留 simctl 定位注入（隐藏式投递）必须被识别。
start_sandbox="$(mktemp -d "${TMPDIR:-/tmp}/purepace-check-ios-start.XXXXXX")"
cp scripts/test-ios.sh "$start_sandbox/test-ios.sh"
printf '%s\n' 'xcrun simctl location "$sim_udid" set 37.3349,-122.0090' >> "$start_sandbox/test-ios.sh"
if [ -n "$(test_ios_preparation_problems "$start_sandbox/test-ios.sh")" ]; then
  pass "ac-test-ios-no-simctl-location (self-test)"
else
  fail "ac-test-ios-no-simctl-location" "残留 simctl 定位注入的违规样本未被识别"
fi
rm -rf "$start_sandbox"

# 反例自检：交换单测/UI 调用顺序必须被识别。
order_sandbox="$(mktemp -d "${TMPDIR:-/tmp}/purepace-check-ios-order.XXXXXX")"
python3 - "$order_sandbox/test-ios.sh" <<'PY'
import sys
src = open("scripts/test-ios.sh", encoding="utf-8").read()
unit = "    -only-testing:PurePaceTests \\\n"
ui = '  ui_call "runflow" "$ui_log" "PurePaceUITests/RunFlowUITests"'
swapped = src.replace(unit, "@@UNIT@@")
swapped = swapped.replace(ui, unit.replace("    ", "  "))
swapped = swapped.replace("@@UNIT@@", ui)
open(sys.argv[1], "w", encoding="utf-8").write(swapped)
PY
if [ -n "$(test_ios_preparation_problems "$order_sandbox/test-ios.sh")" ]; then
  pass "ac-test-ios-unit-before-ui (self-test)"
else
  fail "ac-test-ios-unit-before-ui" "单测/UI 顺序颠倒的违规样本未被识别"
fi
rm -rf "$order_sandbox"

# 反例自检：删掉 UI 调用的测试预算参数必须被识别。
budget_sandbox="$(mktemp -d "${TMPDIR:-/tmp}/purepace-check-ios-budget.XXXXXX")"
python3 - "$budget_sandbox/test-ios.sh" <<'PY'
import sys
src = open("scripts/test-ios.sh", encoding="utf-8").read()
# 只删 UI 调用块里的一处 -test-timeouts-enabled，保留单测块那一处。
idx = src.rindex("-test-timeouts-enabled YES")
open(sys.argv[1], "w", encoding="utf-8").write(src[:idx] + src[idx + len("-test-timeouts-enabled YES"):])
PY
if [ -n "$(test_ios_preparation_problems "$budget_sandbox/test-ios.sh")" ]; then
  pass "ac-test-ios-budget-params (self-test)"
else
  fail "ac-test-ios-budget-params" "缺少 UI 测试预算参数的违规样本未被识别"
fi
rm -rf "$budget_sandbox"

# 反例自检：看门狗默认超时 >600s 必须被识别。
timeout_sandbox="$(mktemp -d "${TMPDIR:-/tmp}/purepace-check-ios-timeout.XXXXXX")"
sed 's/IOS_XCODEBUILD_TIMEOUT:-600/IOS_XCODEBUILD_TIMEOUT:-1800/' scripts/test-ios.sh > "$timeout_sandbox/test-ios.sh"
if [ -n "$(test_ios_preparation_problems "$timeout_sandbox/test-ios.sh")" ]; then
  pass "ac-test-ios-watchdog-budget (self-test)"
else
  fail "ac-test-ios-watchdog-budget" "看门狗 1800s 的违规样本未被识别"
fi
rm -rf "$timeout_sandbox"

# ------------------- 预算记账/墙钟看门狗确定性单测随 lint-ios-scripts 门执行（无模拟器）
budget_test_out="$(bash scripts/tests/test-ios-budget.sh 2>&1)" && budget_test_rc=0 || budget_test_rc=$?
if [ "$budget_test_rc" -eq 0 ]; then
  pass "ac-ios-budget-unit-tests"
else
  fail "ac-ios-budget-unit-tests" "$(printf '%s' "$budget_test_out" | tr '\n' ' ')"
fi

# 反例自检：沙箱里把墙钟判定改回轮询计数，预算单测必须报错。
budget_selftest_dir="$(mktemp -d "${TMPDIR:-/tmp}/purepace-check-ios-budget-unit.XXXXXX")"
mkdir -p "$budget_selftest_dir/scripts/lib" "$budget_selftest_dir/scripts/tests"
cp scripts/test-ios.sh "$budget_selftest_dir/scripts/test-ios.sh"
cp scripts/lib/ios-budget.sh "$budget_selftest_dir/scripts/lib/ios-budget.sh"
cp scripts/tests/test-ios-budget.sh "$budget_selftest_dir/scripts/tests/test-ios-budget.sh"
printf '%s\n' '    waited=$((waited + 1))' >> "$budget_selftest_dir/scripts/test-ios.sh"
if ( cd "$budget_selftest_dir" && bash scripts/tests/test-ios-budget.sh >/dev/null 2>&1 ); then
  fail "ac-ios-budget-unit-tests (self-test)" "注入轮询计数记账的违规样本未被识别"
else
  pass "ac-ios-budget-unit-tests (self-test)"
fi
rm -rf "$budget_selftest_dir"

# ------------- UI 套件全覆盖守卫：ios/PurePaceUITests 下所有 XCTestCase 套件必须进入 ui_call 枚举，
# 本机-only 套件只能显式进 scripts/ios-ui-local-only-suites.txt 且每条带非空理由。
ui_allowlist_entry_problems() {
  local file="$1" out="" line="" trimmed="" suite="" reason="" next_line="" lineno=0
  [ -f "$file" ] || { printf '%s' "$out"; return 0; }
  while IFS= read -r line || [ -n "$line" ]; do
    lineno=$((lineno + 1))
    trimmed="$(printf '%s' "$line" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
    case "$trimmed" in
      ""|"#"*) continue ;;
    esac
    if [[ "$trimmed" == *"|"* ]]; then
      suite="${trimmed%%|*}"
      reason="${trimmed#*|}"
    elif [[ "$trimmed" == *"#"* ]]; then
      suite="${trimmed%%#*}"
      reason="${trimmed#*#}"
    else
      suite="$trimmed"
      reason=""
    fi
    suite="$(printf '%s' "$suite" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
    reason="$(printf '%s' "$reason" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
    if ! printf '%s' "$suite" | grep -Eq '^[A-Za-z_][A-Za-z0-9_]*$'; then
      out="$out allowlist 第 ${lineno} 行缺少有效套件名;"
      continue
    fi
    if [ -z "$reason" ]; then
      # 理由也可紧随写在同一套件名的下一行（非空、非注释）。
      next_line="$(sed -n "$((lineno + 1))p" "$file" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
      case "$next_line" in
        ""|"#"*) : ;;
        *) reason="$next_line" ;;
      esac
    fi
    [ -n "$reason" ] || out="$out allowlist 第 ${lineno} 行套件 ${suite} 缺少非空理由;"
  done < "$file"
  printf '%s' "$out"
}

ui_allowlisted_suite() {
  local file="$1" wanted="$2" line="" trimmed="" suite=""
  [ -f "$file" ] || return 1
  while IFS= read -r line || [ -n "$line" ]; do
    trimmed="$(printf '%s' "$line" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
    case "$trimmed" in
      ""|"#"*) continue ;;
    esac
    suite="${trimmed%%|*}"
    suite="${suite%%#*}"
    suite="$(printf '%s' "$suite" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
    [ "$suite" = "$wanted" ] && return 0
  done < "$file"
  return 1
}

ui_suite_coverage_problems() {
  local root="$1" out="" ui_file="$1/scripts/test-ios.sh" allowlist="$1/scripts/ios-ui-local-only-suites.txt"
  local suites="" suite="" targets=""
  if [ ! -f "$ui_file" ]; then
    printf '缺少 %s;' "$ui_file"
    return 0
  fi
  out="$(ui_allowlist_entry_problems "$allowlist")"
  # 只认 ui_call 的引号目标参数，避免用法说明里的同名字样掩盖真实漏枚举。
  targets="$(grep -hE '"PurePaceUITests/[A-Za-z_][A-Za-z0-9_]*' "$ui_file" || true)"
  suites="$(grep -hoE 'class[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]*:[[:space:]]*XCTestCase' \
    "$root"/ios/PurePaceUITests/*.swift 2>/dev/null \
    | sed -E 's/class[[:space:]]+([A-Za-z_][A-Za-z0-9_]*).*/\1/' | sort -u || true)"
  if [ -z "$suites" ]; then
    printf '%s未枚举到 ios/PurePaceUITests 下的 XCTestCase 套件;' "$out"
    return 0
  fi
  for suite in $suites; do
    if printf '%s\n' "$targets" | grep -Fq -- "PurePaceUITests/${suite}"; then
      continue
    fi
    if ui_allowlisted_suite "$allowlist" "$suite"; then
      continue
    fi
    out="$out 套件 ${suite} 未进入 ui_call 的 -only-testing 目标（本机-only 需写入 scripts/ios-ui-local-only-suites.txt 并带非空理由）;"
  done
  printf '%s' "$out"
}

problems="$(ui_suite_coverage_problems .)"
if [ -z "$problems" ]; then
  pass "ac-ui-suite-coverage-guard"
else
  fail "ac-ui-suite-coverage-guard" "$problems"
fi

ui_coverage_sandbox() {
  local sandbox=""
  sandbox="$(mktemp -d "${TMPDIR:-/tmp}/purepace-check-ios-uicov.XXXXXX")"
  mkdir -p "$sandbox/scripts" "$sandbox/ios/PurePaceUITests"
  cp scripts/test-ios.sh "$sandbox/scripts/"
  if [ -f scripts/ios-ui-local-only-suites.txt ]; then
    cp scripts/ios-ui-local-only-suites.txt "$sandbox/scripts/"
  fi
  cp ios/PurePaceUITests/*.swift "$sandbox/ios/PurePaceUITests/"
  printf '%s' "$sandbox"
}

# 正向对照：未改动沙箱必须判绿（否则守卫是恒真/恒假断言）。
coverage_sandbox="$(ui_coverage_sandbox)"
if [ -z "$(ui_suite_coverage_problems "$coverage_sandbox")" ]; then
  pass "ac-ui-suite-coverage-guard (untouched sandbox green)"
else
  fail "ac-ui-suite-coverage-guard" "未改动沙箱被误判红"
fi
# 反例：删掉一个已入枚举套件的 ui_call 目标，守卫必须判红并点名该套件。
sed -i '' 's#"PurePaceUITests/RunFlowUITests"##' "$coverage_sandbox/scripts/test-ios.sh"
coverage_out="$(ui_suite_coverage_problems "$coverage_sandbox")"
if [ -n "$coverage_out" ] && printf '%s' "$coverage_out" | grep -Fq 'RunFlowUITests'; then
  pass "ac-ui-suite-coverage-guard (self-test)"
else
  fail "ac-ui-suite-coverage-guard" "删掉 RunFlowUITests 目标后未被识别"
fi
rm -rf "$coverage_sandbox"

# allowlist 缺失/仅注释合法；无理由条目必须判红。
allowlist_sandbox="$(mktemp -d "${TMPDIR:-/tmp}/purepace-check-ios-uiallow.XXXXXX")"
mkdir -p "$allowlist_sandbox/scripts" "$allowlist_sandbox/ios/PurePaceUITests"
cp scripts/test-ios.sh "$allowlist_sandbox/scripts/"
cp ios/PurePaceUITests/*.swift "$allowlist_sandbox/ios/PurePaceUITests/"
if [ -z "$(ui_allowlist_entry_problems "$allowlist_sandbox/scripts/ios-ui-local-only-suites.txt")" ]; then
  pass "ac-ui-allowlist-requires-reason (missing allowlist is empty)"
else
  fail "ac-ui-allowlist-requires-reason" "allowlist 缺失被误判红"
fi
printf '%s\n' 'NotReasonSuite' > "$allowlist_sandbox/scripts/ios-ui-local-only-suites.txt"
allowlist_out="$(ui_suite_coverage_problems "$allowlist_sandbox")"
if [ -n "$allowlist_out" ] && printf '%s' "$allowlist_out" | grep -Fq '缺少非空理由'; then
  pass "ac-ui-allowlist-requires-reason (self-test)"
else
  fail "ac-ui-allowlist-requires-reason" "无理由 allowlist 条目未被识别"
fi
rm -rf "$allowlist_sandbox"

# 深色段外观 / 失败即停反例：删恢复 light 行、删分段门控都必须判红。
appearance_sandbox="$(mktemp -d "${TMPDIR:-/tmp}/purepace-check-ios-uiappr.XXXXXX")"
cp scripts/test-ios.sh "$appearance_sandbox/test-ios.sh"
sed -i '' '/appearance light/d' "$appearance_sandbox/test-ios.sh"
if [ -n "$(test_ios_preparation_problems "$appearance_sandbox/test-ios.sh")" ]; then
  pass "ac-dark-appearance-gated (self-test)"
else
  fail "ac-dark-appearance-gated" "删掉 appearance light 恢复行的违规样本未被识别"
fi
rm -rf "$appearance_sandbox"

failfast_sandbox="$(mktemp -d "${TMPDIR:-/tmp}/purepace-check-ios-uifast.XXXXXX")"
python3 - "$failfast_sandbox/test-ios.sh" <<'PY'
import sys

src = open("scripts/test-ios.sh", encoding="utf-8").read()
guard = '  if [ "$ui_status" -eq 0 ]; then\n'
idx = src.rindex(guard)
open(sys.argv[1], "w", encoding="utf-8").write(src[:idx] + src[idx + len(guard):])
PY
if [ -n "$(test_ios_preparation_problems "$failfast_sandbox/test-ios.sh")" ]; then
  pass "ac-ui-legs-fail-fast-order (self-test)"
else
  fail "ac-ui-legs-fail-fast-order" "删掉分段 ui_status==0 门控的违规样本未被识别"
fi
rm -rf "$failfast_sandbox"

# ---------------- verify-ios-sim-runtime.sh 真实 CoreLocation 注入不得被误删
sim_runtime_problems() {
  local file="$1" out=""
  if [ ! -f "$file" ]; then
    printf '缺少 %s;' "$file"
    return 0
  fi
  grep -Fq -- '"location", udid, "set"' "$file" || out="$out 缺少 1Hz simctl location set 真实注入;"
  grep -Fq -- 'simctl location "${udid}" clear' "$file" || out="$out 缺少 simctl location clear 清理;"
  printf '%s' "$out"
}
problems="$(sim_runtime_problems scripts/verify-ios-sim-runtime.sh)"
# 重腿不作本地阻断门，但真实模拟器覆盖的权威落点必须仍在 CI：ios.yml 跑全量 test-ios.sh。
grep -Fq -- 'bash scripts/test-ios.sh' .github/workflows/ios.yml \
  || problems="$problems .github/workflows/ios.yml 未运行全量 scripts/test-ios.sh（真实模拟器覆盖权威落点丢失）;"
if grep -Fq -- '--unit-only' .github/workflows/ios.yml; then
  problems="$problems .github/workflows/ios.yml 出现 --unit-only（CI 不得跳过 UI 腿）;"
fi
if [ -z "$problems" ]; then
  pass "ac-real-corelocation-gate-kept"
else
  fail "ac-real-corelocation-gate-kept" "$problems"
fi

# 反例自检：删掉真实 simctl location set 注入行必须被识别。
sim_sandbox="$(mktemp -d "${TMPDIR:-/tmp}/purepace-check-ios-simrt.XXXXXX")"
python3 - "$sim_sandbox/verify-ios-sim-runtime.sh" <<'PY'
import sys
src = open("scripts/verify-ios-sim-runtime.sh", encoding="utf-8").read()
needle = '["xcrun", "simctl", "location", udid, "set", "%.7f,%.7f" % (latitude, longitude)]'
open(sys.argv[1], "w", encoding="utf-8").write(src.replace(needle, "[]"))
PY
if [ -n "$(sim_runtime_problems "$sim_sandbox/verify-ios-sim-runtime.sh")" ]; then
  pass "ac-real-corelocation-gate-kept (self-test)"
else
  fail "ac-real-corelocation-gate-kept" "删除真实注入行的违规样本未被识别"
fi
rm -rf "$sim_sandbox"

# ---------------- verify-ios-ui-e2e.sh 证据目录默认无 churn
ui_e2e_evidence_problems() {
  local file="$1" out=""
  if [ ! -f "$file" ]; then
    printf '缺少 %s;' "$file"
    return 0
  fi
  grep -Fq -- '--refresh-evidence' "$file" || out="$out 缺少 --refresh-evidence 开关;"
  grep -Fq -- 'evidence_dir="${work_dir}/evidence"' "$file" || out="$out 默认证据目录不在 .build/ 下;"
  if grep -Fq -- "simctl location" "$file"; then
    out="$out verify-ios-ui-e2e.sh 仍调用 simctl location（UI 应走确定性测试源）;"
  fi
  printf '%s' "$out"
}
problems="$(ui_e2e_evidence_problems scripts/verify-ios-ui-e2e.sh)"
if [ -z "$problems" ]; then
  pass "ac-e2e-evidence-default-no-churn"
else
  fail "ac-e2e-evidence-default-no-churn" "$problems"
fi

# 反例自检：删掉 --refresh-evidence 开关后必须被识别。
e2e_sandbox="$(mktemp -d "${TMPDIR:-/tmp}/purepace-check-ios-e2e.XXXXXX")"
sed 's/--refresh-evidence/--legacy-evidence-flag/g' scripts/verify-ios-ui-e2e.sh > "$e2e_sandbox/verify-ios-ui-e2e.sh"
if [ -n "$(ui_e2e_evidence_problems "$e2e_sandbox/verify-ios-ui-e2e.sh")" ]; then
  pass "ac-e2e-evidence-default-no-churn (self-test)"
else
  fail "ac-e2e-evidence-default-no-churn" "缺少 --refresh-evidence 的违规样本未被识别"
fi
rm -rf "$e2e_sandbox"

# ---------------- .munk/code-gates.json 门数固定（本地只留快而确定腿，重 UI 腿移出阻断）
problems=""
gate_count="$(python3 -c 'import json; print(len(json.load(open(".munk/code-gates.json"))["gates"]))' 2>/dev/null || true)"
if [ -z "$gate_count" ]; then
  problems="$problems 无法解析 .munk/code-gates.json gates;"
elif [ "$gate_count" -ne 22 ]; then
  problems="$problems code-gates 门数 ${gate_count}（期望 22）;"
fi
if [ -z "$problems" ]; then
  pass "ac-code-gates-count"
else
  fail "ac-code-gates-count" "$problems"
fi

# ---------------- 本地门拓扑：快腿必在、模拟器重腿不得本地阻断、test-ios 固定 unit-only
problems=""
topology="$(python3 -c '
import json
cfg = json.load(open(".munk/code-gates.json"))
cmds = {g["id"]: g["command"] for g in cfg["gates"]}
need = [
    "lint", "lint-ios-core", "lint-ios-scripts", "lint-ios-release", "lint-ios-shell",
    "lint-ios-workflow", "lint-ios-run-core", "lint-android", "lint-android-workflow",
    "build-ios-core", "build-ios-run-core", "test-ios-core", "test-ios-run-core",
    "test-ios", "build-android", "test-android", "test", "check-shared",
    "check-gpx-export", "check-shell-expansion",
]
heavy = ["verify-ios-sim-runtime", "verify-ios-ui-e2e"]
bad = ["缺少本地快腿 " + i for i in need if i not in cmds]
bad += ["模拟器重腿 " + i + " 仍在本地阻断门中" for i in heavy if i in cmds]
if cmds.get("test-ios") != "bash scripts/test-ios.sh --unit-only":
    bad.append("test-ios 本地门必须为 bash scripts/test-ios.sh --unit-only（实际 " + str(cmds.get("test-ios")) + "）")
print(";".join(bad))
' 2>/dev/null || true)"
if [ -z "$topology" ] && [ -n "$gate_count" ]; then
  pass "ac-code-gates-local-topology"
else
  problems="$topology"
  [ -z "$problems" ] && problems="无法解析 .munk/code-gates.json gates;"
  fail "ac-code-gates-local-topology" "$problems"
fi

# ------------------------------- 降级分支不伪造成功行（不 echo BUILD/TEST SUCCEEDED）
problems=""
for name in build-ios.sh test-ios.sh; do
  [ -f "scripts/$name" ] || continue
  fabricated="$(grep -nE "^[[:space:]]*(echo|printf)[^#]*(BUILD SUCCEEDED|TEST SUCCEEDED)" "scripts/$name" 2>/dev/null || true)"
  [ -z "$fabricated" ] || problems="$problems scripts/$name 出现伪造成功行: $(printf '%s' "$fabricated" | tr '\n' ' ');"
done
if [ -z "$problems" ]; then
  pass "ac-no-fake-success-line"
else
  fail "ac-no-fake-success-line" "$problems"
fi

# ------------------------------------------------------ version.sh 无参契约
version_value=""
if [ -f VERSION ]; then
  version_value="$(tr -d '\r\n' < VERSION)"
fi
problems=""
if [ ! -f scripts/version.sh ]; then
  problems="$problems 缺少 scripts/version.sh;"
elif [ -z "$version_value" ]; then
  problems="$problems 根 VERSION 不可用;"
else
  bare_out="$(bash scripts/version.sh 2>/dev/null)" && bare_rc=0 || bare_rc=$?
  if [ "$bare_rc" -ne 0 ]; then
    problems="$problems 无参退出 $bare_rc;"
  elif [ "$bare_out" != "$version_value" ]; then
    problems="$problems 无参输出 '$bare_out' 与 VERSION 不一致;"
  fi
fi
if [ -z "$problems" ]; then
  pass "ac-version-bare-unchanged"
else
  fail "ac-version-bare-unchanged" "$problems"
fi

# ------------------- version.sh 不得调用 gradlew，必须离线读 wrapper properties
version_offline_problems() {
  local file="$1" out=""
  if [ ! -f "$file" ]; then
    printf '缺少 %s;' "$file"
    return 0
  fi
  if grep -Fq -- 'gradlew' "$file"; then
    out="$out 正文出现 gradlew（--tools 必须离线解析 wrapper）;"
  fi
  if ! grep -Fq -- 'android/gradle/wrapper/gradle-wrapper.properties' "$file"; then
    out="$out 未读取 android/gradle/wrapper/gradle-wrapper.properties;"
  fi
  printf '%s' "$out"
}

problems="$(version_offline_problems scripts/version.sh)"
if [ -z "$problems" ]; then
  pass "ac-version-tools-no-gradlew"
else
  fail "ac-version-tools-no-gradlew" "$problems"
fi

# 反例自检：向沙箱样本注入 gradlew 调用，必须被同一断言识别（非恒真）。
offline_sandbox="$(mktemp -d "${TMPDIR:-/tmp}/purepace-check-ios-offline.XXXXXX")"
mkdir -p "$offline_sandbox/scripts"
cp scripts/version.sh "$offline_sandbox/scripts/version.sh" 2>/dev/null || true
printf '%s\n' '' '# android/gradlew -p android --version' >> "$offline_sandbox/scripts/version.sh"
if [ -n "$(version_offline_problems "$offline_sandbox/scripts/version.sh")" ]; then
  pass "ac-version-tools-no-gradlew (self-test)"
else
  fail "ac-version-tools-no-gradlew" "注入 gradlew 的违规样本未被识别"
fi
rm -rf "$offline_sandbox"

# ------------------------------------------------------- version.sh --tools
problems=""
if [ -f scripts/version.sh ] && [ -n "$version_value" ]; then
  tools_out="$(bash scripts/version.sh --tools 2>&1)" && tools_rc=0 || tools_rc=$?
  if [ "$tools_rc" -ne 0 ]; then
    problems="$problems --tools 退出 $tools_rc;"
  else
    grep -Fq -- "VERSION: $version_value" <<<"$tools_out" || problems="$problems --tools 缺少根 VERSION 行;"

    if command -v xcodebuild >/dev/null 2>&1; then
      xcode_expected="$(xcodebuild -version 2>/dev/null | sed -n 's/^Xcode \([0-9][0-9.]*\).*/\1/p' | head -n 1 || true)"
    else
      xcode_expected=""
    fi
    if [ -n "$xcode_expected" ]; then
      grep -Fxq -- "Xcode: $xcode_expected" <<<"$tools_out" || problems="$problems Xcode 行与 xcodebuild -version 不一致（期望 ${xcode_expected}）;"
    else
      grep -Eq '^Xcode: 未就绪' <<<"$tools_out" || problems="$problems Xcode 行未标注未就绪;"
    fi

    if command -v swift >/dev/null 2>&1; then
      swift_expected="$(swift --version 2>/dev/null | sed -n 's/.*Apple Swift version \([0-9][0-9.]*\).*/\1/p' | head -n 1 || true)"
    else
      swift_expected=""
    fi
    if [ -n "$swift_expected" ]; then
      grep -Fxq -- "Swift: Apple Swift version $swift_expected" <<<"$tools_out" || problems="$problems Swift 行与 swift --version 不一致（期望 ${swift_expected}）;"
    else
      grep -Eq '^Swift: 未就绪' <<<"$tools_out" || problems="$problems Swift 行未标注未就绪;"
    fi

    if command -v java >/dev/null 2>&1; then
      jdk_expected="$(java -version 2>&1 | sed -n 's/.*version "\([^"]*\)".*/\1/p' | head -n 1 || true)"
      if [ -n "$jdk_expected" ]; then
        grep -Eq "^JDK: .*${jdk_expected}" <<<"$tools_out" || problems="$problems JDK 行与 java -version 不一致（期望含 ${jdk_expected}）;"
      else
        grep -Eq '^JDK: 未就绪' <<<"$tools_out" || problems="$problems JDK 行未标注未就绪;"
      fi
    else
      grep -Eq '^JDK: 未就绪' <<<"$tools_out" || problems="$problems JDK 行未标注未就绪;"
    fi

    gradle_wrapper="android/gradle/wrapper/gradle-wrapper.properties"
    gradle_expected=""
    if [ -f "$gradle_wrapper" ]; then
      gradle_url="$(sed -n 's/^distributionUrl[[:space:]]*=[[:space:]]*//p' "$gradle_wrapper" | tr -d '\r' | head -n 1)"
      gradle_expected="$(sed -n 's/.*gradle-\([0-9][0-9.]*\)-.*\.zip$/\1/p' <<<"$gradle_url")"
    fi
    if [ -n "$gradle_expected" ]; then
      grep -Fxq -- "Gradle: $gradle_expected" <<<"$tools_out" || problems="$problems Gradle 行与 wrapper properties 推导值不一致（期望 ${gradle_expected}）;"
    else
      grep -Eq '^Gradle: 未就绪' <<<"$tools_out" || problems="$problems 缺少 wrapper properties 时 Gradle 行未标注未就绪;"
    fi

    tools_out2="$(bash scripts/version.sh --tools 2>&1)" || true
    [ "$tools_out" = "$tools_out2" ] || problems="$problems --tools 连续两次输出不一致;"
  fi
else
  problems="$problems scripts/version.sh 或根 VERSION 不可用;"
fi
if [ -z "$problems" ]; then
  pass "ac-version-tools-report"
  pass "ac-version-tools-idempotent"
else
  fail "ac-version-tools-report" "$problems"
  fail "ac-version-tools-idempotent" "$problems"
fi

# ------------------------------------------- 脚本与 README 无根 VERSION 字面值
# README 版本表数据行（| 版本 | 日期 | 状态 | CHANGELOG |）是唯一受控豁免；
# 表格外正文与全部 scripts/*.sh 继续禁字面值，补偿控制是 check-baseline.sh 的三源一致断言。
problems=""
if [ -z "$version_value" ]; then
  problems="$problems 根 VERSION 不可用;"
else
  hits="$(grep -Fn -- "$version_value" scripts/*.sh 2>/dev/null || true)"
  [ -z "$hits" ] || problems="$problems 出现版本字面值 '$version_value': $(printf '%s' "$hits" | tr '\n' ' ');"
  readme_hits="$(awk '!/^\| *[0-9]+\.[0-9]+\.[0-9]+ *\|/' README.md 2>/dev/null | grep -Fn -- "$version_value" || true)"
  [ -z "$readme_hits" ] || problems="$problems README 版本表之外出现版本字面值 '$version_value': $(printf '%s' "$readme_hits" | tr '\n' ' ');"
fi
if [ -z "$problems" ]; then
  pass "ac-no-version-literal"
else
  fail "ac-no-version-literal" "$problems"
fi

printf '\n%d 项断言，%d 项失败\n' "$CHECKS" "$FAILURES"
if [ "$FAILURES" -ne 0 ]; then
  exit 1
fi
printf 'ios scripts OK\n'
