#!/usr/bin/env bash
# 从仓库根 VERSION 生成 ios/Config/Version.xcconfig（MARKETING_VERSION 唯一来源）。
# 幂等：内容未变化时不重写文件。
set -euo pipefail

usage() {
  cat <<'EOF'
用法: scripts/sync-ios-version.sh [--help]

读取仓库根 VERSION，并写入 ios/Config/Version.xcconfig：
  MARKETING_VERSION = <VERSION>
该文件是 Xcode 工程 MARKETING_VERSION 的唯一来源，禁止手改；
project.yml 通过 configFiles 引用它，版本号不写进 project.yml 或源码。

选项:
  -h, --help   显示本帮助并退出 0

退出码:
  0  文件已是最新或写入成功
  1  VERSION 不可读或写入失败
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
    echo "sync-ios-version: 未知参数 '$1'（使用 --help 查看用法）" >&2
    exit 2
    ;;
esac

if [ "$#" -gt 1 ]; then
  echo "sync-ios-version: 只接受一个参数（使用 --help 查看用法）" >&2
  exit 2
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
cd "$repo_root"

version="$(bash scripts/version.sh)"
target="ios/Config/Version.xcconfig"
mkdir -p "$(dirname "$target")"

tmp="$(mktemp "${target}.XXXXXX")"
trap 'rm -f "$tmp"' EXIT
{
  printf '// 由 scripts/sync-ios-version.sh 从仓库根 VERSION 生成；请勿手改。\n'
  printf 'MARKETING_VERSION = %s\n' "$version"
} > "$tmp"

if [ -f "$target" ] && cmp -s "$tmp" "$target"; then
  printf 'sync-ios-version: 已是最新（%s）\n' "$version"
else
  mv "$tmp" "$target"
  trap - EXIT
  printf 'sync-ios-version: 已写入 %s（%s）\n' "$target" "$version"
fi
