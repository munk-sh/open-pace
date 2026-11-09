#!/usr/bin/env bash
# iOS 测试入口：先由根 VERSION 同步 xcconfig，工程可用时走 xcodegen + xcodebuild test
# 真跑 XCTest/XCUITest，缺失时显式 blocked 并降级到 ios/Core 的 swift test，保留真实用例数。
set -euo pipefail

usage() {
  cat <<'EOF'
用法: scripts/test-ios.sh [--unit-only|--help]

测试 iOS 侧产物，按工程可用性自动选择分支：
  - 分支 A（工程可用）：先执行 scripts/sync-ios-version.sh 由根 VERSION 生成
    ios/Config/Version.xcconfig；ios/PurePace.xcodeproj 存在，或 ios/project.yml
    存在且本机有 xcodegen 可从 spec 生成工程时，在 bootstatus 之后拆成两次
    xcodebuild test（共用 .build/ios 派生数据）：
      1) -only-testing:PurePaceTests（日志 .build/logs/xcodebuild-unit.log，Executed 摘要先落盘）
      2) -only-testing:PurePaceUITests -skip-testing:PurePaceUITests/DeviceFlowUITests（日志 .build/logs/xcodebuild-ui.log；
         DeviceFlowUITests 只由 scripts/verify-ios-device-flow.sh 分阶段驱动，不进默认 CI UI 腿）
    UI 测试由启动参数 -uiTestLocation 门控的 DEBUG 确定性定位源驱动，不再依赖
    simulator 的隐藏式定位投递；真实 CoreLocation 覆盖由 scripts/verify-ios-sim-runtime.sh 承担。
    测试前按固定顺序准备模拟器状态：bootstatus 等待设备可用 → simctl uninstall 清容器 →
    构建并安装 App → simctl privacy grant location 预置定位授权（授权只对已安装 bundle 生效，
    且卸载会清掉 TCC，故必须在安装之后）→ simctl launch/terminate 启动预热。
    两次 xcodebuild test 都带测试执行预算（-test-timeouts-enabled / -default-test-execution-time-allowance /
    -maximum-test-execution-time-allowance）与进程级硬超时（bash 看门狗，不依赖 GNU timeout）；
    单测/UI 两腿各有独立硬超时（默认 600s）；UI 腿可用预算低于最小阈值时明确失败，超时后非零退出并打印超时阶段与已执行的测试摘要。
    任一调用失败脚本非零退出，单测结论先于 UI 输出且不被 UI 失败覆盖。
  - 分支 B（工程不可用）：输出 blocked: 明确缺失原因（xcodegen / ios/PurePace.xcodeproj），
    降级真实执行 swift test --package-path ios/Core，并保留真实 Executed 用例数与失败数。
  - 两个分支都会追加执行 swift test --package-path ios/RunCore（跑步域纯逻辑包）；
    ios/RunCore 缺失时打印 blocked: 并继续，RunCore 测试失败时脚本非零退出。

选项:
  --unit-only  只跑 PurePaceTests 单测，跳过 PurePaceUITests（本地门快腿专用；
               权威全量 UI 覆盖由 .github/workflows/ios.yml 的 test 步承载）
  -h, --help   显示本帮助并退出 0

环境变量:
  IOS_XCODEBUILD_TIMEOUT  xcodebuild test 每腿（单测/UI 各一份）的硬超时秒数，默认 600（≤600，压住 AX 初始化静默等待）
  PUREPACE_IOS_UI_MIN_BUDGET_SECONDS
                           UI 腿最小可用预算秒数，默认 300；可用预算低于该值时明确失败
  PUREPACE_IOS_TEST_STEP_BUDGET_SECONDS
                           step 级总预算秒数（CI 由 ios.yml 注入 2700）；与下面的起点同时存在时生效
  PUREPACE_IOS_STEP_STARTED_AT
                           step 起始 epoch 秒；UI 可用预算再取 min(单腿预算, step 剩余)

退出码:
  0    测试通过，或工程缺失但降级的 swift test 真实通过（输出含 blocked:）
  1    工程存在但真实测试失败，或降级 swift test 失败
  2    参数非法
  124  xcodebuild test 触发硬超时，或 UI 腿可用预算低于最小阈值（看门狗已强制终止/未起跑）
EOF
}

