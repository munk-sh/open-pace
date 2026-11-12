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
    存在且本机有 xcodegen 可从 spec 生成工程时，在模拟器就绪后拆成两次
    xcodebuild test（共用 .build/ios 派生数据）：
      1) -only-testing:PurePaceTests（日志 .build/logs/xcodebuild-unit.log，Executed 摘要先落盘）
      2) -only-testing:PurePaceUITests（日志 .build/logs/xcodebuild-ui.log）
    UI 测试由启动参数 -uiTestLocation 门控的 DEBUG 确定性定位源驱动，不再依赖
    simulator 的隐藏式定位投递；真实 CoreLocation 覆盖由 scripts/verify-ios-sim-runtime.sh 承担。
    结束态内容 canonical（本地 / CI 同构，见 docs/verification-matrix.md 保存态行）：
    UI 用例用 -uiTestLocationTargetMeters 把距离锁死在 0 行 = 400m、1 行 = 1200m，
    分段行数 = floor(m/1000) 只由参数决定，不再随 runner 墙钟（1 Hz tick 数）漂移；
    因此 `bash scripts/test-ios.sh`（不带 --unit-only）就是保存态三判据与地图 ≥96pt 的本地复现入口，
    不会出现「本地绿 / CI 红」的内容差。
    模拟器准备：目标设备已 Booted 且持锁后无并发时直接复用（不 shutdown）；
    否则清场 → 显式 simctl boot（与 build-for-testing 并行）→ 有界 bootstatus 轮询至就绪。
    之后按固定顺序准备模拟器状态：simctl uninstall 清容器 →
    构建并安装 App → simctl privacy grant location 预置定位授权（授权只对已安装 bundle 生效，
    且卸载会清掉 TCC，故必须在安装之后）→ simctl launch/terminate 启动预热。
    两次 xcodebuild test 都带测试执行预算（-test-timeouts-enabled / -default-test-execution-time-allowance /
    -maximum-test-execution-time-allowance）与进程级硬超时（bash 看门狗，不依赖 GNU timeout）；
    看门狗按墙钟差额判定超时（sleep 仅作轮询粒度）；单测/UI 两腿各有独立上限（默认 600s），
    实际腿预算再取 min(单腿上界, 本次 attempt 剩余)；本次 attempt 预算 = step 预算 − 重试余量
    （默认 2700 − 900 = 1800s，严格小于 45min step 超时，为 ios.yml 的一次 infra 重试留余量）。
    承载层预算不足/超时时以 124 退出并打印承载层预算口径，不写成产品断言失败。
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
  PUREPACE_IOS_BOOT_TIMEOUT_SECONDS
                           模拟器 boot 有界等待秒数，默认 1200；超限打印 simulator-boot 阶段超时并以 124 退出
  PUREPACE_IOS_UI_MIN_BUDGET_SECONDS
                           UI 腿最小可用预算秒数，默认 300；可用预算低于该值时明确失败
  PUREPACE_IOS_TEST_STEP_BUDGET_SECONDS
                          step 级总预算秒数（CI 由 ios.yml 注入 2700）；未设置/非法时回落 2700
  PUREPACE_IOS_RETRY_RESERVE_SECONDS
                          为 ios.yml 一次 infra 重试预留的余量秒数，默认 900；
                          本次 attempt 预算 = step 预算 − 该余量（默认 1800s，严格小于 2700s）
  PUREPACE_IOS_STEP_STARTED_AT
                          step 起始 epoch 秒；attempt 起点的 step 剩余 ≤ 首次 attempt 预算时，
                          该次 attempt 预算取 step 剩余（重试 attempt 不重复扣余量）
  IOS_WATCHDOG_POLL_SECONDS
                          看门狗轮询粒度秒数，默认 1（只影响轮询频率，不参与超时判定）

