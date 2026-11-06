#!/usr/bin/env bash
# 真实构建 iOS 空壳：同步 VERSION → 生成工程 → xcodebuild 构建模拟器 .app。
set -euo pipefail

usage() {
  cat <<'EOF'
用法: scripts/build-ios.sh [--help]

用 XcodeGen 从 ios/project.yml 生成 ios/PurePace.xcodeproj，
再对 iPhone 16 (iOS 18.6) 模拟器执行无签名的 xcodebuild build。

选项:
  -h, --help   显示本帮助并退出 0

环境变量:
  IOS_DESTINATION        覆盖默认模拟器 destination
  IOS_DERIVED_DATA_PATH  覆盖默认 DerivedData 目录

退出码:
  0  构建成功并产出 PurePace.app
  1  xcodegen 缺失、生成失败或构建失败
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
    echo "build-ios: 未知参数 '$1'（使用 --help 查看用法）" >&2
    exit 2
    ;;
esac

if [ "$#" -gt 1 ]; then
  echo "build-ios: 只接受一个参数（使用 --help 查看用法）" >&2
  exit 2
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
cd "$repo_root"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "build-ios: 缺少 xcodegen；本脚本不手写 .xcodeproj，请先安装 xcodegen" >&2
  exit 1
fi

bash scripts/sync-ios-version.sh
xcodegen generate --spec ios/project.yml

destination="${IOS_DESTINATION:-platform=iOS Simulator,id=B3F00298-E08A-41E0-876E-6E8A75C730FD}"
derived_data="${IOS_DERIVED_DATA_PATH:-$repo_root/ios/.build/DerivedData}"

echo "build-ios: destination=$destination"
echo "build-ios: derivedData=$derived_data"

xcodebuild build \
  -project ios/PurePace.xcodeproj \
  -scheme PurePace \
  -destination "$destination" \
  -derivedDataPath "$derived_data" \
  CODE_SIGNING_ALLOWED=NO

app_path="$(find "$derived_data/Build/Products" -maxdepth 3 -type d -name 'PurePace.app' -print -quit 2>/dev/null || true)"
if [ -z "$app_path" ]; then
  echo "build-ios: 构建完成但未找到 PurePace.app" >&2
  exit 1
fi

printf 'build-ios OK: %s\n' "$app_path"