unit_only=0
case "${1:-}" in
  -h|--help)
    usage
    exit 0
    ;;
  --unit-only)
    unit_only=1
    ;;
  "")
    ;;
  *)
    echo "test-ios: 未知参数 '$1'（使用 --help 查看用法）" >&2
    exit 2
    ;;
esac

if [ "$#" -gt 1 ]; then
  echo "test-ios: 只接受一个参数（使用 --help 查看用法）" >&2
  exit 2
fi

# 以脚本自身位置推导仓库根，保证在任意 cwd 下运行结果一致。
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
cd "$repo_root"

ios_dir="ios"
project_path="$ios_dir/PurePace.xcodeproj"
spec_path="$ios_dir/project.yml"
derived_data=".build/ios"
scheme="PurePace"
destination="platform=iOS Simulator,name=iPhone 16,OS=18.6"
bundle_id="com.chaxiu.purepace"

# 版本派生：MARKETING_VERSION 只能来自根 VERSION（写 ios/Config/Version.xcconfig）。
if [ -f scripts/sync-ios-version.sh ]; then
  bash scripts/sync-ios-version.sh
fi

# XCUITest 的定位链路：UI 用例由 `-uiTestLocation` 门控的 DEBUG 确定性测试源驱动，
# 不再依赖 hosted runner 的隐藏式 simulator 定位投递；真实 CoreLocation 覆盖由
# scripts/verify-ios-sim-runtime.sh 的门禁承担。固定 iPhone 16 / iOS 18.6；bootstatus
# 等待设备完全可用，卸载清容器 → 构建安装 App → simctl privacy 预置定位授权 → 启动预热，
# 最后拆成「单测 → UI」两次 xcodebuild test，共用派生数据但预算按腿独立。
sim_udid=""
app_path="$derived_data/Build/Products/Debug-iphonesimulator/PurePace.app"
ui_runner_path="$derived_data/Build/Products/Debug-iphonesimulator/PurePaceUITests-Runner.app"
log_dir=".build/logs"
unit_log="$log_dir/xcodebuild-unit.log"
ui_log="$log_dir/xcodebuild-ui.log"
xcodebuild_timeout="${IOS_XCODEBUILD_TIMEOUT:-600}"
# 单测腿 / UI 腿各自独立预算（各一份 IOS_XCODEBUILD_TIMEOUT，默认 600s）；
# 不再用「单测已耗时」从 UI 预算里扣减。UI 腿另有最小可用预算阈值。
unit_budget="$xcodebuild_timeout"
ui_budget="$xcodebuild_timeout"
ui_min_budget="${PUREPACE_IOS_UI_MIN_BUDGET_SECONDS:-300}"
step_budget_seconds="${PUREPACE_IOS_TEST_STEP_BUDGET_SECONDS:-}"
step_started_at="${PUREPACE_IOS_STEP_STARTED_AT:-}"

# step 级剩余预算（秒）；两个 env 缺失或非法时不约束（输出空串）。
step_budget_remaining() {
  case "${step_budget_seconds}" in
    ""|*[!0-9]*) return 0 ;;
  esac
  case "${step_started_at}" in
    ""|*[!0-9]*) return 0 ;;
  esac
  local now elapsed remaining
  now="$(date +%s)"
  elapsed=$((now - step_started_at))
  if [ "$elapsed" -lt 0 ]; then
    elapsed=0
  fi
  remaining=$((step_budget_seconds - elapsed))
  if [ "$remaining" -lt 0 ]; then
    remaining=0
  fi
  printf '%s' "$remaining"
}

# UI 腿可用预算：min(单腿预算, step 剩余)；step env 缺失时不约束。
ui_leg_budget() {
  local available="$ui_budget" step_left=""
  step_left="$(step_budget_remaining)"
  if [ -n "$step_left" ] && [ "$step_left" -lt "$available" ]; then
    available="$step_left"
  fi
  printf '%s' "$available"
}

# UI 可用预算低于最小阈值时打印一行并返回 0（调用方据此失败退出 124）。
ui_budget_insufficient() {
  local available="$1"
  if [ "$available" -lt "$ui_min_budget" ]; then
    echo "test-ios: 承载层预算不足：UI 腿可用 ${available}s < 最小阈值 ${ui_min_budget}s" >&2
    return 0
  fi
  return 1
}

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

