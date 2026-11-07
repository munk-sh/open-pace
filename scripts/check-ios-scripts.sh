#!/usr/bin/env bash
# iOS 脚本静态/契约断言（.munk/code-gates.json 的 lint-ios-scripts 门真实执行体）。
# 校验 build-ios.sh / test-ios.sh / check-ios-scripts.sh / version.sh 的 bash 严格模式、
# 参数契约、xcodebuild 分支字面量、降级分支、无写死版本、无伪造成功行；任一条失败即非零退出。
set -euo pipefail

usage() {
  cat <<'EOF'
用法: scripts/check-ios-scripts.sh [--help]

对 iOS 构建/测试/版本脚本做结构与契约断言并打印逐条结果：
  - 四个脚本 bash -n 通过、shebang 为 #!/usr/bin/env bash、正文含 set -euo pipefail
  - build-ios.sh / test-ios.sh / check-ios-scripts.sh 的 --help 退出 0 且含「用法」，未知参数退出 2
  - build-ios.sh 含 xcodebuild build、-scheme、iPhone 16 destination（可带 OS/UDID）与 swift build 降级分支
  - test-ios.sh 含 xcodebuild test、-scheme、iPhone 16 destination（可带 OS/UDID）与 swift test 降级分支
  - 分支判定基于 ios/PurePace.xcodeproj 存在性；降级分支输出 blocked: 且不输出伪造成功行
  - version.sh 无参输出等于根 VERSION，--tools 输出可核对且逐字节幂等
  - 脚本与 README.md 不出现根 VERSION 字面值，不出现不实验收措辞

选项:
  -h, --help   显示本帮助并退出 0

退出码:
  0  全部断言通过
  1  存在失败断言
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
    echo "check-ios-scripts: 未知参数 '$1'（使用 --help 查看用法）" >&2
    exit 2
    ;;
esac

if [ "$#" -gt 1 ]; then
  echo "check-ios-scripts: 只接受一个参数（使用 --help 查看用法）" >&2
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

targets="build-ios.sh test-ios.sh check-ios-scripts.sh version.sh"
strict_targets="build-ios.sh test-ios.sh check-ios-scripts.sh"

# ------------------------------------------------- 脚本存在、语法与严格模式
problems=""
for name in $targets; do
  [ -f "scripts/$name" ] || problems="$problems 缺少 scripts/$name;"
done
if [ -z "$problems" ]; then
  pass "ac-ios-scripts-present"
else
  fail "ac-ios-scripts-present" "$problems"
fi

problems=""
for name in $targets; do
  [ -f "scripts/$name" ] || continue
  bash -n "scripts/$name" >/dev/null 2>&1 || problems="$problems scripts/$name bash -n 失败;"
done
if [ -z "$problems" ]; then
  pass "ac-ios-scripts-bash-strict (bash -n)"
else
  fail "ac-ios-scripts-bash-strict" "$problems"
fi

problems=""
for name in $strict_targets; do
  [ -f "scripts/$name" ] || continue
  first_line="$(sed -n '1p' "scripts/$name")"
  [ "$first_line" = "#!/usr/bin/env bash" ] || problems="$problems scripts/$name shebang 为 '$first_line';"
  grep -Fq -- 'set -euo pipefail' "scripts/$name" || problems="$problems scripts/$name 缺少 set -euo pipefail;"
  grep -Fq -- 'BASH_SOURCE' "scripts/$name" || problems="$problems scripts/$name 未以 BASH_SOURCE 推导仓库根;"
done
if [ -z "$problems" ]; then
  pass "ac-ios-scripts-bash-strict (shebang/set/BASH_SOURCE)"
else
  fail "ac-ios-scripts-bash-strict" "$problems"
fi

# --------------------------------------- --help 退出 0 且含「用法」，未知参数退出 2
problems=""
for name in $strict_targets; do
  [ -f "scripts/$name" ] || continue
  help_out="$(bash "scripts/$name" --help 2>&1)" && help_rc=0 || help_rc=$?
  if [ "$help_rc" -ne 0 ]; then
    problems="$problems scripts/$name --help 退出 $help_rc;"
  elif ! printf '%s' "$help_out" | grep -Fq -- "用法"; then
    problems="$problems scripts/$name --help 输出缺少「用法」;"
  fi
  bash "scripts/$name" --definitely-invalid >/dev/null 2>&1 && bad_rc=0 || bad_rc=$?
  [ "$bad_rc" -eq 2 ] || problems="$problems scripts/$name 未知参数退出 ${bad_rc}（期望 2）;"
done
if [ -z "$problems" ]; then
  pass "ac-ios-scripts-help"
else
  fail "ac-ios-scripts-help" "$problems"
fi

# --------------------------------------------------- build-ios.sh 契约字面量
problems=""
if [ ! -f scripts/build-ios.sh ]; then
  problems="$problems 缺少 scripts/build-ios.sh;"
else
  for needle in \
    "xcodebuild build" \
    "-scheme" \
    "ios/PurePace.xcodeproj" \
    "swift build --package-path ios/Core" \
    "blocked:"; do
    grep -Fq -- "$needle" scripts/build-ios.sh || problems="$problems 缺少 '$needle';"
  done
  # destination 必须钉住 iPhone 16；允许显式 OS 版本或 UDID 以消除 latest 歧义。
  grep -Eq -- "-destination ['\"]platform=iOS Simulator,name=iPhone 16(,OS=[0-9.]+|,id=[0-9A-Fa-f-]+)?['\"]" scripts/build-ios.sh \
    || problems="$problems 缺少 iPhone 16 destination;"
fi
if [ -z "$problems" ]; then
  pass "ac-build-ios-xcodebuild-path"
else
  fail "ac-build-ios-xcodebuild-path" "$problems"
fi

# ---------------------------------------------------- test-ios.sh 契约字面量
problems=""
if [ ! -f scripts/test-ios.sh ]; then
  problems="$problems 缺少 scripts/test-ios.sh;"
else
  for needle in \
    "xcodebuild test" \
    "-scheme" \
    "ios/PurePace.xcodeproj" \
    "swift test --package-path ios/Core" \
    "blocked:"; do
    grep -Fq -- "$needle" scripts/test-ios.sh || problems="$problems 缺少 '$needle';"
  done
  # destination 必须钉住 iPhone 16；允许显式 OS 版本或 UDID 以消除 latest 歧义。
  grep -Eq -- "-destination ['\"]platform=iOS Simulator,name=iPhone 16(,OS=[0-9.]+|,id=[0-9A-Fa-f-]+)?['\"]" scripts/test-ios.sh \
    || problems="$problems 缺少 iPhone 16 destination;"
fi
if [ -z "$problems" ]; then
  pass "ac-test-ios-xcodebuild-path"
else
  fail "ac-test-ios-xcodebuild-path" "$problems"
fi

# ------------------------------- 降级分支不伪造成功行（不 echo BUILD/TEST SUCCEEDED）
problems=""
for name in build-ios.sh test-ios.sh; do
  [ -f "scripts/$name" ] || continue
  fabricated="$(grep -nE "^[[:space:]]*(echo|printf)[^#]*(BUILD SUCCEEDED|TEST SUCCEEDED)" "scripts/$name" 2>/dev/null || true)"
  [ -z "$fabricated" ] || problems="$problems scripts/$name 出现伪造成功行: $(printf '%s' "$fabricated" | tr '\n' ' ');"
done
if [ -z "$problems" ]; then
  pass "ac-no-fake-success-line"
else
  fail "ac-no-fake-success-line" "$problems"
fi

# ------------------------------------------------------ version.sh 无参契约
version_value=""
if [ -f VERSION ]; then
  version_value="$(tr -d '\r\n' < VERSION)"
fi
problems=""
if [ ! -f scripts/version.sh ]; then
  problems="$problems 缺少 scripts/version.sh;"
elif [ -z "$version_value" ]; then
  problems="$problems 根 VERSION 不可用;"
else
  bare_out="$(bash scripts/version.sh 2>/dev/null)" && bare_rc=0 || bare_rc=$?
  if [ "$bare_rc" -ne 0 ]; then
    problems="$problems 无参退出 $bare_rc;"
  elif [ "$bare_out" != "$version_value" ]; then
    problems="$problems 无参输出 '$bare_out' 与 VERSION 不一致;"
  fi
fi
if [ -z "$problems" ]; then
  pass "ac-version-bare-unchanged"
else
  fail "ac-version-bare-unchanged" "$problems"
fi

# ------------------------------------------------------- version.sh --tools
problems=""
if [ -f scripts/version.sh ] && [ -n "$version_value" ]; then
  tools_out="$(bash scripts/version.sh --tools 2>&1)" && tools_rc=0 || tools_rc=$?
  if [ "$tools_rc" -ne 0 ]; then
    problems="$problems --tools 退出 $tools_rc;"
  else
    printf '%s' "$tools_out" | grep -Fq -- "VERSION: $version_value" || problems="$problems --tools 缺少根 VERSION 行;"

    if command -v xcodebuild >/dev/null 2>&1; then
      xcode_expected="$(xcodebuild -version 2>/dev/null | sed -n 's/^Xcode \([0-9][0-9.]*\).*/\1/p' | head -n 1 || true)"
    else
      xcode_expected=""
    fi
    if [ -n "$xcode_expected" ]; then
      printf '%s' "$tools_out" | grep -Fxq -- "Xcode: $xcode_expected" || problems="$problems Xcode 行与 xcodebuild -version 不一致（期望 ${xcode_expected}）;"
    else
      printf '%s' "$tools_out" | grep -Eq '^Xcode: 未就绪' || problems="$problems Xcode 行未标注未就绪;"
    fi

    if command -v swift >/dev/null 2>&1; then
      swift_expected="$(swift --version 2>/dev/null | sed -n 's/.*Apple Swift version \([0-9][0-9.]*\).*/\1/p' | head -n 1 || true)"
    else
      swift_expected=""
    fi
    if [ -n "$swift_expected" ]; then
      printf '%s' "$tools_out" | grep -Fxq -- "Swift: Apple Swift version $swift_expected" || problems="$problems Swift 行与 swift --version 不一致（期望 ${swift_expected}）;"
    else
      printf '%s' "$tools_out" | grep -Eq '^Swift: 未就绪' || problems="$problems Swift 行未标注未就绪;"
    fi

    if command -v java >/dev/null 2>&1; then
      jdk_expected="$(java -version 2>&1 | sed -n 's/.*version "\([^"]*\)".*/\1/p' | head -n 1 || true)"
      if [ -n "$jdk_expected" ]; then
        printf '%s' "$tools_out" | grep -Eq "^JDK: .*${jdk_expected}" || problems="$problems JDK 行与 java -version 不一致（期望含 ${jdk_expected}）;"
      else
        printf '%s' "$tools_out" | grep -Eq '^JDK: 未就绪' || problems="$problems JDK 行未标注未就绪;"
      fi
    else
      printf '%s' "$tools_out" | grep -Eq '^JDK: 未就绪' || problems="$problems JDK 行未标注未就绪;"
    fi

    if [ -x android/gradlew ]; then
      printf '%s' "$tools_out" | grep -Eq '^Gradle: [0-9]' || problems="$problems Gradle 行未取到真实版本;"
    else
      printf '%s' "$tools_out" | grep -Eq '^Gradle: 未就绪' || problems="$problems 缺少 android/gradlew 时 Gradle 行未标注未就绪;"
    fi

    tools_out2="$(bash scripts/version.sh --tools 2>&1)" || true
    [ "$tools_out" = "$tools_out2" ] || problems="$problems --tools 连续两次输出不一致;"
  fi
else
  problems="$problems scripts/version.sh 或根 VERSION 不可用;"
fi
if [ -z "$problems" ]; then
  pass "ac-version-tools-report"
  pass "ac-version-tools-idempotent"
else
  fail "ac-version-tools-report" "$problems"
  fail "ac-version-tools-idempotent" "$problems"
fi

# ------------------------------------------- 脚本与 README 无根 VERSION 字面值
problems=""
if [ -z "$version_value" ]; then
  problems="$problems 根 VERSION 不可用;"
else
  hits="$(grep -Fn -- "$version_value" scripts/*.sh README.md 2>/dev/null || true)"
  [ -z "$hits" ] || problems="$problems 出现版本字面值 '$version_value': $(printf '%s' "$hits" | tr '\n' ' ');"
fi
if [ -z "$problems" ]; then
  pass "ac-no-version-literal"
else
  fail "ac-no-version-literal" "$problems"
fi

printf '\n%d 项断言，%d 项失败\n' "$CHECKS" "$FAILURES"
if [ "$FAILURES" -ne 0 ]; then
  exit 1
fi
printf 'ios scripts OK\n'
