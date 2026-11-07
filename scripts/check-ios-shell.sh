#!/usr/bin/env bash
# iOS 空壳工程结构断言（.munk/code-gates.json 的 lint-ios-shell 门真实执行体）。
# 校验：XcodeGen 单一真源与可重复生成、无手写工程、构建设置、占位页内容、
# XCTest/XCUITest 落点、构建/测试脚本真实执行。任一条失败即非零退出。
set -euo pipefail

usage() {
  cat <<'EOF'
用法: scripts/check-ios-shell.sh [--help]

对 PurePace iOS 空壳工程做结构断言并打印逐条结果：
  - ios/project.yml 存在，xcodegen 连续两次生成结果一致
  - project.pbxproj 仅存在于 ios/PurePace.xcodeproj
  - iOS 17.0 / Swift 6.2 / 仅本地 path package RunCore / MARKETING_VERSION 来自 VERSION
  - 三个 target 与占位页（PurePace、tagline、Run/History/Log/Settings）
  - XCTest 与 XCUITest 源码落点
  - scripts/build-ios.sh、scripts/test-ios.sh 真实执行 xcodebuild

选项:
  -h, --help    显示本帮助并退出 0
  --self-test   只跑本地包断言的负向自检（正例 + 远程 url/path 反例）

退出码:
  0  全部断言通过
  1  存在失败断言
  2  参数非法
EOF
}

self_test=0
case "${1:-}" in
  -h|--help)
    usage
    exit 0
    ;;
  --self-test)
    self_test=1
    ;;
  "")
    ;;
  *)
    echo "check-ios-shell: 未知参数 '$1'（使用 --help 查看用法）" >&2
    exit 2
    ;;
esac

if [ "$#" -gt 1 ]; then
  echo "check-ios-shell: 只接受一个参数（使用 --help 查看用法）" >&2
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

# 只允许本地 path package 且路径限于 RunCore；远程/第三方仍判失败。
# 输出为空字符串表示通过，否则返回问题描述。
validate_packages() {
  local spec_file="$1"
  local problems=""

  if grep -Fq '.package(' "$spec_file" 2>/dev/null; then
    problems="$problems project.yml 使用 .package( 远程 URL 依赖;"
  fi
  if grep -Eq 'https://|url:' "$spec_file" 2>/dev/null; then
    problems="$problems project.yml 声明了远程 SwiftPM 依赖;"
  fi

  if ! grep -Fq 'packages:' "$spec_file" 2>/dev/null; then
    problems="$problems project.yml 未声明本地 path package;"
  else
    local block
    block="$(awk '/^packages:/{flag=1;next} flag && /^[^[:space:]#]/{flag=0} flag' "$spec_file")"
    if [ -z "$block" ]; then
      problems="$problems packages 段为空;"
    fi
    printf '%s\n' "$block" | grep -Fq 'path: RunCore' \
      || problems="$problems packages 未声明 path: RunCore;"
    local unauthorized
    unauthorized="$(printf '%s\n' "$block" | grep -Ev '^[[:space:]]*(#.*)?$|^[[:space:]]*[A-Za-z0-9_.-]+:[[:space:]]*$|^[[:space:]]*path:[[:space:]]*RunCore[[:space:]]*$' || true)"
    [ -z "$unauthorized" ] \
      || problems="$problems packages 含非本地/非 RunCore 条目: $(printf '%s' "$unauthorized" | tr '\n' ' ');"
  fi

  printf '%s' "$problems"
}

run_self_test() {
  local tmp_dir
  tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/purepace-ios-shell.XXXXXX")"
  trap "rm -rf '$tmp_dir'" EXIT

  printf 'name: T\npackages:\n  PurePaceRunCore:\n    path: RunCore\n' > "$tmp_dir/good.yml"
  printf 'name: T\npackages:\n  EvilPackage:\n    url: https://example.com/evil.git\n' > "$tmp_dir/remote-url.yml"
  printf 'name: T\npackages:\n  EvilPackage:\n    path: ../evil\n' > "$tmp_dir/remote-path.yml"

  local failed=0
  if [ -n "$(validate_packages "$tmp_dir/good.yml")" ]; then
    echo "[FAIL] self-test: 合法的本地 RunCore 包被判失败" >&2
    failed=1
  fi
  if [ -z "$(validate_packages "$tmp_dir/remote-url.yml")" ]; then
    echo "[FAIL] self-test: url 远程包反例未被判失败" >&2
    failed=1
  fi
  if [ -z "$(validate_packages "$tmp_dir/remote-path.yml")" ]; then
    echo "[FAIL] self-test: 非 RunCore 的 path 包反例未被判失败" >&2
    failed=1
  fi

  if [ "$failed" -ne 0 ]; then
    exit 1
  fi
  printf '[PASS] self-test (本地 path package 正/负反例)\n'
  printf '\n1 项断言，0 项失败\nself-test OK\n'
}