select_simulator() {
  xcrun simctl list devices available --json 2>/dev/null | python3 -c '
import json, sys
data = json.load(sys.stdin).get("devices", {})
for runtime, devices in data.items():
    if not runtime.endswith("iOS-18-6"):
        continue
    for device in devices:
        if device.get("name") == "iPhone 16" and device.get("isAvailable", True):
            print(device["udid"])
            sys.exit(0)
sys.exit(1)
'
}

# 干净设备 boot 等待：bootstatus -b 通过才继续，失败时打印 udid 与阶段并非零退出。
wait_for_simulator_boot() {
  sim_udid="$(select_simulator || true)"
  if [ -z "$sim_udid" ]; then
    echo "test-ios: 未找到 iPhone 16 / iOS 18.6 模拟器，无法运行 UI 测试" >&2
    exit 1
  fi
  echo "info: 使用模拟器 $sim_udid 注入 CoreLocation 更新"
  if ! xcrun simctl bootstatus "$sim_udid" -b >/dev/null 2>&1; then
    echo "test-ios: 阶段 simulator-boot 失败：模拟器 $sim_udid 启动/就绪失败（xcrun simctl bootstatus $sim_udid -b）" >&2
    exit 1
  fi
}

# 容器清理 → 构建 → 安装 → 预置定位授权 → 启动预热。
# TCC 只对已安装 bundle 生效且 simctl uninstall 会清掉它，所以授权必须排在安装之后。
prepare_simulator_for_ui_tests() {
  mkdir -p "$log_dir"
  # 清理上次运行残留：保证容器为空（History 恰 1 条）并回到首次未授权路径。
  xcrun simctl uninstall "$sim_udid" "$bundle_id" >/dev/null 2>&1 || true

  # build-for-testing：一次构建 App + 单测包 + UI Runner，后续两次执行都用
  # test-without-building，避免 xcodebuild test 重装 App 把已预置的 TCC 授权清掉。
  echo "info: 阶段 xcodebuild-build：构建 App 与测试包（build-for-testing，派生数据 ${derived_data}）"
  if ! xcodebuild build-for-testing \
    -project "$project_path" \
    -scheme "$scheme" \
    -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' \
    -derivedDataPath "$derived_data" \
    CODE_SIGNING_ALLOWED=NO; then
    echo "test-ios: 阶段 xcodebuild-build 失败：构建 App 与测试包失败（模拟器 ${sim_udid}）" >&2
    exit 1
  fi

  if [ ! -d "$app_path" ]; then
    echo "test-ios: 阶段 simulator-install 失败：未找到构建产物 ${app_path}（模拟器 ${sim_udid}）" >&2
    exit 1
  fi
  echo "info: 阶段 simulator-install：安装 $app_path"
  if ! xcrun simctl install "$sim_udid" "$app_path" >/dev/null 2>&1; then
    echo "test-ios: 阶段 simulator-install 失败：simctl install 安装 $bundle_id 失败（模拟器 ${sim_udid}）" >&2
    exit 1
  fi
  # UI Runner 必须预装：test-without-building 不会自动安装它（否则启动 xctrunner 失败）。
  if [ ! -d "$ui_runner_path" ]; then
    echo "test-ios: 阶段 simulator-install 失败：未找到 UI 测试 Runner ${ui_runner_path}（模拟器 ${sim_udid}）" >&2
    exit 1
  fi
  echo "info: 阶段 simulator-install：安装 UI Runner $ui_runner_path"
  if ! xcrun simctl install "$sim_udid" "$ui_runner_path" >/dev/null 2>&1; then
    echo "test-ios: 阶段 simulator-install 失败：simctl install 安装 UI Runner 失败（模拟器 ${sim_udid}）" >&2
    exit 1
  fi

  # 预热必须先于授权：首次安装的 bundle 需先被启动一次向 locationd 注册，
  # 之后 `simctl privacy grant location-always` 才会真正生效（否则冷启动仍读未授权）。
  echo "info: 阶段 simulator-warmup：启动并终止 App 一次完成预热与 locationd 注册"
  if ! xcrun simctl launch "$sim_udid" "$bundle_id" >/dev/null 2>&1; then
    echo "test-ios: 阶段 simulator-warmup 失败：simctl launch ${bundle_id}（模拟器 ${sim_udid}）" >&2
    exit 1
  fi
  sleep 2
  if ! xcrun simctl terminate "$sim_udid" "$bundle_id" >/dev/null 2>&1; then
    echo "test-ios: 阶段 simulator-warmup 失败：simctl terminate ${bundle_id}（模拟器 ${sim_udid}）" >&2
    exit 1
  fi

  # terminate 与随后 xcodebuild 的 terminate_running_process=1 之间存在拆进程窗口，
  # SBMainWorkspace 可能在上一个实例真正退出前返回 Busy/preflight 失败。轮询 launchctl
  # 确认 bundle 进程已消失再返回；有界约 10s，不使用裸 sleep 定时器或无限重试。
  local warmup_waited=0
  local warmup_limit=10
  while [ "$warmup_waited" -lt "$warmup_limit" ]; do
    if ! xcrun simctl spawn "$sim_udid" launchctl list 2>/dev/null | grep -Fq -- "$bundle_id"; then
      warmup_waited=$warmup_limit
      break
    fi
    sleep 1
    warmup_waited=$((warmup_waited + 1))
  done
  if xcrun simctl spawn "$sim_udid" launchctl list 2>/dev/null | grep -Fq -- "$bundle_id"; then
    echo "test-ios: 阶段 simulator-warmup 失败：terminate 后 ${warmup_limit}s 内 ${bundle_id} 仍在 launchctl 列表（模拟器 ${sim_udid}）" >&2
    exit 1
  fi

  echo "info: 阶段 simulator-privacy：预置定位授权（simctl privacy grant location ${bundle_id}）"
  if ! xcrun simctl privacy "$sim_udid" grant location "$bundle_id" >/dev/null 2>&1; then
    echo "test-ios: 阶段 simulator-privacy 失败：simctl privacy grant location ${bundle_id}（模拟器 ${sim_udid}）" >&2
    exit 1
  fi
  # ac-tel-always：升级到「始终允许」，使 App 侧授权探针读回 authorizedAlways（rawValue 3）。
  echo "info: 阶段 simulator-privacy：预置「始终允许」授权（simctl privacy grant location-always ${bundle_id}）"
  if ! xcrun simctl privacy "$sim_udid" grant location-always "$bundle_id" >/dev/null 2>&1; then
    echo "test-ios: 阶段 simulator-privacy 失败：simctl privacy grant location-always ${bundle_id}（模拟器 ${sim_udid}）" >&2
    exit 1
  fi
}

