#!/usr/bin/env bash
# 将隐私政策真源逐字节同步到 App bundle（ios/PurePace/Resources/）。
# 真源：docs/privacy/privacy-policy-zh-Hans.md；产物仅供打包，禁止手改。
# 幂等：内容未变化时不重写文件。
set -euo pipefail

usage() {
  cat <<'EOF'
用法: scripts/sync-privacy-policy.sh [--help]

把 docs/privacy/privacy-policy-zh-Hans.md 逐字节复制为
ios/PurePace/Resources/privacy-policy-zh-Hans.md（App bundle 内正文副本）。

选项:
  -h, --help   显示本帮助并退出 0

退出码:
  0  文件已是最新或写入成功
  1  真源不可读或写入失败
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
    echo "sync-privacy-policy: 未知参数 '$1'（使用 --help 查看用法）" >&2
    exit 2
    ;;
esac

if [ "$#" -gt 1 ]; then
  echo "sync-privacy-policy: 只接受一个参数（使用 --help 查看用法）" >&2
  exit 2
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
cd "$repo_root"

source_file="docs/privacy/privacy-policy-zh-Hans.md"
target="ios/PurePace/Resources/privacy-policy-zh-Hans.md"

if [ ! -s "$source_file" ]; then
  echo "sync-privacy-policy: 缺少政策真源 $source_file" >&2
  exit 1
fi

mkdir -p "$(dirname "$target")"

if [ -f "$target" ] && cmp -s "$source_file" "$target"; then
  printf 'sync-privacy-policy: 已是最新（%s）\n' "$target"
else
  cp "$source_file" "$target"
  printf 'sync-privacy-policy: 已写入 %s\n' "$target"
fi
