#!/usr/bin/env bash
# iOS 测试入口：先由根 VERSION 同步 xcconfig，工程可用时走 xcodegen + xcodebuild test
# 真跑 XCTest/XCUITest，缺失时显式 blocked 并降级到 ios/Core 的 swift test，保留真实用例数。
set -euo pipefail

usage() {
  cat <<'EOF'
用法: scripts/test-ios.sh [--help]

测试 iOS 侧产物，按工程可用性自动选择分支：
  - 分支 A（工程可用）：先执行 scripts/sync-ios-version.sh 由根 VERSION 生成
    ios/Config/Version.xcconfig；ios/PurePace.xcodeproj 存在，或 ios/project.yml
    存在且本机有 xcodegen 可从 spec 生成工程时，执行
    xcodebuild test -scheme PurePace -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6'，
    派生数据写入 .build/ios，scheme 同时运行 PurePaceTests（XCTest）与 PurePaceUITests（XCUITest）。
    测试前按固定顺序准备模拟器状态：bootstatus 等待设备可用 → simctl uninstall 清容器 →
    构建并安装 App → simctl privacy grant location 预置定位授权（授权只对已安装 bundle 生效，
    且卸载会清掉 TCC，故必须在安装之后）→ simctl launch/terminate 启动预热 →
    每秒一次 xcrun simctl location <udid> set <lat>,<lon> 直线推进注入真实 CoreLocation
    （不用 start 路线回放：hosted runner 上实测不投递样本），测试结束在 trap 中停止循环并 clear。
    xcodebuild test 带测试执行预算（-test-timeouts-enabled / -default-test-execution-time-allowance /
    -maximum-test-execution-time-allowance）与进程级硬超时（bash 看门狗，不依赖 GNU timeout），
    单次 attempt 静默等待 ≤600s；超时后非零退出并打印超时阶段与已执行的测试摘要。
  - 分支 B（工程不可用）：输出 blocked: 明确缺失原因（xcodegen / ios/PurePace.xcodeproj），
    降级真实执行 swift test --package-path ios/Core，并保留真实 Executed 用例数与失败数。
  - 两个分支都会追加执行 swift test --package-path ios/RunCore（跑步域纯逻辑包）；
    ios/RunCore 缺失时打印 blocked: 并继续，RunCore 测试失败时脚本非零退出。

选项:
  -h, --help   显示本帮助并退出 0

环境变量:
  IOS_XCODEBUILD_TIMEOUT  xcodebuild test 的硬超时秒数，默认 600（≤600，压住 AX 初始化静默等待）

退出码:
  0    测试通过，或工程缺失但降级的 swift test 真实通过（输出含 blocked:）
  1    工程存在但真实测试失败，或降级 swift test 失败
  2    参数非法
  124  xcodebuild test 触发硬超时（看门狗已强制终止）
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

# XCUITest 的真实定位链路：固定 iPhone 16 / iOS 18.6；bootstatus 等待设备完全可用，
# 卸载清容器 → 构建安装 App → simctl privacy 预置定位授权 → 启动预热 → 注入航点，
# 最后带硬超时跑 xcodebuild test。测试结束在 trap 中 clear，不用 launch-arg 假流替代。
sim_udid=""
location_started=0
location_pid=""
app_path="$derived_data/Build/Products/Debug-iphonesimulator/PurePace.app"
log_dir=".build/logs"
xcodebuild_log="$log_dir/xcodebuild-test.log"
xcodebuild_timeout="${IOS_XCODEBUILD_TIMEOUT:-600}"
cleanup_location() {
  if [ -n "$location_pid" ]; then
    kill -TERM "$location_pid" >/dev/null 2>&1 || true
    wait "$location_pid" >/dev/null 2>&1 || true
    location_pid=""
  fi
  if [ "$location_started" -eq 1 ] && [ -n "$sim_udid" ]; then
    xcrun simctl location "$sim_udid" clear >/dev/null 2>&1 || true
  fi
}
trap cleanup_location EXIT

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
    echo "test-ios: 未找到 iPhone 16 / iOS 18.6 模拟器，无法注入真实定位" >&2
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

  echo "info: 阶段 xcodebuild-build：构建 App 供安装与授权（派生数据 ${derived_data}）"
  if ! xcodebuild build \
    -project "$project_path" \
    -scheme "$scheme" \
    -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' \
    -derivedDataPath "$derived_data" \
    CODE_SIGNING_ALLOWED=NO; then
    echo "test-ios: 阶段 xcodebuild-build 失败：构建 App 失败（模拟器 ${sim_udid}）" >&2
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

  echo "info: 阶段 simulator-privacy：预置定位授权（simctl privacy grant location ${bundle_id}）"
  if ! xcrun simctl privacy "$sim_udid" grant location "$bundle_id" >/dev/null 2>&1; then
    echo "test-ios: 阶段 simulator-privacy 失败：simctl privacy grant location ${bundle_id}（模拟器 ${sim_udid}）" >&2
    exit 1
  fi

  echo "info: 阶段 simulator-warmup：启动并终止 App 一次完成预热"
  if ! xcrun simctl launch "$sim_udid" "$bundle_id" >/dev/null 2>&1; then
    echo "test-ios: 阶段 simulator-warmup 失败：simctl launch ${bundle_id}（模拟器 ${sim_udid}）" >&2
    exit 1
  fi
  if ! xcrun simctl terminate "$sim_udid" "$bundle_id" >/dev/null 2>&1; then
    echo "test-ios: 阶段 simulator-warmup 失败：simctl terminate ${bundle_id}（模拟器 ${sim_udid}）" >&2
    exit 1
  fi
}