# ac-tel-always：xcodebuild 每次 test-without-building 都会把 App 重装到新的 Bundle
# 容器，而 locationd 的 TCC 记录与容器路径绑定，预置授权会随之失效；既有 UI 用例也可能
# 把授权降级为 whenInUse。故在 UI 调用全程后台轮询已安装容器并幂等重申 location-always，
# 保证探针在跑次结束时刻读回 authorizedAlways（rawValue 3）。
refresh_location_always_until_stopped() {
  local stop_file="$1"
  while [ ! -e "$stop_file" ]; do
    if xcrun simctl get_app_container "$sim_udid" "$bundle_id" app >/dev/null 2>&1; then
      xcrun simctl privacy "$sim_udid" grant location-always "$bundle_id" >/dev/null 2>&1 || true
    fi
    sleep 2
  done
}

# 进程级硬超时看门狗（macOS bash 3.2 无 GNU timeout）：超时先 TERM 再 KILL，
# 打印超时阶段与已执行测试摘要，返回 124；正常退出时透传子进程退出码。
run_with_watchdog() {
  local timeout_seconds="$1"
  local out_log="$2"
  shift 2
  local command_pid=""
  local waited=0
  local wait_status=0
  "$@" >"$out_log" 2>&1 &
  command_pid=$!
  while kill -0 "$command_pid" 2>/dev/null; do
    if [ "$waited" -ge "$timeout_seconds" ]; then
      echo "test-ios: 阶段 xcodebuild-test 硬超时（${timeout_seconds}s），强制终止 PID ${command_pid}" >&2
      kill -TERM "$command_pid" >/dev/null 2>&1 || true
      sleep 2
      kill -KILL "$command_pid" >/dev/null 2>&1 || true
      wait "$command_pid" >/dev/null 2>&1 || true
      echo "test-ios: runner bootstrap 挂起：xcodebuild test 在 ${timeout_seconds}s 硬超时前未完成（未进入产品断言）" >&2
      echo "test-ios: 超时前已执行的测试摘要：" >&2
      grep -E "Test Case .*(started|passed|failed)|Executed [0-9]+ tests" "$out_log" 2>/dev/null | tail -n 40 >&2 || true
      cat "$out_log" 2>/dev/null || true
      return 124
    fi
    sleep 1
    waited=$((waited + 1))
  done
  wait "$command_pid" || wait_status=$?
  return "$wait_status"
}