退出码:
  0    测试通过，或工程缺失但降级的 swift test 真实通过（输出含 blocked:）
  1    工程存在但真实测试失败，或降级 swift test 失败
  2    参数非法
  124  承载层硬超时（看门狗强制终止），或承载层预算不足（attempt/腿可用预算低于阈值，未起跑）
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

# 预算记账与看门狗抽到可 source 的纯逻辑库（scripts/tests/test-ios-budget.sh 直接单测）。
# shellcheck source=lib/ios-budget.sh
. "${script_dir}/lib/ios-budget.sh"

ios_dir="ios"
project_path="$ios_dir/PurePace.xcodeproj"
spec_path="$ios_dir/project.yml"
derived_data=".build/ios"
scheme="PurePace"
destination="platform=iOS Simulator,name=iPhone 16,OS=18.6"
bundle_id="sh.munk.purepace"

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
timing_log="$log_dir/test-ios-timing.log"
# 承载层分段计时：boot 起点早于 build 结束即证明 boot 与 build-for-testing 并行。
timing_started_at="$(date +%s)"
phase_boot_seconds=0
phase_prep_seconds=0
phase_build_seconds=0
phase_unit_seconds=0
phase_ui_seconds=0
phase_runcore_seconds=0
boot_timeout_seconds="${PUREPACE_IOS_BOOT_TIMEOUT_SECONDS:-1200}"
# 复用标记：1 表示目标设备在持锁且 quiescent 后已是 Booted，直接复用给单测与 UI 两腿。
sim_reused_booted=0
sim_boot_started_at=0
sim_boot_pid=""
xcodebuild_timeout="${IOS_XCODEBUILD_TIMEOUT:-600}"
# 单测腿 / UI 腿各自独立上限（各一份 IOS_XCODEBUILD_TIMEOUT，默认 600s）；
# 实际腿预算再取 min(单腿上界, 本次 attempt 剩余)，不再用「单测已耗时」从 UI 预算里扣减。
unit_budget_cap="$xcodebuild_timeout"
ui_budget_cap="$xcodebuild_timeout"
ui_min_budget="${PUREPACE_IOS_UI_MIN_BUDGET_SECONDS:-300}"
# 预算记账：attempt 预算 = step 预算 − 重试余量（默认 2700 − 900 = 1800，严格小于 45min step 超时），
# 为 ios.yml 的一次 infra 重试留出可判定余量；两个 env 均可覆盖，非法值回落默认。
step_budget_seconds="$(ios_seconds_or_default "${PUREPACE_IOS_TEST_STEP_BUDGET_SECONDS:-}" 2700)"
retry_reserve_seconds="$(ios_seconds_or_default "${PUREPACE_IOS_RETRY_RESERVE_SECONDS:-}" 900)"
step_started_at="${PUREPACE_IOS_STEP_STARTED_AT:-}"
attempt_started_at=0
attempt_budget=""

# attempt 起点的 step 剩余（秒）；PUREPACE_IOS_STEP_STARTED_AT 缺失/非法时输出空串（不约束）。
step_remaining_at_start() {
  case "${step_started_at}" in
    ""|*[!0-9]*) return 0 ;;
  esac
  local now elapsed remaining
  now="$(ios_now_epoch)"
  elapsed=$((now - step_started_at))
  if [ "${elapsed}" -lt 0 ]; then
    elapsed=0
  fi
  remaining=$((step_budget_seconds - elapsed))
  if [ "${remaining}" -lt 0 ]; then
    remaining=0
  fi
  printf '%s' "${remaining}"
}

# 本次 attempt 已用秒数（墙钟差额）。
attempt_elapsed() {
  local now elapsed
  now="$(ios_now_epoch)"
  elapsed=$((now - attempt_started_at))
  if [ "${elapsed}" -lt 0 ]; then
    elapsed=0
  fi
  printf '%s' "${elapsed}"
}