if [ "$self_test" -eq 1 ]; then
  run_self_test
  exit 0
fi

version_value="$(bash scripts/version.sh 2>/dev/null || true)"
spec="ios/project.yml"
xcodeproj="ios/PurePace.xcodeproj"
pbxproj="$xcodeproj/project.pbxproj"

# ------------------------------------------------ XcodeGen 单一真源
if [ ! -f "$spec" ]; then
  fail "ac-xcodegen-single-source" "缺少 $spec"
elif ! command -v xcodegen >/dev/null 2>&1; then
  fail "ac-xcodegen-single-source" "缺少 xcodegen，无法验证工程由 project.yml 生成"
elif [ -z "$version_value" ]; then
  fail "ac-xcodegen-single-source" "无法从 scripts/version.sh 取得版本号"
else
  bash scripts/sync-ios-version.sh >/dev/null 2>&1 || true
  project_checksum() {
    find "$xcodeproj" -type f -print0 | sort -z | xargs -0 shasum 2>/dev/null | shasum | awk '{print $1}'
  }
  problems=""
  if ! xcodegen generate --spec "$spec" >/dev/null 2>&1; then
    problems="$problems xcodegen 首次生成失败;"
  else
    first_sum="$(project_checksum)"
    if ! xcodegen generate --spec "$spec" >/dev/null 2>&1; then
      problems="$problems xcodegen 二次生成失败;"
    else
      second_sum="$(project_checksum)"
      [ "$first_sum" = "$second_sum" ] || problems="$problems 连续两次生成结果不一致（工程不可重复生成）;"
    fi
    [ -f "$pbxproj" ] || problems="$problems 生成后缺少 project.pbxproj;"
    if [ -f "$pbxproj" ]; then
      grep -Fq 'XCLocalSwiftPackageReference' "$pbxproj" \
        || problems="$problems 生成工程缺少本地包引用;"
      if grep -Eq 'XCRemoteSwiftPackageReference|https://' "$pbxproj"; then
        problems="$problems 生成工程含远程 package 引用;"
      fi
    fi
  fi
  if [ -z "$problems" ]; then
    pass "ac-xcodegen-single-source (xcodegen $(xcodegen --version 2>/dev/null | tail -1))"
  else
    fail "ac-xcodegen-single-source" "$problems"
  fi
fi

# ------------------------------------------------ 无手写工程文件
problems=""
stray_pbxproj="$(find . -name project.pbxproj -not -path "./$pbxproj" -not -path './ios/.build/*' -print 2>/dev/null | head -20 || true)"
[ -z "$stray_pbxproj" ] || problems="$problems 存在额外 project.pbxproj: $(printf '%s' "$stray_pbxproj" | tr '\n' ' ');"
stray_projects="$(find . -name '*.xcodeproj' -not -path "./$xcodeproj" -not -path './ios/.build/*' -print 2>/dev/null | head -20 || true)"
[ -z "$stray_projects" ] || problems="$problems 存在额外 .xcodeproj: $(printf '%s' "$stray_projects" | tr '\n' ' ');"
if [ -z "$problems" ]; then
  pass "ac-no-handwritten-pbxproj"
else
  fail "ac-no-handwritten-pbxproj" "$problems"
fi

# ------------------------------------------------ 构建设置
if [ ! -f "$spec" ]; then
  fail "ac-build-settings" "缺少 $spec"
