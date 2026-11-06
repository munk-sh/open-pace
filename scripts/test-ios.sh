#!/usr/bin/env bash
# 真实运行 iOS 空壳测试：同步 VERSION → 生成工程 → XCTest + XCUITest。
# 测试在 iPhone 16 (iOS 18.6) 模拟器上执行，统一关闭签名。
set -euo pipefail

usage() {
  cat <<'EOF'
用法: scripts/test-ios.sh [--help]

用 XcodeGen 从 ios/project.yml 生成 ios/PurePace.xcodeproj，
再对 iPhone 16 (iOS 18.6) 模拟器执行 xcodebuild test，
scheme PurePace 同时运行 PurePaceTests（XCTest）与 PurePaceUITests（XCUITest）。

选项:
  -h, --help   显示本帮助并退出 0

环境变量:
  IOS_DESTINATION        覆盖默认模拟器 destination
  IOS_DERIVED_DATA_PATH  覆盖默认 DerivedData 目录
  IOS_ONLY_TESTING       覆盖 -only-testing 目标（默认整个 scheme）

退出码:
  0  全部测试通过
  1  xcodegen 缺失、生成失败或测试失败
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

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
cd "$repo_root"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "test-ios: 缺少 xcodegen；本脚本不手写 .xcodeproj，请先安装 xcodegen" >&2
  exit 1
fi

bash scripts/sync-ios-version.sh
xcodegen generate --spec ios/project.yml

destination="${IOS_DESTINATION:-platform=iOS Simulator,id=B3F00298-E08A-41E0-876E-6E8A75C730FD}"
derived_data="${IOS_DERIVED_DATA_PATH:-$repo_root/ios/.build/DerivedData}"
only_testing="${IOS_ONLY_TESTING:-}"

echo "test-ios: destination=$destination"
echo "test-ios: derivedData=$derived_data"

if [ -n "$only_testing" ]; then
  xcodebuild test \
    -project ios/PurePace.xcodeproj \
    -scheme PurePace \
    -destination "$destination" \
    -derivedDataPath "$derived_data" \
    -only-testing:"$only_testing" \
    CODE_SIGNING_ALLOWED=NO
else
  xcodebuild test \
    -project ios/PurePace.xcodeproj \
    -scheme PurePace \
    -destination "$destination" \
    -derivedDataPath "$derived_data" \
    CODE_SIGNING_ALLOWED=NO
fi

echo "test-ios OK"