# 本次 attempt 剩余预算（秒）。
attempt_budget_remaining() {
  local left
  left=$((attempt_budget - $(attempt_elapsed)))
  if [ "${left}" -lt 0 ]; then
    left=0
  fi
  printf '%s' "${left}"
}

# UI 腿可用预算：min(UI 单腿上界, 本次 attempt 剩余)。
ui_leg_budget() {
  ios_leg_budget "${ui_budget_cap}" "$(attempt_budget_remaining)"
}

# 承载层预算不足时打印口径行并返回 0（调用方据此以 124 退出）。
budget_insufficient() {
  local scope="$1"
  local available="$2"
  local threshold="$3"
  if ios_budget_short "${available}" "${threshold}"; then
    ios_budget_message "${scope}" "${available}" "${threshold}" "${step_budget_seconds}" "${retry_reserve_seconds}"
    return 0
  fi
  return 1
}

# UI 可用预算低于最小阈值时打印一行并返回 0（调用方据此失败退出 124）。
ui_budget_insufficient() {
  budget_insufficient "UI 腿" "$1" "${ui_min_budget}"
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
  local elapsed=0 holder now mtime age stale started_at
  started_at="$(ios_now_epoch)"
  while :; do
    elapsed=$(( $(ios_now_epoch) - started_at ))
    if [ "${elapsed}" -lt 0 ]; then
      elapsed=0
    fi
    if mkdir "${ios_gate_lock_dir}" 2>/dev/null; then
      printf '%s\n' "$$" > "${ios_gate_lock_dir}/pid"
      ios_gate_lock_held=1
      export PUREPACE_IOS_GATE_LOCK_HELD=1
      trap 'emit_timing; ios_gate_lock_release' EXIT
      echo "[lock] acquired pid=$$ waited=${elapsed}s dir=${ios_gate_lock_dir}"
      return 0
    fi
    holder="$(cat "${ios_gate_lock_dir}/pid" 2>/dev/null || true)"
    now="$(ios_now_epoch)"
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
    if [ "${elapsed}" -ge 1200 ]; then
      echo "[lock] timeout pid=$$ waited=${elapsed}s holder=${holder:-<none>}" >&2
      return 3
    fi
    if [ "${elapsed}" -eq 0 ]; then
      echo "[lock] waiting pid=$$ holder=${holder:-<none>}"
    fi
    sleep 30
  done
}

# 取锁后先有界等待其它 worktree 的 xcodebuild/simctl 归零；有并发时禁止 shutdown/erase。
ios_gate_lock_wait_quiescent() {
  local elapsed=0 others started_at
  started_at="$(ios_now_epoch)"
  while :; do
    elapsed=$(( $(ios_now_epoch) - started_at ))
    if [ "${elapsed}" -lt 0 ]; then
      elapsed=0
    fi
    # 真实设备 WebDriverAgentRunner 常驻且不操作模拟器，不参与模拟器清场互斥。
    others="$(pgrep -fl 'xcodebuild|simctl' 2>/dev/null | grep -v -e 'purepace-ios-gate' -e 'WebDriverAgentRunner' -e "^$$ " -e "^${PPID} " || true)"
    if [ -z "${others}" ]; then
      echo "[lock] quiescent pid=$$ waited=${elapsed}s"
      return 0
    fi
    if [ "${elapsed}" -ge 600 ]; then
      echo "[lock] timeout-quiescent pid=$$ waited=${elapsed}s" >&2
      printf '%s\n' "${others}" >&2
      return 4
    fi
    if [ "${elapsed}" -eq 0 ]; then
      echo "[lock] waiting-quiescent pid=$$"
    fi
    sleep 10
  done
}

simulator_is_booted() {
  [ -n "${sim_udid}" ] && xcrun simctl list devices available 2>/dev/null | grep -F -- "${sim_udid}" | grep -Fq -- "(Booted)"
}

