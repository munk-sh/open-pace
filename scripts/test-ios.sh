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
  - 分支 B（工程不可用）：输出 blocked: 明确缺失原因（xcodegen / ios/PurePace.xcodeproj），
    降级真实执行 swift test --package-path ios/Core，并保留真实 Executed 用例数与失败数。

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

# 版本派生：MARKETING_VERSION 只能来自根 VERSION（写 ios/Config/Version.xcconfig）。
if [ -f scripts/sync-ios-version.sh ]; then
  bash scripts/sync-ios-version.sh
fi

test_with_xcodebuild() {
  echo "info: xcodebuild test -scheme $scheme -destination '$destination'（派生数据 ${derived_data}）"
  xcodebuild test \
    -project "$project_path" \
    -scheme "$scheme" \
    -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' \
    -derivedDataPath "$derived_data" \
    CODE_SIGNING_ALLOWED=NO
}

if [ -d "$project_path" ]; then
  test_with_xcodebuild
  exit 0
fi

if [ -f "$spec_path" ] && command -v xcodegen >/dev/null 2>&1; then
  echo "info: 缺 ${project_path}，使用 xcodegen 从 $spec_path 生成工程"
  xcodegen generate --spec "$spec_path" --project "$ios_dir"
  test_with_xcodebuild
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
