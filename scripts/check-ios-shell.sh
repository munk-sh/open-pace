#!/usr/bin/env bash
# iOS 工程结构断言（.munk/code-gates.json 的 lint-ios-shell 门真实执行体）。
# 校验：XcodeGen 单一真源与可重复生成、无手写工程、构建设置、真实跑步 UI、
# XCTest/XCUITest 落点、构建/测试脚本真实执行。任一条失败即非零退出。
set -euo pipefail

usage() {
  cat <<'EOF'
用法: scripts/check-ios-shell.sh [--help]

对 PurePace iOS 工程做结构断言并打印逐条结果：
  - ios/project.yml 存在，xcodegen 连续两次生成结果一致
  - project.pbxproj 仅存在于 ios/PurePace.xcodeproj
  - iOS 17.0 / Swift 6.2 / 仅本地 path package RunCore / MARKETING_VERSION 来自 VERSION
  - 三个 target 与真实跑步页（Run / History / Settings，无 Log）
  - App import 允许表（CoreLocation 仅限 ios/PurePace/Harness/ 与 Location/）
  - project.yml 定位用途说明与后台定位模式声明非空
  - Harness 文件清单 + 真实跑步 UI 文件清单 + 无障碍标识
  - XCTest 与 XCUITest 源码落点（真实流程断言、无固定 sleep）
  - scripts/build-ios.sh、scripts/test-ios.sh 真实执行 xcodebuild

选项:
  -h, --help    显示本帮助并退出 0
  --self-test   只跑本地包/import/定位配置/Harness 清单断言的正负反例自检

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

# App 源码 import 允许表：CoreLocation 只许出现在 Harness/，AVFoundation 只许出现在 Audio/。
# 输出为空字符串表示通过，否则返回问题描述。
validate_app_imports() {
  local app_dir="$1"
  local problems=""

  local app_imports
  app_imports="$(grep -rhE --include='*.swift' '^import [A-Za-z0-9_]+' "$app_dir" 2>/dev/null | awk '{print $2}' | sort -u || true)"
  local module
  for module in $app_imports; do
    case "$module" in
      SwiftUI|Foundation|AVFoundation|CoreLocation|PurePaceRunCore) ;;
      *) problems="$problems App 含非允许 import '$module';" ;;
    esac
  done

  local file
  while IFS= read -r file; do
    [ -z "$file" ] && continue
    case "$file" in
      "$app_dir"/Audio/*.swift) ;;
      *) problems="$problems AVFoundation 只允许出现在 ios/PurePace/Audio/: $file;" ;;
    esac
  done <<< "$(grep -rlE --include='*.swift' '^import AVFoundation' "$app_dir" 2>/dev/null || true)"

  while IFS= read -r file; do
    [ -z "$file" ] && continue
    case "$file" in
      "$app_dir"/Harness/*.swift|"$app_dir"/Location/*.swift) ;;
      *) problems="$problems CoreLocation 只允许出现在 ios/PurePace/Harness/ 与 ios/PurePace/Location/: $file;" ;;
    esac
  done <<< "$(grep -rlE --include='*.swift' 'CoreLocation' "$app_dir" 2>/dev/null || true)"

  if grep -rEq --include='*.swift' 'HealthKit|MapKit|CoreMotion|UserNotifications|URLSession' "$app_dir" 2>/dev/null; then
    problems="$problems App 源码引用了非允许的业务/网络框架;"
  fi

  printf '%s' "$problems"
}

# project.yml 定位配置：用途说明非空 + 后台定位模式声明。
validate_location_config() {
  local spec_file="$1"
  local problems=""

  local usage_line
  usage_line="$(grep -E '^[[:space:]]*INFOPLIST_KEY_NSLocationWhenInUseUsageDescription:' "$spec_file" 2>/dev/null | head -n 1 || true)"
  if [ -z "$usage_line" ]; then
    problems="$problems project.yml 缺少 INFOPLIST_KEY_NSLocationWhenInUseUsageDescription;"
  else
    local usage_value
    usage_value="$(printf '%s' "${usage_line#*:}" | tr -d "[:space:]\"'")"
    if [ -z "$usage_value" ]; then
      problems="$problems INFOPLIST_KEY_NSLocationWhenInUseUsageDescription 为空;"
    fi
  fi

  local background_line
  background_line="$(grep -E '^[[:space:]]*INFOPLIST_KEY_UIBackgroundModes:' "$spec_file" 2>/dev/null | head -n 1 || true)"
  if [ -z "$background_line" ]; then
    problems="$problems project.yml 缺少 INFOPLIST_KEY_UIBackgroundModes;"
  elif ! printf '%s' "$background_line" | grep -Fq 'location'; then
    problems="$problems INFOPLIST_KEY_UIBackgroundModes 未声明 location;"
  fi

  # INFOPLIST_KEY_UIBackgroundModes 不被 Xcode 的 plist 生成器支持（数组键），
  # 真正进产物的 UIBackgroundModes 必须由 spec 同目录下 xcodegen 生成的 Info.plist 承载。
  local plist_file
  plist_file="$(dirname "$spec_file")/PurePace/Info.plist"
  if [ ! -s "$plist_file" ]; then
    problems="$problems 缺少 $(dirname "$spec_file")/PurePace/Info.plist（UIBackgroundModes 必需）;"
  elif ! grep -Fq 'UIBackgroundModes' "$plist_file" || ! grep -Fq 'location' "$plist_file"; then
    problems="$problems $plist_file 未声明 UIBackgroundModes location;"
  fi

  printf '%s' "$problems"
}

# Harness 文件清单与「无内置样例/夹具数据」静态断言。
validate_harness_manifest() {
  local root="$1"
  local problems=""
  local rel

  for rel in \
    "ios/PurePace/Harness/HarnessArguments.swift" \
    "ios/PurePace/Harness/HarnessStreamParser.swift" \
    "ios/PurePace/Harness/HarnessStatus.swift" \
    "ios/PurePace/Harness/HarnessCore.swift" \
    "ios/PurePace/Harness/HarnessRunner.swift" \
    "ios/PurePace/Harness/HarnessLocationSource.swift" \
    "ios/PurePace/Harness/HarnessRootView.swift"; do
    if [ ! -s "$root/$rel" ]; then
      problems="$problems 缺少或为空 $rel;"
    fi
  done

  if grep -rEq --include='*.swift' 'shared/fixtures|\.gpx|\.tcx' "$root/ios/PurePace/Harness" 2>/dev/null; then
    problems="$problems Harness 源码引用了夹具/样例数据;"
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

  local checks=0
  local failures=0
  check_ok() {
    checks=$((checks + 1))
    if [ -n "$2" ]; then
      echo "[FAIL] self-test: $1（正例被判失败: $2）" >&2
      failures=$((failures + 1))
    fi
  }
  check_fail() {
    checks=$((checks + 1))
    if [ -z "$2" ]; then
      echo "[FAIL] self-test: $1（反例未被判失败）" >&2
      failures=$((failures + 1))
    fi
  }

  check_ok "本地 path package 正例" "$(validate_packages "$tmp_dir/good.yml")"
  check_fail "url 远程包反例" "$(validate_packages "$tmp_dir/remote-url.yml")"
  check_fail "非 RunCore path 包反例" "$(validate_packages "$tmp_dir/remote-path.yml")"

  # import 作用域正负反例
  mkdir -p "$tmp_dir/app/Harness" "$tmp_dir/app/Audio" "$tmp_dir/app/Location"
  printf 'import SwiftUI\n' > "$tmp_dir/app/PurePaceApp.swift"
  printf 'import CoreLocation\nimport Foundation\n' > "$tmp_dir/app/Harness/LocationSource.swift"
  printf 'import CoreLocation\nimport Foundation\n' > "$tmp_dir/app/Location/RunLocationSource.swift"
  printf 'import AVFoundation\n' > "$tmp_dir/app/Audio/AudioSessionAdapter.swift"
  check_ok "App import 允许表正例（Harness + Location 双作用域）" "$(validate_app_imports "$tmp_dir/app")"

  mkdir -p "$tmp_dir/app-bad-corelocation"
  printf 'import CoreLocation\n' > "$tmp_dir/app-bad-corelocation/ContentView.swift"
  check_fail "CoreLocation 越界反例" "$(validate_app_imports "$tmp_dir/app-bad-corelocation")"

  mkdir -p "$tmp_dir/app-bad-corelocation-scope/Run"
  printf 'import CoreLocation\n' > "$tmp_dir/app-bad-corelocation-scope/Run/RunView.swift"
  check_fail "CoreLocation 在非 Harness/Location 目录反例" "$(validate_app_imports "$tmp_dir/app-bad-corelocation-scope")"

  mkdir -p "$tmp_dir/app-bad-framework/Harness"
  printf 'import MapKit\n' > "$tmp_dir/app-bad-framework/Harness/Map.swift"
  check_fail "禁用业务框架反例" "$(validate_app_imports "$tmp_dir/app-bad-framework")"

  mkdir -p "$tmp_dir/app-bad-av"
  printf 'import AVFoundation\n' > "$tmp_dir/app-bad-av/Other.swift"
  check_fail "AVFoundation 越界反例" "$(validate_app_imports "$tmp_dir/app-bad-av")"

  mkdir -p "$tmp_dir/app-bad-unknown"
  printf 'import UIKit\n' > "$tmp_dir/app-bad-unknown/Other.swift"
  check_fail "未知 import 反例" "$(validate_app_imports "$tmp_dir/app-bad-unknown")"

  # project.yml 定位配置正负反例
  printf 'settings:\n  base:\n    INFOPLIST_KEY_NSLocationWhenInUseUsageDescription: "跑步定位用途说明"\n    INFOPLIST_KEY_UIBackgroundModes: location\n' > "$tmp_dir/location-good.yml"
  printf 'settings:\n  base:\n    INFOPLIST_KEY_NSLocationWhenInUseUsageDescription: "跑步定位用途说明"\n' > "$tmp_dir/location-no-background.yml"
  printf 'settings:\n  base:\n    INFOPLIST_KEY_NSLocationWhenInUseUsageDescription: ""\n    INFOPLIST_KEY_UIBackgroundModes: location\n' > "$tmp_dir/location-empty-usage.yml"
  printf 'settings:\n  base:\n    INFOPLIST_KEY_NSLocationWhenInUseUsageDescription: "跑步定位用途说明"\n    INFOPLIST_KEY_UIBackgroundModes: audio\n' > "$tmp_dir/location-no-mode.yml"
  mkdir -p "$tmp_dir/PurePace"
  printf '<dict><key>UIBackgroundModes</key><array><string>location</string></array></dict>\n' > "$tmp_dir/PurePace/Info.plist"
  check_ok "定位配置正例" "$(validate_location_config "$tmp_dir/location-good.yml")"
  check_fail "缺后台定位模式反例" "$(validate_location_config "$tmp_dir/location-no-background.yml")"
  check_fail "用途说明为空反例" "$(validate_location_config "$tmp_dir/location-empty-usage.yml")"
  check_fail "后台模式非 location 反例" "$(validate_location_config "$tmp_dir/location-no-mode.yml")"

  # 承载 UIBackgroundModes 的基础 Info.plist 正负反例
  mkdir -p "$tmp_dir/location-no-plist"
  printf 'settings:\n  base:\n    INFOPLIST_KEY_NSLocationWhenInUseUsageDescription: "跑步定位用途说明"\n    INFOPLIST_KEY_UIBackgroundModes: location\n' > "$tmp_dir/location-no-plist/project.yml"
  check_fail "缺基础 Info.plist 反例" "$(validate_location_config "$tmp_dir/location-no-plist/project.yml")"

  mkdir -p "$tmp_dir/location-bad-plist/PurePace"
  printf 'settings:\n  base:\n    INFOPLIST_KEY_NSLocationWhenInUseUsageDescription: "跑步定位用途说明"\n    INFOPLIST_KEY_UIBackgroundModes: location\n' > "$tmp_dir/location-bad-plist/project.yml"
  printf '<dict><key>UIBackgroundModes</key><array><string>audio</string></array></dict>\n' > "$tmp_dir/location-bad-plist/PurePace/Info.plist"
  check_fail "基础 Info.plist 非 location 反例" "$(validate_location_config "$tmp_dir/location-bad-plist/project.yml")"

  # Harness 文件清单正负反例
  local harness_rel
  for harness_rel in \
    HarnessArguments.swift HarnessStreamParser.swift HarnessStatus.swift HarnessCore.swift \
    HarnessRunner.swift HarnessLocationSource.swift HarnessRootView.swift; do
    mkdir -p "$tmp_dir/manifest-good/ios/PurePace/Harness"
    printf 'import Foundation\n' > "$tmp_dir/manifest-good/ios/PurePace/Harness/$harness_rel"
  done
  check_ok "Harness 清单正例" "$(validate_harness_manifest "$tmp_dir/manifest-good")"

  mkdir -p "$tmp_dir/manifest-bad/ios/PurePace/Harness"
  printf 'import Foundation\n' > "$tmp_dir/manifest-bad/ios/PurePace/Harness/HarnessArguments.swift"
  check_fail "Harness 清单缺文件反例" "$(validate_harness_manifest "$tmp_dir/manifest-bad")"

  mkdir -p "$tmp_dir/manifest-fixture/ios/PurePace/Harness"
  for harness_rel in \
    HarnessArguments.swift HarnessStreamParser.swift HarnessStatus.swift HarnessCore.swift \
    HarnessRunner.swift HarnessLocationSource.swift HarnessRootView.swift; do
    printf 'import Foundation\n' > "$tmp_dir/manifest-fixture/ios/PurePace/Harness/$harness_rel"
  done
  printf 'let fixture = "shared/fixtures/sample-run.gpx"\n' > "$tmp_dir/manifest-fixture/ios/PurePace/Harness/HarnessArguments.swift"
  check_fail "Harness 引用夹具反例" "$(validate_harness_manifest "$tmp_dir/manifest-fixture")"

  if [ "$failures" -ne 0 ]; then
    exit 1
  fi
  printf '[PASS] self-test (包/import/定位配置/Harness 清单正负反例)\n'
  printf '\n%d 项断言，0 项失败\nself-test OK\n' "$checks"
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
  import_problems="$(validate_app_imports ios/PurePace)"
  [ -z "$import_problems" ] || problems="$problems $import_problems"
  if [ -z "$problems" ]; then
    pass "ac-app-targets-and-frameworks (3 targets / import 允许表含 Harness + Location 作用域)"
  else
    fail "ac-app-targets-and-frameworks" "$problems"
  fi
fi

# ------------------------------------------------ 定位配置声明
if [ ! -f "$spec" ]; then
  fail "ac-corelocation-config-declared" "缺少 $spec"
else
  location_problems="$(validate_location_config "$spec")"
  if [ -z "$location_problems" ]; then
    pass "ac-corelocation-config-declared (用途说明非空 + 后台模式 location)"
  else
    fail "ac-corelocation-config-declared" "$location_problems"
  fi
fi

# ------------------------------------------------ Harness 文件清单
harness_problems="$(validate_harness_manifest ".")"
if [ -z "$harness_problems" ]; then
  pass "ac-harness-manifest (Harness 文件清单 + 无夹具数据)"
else
  fail "ac-harness-manifest" "$harness_problems"
fi

# ------------------------------------------------ 真实跑步 UI
problems=""
live_sources="ios/PurePace/PurePaceApp.swift ios/PurePace/ContentView.swift ios/PurePace/Run/RunView.swift ios/PurePace/Run/RunSessionViewModel.swift ios/PurePace/Run/RunFormatting.swift ios/PurePace/Run/RunStorage.swift ios/PurePace/Location/RunLocationSource.swift ios/PurePace/History/HistoryView.swift ios/PurePace/History/RunDetailView.swift ios/PurePace/History/RunDetailContent.swift ios/PurePace/Settings/SettingsView.swift"
for file in $live_sources; do
  [ -f "$file" ] || problems="$problems 缺少 $file;"
done
if [ -z "$problems" ]; then
  grep -Fq 'TabView' ios/PurePace/ContentView.swift || problems="$problems 首屏缺少 TabView;"
  for tab in Run History Settings; do
    grep -Fq "\"$tab\"" ios/PurePace/ContentView.swift || problems="$problems 缺少 Tab '$tab';"
  done
  if grep -Fq '"Log"' ios/PurePace/ContentView.swift || grep -Fq 'case log' ios/PurePace/ContentView.swift; then
    problems="$problems 首屏仍含 Log Tab;"
  fi
  # 真实 CoreLocation 数据源配置
  grep -Fq 'CLLocationManager' ios/PurePace/Location/RunLocationSource.swift || problems="$problems 定位数据源未使用 CLLocationManager;"
  grep -Fq 'requestWhenInUseAuthorization' ios/PurePace/Location/RunLocationSource.swift || problems="$problems 定位数据源未请求使用期间授权;"
  grep -Fq 'activityType = .fitness' ios/PurePace/Location/RunLocationSource.swift || problems="$problems 定位数据源未声明 fitness 活动类型;"
  grep -Fq 'distanceFilter = kCLDistanceFilterNone' ios/PurePace/Location/RunLocationSource.swift || problems="$problems 定位数据源未关闭距离过滤;"
  grep -Fq 'pausesLocationUpdatesAutomatically = false' ios/PurePace/Location/RunLocationSource.swift || problems="$problems 定位数据源未关闭自动暂停;"
  # 会话 ViewModel 必须经编排器取度量
  grep -Fq 'RunSessionOrchestrator' ios/PurePace/Run/RunSessionViewModel.swift || problems="$problems ViewModel 未持有 RunSessionOrchestrator;"
  grep -Fq 'orchestrator.metrics' ios/PurePace/Run/RunSessionViewModel.swift || problems="$problems ViewModel 未从编排器读取 metrics;"
  # 无障碍标识（测试契约）
  for id in run.distance run.elapsed run.currentPace run.averagePace run.splits run.start run.pause run.resume run.finish run.saved; do
    grep -Fq "\"$id\"" ios/PurePace/Run/RunView.swift || problems="$problems 缺少无障碍标识 $id;"
  done
  # History / Settings 诚实态
  grep -Fq '"history.empty"' ios/PurePace/History/HistoryView.swift || problems="$problems History 缺少 history.empty 空态;"
  grep -Fq '"history.row"' ios/PurePace/History/HistoryView.swift || problems="$problems History 缺少 history.row 行标识;"
  grep -Fq 'archiveStore.list()' ios/PurePace/History/HistoryView.swift || problems="$problems History 未读取真实归档;"
  grep -Fq 'RunFormatting.paceText' ios/PurePace/History/HistoryView.swift || problems="$problems History 行未补平均配速;"
  grep -Fq 'RunDetailView(record:' ios/PurePace/History/HistoryView.swift || problems="$problems History 未接入跑次详情;"
  # 跑次详情：字段来自 RunRecord 与 RunDetailContent，稳定标识供 UI 测试
  grep -Fq 'RunDetailContent(record: record)' ios/PurePace/History/RunDetailView.swift || problems="$problems 详情页未使用 RunDetailContent;"
  for id in runDetail.root runDetail.startedAt runDetail.endedAt runDetail.distance runDetail.activeDuration runDetail.averagePace runDetail.splits runDetail.splitRow runDetail.splitsEmpty; do
    grep -Fq "\"$id\"" ios/PurePace/History/RunDetailView.swift || problems="$problems 缺少详情无障碍标识 $id;"
  done
  grep -Fq 'record.startedAt' ios/PurePace/History/RunDetailContent.swift || problems="$problems 详情映射未取 startedAt;"
  grep -Fq 'record.splits' ios/PurePace/History/RunDetailContent.swift || problems="$problems 详情映射未取 splits;"
  grep -Fq '暂无可配置项' ios/PurePace/Settings/SettingsView.swift || problems="$problems Settings 未声明无可配置项;"
  if grep -Eq 'Toggle|Stepper|Slider' ios/PurePace/Settings/SettingsView.swift; then
    problems="$problems Settings 含可切换控件;"
  fi
  # 无内置样例、无夹具引用、无假计时
  if grep -rEq --include='*.swift' 'shared/fixtures|\.gpx|\.tcx' ios/PurePace; then
    problems="$problems App 源码引用夹具/样例数据;"
  fi
  if grep -rEq --include='*.swift' 'Timer|DispatchQueue\.asyncAfter|CADisplayLink' ios/PurePace/Run; then
    problems="$problems Run 目录含定时器/假计时逻辑;"
  fi
fi
if [ -z "$problems" ]; then
  pass "ac-live-run-ui (Run/History/Settings + 真实定位数据源 + 无障碍标识)"
else
  fail "ac-live-run-ui" "$problems"
fi

# ------------------------------------------------ 测试落点
problems=""
unit_tests="ios/PurePaceTests/RunSessionViewModelTests.swift ios/PurePaceTests/RunFormattingTests.swift ios/PurePaceTests/RunDetailContentTests.swift"
ui_tests="ios/PurePaceUITests/RunFlowUITests.swift"
for file in $unit_tests $ui_tests; do
  [ -f "$file" ] || problems="$problems 缺少 $file;"
done
if [ -z "$problems" ]; then
  for file in $unit_tests; do
    grep -Fq '@testable import PurePace' "$file" || problems="$problems $file 未导入 App 模块;"
    grep -Fq 'XCTAssert' "$file" || problems="$problems $file 无断言;"
  done
  grep -Fq 'XCUIApplication' "$ui_tests" || problems="$problems XCUITest 未使用 XCUIApplication;"
  grep -Fq 'app.launch()' "$ui_tests" || problems="$problems XCUITest 未启动 App;"
  for id in run.start run.pause run.resume run.finish run.saved history.row runDetail.root runDetail.startedAt runDetail.endedAt runDetail.distance runDetail.activeDuration runDetail.averagePace runDetail.splits runDetail.splitRow runDetail.splitsEmpty; do
    grep -Fq "\"$id\"" "$ui_tests" || problems="$problems XCUITest 未断言 $id;"
  done
  if grep -Eq '(Thread\.sleep|sleep\()' "$ui_tests"; then
    problems="$problems XCUITest 使用固定 sleep 作为成功判据;"
  fi
fi
if [ -z "$problems" ]; then
  pass "ac-tests-present (XCTest + XCUITest 真实流程)"
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
