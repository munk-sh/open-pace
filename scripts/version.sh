#!/usr/bin/env bash
# 版本号读取的唯一入口：读取仓库根 VERSION 文件并输出。
# 任何 README、构建脚本、工程配置需要版本号时，都必须经由本脚本，不得写死。
set -euo pipefail

usage() {
  cat <<'EOF'
用法: scripts/version.sh [--help]

读取仓库根 VERSION 文件并输出其内容（x.y.z，无 v 前缀）。
这是仓库内获取版本号的唯一入口；脚本不接受版本号参数，也不缓存结果。

选项:
  -h, --help   显示本帮助并退出 0

退出码:
  0  输出成功
  1  VERSION 缺失、为空或格式非法
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
    echo "version: 未知参数 '$1'（使用 --help 查看用法）" >&2
    exit 2
    ;;
esac

if [ "$#" -gt 1 ]; then
  echo "version: 只接受一个参数（使用 --help 查看用法）" >&2
  exit 2
fi

# 以脚本自身位置推导仓库根，保证在任意 cwd 下运行结果一致。
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
version_file="$repo_root/VERSION"

if [ ! -f "$version_file" ]; then
  echo "version: 缺少 $version_file" >&2
  exit 1
fi

version="$(tr -d '\r\n' < "$version_file")"

if [ -z "$version" ]; then
  echo "version: $version_file 为空" >&2
  exit 1
fi

if ! printf '%s' "$version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  echo "version: $version_file 内容不是 x.y.z 格式: $version" >&2
  exit 1
fi

printf '%s\n' "$version"