# 单测/UI 两次 xcodebuild test 的公共前置说明：
# 两次调用各自落盘日志（xcodebuild-unit.log / xcodebuild-ui.log），预算按腿独立。
test_with_xcodebuild() {
  ios_gate_lock_acquire || exit $?
  # 取锁后先等待其它 worktree 的 xcodebuild/simctl 归零，再清场（有并发时禁止 shutdown/erase）。
  ios_gate_lock_prepare_simulator || exit $?
  wait_for_simulator_boot
  prepare_simulator_for_ui_tests
  echo "info: location-source=deterministic(-uiTestLocation)（真实 CoreLocation 由 scripts/verify-ios-sim-runtime.sh 覆盖）"
  # 第一次调用：单元测试（-only-testing:PurePaceTests）；日志与 Executed 摘要先落盘。
  local unit_status=0
  echo "info: xcodebuild test-without-building -only-testing:PurePaceTests -scheme ${scheme} -destination '${destination}'（预算 ${unit_budget}s，日志 ${unit_log}）"
  run_with_watchdog "$unit_budget" "$unit_log" \
    xcodebuild test-without-building \
    -project "$project_path" \
    -scheme "$scheme" \
    -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' \
    -derivedDataPath "$derived_data" \
    -only-testing:PurePaceTests \
    -test-timeouts-enabled YES \
    -default-test-execution-time-allowance 300 \
    -maximum-test-execution-time-allowance 540 \
    CODE_SIGNING_ALLOWED=NO || unit_status=$?
  cat "$unit_log" 2>/dev/null || true
  # 单测摘要必须先于 UI 调用输出：UI 失败不得覆盖单测结论。
  echo "info: PurePaceTests 摘要（先于 UI 落盘：${unit_log}）："
  grep -E "Executed [0-9]+ tests|Test Case .*(started|passed|failed)" "$unit_log" 2>/dev/null | tail -n 10 || true
  if [ "$unit_status" -ne 0 ]; then
    echo "test-ios: 阶段 xcodebuild-unit 失败：PurePaceTests 退出 ${unit_status}（模拟器 ${sim_udid}）" >&2
    return "$unit_status"
  fi
  # --unit-only：本地门只做快而确定的单测腿，UI 腿不阻断本地；全量 UI 由 ios.yml 承载。
  if [ "${unit_only}" = "1" ]; then
    echo "info: unit-only 模式：跳过 PurePaceUITests（本地旁证，权威看 .github/workflows/ios.yml）"
    return 0
  fi
  # 单测腿与 UI 腿预算按腿独立（各一份，默认 600s）；step 预算生效时 UI 再取 min(单腿预算, step 剩余)。
  local ui_available=""
  ui_available="$(ui_leg_budget)"
  if ui_budget_insufficient "$ui_available"; then
    return 124
  fi
  # test-without-building 仍可能重装宿主 App，从而清掉 TCC 授权；UI 前重装 Runner 并
  # 重申「始终允许」，保证 ac-tel-always 的 authorizedAlways（rawValue 3）可机器成立。
  if [ -d "$ui_runner_path" ]; then
    xcrun simctl install "$sim_udid" "$ui_runner_path" >/dev/null 2>&1 || true
  fi
  echo "info: 阶段 simulator-privacy：UI 前重申定位授权（location + location-always ${bundle_id}）"
  if ! xcrun simctl privacy "$sim_udid" grant location "$bundle_id" >/dev/null 2>&1; then
    echo "test-ios: 阶段 simulator-privacy 失败：simctl privacy grant location ${bundle_id}（模拟器 ${sim_udid}）" >&2
    return 1
  fi
  if ! xcrun simctl privacy "$sim_udid" grant location-always "$bundle_id" >/dev/null 2>&1; then
    echo "test-ios: 阶段 simulator-privacy 失败：simctl privacy grant location-always ${bundle_id}（模拟器 ${sim_udid}）" >&2
    return 1
  fi
  # 第二次调用：UI 测试（-only-testing:PurePaceUITests），由 -uiTestLocation 确定性测试源驱动。
  # DeviceFlowUITests 是真机取证套件（由 scripts/verify-ios-device-flow.sh 分阶段单独驱动），
  # 不进默认 CI UI 腿：无设备前置时会 4/4 确定性失败并撞满 600s 预算。此处显式排除，
  # 重试路径复用同一脚本，因此两次 attempt 的选择器一致。
  local tcc_stop_file="${TMPDIR:-/tmp}/purepace-tcc-refresh.$$"
  rm -f "$tcc_stop_file"
  refresh_location_always_until_stopped "$tcc_stop_file" &
  local tcc_refresher_pid=$!
  local ui_status=0
  echo "info: xcodebuild test-without-building -only-testing:PurePaceUITests -skip-testing:PurePaceUITests/DeviceFlowUITests -scheme ${scheme} -destination '${destination}'（预算 ${ui_available}s，日志 ${ui_log}）"
  run_with_watchdog "$ui_available" "$ui_log" \
    xcodebuild test-without-building \
    -project "$project_path" \
    -scheme "$scheme" \
    -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' \
    -derivedDataPath "$derived_data" \
    -only-testing:PurePaceUITests \
    -skip-testing:PurePaceUITests/DeviceFlowUITests \
    -test-timeouts-enabled YES \
    -default-test-execution-time-allowance 300 \
    -maximum-test-execution-time-allowance 540 \
    CODE_SIGNING_ALLOWED=NO || ui_status=$?
  touch "$tcc_stop_file"
  wait "$tcc_refresher_pid" 2>/dev/null || true
  rm -f "$tcc_stop_file"
  cat "$ui_log" 2>/dev/null || true
  echo "info: PurePaceUITests 摘要（日志 ${ui_log}）："
  grep -E "Executed [0-9]+ tests|Test Case .*(started|passed|failed)" "$ui_log" 2>/dev/null | tail -n 10 || true
  if [ "$ui_status" -eq 124 ]; then
    echo "test-ios: 阶段 xcodebuild-ui 失败：超过 ${ui_available}s 硬超时被强制终止（模拟器 ${sim_udid}）" >&2
  elif [ "$ui_status" -ne 0 ]; then
    echo "test-ios: 阶段 xcodebuild-ui 失败：xcodebuild test 退出 ${ui_status}（模拟器 ${sim_udid}）" >&2
  fi
  return "$ui_status"
}