# 取锁并等并发归零后：目标设备已 Booted 则复用（不再无条件 shutdown all），否则清场冷启。
ios_gate_lock_prepare_simulator() {
  ios_gate_lock_wait_quiescent || return $?
  if simulator_is_booted; then
    sim_reused_booted=1
    echo "[sim] reuse booted ${sim_udid}"
    return 0
  fi
  echo "[sim] cold boot ${sim_udid}：清场后重新启动"
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

# 显式 simctl boot（非阻塞）：与随后的 build-for-testing 并行；已 Booted 时该调用返回
# 非零（Unable to boot device in current state）不判失败。
start_simulator_boot() {
  if [ "${sim_reused_booted}" = "1" ]; then
    echo "[boot] reuse booted ${sim_udid} elapsed=0s"
    return 0
  fi
  sim_boot_started_at="$(date +%s)"
  echo "[boot] request ${sim_udid}（与 build-for-testing 并行）"
  ( xcrun simctl boot "${sim_udid}" >/dev/null 2>&1 || true ) &
  sim_boot_pid=$!
}

# 有界等待 boot 就绪：后台 simctl bootstatus 轮询 + 每轮打印 [boot] elapsed=<n>s；
# 超过 PUREPACE_IOS_BOOT_TIMEOUT_SECONDS（默认 1200s）打印 simulator-boot 阶段超时并以 124 退出。
wait_for_simulator_boot() {
  local limit="${boot_timeout_seconds}"
  case "${limit}" in
    ""|*[!0-9]*) limit=1200 ;;
  esac
  if [ "${sim_reused_booted}" = "1" ]; then
    phase_boot_seconds=0
    return 0
  fi
  local started="${sim_boot_started_at}"
  local boot_pid="" elapsed=0 status=0
  xcrun simctl bootstatus "${sim_udid}" >/dev/null 2>&1 &
  boot_pid=$!
  while kill -0 "${boot_pid}" 2>/dev/null; do
    elapsed=$(( $(date +%s) - started ))
    echo "[boot] elapsed=${elapsed}s"
    if [ "${elapsed}" -ge "${limit}" ]; then
      kill -TERM "${boot_pid}" >/dev/null 2>&1 || true
      sleep 2
      kill -KILL "${boot_pid}" >/dev/null 2>&1 || true
      wait "${boot_pid}" >/dev/null 2>&1 || true
      if [ -n "${sim_boot_pid}" ]; then
        wait "${sim_boot_pid}" >/dev/null 2>&1 || true
      fi
      echo "test-ios: 阶段 simulator-boot 超时：${limit}s 内模拟器 ${sim_udid} 未就绪（xcrun simctl bootstatus ${sim_udid}）" >&2
      exit 124
    fi
    sleep 5
  done
  wait "${boot_pid}" || status=$?
  if [ -n "${sim_boot_pid}" ]; then
    wait "${sim_boot_pid}" >/dev/null 2>&1 || true
  fi
  elapsed=$(( $(date +%s) - started ))
  phase_boot_seconds="${elapsed}"
  if [ "${status}" -ne 0 ]; then
    echo "test-ios: 阶段 simulator-boot 失败：模拟器 ${sim_udid} 启动/就绪失败（xcrun simctl bootstatus ${sim_udid}，elapsed=${elapsed}s）" >&2
    exit 1
  fi
  echo "[boot] ready ${sim_udid} elapsed=${elapsed}s"
}

# build-for-testing：一次构建 App + 单测包 + UI Runner，后续两次执行都用
# test-without-building，避免 xcodebuild test 重装 App 把已预置的 TCC 授权清掉。
# 该段与 start_simulator_boot 发起的 boot 并行，故先于 wait_for_simulator_boot 调用。
build_for_testing() {
  mkdir -p "$log_dir"
  local started
  started="$(date +%s)"
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
  phase_build_seconds=$(( $(date +%s) - started ))
}

