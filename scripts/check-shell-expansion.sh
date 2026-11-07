#!/usr/bin/env bash
# 变量展开卫生静态门（.munk/code-gates.json 的 check-shell-expansion 门真实执行体）。
# 扫描 scripts/**/*.sh、android/** 的 shell 文件（含无扩展名的 android/gradlew）
# 与 .github/workflows/*.yml|*.yaml 的非注释行，禁止裸变量紧跟非 ASCII 字节。
# 字节级判定（>= 0x80），扫描器只用 python3 或 perl，二者都缺失即失败，禁止 skip。
set -euo pipefail

usage() {
  cat <<'EOF'
用法: scripts/check-shell-expansion.sh [--help]

按字节级判据扫描 shell 与 workflow，要求变量展开写作带花括号的形式：
  - 扫描范围: scripts/**/*.sh、android/** 的 *.sh 与 android/gradlew、
    .github/workflows/*.yml|*.yaml
  - 命中判据: 美元符号后接 ASCII 字母/下划线开头的标识符，紧跟非 ASCII 字节
  - 注释豁免: 行首（允许前导空白）为 # 的行整行跳过
  - 不依赖 locale: 扫描器直接比较原始字节，非 ASCII 判定为字节 >= 0x80
  - 不依赖 GNU grep -P: 扫描器只用 python3 或 perl，二者都缺失时显式失败
  - 内置自检: 带花括号正例不误报、裸变量反例必命中、注释行样本必豁免

选项:
  -h, --help   显示本帮助并退出 0

退出码:
  0  全部门断言通过（真实仓库零命中 + 内置三组自检）
  1  存在命中或自检失败
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
    echo "check-shell-expansion: 未知参数 '$1'（使用 --help 查看用法）" >&2
    exit 2
    ;;
esac

if [ "$#" -gt 1 ]; then
  echo "check-shell-expansion: 只接受一个参数（使用 --help 查看用法）" >&2
  exit 2
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
cd "$repo_root"

CHECKS=0
FAILURES=0

pass() {
  CHECKS=$((CHECKS + 1))
  printf '[PASS] %s\n' "$1"
}

fail() {
  CHECKS=$((CHECKS + 1))
  FAILURES=$((FAILURES + 1))
  printf '[FAIL] %s: %s\n' "$1" "$2"
}

summary_and_exit() {
  printf '\n%d 项断言，%d 项失败\n' "$CHECKS" "$FAILURES"
  if [ "$FAILURES" -ne 0 ]; then
    exit 1
  fi
  printf 'check-shell-expansion OK\n'
  exit 0
}

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/purepace-shell-expansion.XXXXXX")"
cleanup() { rm -rf "$work_dir"; }
trap cleanup EXIT

# ------------------------------------------------------------- 扫描器落地
cat > "$work_dir/scan.py" <<'PY'
import re
import sys

PATTERN = re.compile(rb'\$([A-Za-z_][A-Za-z0-9_]*)([\x80-\xff])')

hits = 0
out = sys.stdout.buffer
for path in sys.argv[1:]:
    with open(path, 'rb') as handle:
        data = handle.read()
    for lineno, raw in enumerate(data.split(b'\n'), 1):
        if raw.lstrip().startswith(b'#'):
            continue
        if PATTERN.search(raw):
            hits += 1
            prefix = ('%s:%d: ' % (path, lineno)).encode('utf-8', 'replace')
            out.write(prefix + raw.strip() + b'\n')
sys.exit(1 if hits else 0)
PY

cat > "$work_dir/scan.pl" <<'PL'
use strict;
use warnings;

my $pattern = qr/\$([A-Za-z_][A-Za-z0-9_]*)([\x80-\xFF])/;
my $hits = 0;
for my $path (@ARGV) {
    open(my $handle, '<:raw', $path) or do {
        print STDERR "无法读取 $path: $!\n";
        exit 2;
    };
    my $lineno = 0;
    while (my $raw = <$handle>) {
        $lineno++;
        chomp $raw;
        next if $raw =~ /^\s*#/;
        if ($raw =~ /$pattern/) {
            $hits++;
            print "$path:$lineno: $raw\n";
        }
    }
    close($handle);
}
exit($hits ? 1 : 0);
PL

# --------------------------------------------------------------- 工具依赖
scanner_kind=""
if command -v python3 >/dev/null 2>&1; then
  scanner_kind="python3"
  pass "scanner-available-python3"
elif command -v perl >/dev/null 2>&1; then
  scanner_kind="perl"
  pass "scanner-available-perl"
else
  fail "scanner-available" "python3 与 perl 均不可用，无法按字节级判定，禁止放行"
  summary_and_exit
fi

run_scanner() {
  if [ "$scanner_kind" = "python3" ]; then
    LC_ALL=C python3 "$work_dir/scan.py" "$@"
  else
    LC_ALL=C perl "$work_dir/scan.pl" "$@"
  fi
}

# ------------------------------------------------------------- 扫描范围
file_list="$work_dir/files.txt"
: > "$file_list"
if [ -d scripts ]; then
  find scripts -type f -name '*.sh' >> "$file_list"
fi
if [ -d android ]; then
  find android -type f \( -name '*.sh' -o -name gradlew \) >> "$file_list"
fi
if [ -d .github/workflows ]; then
  find .github/workflows -maxdepth 1 -type f \( -name '*.yml' -o -name '*.yaml' \) >> "$file_list"
fi
sort -u -o "$file_list" "$file_list"

if [ -s "$file_list" ]; then
  pass "scan-scope-nonempty"
else
  fail "scan-scope-nonempty" "扫描范围为空，范围枚举失效"
fi

if grep -Fxq 'android/gradlew' "$file_list"; then
  pass "scan-scope-covers-android-gradlew"
else
  fail "scan-scope-covers-android-gradlew" "扫描范围未覆盖 android/gradlew"
fi

scan_files=()
while IFS= read -r candidate; do
  scan_files+=("$candidate")
done < "$file_list"

# --------------------------------------------------------- 真实仓库零命中
if hits_out="$(run_scanner "${scan_files[@]}")"; then
  pass "ac-scan-zero-hits"
else
  fail "ac-scan-zero-hits" "$(printf '%s' "$hits_out" | tr '\n' ' ')"
fi

# --------------------------------------------------------------- 内置自检
selftest_dir="$work_dir/selftest"
mkdir -p "$selftest_dir"
dollar_var='$var'
braced_var='${var}'

printf '%s\n' "echo \"值=${braced_var}中文\"" > "$selftest_dir/positive.sh"
if run_scanner "$selftest_dir/positive.sh" >/dev/null 2>&1; then
  pass "ac-gate-self-test-positive"
else
  fail "ac-gate-self-test-positive" "带花括号正例被误判为命中"
fi

printf '%s\n' "echo \"值=${dollar_var}中文\"" > "$selftest_dir/negative.sh"
if run_scanner "$selftest_dir/negative.sh" >/dev/null 2>&1; then
  fail "ac-gate-self-test-negative" "裸变量反例未被判为命中，断言恒真"
else
  pass "ac-gate-self-test-negative"
fi

printf '%s\n' "# ${dollar_var}中文" > "$selftest_dir/comment.sh"
if run_scanner "$selftest_dir/comment.sh" >/dev/null 2>&1; then
  pass "ac-gate-comment-exempt"
else
  fail "ac-gate-comment-exempt" "注释行样本未被豁免"
fi

summary_and_exit
