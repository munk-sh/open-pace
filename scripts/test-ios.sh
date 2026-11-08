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
    测试前 boot iPhone 16 / iOS 18.6 模拟器并以 xcrun simctl location start --speed=3 --interval=1
    注入 ≥20 km 直线航点驱动真实 CoreLocation，测试结束在 trap 中 clear。
  - 分支 B（工程不可用）：输出 blocked: 明确缺失原因（xcodegen / ios/PurePace.xcodeproj），
    降级真实执行 swift test --package-path ios/Core，并保留真实 Executed 用例数与失败数。
  - 两个分支都会追加执行 swift test --package-path ios/RunCore（跑步域纯逻辑包）；
    ios/RunCore 缺失时打印 blocked: 并继续，RunCore 测试失败时脚本非零退出。

选项:
  -h, --help   显示本帮助并退出 0

退出码:
  0  测试通过，或工程缺失但降级的 swift test 真实通过（输出含 blocked:）
  1  工程存在但真实测试失败，或降级 swift test 失败
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

# XCUITest 的真实定位链路：固定 iPhone 16 / iOS 18.6，boot 后注入 ≥20 km 直线航点，
# 速率 3 m/s、间隔 1 s；测试结束在 trap 中 clear，不用 launch-arg 假流替代。
sim_udid=""
location_started=0
cleanup_location() {
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

start_location_injection() {
  sim_udid="$(select_simulator || true)"
  if [ -z "$sim_udid" ]; then
    echo "test-ios: 未找到 iPhone 16 / iOS 18.6 模拟器，无法注入真实定位" >&2
    exit 1
  fi
  echo "info: 使用模拟器 $sim_udid 注入 CoreLocation 更新"
  if ! xcrun simctl bootstatus "$sim_udid" -b >/dev/null 2>&1; then
    echo "test-ios: 模拟器 $sim_udid 启动失败" >&2
    exit 1
  fi
  # 清理上次运行残留：保证容器为空（History 恰 1 条）并回到首次未授权路径。
  xcrun simctl uninstall "$sim_udid" "$bundle_id" >/dev/null 2>&1 || true
  xcrun simctl location "$sim_udid" clear >/dev/null 2>&1 || true
  location_started=1
  if ! xcrun simctl location "$sim_udid" start --speed=3 --interval=1 37.3349,-122.0090 37.5200,-122.0090 >/dev/null 2>&1; then
    echo "test-ios: xcrun simctl location start 注入失败" >&2
    exit 1
  fi
}

test_with_xcodebuild() {
  start_location_injection
  echo "info: xcodebuild test -scheme $scheme -destination '$destination'（派生数据 ${derived_data}）"
  xcodebuild test \
    -project "$project_path" \
    -scheme "$scheme" \
    -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' \
    -derivedDataPath "$derived_data" \
    CODE_SIGNING_ALLOWED=NO
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