else
  problems=""
  grep -Eq 'deploymentTarget:[[:space:]]*$' "$spec" || grep -q 'deploymentTarget:' "$spec" || problems="$problems 未声明 deploymentTarget;"
  grep -Fq 'iOS: "17.0"' "$spec" || problems="$problems 未声明 iOS 17.0;"
  grep -Fq 'SWIFT_VERSION: "6.2"' "$spec" || problems="$problems 未声明 SWIFT_VERSION 6.2;"
  grep -Fq 'Debug: Config/Version.xcconfig' "$spec" || problems="$problems project.yml 未引用 Config/Version.xcconfig;"
  grep -Fq 'Release: Config/Version.xcconfig' "$spec" || problems="$problems project.yml 未引用 Config/Version.xcconfig;"
  if [ -n "$version_value" ]; then
    grep -Fq "MARKETING_VERSION = $version_value" ios/Config/Version.xcconfig \
      || problems="$problems Version.xcconfig 与根 VERSION 不一致;"
  fi
  if grep -Eq 'MARKETING_VERSION:[[:space:]]*[0-9]+\.[0-9]+\.[0-9]+' "$spec"; then
    problems="$problems project.yml 写死了 MARKETING_VERSION 版本字面值;"
  fi
  if grep -Eq '[0-9]+\.[0-9]+\.[0-9]+' ios/PurePace/*.swift 2>/dev/null; then
    problems="$problems App 源码写死了版本字面值;"
  fi
  package_problems="$(validate_packages "$spec")"
  [ -z "$package_problems" ] || problems="$problems $package_problems"
  if [ -z "$problems" ]; then
    pass "ac-build-settings (iOS 17.0 / Swift 6.2 / MARKETING_VERSION 来自 VERSION)"
  else
    fail "ac-build-settings" "$problems"
  fi
fi

# ------------------------------------------------ target 与系统框架
if [ ! -f "$spec" ]; then
  fail "ac-app-targets-and-frameworks" "缺少 $spec"
else
  problems=""
  for needle in 'PurePace:' 'PurePaceTests:' 'PurePaceUITests:' 'type: application' 'type: bundle.unit-test' 'type: bundle.ui-testing'; do
    grep -Fq -- "$needle" "$spec" || problems="$problems 缺少 '$needle';"
  done
  app_imports="$(grep -rhE --include='*.swift' '^import [A-Za-z0-9_]+' ios/PurePace 2>/dev/null | awk '{print $2}' | sort -u || true)"
  for module in $app_imports; do
    case "$module" in
      SwiftUI|Foundation|AVFoundation|PurePaceRunCore) ;;
      *) problems="$problems App 含非允许 import '$module';" ;;
    esac
  done
  # AVFoundation 只允许出现在音频适配器文件；首屏/占位页不得引入。
  av_import_files="$(grep -rlE --include='*.swift' '^import AVFoundation' ios/PurePace 2>/dev/null || true)"
  while IFS= read -r file; do
    [ -z "$file" ] && continue
    case "$file" in
      ios/PurePace/Audio/*.swift) ;;
      *) problems="$problems AVFoundation 只允许出现在 ios/PurePace/Audio/: $file;" ;;
    esac
  done <<< "$av_import_files"
  if grep -rEq --include='*.swift' 'CoreLocation|HealthKit|MapKit|CoreMotion|UserNotifications|URLSession' ios/PurePace 2>/dev/null; then
    problems="$problems App 源码引用了非允许的业务/网络框架;"
  fi
  if [ -z "$problems" ]; then
    pass "ac-app-targets-and-frameworks (3 targets / 仅系统框架)"
  else
    fail "ac-app-targets-and-frameworks" "$problems"
  fi
fi

# ------------------------------------------------ 占位页内容
problems=""
for file in ios/PurePace/PurePaceApp.swift ios/PurePace/ContentView.swift ios/PurePace/PlaceholderCopy.swift ios/PurePace/PlaceholderScreen.swift; do
  [ -f "$file" ] || problems="$problems 缺少 $file;"
done
if [ -z "$problems" ]; then
  grep -Fq 'PurePace' ios/PurePace/PlaceholderCopy.swift || problems="$problems 缺少 PurePace 文案;"
  grep -Fq 'Your pace, purely yours.' ios/PurePace/PlaceholderCopy.swift || problems="$problems 缺少 tagline;"
  grep -Fq 'TabView' ios/PurePace/ContentView.swift || problems="$problems 首屏缺少 TabView;"
  for tab in Run History Log Settings; do
    grep -Fq "\"$tab\"" ios/PurePace/PlaceholderCopy.swift || problems="$problems 缺少 Tab '$tab';"
  done
  # 显式文件清单：不靠非递归 glob 漏掉子目录（Audio/ 下的适配器不受占位页断言约束）。
  placeholder_sources="ios/PurePace/PurePaceApp.swift ios/PurePace/ContentView.swift ios/PurePace/PlaceholderCopy.swift ios/PurePace/PlaceholderScreen.swift"
  if grep -Eq 'URLSession|CoreLocation|AVFoundation|HealthKit' $placeholder_sources 2>/dev/null; then
    problems="$problems 占位页含业务逻辑/网络请求;"
  fi
fi
if [ -z "$problems" ]; then
  pass "ac-placeholder-ui (名称 + tagline + 四个空 Tab)"
else
  fail "ac-placeholder-ui" "$problems"
fi

# ------------------------------------------------ 测试落点
problems=""
unit_tests="ios/PurePaceTests/PlaceholderCopyTests.swift"
ui_tests="ios/PurePaceUITests/PlaceholderUITests.swift"
[ -f "$unit_tests" ] || problems="$problems 缺少 $unit_tests;"
[ -f "$ui_tests" ] || problems="$problems 缺少 $ui_tests;"
if [ -z "$problems" ]; then
  grep -Fq '@testable import PurePace' "$unit_tests" || problems="$problems XCTest 未导入 App 模块;"
  grep -Fq 'XCTAssert' "$unit_tests" || problems="$problems XCTest 无断言;"
  grep -Fq 'XCUIApplication' "$ui_tests" || problems="$problems XCUITest 未使用 XCUIApplication;"
  grep -Fq 'app.launch()' "$ui_tests" || problems="$problems XCUITest 未启动 App;"
  grep -Fq 'PurePace' "$ui_tests" || problems="$problems XCUITest 未断言 PurePace 文案;"
  for tab in Run History Log Settings; do
    grep -Fq "\"$tab\"" "$ui_tests" || problems="$problems XCUITest 未断言 Tab '$tab';"
  done
fi
if [ -z "$problems" ]; then
  pass "ac-tests-present (XCTest + XCUITest)"
else
  fail "ac-tests-present" "$problems"
fi

# ------------------------------------------------ 脚本与门禁真实执行
problems=""
for file in scripts/build-ios.sh scripts/test-ios.sh scripts/sync-ios-version.sh scripts/check-ios-shell.sh; do
  [ -f "$file" ] || problems="$problems 缺少 $file;"
  [ -x "$file" ] || problems="$problems $file 不可执行;"
  bash -n "$file" 2>/dev/null || problems="$problems $file 语法错误;"
done
if [ -z "$problems" ]; then
  bash scripts/build-ios.sh --help >/dev/null 2>&1 || problems="$problems build-ios.sh --help 未退出 0;"
  bash scripts/test-ios.sh --help >/dev/null 2>&1 || problems="$problems test-ios.sh --help 未退出 0;"
  bash scripts/sync-ios-version.sh --help >/dev/null 2>&1 || problems="$problems sync-ios-version.sh --help 未退出 0;"
  grep -Fq 'sync-ios-version.sh' scripts/build-ios.sh || problems="$problems build-ios.sh 未从 VERSION 同步版本;"
  grep -Fq 'sync-ios-version.sh' scripts/test-ios.sh || problems="$problems test-ios.sh 未从 VERSION 同步版本;"
  grep -Fq 'xcodegen generate' scripts/build-ios.sh || problems="$problems build-ios.sh 未调用 xcodegen;"
  grep -Fq 'xcodebuild build' scripts/build-ios.sh || problems="$problems build-ios.sh 未真实调用 xcodebuild build;"
  grep -Fq 'xcodegen generate' scripts/test-ios.sh || problems="$problems test-ios.sh 未调用 xcodegen;"
  grep -Fq 'xcodebuild test' scripts/test-ios.sh || problems="$problems test-ios.sh 未真实调用 xcodebuild test;"
  for gate_id in lint-ios-shell build-ios test-ios; do
    grep -Fq "\"$gate_id\"" .munk/code-gates.json || problems="$problems .munk/code-gates.json 缺少 $gate_id 门;"
  done
fi
if [ -z "$problems" ]; then
  pass "ac-scripts-and-gates (真实构建/测试脚本 + code-gates)"
else
  fail "ac-scripts-and-gates" "$problems"
fi

printf '\n%d 项断言，%d 项失败\n' "$CHECKS" "$FAILURES"
if [ "$FAILURES" -ne 0 ]; then
  exit 1
fi
printf 'ios shell OK\n'
