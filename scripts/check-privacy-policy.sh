#!/usr/bin/env bash
# 隐私政策正文真源断言 + 沙箱反例：
#   1) 真源 docs/privacy/privacy-policy-zh-Hans.md 覆盖必需条目与关键词；
#   2) App bundle 副本与真源逐字节一致（漂移即判红）；
#   3) 反例不自证：删掉「撤回同意 / 存储与保留 / 采集项」任一必需条目后，
#      对副本重跑同一断言必须判红；未改动副本必须先判绿。
set -euo pipefail

usage() {
  cat <<'EOF'
用法: scripts/check-privacy-policy.sh [--help]

校验：
  - docs/privacy/privacy-policy-zh-Hans.md 存在且覆盖采集项 / 用途 / 权限清单 /
    存储与保留 / 共享 / 删除 / 撤回同意 / 未成年人 / 联系方式 / 生效日期；
  - 逐条命中必需关键词，且不含肯定式虚假采集声明；
  - ios/PurePace/Resources/privacy-policy-zh-Hans.md 与真源逐字节一致；
  - 沙箱反例：删除必需条目后同一断言必须判红（未改动副本先判绿）。

选项:
  -h, --help   显示本帮助并退出 0

退出码:
  0  全部通过
  1  断言失败
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
    echo "check-privacy-policy: 未知参数 '$1'（使用 --help 查看用法）" >&2
    exit 2
    ;;
esac

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
cd "$repo_root"

source_file="docs/privacy/privacy-policy-zh-Hans.md"
bundle_file="ios/PurePace/Resources/privacy-policy-zh-Hans.md"

required_sections="采集项 用途 权限清单 存储与保留 共享 删除 撤回同意 未成年人 联系方式 生效日期"
required_keywords="定位坐标 时间戳 距离 配速 分段 不涉及账号 不涉及通讯录 不涉及广告标识 本机 导出 GPX TCX 分享 使用期间 后台 通知 音频播放 语音播报 仅本机 沙盒 无账号 无云同步 不上传服务器 用户主动导出 接收方 应用内删除 卸载 撤回同意 敏感个人信息 不出本机 未请求通知权限 无需额外授权 不使用麦克风录音 munk.sh/privacy 专项小节"
forbidden_phrases="已请求通知权限
读取通讯录
使用广告标识
待增补
通用页
专项条款未落地
尚不含
已发布
已分发
可下载"

# 断言函数：读取传入文件，输出为空表示通过；反例在沙箱副本上重跑同一函数。
assert_policy() { # file
  local file="$1"
  local problems=""
  if [ ! -s "$file" ]; then
    printf '缺少政策正文文件 %s' "$file"
    return
  fi

  local section count
  for section in $required_sections; do
    count="$(grep -cF "## $section" "$file" || true)"
    if [ "$count" != "1" ]; then
      problems="$problems 条目「${section}」必须恰出现一次（实际 ${count}）;"
    fi
  done

  local keyword
  for keyword in $required_keywords; do
    if ! grep -Fq "$keyword" "$file"; then
      problems="$problems 缺少关键词「${keyword}」;"
    fi
  done

  local phrase
  while IFS= read -r phrase; do
    [ -n "$phrase" ] || continue
    if grep -Fq "$phrase" "$file"; then
      problems="$problems 出现肯定式虚假采集声明「${phrase}」;"
    fi
  done <<< "$forbidden_phrases"

  printf '%s' "$problems"
}

# 删除某个二级标题起至下一个二级标题前的整段（含标题）。
strip_section() { # file, heading
  awk -v heading="## $2" '
    $0 == heading { skipping = 1; next }
    skipping && /^## / { skipping = 0 }
    !skipping { print }
  ' "$1"
}

fail() {
  printf '[FAIL] %s\n' "$1"
  exit 1
}

# ---------------------------------------------------------------- 真源断言
problems="$(assert_policy "$source_file")"
if [ -n "$problems" ]; then
  fail "ac-policy-covers-required-items:$problems"
fi
printf '[PASS] ac-policy-covers-required-items\n'

# ------------------------------------------------------- bundle 逐字节一致
if [ ! -f "$bundle_file" ]; then
  fail "ac-policy-single-source:缺少 bundle 副本 ${bundle_file}（先运行 scripts/sync-privacy-policy.sh）"
fi
if ! cmp -s "$source_file" "$bundle_file"; then
  fail "ac-policy-single-source:bundle 副本与真源不一致（禁止手改副本，先同步）"
fi
source_sha="$(shasum -a 256 "$source_file" | awk '{print $1}')"
bundle_sha="$(shasum -a 256 "$bundle_file" | awk '{print $1}')"
if [ "$source_sha" != "$bundle_sha" ]; then
  fail "ac-policy-single-source:sha256 不一致（${source_sha} != ${bundle_sha}）"
fi
printf '[PASS] ac-policy-single-source\n'

# ------------------------------------------------------------ 沙箱反例
sandbox="$(mktemp -d "${TMPDIR:-/tmp}/purepace-privacy.XXXXXX")"
trap 'rm -rf "$sandbox"' EXIT

positive="$sandbox/privacy-policy.md"
cp "$source_file" "$positive"
if [ -n "$(assert_policy "$positive")" ]; then
  fail "ac-policy-keyword-red-proof:未改动副本未先判绿"
fi

for heading in "撤回同意" "存储与保留" "采集项"; do
  case_file="$sandbox/removed-${heading}.md"
  strip_section "$source_file" "$heading" > "$case_file"
  if [ ! -s "$case_file" ]; then
    fail "ac-policy-keyword-red-proof:删除「${heading}」条目后副本为空"
  fi
  if [ -z "$(assert_policy "$case_file")" ]; then
    fail "ac-policy-keyword-red-proof:删除「${heading}」条目后断言未判红"
  fi
done
printf '[PASS] ac-policy-keyword-red-proof\n'

printf 'privacy policy OK（sha256=%s）\n' "$source_sha"