# RunCore 是纯逻辑 SwiftPM 包，两个分支都真实执行；包缺失时显式 blocked 不伪造成功。
test_with_run_core() {
  if [ ! -d ios/RunCore ]; then
    echo "blocked: 缺 ios/RunCore，跳过 RunCore 的 swift test"
    return 0
  fi
  echo "info: 执行 swift test --package-path ios/RunCore"
  if swift test --package-path ios/RunCore; then
    echo "info: RunCore SwiftPM 测试完成"
  else
    status=$?
    echo "test-ios: RunCore 的 swift test 失败（退出码 ${status}）" >&2
    return "$status"
  fi
}

if [ -d "$project_path" ]; then
  test_with_xcodebuild
  test_with_run_core
  exit 0
fi

if [ -f "$spec_path" ] && command -v xcodegen >/dev/null 2>&1; then
  echo "info: 缺 ${project_path}，使用 xcodegen 从 $spec_path 生成工程"
  xcodegen generate --spec "$spec_path" --project "$ios_dir"
  test_with_xcodebuild
  test_with_run_core
  exit 0
fi

if [ ! -f "$spec_path" ] && ! command -v xcodegen >/dev/null 2>&1; then
  missing_reason="缺 xcodegen 且缺 $spec_path"
elif [ ! -f "$spec_path" ]; then
  missing_reason="缺 ${spec_path}（xcodegen 已安装，但没有可供生成的 spec）"
elif ! command -v xcodegen >/dev/null 2>&1; then
  missing_reason="缺 xcodegen（有 ${spec_path}，但本机无法生成工程）"
else
  missing_reason="缺 xcodegen 可用的 $project_path"
fi

echo "blocked: ${missing_reason}，无法生成或使用 ${project_path}，跳过 xcodebuild test"
echo "info: 降级执行 swift test --package-path ios/Core"
if swift test --package-path ios/Core; then
  echo "info: 降级 SwiftPM 测试完成（未运行 XCTest/XCUITest）"
else
  status=$?
  echo "test-ios: 降级 swift test 失败（退出码 ${status}）" >&2
  exit "$status"
fi

test_with_run_core