# 容器清理 → 安装 → 预置定位授权 → 启动预热（设备必须已就绪）。
# TCC 只对已安装 bundle 生效且 simctl uninstall 会清掉它，所以授权必须排在安装之后。
prepare_simulator_for_ui_tests() {
  local started
  started="$(date +%s)"
  mkdir -p "$log_dir"
  # 清理上次运行残留：保证容器为空（History 恰 1 条）并回到首次未授权路径。
  xcrun simctl uninstall "$sim_udid" "$bundle_id" >/dev/null 2>&1 || true

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
  local warmup_started_at=0
  local warmup_elapsed=0
  local warmup_limit=10
  warmup_started_at="$(ios_now_epoch)"
  while :; do
    if ! xcrun simctl spawn "$sim_udid" launchctl list 2>/dev/null | grep -Fq -- "$bundle_id"; then
      break
    fi
    warmup_elapsed=$(( $(ios_now_epoch) - warmup_started_at ))
    if [ "${warmup_elapsed}" -ge "${warmup_limit}" ]; then
      break
    fi
    sleep 1
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
  phase_prep_seconds=$(( $(date +%s) - started ))
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

# 进程级硬超时看门狗（macOS bash 3.2 无 GNU timeout）定义在 scripts/lib/ios-budget.sh：
# 按墙钟差额判定超时（sleep 仅作轮询粒度），超时先 TERM 再 KILL 后返回 124，正常退出透传退出码。

# 单测/UI 两次 xcodebuild test 的公共前置说明：
# 两次调用各自落盘日志（xcodebuild-unit.log / xcodebuild-ui.log），预算按腿独立。
test_with_xcodebuild() {
  # 本次 attempt 预算 = step 预算 − 重试余量；重试 attempt（step 剩余 ≤ 首次预算）取 step 剩余。
  attempt_started_at="$(ios_now_epoch)"
  attempt_budget="$(ios_attempt_budget "${step_budget_seconds}" "${retry_reserve_seconds}" "$(step_remaining_at_start)")"
  if budget_insufficient "本次 attempt" "${attempt_budget}" "${ui_min_budget}"; then
    return 124
  fi
  ios_gate_lock_acquire || exit $?
  sim_udid="$(select_simulator || true)"
  if [ -z "$sim_udid" ]; then
    echo "test-ios: 未找到 iPhone 16 / iOS 18.6 模拟器，无法运行 UI 测试" >&2
    exit 1
  fi
  echo "info: 使用模拟器 ${sim_udid} 注入 CoreLocation 更新"
  # 取锁后先等待其它 worktree 的 xcodebuild/simctl 归零；已 Booted 则复用，否则清场冷启。
  ios_gate_lock_prepare_simulator || exit $?
  # boot 与 build-for-testing 并行：先发起 boot，再构建；构建结束后才有界等待 bootstatus 就绪。
  start_simulator_boot
  build_for_testing
  wait_for_simulator_boot
  prepare_simulator_for_ui_tests
  echo "info: location-source=deterministic(-uiTestLocation)（真实 CoreLocation 由 scripts/verify-ios-sim-runtime.sh 覆盖）"
  # 第一次调用：单元测试（-only-testing:PurePaceTests）；日志与 Executed 摘要先落盘。
  local unit_status=0
  local unit_started
  local unit_budget=""
  unit_budget="$(ios_leg_budget "${unit_budget_cap}" "$(attempt_budget_remaining)")"
  if budget_insufficient "单测腿" "${unit_budget}" 1; then
    return 124
  fi
  unit_started="$(date +%s)"
  echo "info: xcodebuild test-without-building -only-testing:PurePaceTests -scheme ${scheme} -destination '${destination}'（预算 ${unit_budget}s，attempt 剩余 ${attempt_budget}s，日志 ${unit_log}）"
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
  phase_unit_seconds=$(( $(date +%s) - unit_started ))
  cat "$unit_log" 2>/dev/null || true
  # 单测摘要必须先于 UI 调用输出：UI 失败不得覆盖单测结论。
  echo "info: PurePaceTests 摘要（先于 UI 落盘：${unit_log}）："
  grep -E "Executed [0-9]+ tests|Test Case .*(started|passed|failed)" "$unit_log" 2>/dev/null | tail -n 10 || true
  if [ "$unit_status" -eq 124 ]; then
    # 归口复用 ios-budget.sh 的同一判定：同日志已出现 failed 用例时不得再写成承载层预算。
    ios_timeout_classification_message "单测腿" "$unit_log" "" "$unit_budget" \
      "attempt 预算 ${attempt_budget}s = step 预算 ${step_budget_seconds}s − 重试余量 ${retry_reserve_seconds}s"
    return 124
  fi
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
  # UI 腿分段执行（拆分≠放宽，见 AGENTS「测试稳定性约定」）：
  # 证据 = CI run 43142574712 attempt1 在 600s 看门狗硬超时时 13 条 UI 用例仍未跑完
  # （逐用例墙钟合计 ≈537s + 13 次 app 冷启/setup 开销已结构性顶到单腿上界）。
  # 因此把 UI 目标拆成两次 xcodebuild 调用：每次仍 ≤ IOS_XCODEBUILD_TIMEOUT(600)、
  # 仍带同一组测试执行预算参数、仍由 -uiTestLocation 确定性源驱动；
  # 阈值 / 用例数 / 断言强度 / 重试策略全部不变，无 continue-on-error、无腿被删。
  local ui_status=0
  ui_call() {
    local group="$1"
    local group_log="$2"
    shift 2
    local group_budget=""
    group_budget="$(ios_leg_budget "${ui_budget_cap}" "$(attempt_budget_remaining)")"
    if ui_budget_insufficient "${group_budget}"; then
      return 124
    fi
    # test-without-building 仍可能重装宿主 App，从而清掉 TCC 授权；每次调用前重装 Runner 并
    # 重申「始终允许」，保证 ac-tel-always 的 authorizedAlways（rawValue 3）可机器成立。
    if [ -d "$ui_runner_path" ]; then
      xcrun simctl install "$sim_udid" "$ui_runner_path" >/dev/null 2>&1 || true
    fi
    echo "info: 阶段 simulator-privacy：UI（${group}）前重申定位授权（location + location-always ${bundle_id}）"
    if ! xcrun simctl privacy "$sim_udid" grant location "$bundle_id" >/dev/null 2>&1; then
      echo "test-ios: 阶段 simulator-privacy 失败：simctl privacy grant location ${bundle_id}（模拟器 ${sim_udid}）" >&2
      return 1
    fi
    if ! xcrun simctl privacy "$sim_udid" grant location-always "$bundle_id" >/dev/null 2>&1; then
      echo "test-ios: 阶段 simulator-privacy 失败：simctl privacy grant location-always ${bundle_id}（模拟器 ${sim_udid}）" >&2
      return 1
    fi
    local tcc_stop_file="${TMPDIR:-/tmp}/purepace-tcc-refresh.$$"
    rm -f "$tcc_stop_file"
    refresh_location_always_until_stopped "$tcc_stop_file" &
    local tcc_refresher_pid=$!
    local only_args=()
    local target=""
    for target in "$@"; do
      only_args+=("-only-testing:${target}")
    done
    local group_started=0
    local group_status=0
    local group_elapsed=0
    group_started="$(date +%s)"
    echo "info: xcodebuild test-without-building ${only_args[*]} -scheme ${scheme} -destination '${destination}'（预算 ${group_budget}s，日志 ${group_log}）"
    run_with_watchdog "${group_budget}" "${group_log}" \
      xcodebuild test-without-building \
      -project "$project_path" \
      -scheme "$scheme" \
      -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' \
      -derivedDataPath "$derived_data" \
      ${only_args[@]+"${only_args[@]}"} \
      -test-timeouts-enabled YES \
      -default-test-execution-time-allowance 300 \
      -maximum-test-execution-time-allowance 540 \
      CODE_SIGNING_ALLOWED=NO || group_status=$?
    group_elapsed=$(( $(date +%s) - group_started ))
    phase_ui_seconds=$(( phase_ui_seconds + group_elapsed ))
    touch "$tcc_stop_file"
    wait "$tcc_refresher_pid" 2>/dev/null || true
    rm -f "$tcc_stop_file"
    cat "$group_log" 2>/dev/null || true
    echo "info: UI 腿（${group}）摘要（日志 ${group_log}）："
    grep -E "Executed [0-9]+ tests|Test Case .*(started|passed|failed)" "$group_log" 2>/dev/null | tail -n 10 || true
    if [ "$group_status" -eq 124 ]; then
      # 与看门狗同一分类：UI 日志里有 failed 用例 → 产品用例失败；没有才归口承载层预算。
      ios_timeout_classification_message "UI 腿（${group}）" "$group_log" "${group_elapsed}" "${group_budget}" \
        "attempt 预算 ${attempt_budget}s = step 预算 ${step_budget_seconds}s − 重试余量 ${retry_reserve_seconds}s"
    elif [ "$group_status" -ne 0 ]; then
      echo "test-ios: 阶段 xcodebuild-ui（${group}）失败：xcodebuild test 退出 ${group_status}（模拟器 ${sim_udid}）" >&2
    fi
    return "$group_status"
  }
  # 分段 1：跑步主流程（6 条）。任一分段失败即停，保留原始退出码，不掩盖为成功。
  ui_call "runflow" "$ui_log" "PurePaceUITests/RunFlowUITests" || ui_status=$?
  if [ "$ui_status" -eq 0 ]; then
    # 分段 2：取证 / AX5 / 音频自检（7 条）。独立调用，自带容器与授权前置。
    ui_call "evidence" "$log_dir/xcodebuild-ui-2.log" \
      "PurePaceUITests/EvidenceCaptureUITests" \
      "PurePaceUITests/Ax5ScrollAuditCounterexampleTests" \
      "PurePaceUITests/MusicSourceSelfCheckUITests" || ui_status=$?
  fi
  return "$ui_status"
}

# RunCore 是纯逻辑 SwiftPM 包，两个分支都真实执行；包缺失时显式 blocked 不伪造成功。
test_with_run_core() {
  if [ ! -d ios/RunCore ]; then
    echo "blocked: 缺 ios/RunCore，跳过 RunCore 的 swift test"
    return 0
  fi
  local runcore_started
  runcore_started="$(date +%s)"
  echo "info: 执行 swift test --package-path ios/RunCore"
  if swift test --package-path ios/RunCore; then
    phase_runcore_seconds=$(( $(date +%s) - runcore_started ))
    echo "info: RunCore SwiftPM 测试完成"
  else
    status=$?
    phase_runcore_seconds=$(( $(date +%s) - runcore_started ))
    echo "test-ios: RunCore 的 swift test 失败（退出码 ${status}）" >&2
    return "$status"
  fi
}

# 分段计时只落一行并追加到 .build/logs/test-ios-timing.log；EXIT trap 与降级分支都经此输出，
# 用 timing_emitted 保证每次运行只写一行。
timing_emitted=0
emit_timing() {
  if [ "${timing_emitted}" = "1" ]; then
    return 0
  fi
  timing_emitted=1
  local total
  total=$(( $(date +%s) - timing_started_at ))
  local line="[timing] boot=${phase_boot_seconds}s prep=${phase_prep_seconds}s build=${phase_build_seconds}s unit=${phase_unit_seconds}s ui=${phase_ui_seconds}s runcore=${phase_runcore_seconds}s total=${total}s"
  echo "$line"
  mkdir -p "$log_dir"
  printf '%s\n' "$line" >> "$timing_log"
  echo "info: 分段计时已追加写入 ${timing_log}"
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
emit_timing