# 确定性真实定位注入：每秒一次 `simctl location <udid> set` 沿直线推进。
# hosted runner 上 `simctl location start --speed --interval` 虽 exit 0 却不投递样本（见
# .munk/runs/run_intake_c3e9dcf5599c9324/root-cause.md），改用逐秒 set 让 CoreLocation
# 持续产生离散更新；循环在 trap 中停止并 clear，保留真实 CoreLocation 链路。
start_location_injection() {
  xcrun simctl location "$sim_udid" clear >/dev/null 2>&1 || true
  location_started=1
  # 基准坐标 37.334900,-122.009000；纬度每秒 +0.000090 度（约 10 m/s）。
  local base_lon="-122.009000"
  local lat_micro=37334900
  local step_micro=90
  local lat_int=$((lat_micro / 1000000))
  local lat_frac=$((lat_micro % 1000000))
  local coord=""
  printf -v coord '%d.%06d,%s' "$lat_int" "$lat_frac" "$base_lon"
  if ! xcrun simctl location "$sim_udid" set "$coord" >/dev/null 2>&1; then
    echo "test-ios: 阶段 simulator-location 失败：xcrun simctl location set ${coord} 注入失败（模拟器 ${sim_udid}）" >&2
    exit 1
  fi
  echo "info: location-injection udid=${sim_udid} start=${coord} step_lat_deg=0.000090 interval=1s"
  # 后台循环：每秒推进坐标；上限 1200 次（20 分钟）覆盖整个测试窗口并保证有界退出。
  (
    local tick=0
    while [ "$tick" -lt 1200 ]; do
      sleep 1
      tick=$((tick + 1))
      lat_micro=$((lat_micro + step_micro))
      lat_int=$((lat_micro / 1000000))
      lat_frac=$((lat_micro % 1000000))
      printf -v coord '%d.%06d,%s' "$lat_int" "$lat_frac" "$base_lon"
      xcrun simctl location "$sim_udid" set "$coord" >/dev/null 2>&1 || true
    done
  ) &
  location_pid=$!
}

# App 侧定位诊断（仅模拟器，DEBUG/测试路径）：把授权状态与样本计数写入 App 容器
# Documents/location-diagnostics.log；测试结束后回读到脚本日志，供失败取证。
dump_location_diagnostics() {
  local container=""
  local diag_file=""
  container="$(xcrun simctl get_app_container "$sim_udid" "$bundle_id" data 2>/dev/null || true)"
  if [ -z "$container" ]; then
    echo "info: location-diagnostics: 无可读 App 容器（模拟器 ${sim_udid}）"
    return 0
  fi
  diag_file="$container/Documents/location-diagnostics.log"
  if [ -f "$diag_file" ]; then
    echo "info: location-diagnostics: ${diag_file}（udid=${sim_udid}）"
    cat "$diag_file" 2>/dev/null || true
  else
    echo "info: location-diagnostics: 未找到 ${diag_file}（App 可能在测试前被卸载或未启动）"
  fi
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

test_with_xcodebuild() {
  wait_for_simulator_boot
  prepare_simulator_for_ui_tests
  start_location_injection
  echo "info: xcodebuild test -scheme $scheme -destination '$destination'（硬超时 ${xcodebuild_timeout}s，日志 ${xcodebuild_log}）"
  local xcodebuild_status=0
  run_with_watchdog "$xcodebuild_timeout" "$xcodebuild_log" \
    xcodebuild test \
    -project "$project_path" \
    -scheme "$scheme" \
    -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' \
    -derivedDataPath "$derived_data" \
    -test-timeouts-enabled YES \
    -default-test-execution-time-allowance 300 \
    -maximum-test-execution-time-allowance 540 \
    CODE_SIGNING_ALLOWED=NO || xcodebuild_status=$?
  cat "$xcodebuild_log" 2>/dev/null || true
  dump_location_diagnostics
  if [ "$xcodebuild_status" -eq 124 ]; then
    echo "test-ios: 阶段 xcodebuild-test 失败：超过 ${xcodebuild_timeout}s 硬超时被强制终止（模拟器 ${sim_udid}）" >&2
  elif [ "$xcodebuild_status" -ne 0 ]; then
    echo "test-ios: 阶段 xcodebuild-test 失败：xcodebuild test 退出 ${xcodebuild_status}（模拟器 ${sim_udid}）" >&2
  fi
  return "$xcodebuild_status"
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
