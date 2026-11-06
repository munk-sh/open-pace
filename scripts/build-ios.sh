#!/usr/bin/env bash
# iOS 构建入口：app 工程可用时走 xcodebuild，缺失时显式 blocked 并降级到 ios/Core 的 SwiftPM 构建。
# 分支只由 ios/PurePace.xcodeproj 是否存在（或 project.yml + 本机 xcodegen 可生成）决定，
# 后续 iOS 空壳工程落地后无需修改本脚本或门禁定义即可自动切到 xcodebuild。
set -euo pipefail

usage() {
  cat <<'EOF'
用法: scripts/build-ios.sh [--help]

构建 iOS 侧产物，按工程可用性自动选择分支：
  - 分支 A（工程可用）：ios/PurePace.xcodeproj 存在，或 ios/project.yml 存在且本机有
    xcodegen 可生成时，执行
    xcodebuild build -scheme PurePace -destination 'platform=iOS Simulator,name=iPhone 16'，
    派生数据写入 .build/ios，并在成功时打印真实 .app 产物路径。
  - 分支 B（工程不可用）：输出 blocked: 明确缺失原因（xcodegen / ios/PurePace.xcodeproj），
    降级真实执行 swift build --package-path ios/Core，并以该命令退出码为准；
    本分支绝不输出 BUILD SUCCEEDED。

选项:
  -h, --help   显示本帮助并退出 0

退出码:
  0  构建成功，或工程缺失但降级的 swift build 真实成功（输出含 blocked:）
  1  工程存在但真实构建失败，或降级 swift build 失败
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

# 以脚本自身位置推导仓库根，保证在任意 cwd 下运行结果一致。
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
cd "$repo_root"

ios_dir="ios"
project_path="$ios_dir/PurePace.xcodeproj"
spec_path="$ios_dir/project.yml"
derived_data=".build/ios"
scheme="PurePace"
destination="platform=iOS Simulator,name=iPhone 16"

build_with_xcodebuild() {
  echo "info: xcodebuild build -scheme $scheme -destination '$destination'（派生数据 $derived_data）"
  xcodebuild build \
    -project "$project_path" \
    -scheme "$scheme" \
    -destination 'platform=iOS Simulator,name=iPhone 16' \
    -derivedDataPath "$derived_data" \
    CODE_SIGNING_ALLOWED=NO

  app_path="$(find "$derived_data/Build/Products" -type d -name '*.app' -print -quit 2>/dev/null || true)"
  if [ -z "$app_path" ]; then
    echo "build-ios: xcodebuild 报告成功但未找到 .app 产物" >&2
    exit 1
  fi
  echo "info: .app 产物 $app_path"
}

if [ -d "$project_path" ]; then
  build_with_xcodebuild
  exit 0
fi

if [ -f "$spec_path" ] && command -v xcodegen >/dev/null 2>&1; then
  echo "info: 缺 $project_path，使用 xcodegen 从 $spec_path 生成工程"
  xcodegen generate --spec "$spec_path" --project "$ios_dir"
  build_with_xcodebuild
  exit 0
fi

if [ ! -f "$spec_path" ] && ! command -v xcodegen >/dev/null 2>&1; then
  missing_reason="缺 xcodegen 且缺 $spec_path"
elif [ ! -f "$spec_path" ]; then
  missing_reason="缺 $spec_path（xcodegen 已安装，但没有可供生成的 spec）"
elif ! command -v xcodegen >/dev/null 2>&1; then
  missing_reason="缺 xcodegen（有 $spec_path，但本机无法生成工程）"
else
  missing_reason="缺 xcodegen 可用的 $project_path"
fi

echo "blocked: $missing_reason，无法生成或使用 $project_path，跳过 xcodebuild"
echo "info: 降级执行 swift build --package-path ios/Core"
if swift build --package-path ios/Core; then
  echo "info: 降级 SwiftPM 构建完成（未产出 iOS .app）"
else
  status=$?
  echo "build-ios: 降级 swift build 失败（退出码 $status）" >&2
  exit "$status"
fi
