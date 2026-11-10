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
  - 生成后 project.pbxproj 确实存在于 ios/PurePace.xcodeproj；.gitignore 忽略该生成物，
    且 git ls-files 无 tracked project.pbxproj；额外/游离 project.pbxproj 仍判失败
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
    grep -Fq 'path: RunCore' <<< "$block" \
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

  local always_usage_line
  always_usage_line="$(grep -E '^[[:space:]]*INFOPLIST_KEY_NSLocationAlwaysAndWhenInUseUsageDescription:' "$spec_file" 2>/dev/null | head -n 1 || true)"
  if [ -z "$always_usage_line" ]; then
    problems="$problems project.yml 缺少 INFOPLIST_KEY_NSLocationAlwaysAndWhenInUseUsageDescription;"
  else
    local always_usage_value
    always_usage_value="$(printf '%s' "${always_usage_line#*:}" | tr -d "[:space:]\"'")"
    if [ -z "$always_usage_value" ]; then
      problems="$problems INFOPLIST_KEY_NSLocationAlwaysAndWhenInUseUsageDescription 为空;"
    fi
  fi

  # ac-project-yml-no-duplicate-setting：INFOPLIST_KEY_UIBackgroundModes 是构建期标量覆盖，
  # 会盖掉 info.properties 的数组声明，必须彻底移除。
  if grep -Eq '^[[:space:]]*INFOPLIST_KEY_UIBackgroundModes:' "$spec_file" 2>/dev/null; then
    problems="$problems project.yml 仍存在 INFOPLIST_KEY_UIBackgroundModes（会覆盖数组声明，必须删除）;"
  fi

  # ac-static-gate-scope：只按 PurePace target 段解析，UITests target 新增的 [audio] 不得影响本断言。
  local app_section spec_modes
  app_section="$(project_target_section "$spec_file" "PurePace")"
  spec_modes="$(project_background_mode_values "$app_section")"
  if [ -z "$spec_modes" ]; then
    problems="$problems project.yml 的 PurePace target 缺少 info.properties.UIBackgroundModes 数组;"
  elif [ "$spec_modes" != "$(printf 'location\naudio')" ]; then
    problems="$problems project.yml 的 PurePace target UIBackgroundModes 必须恰为 [location, audio]（实际 '${spec_modes}'; 脚本内换行以空格分隔）;"
  fi

  # UIBackgroundModes 是数组键，真正进产物的是 spec 同目录下、作为 INFOPLIST_FILE 的 Info.plist；
  # 这里校验其数组本体同时含 location 与 audio（与 ac-built-plist-readback-both 对齐）。
  local plist_file
  plist_file="$(dirname "$spec_file")/PurePace/Info.plist"
  if [ ! -s "$plist_file" ]; then
    problems="$problems 缺少 $(dirname "$spec_file")/PurePace/Info.plist（UIBackgroundModes 必需）;"
  else
    local plist_modes
    plist_modes="$(awk '
      /<key>[[:space:]]*UIBackgroundModes[[:space:]]*<\/key>/ {flag=1; next}
      flag && /<\/array>/ {flag=0; next}
      flag {print}
    ' "$plist_file" 2>/dev/null || true)"
    if [ -z "$plist_modes" ]; then
      problems="$problems $plist_file 缺少 UIBackgroundModes 数组;"
    else
      grep -Fq '<string>location</string>' <<< "$plist_modes" \
        || problems="$problems $plist_file 的 UIBackgroundModes 未含 location;"
      grep -Fq '<string>audio</string>' <<< "$plist_modes" \
        || problems="$problems $plist_file 的 UIBackgroundModes 未含 audio;"
    fi
  fi

  printf '%s' "$problems"
}

# RunLocationSource 后台/Always 采集静态契约（含可注入 seam + 降级提示标识）。
validate_background_location_source() {
  local root="$1"
  local out=""
  local run_source="$root/ios/PurePace/Location/RunLocationSource.swift"
  local run_view="$root/ios/PurePace/Run/RunView.swift"

  if [ ! -f "$run_source" ]; then
    printf '缺少 %s;' "$run_source"
    return 0
  fi
  local needle
  for needle in \
    'allowsBackgroundLocationUpdates = true' \
    'allowsBackgroundLocationUpdates = false' \
    'pausesLocationUpdatesAutomatically = false' \
    'requestWhenInUseAuthorization' \
    'requestAlwaysAuthorization' \
    'backgroundCapable' \
    'backgroundDegradationHint'; do
    grep -Fq -- "$needle" "$run_source" || out="$out RunLocationSource 缺少 '$needle';"
  done

  if [ ! -f "$run_view" ]; then
    out="$out 缺少 $run_view;"
  elif ! grep -Fq -- '"run.backgroundDegraded"' "$run_view"; then
    out="$out RunView 缺少后台定位降级提示标识;"
  fi

  printf '%s' "$out"
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

# Settings 页必须暴露真实播报开关，且不得含「暂无可配置项」或示例数值。
# 输出为空字符串表示通过，否则返回问题描述。
validate_settings_view() {
  local file="$1"
  local problems=""

  if [ ! -f "$file" ]; then
    problems="$problems 缺少 $file;"
    printf '%s' "$problems"
    return
  fi

  grep -Fq 'Toggle' "$file" || problems="$problems Settings 缺少真实 Toggle 开关;"
  grep -Fq '"settings.announcementToggle"' "$file" \
    || problems="$problems Settings 缺少 settings.announcementToggle 标识;"

  if grep -Fq '暂无可配置项' "$file" || grep -Fq 'settings.empty' "$file"; then
    problems="$problems Settings 仍声明无可配置项;"
  fi
  if grep -Eq 'Stepper|Slider' "$file"; then
    problems="$problems Settings 含 Stepper/Slider;"
  fi
  if grep -Eq '示例|Sample' "$file"; then
    problems="$problems Settings 含示例数值;"
  fi

  printf '%s' "$problems"
}

# App 源码不得引用夹具/样例数据；`.gpx` 扩展名本身合法（导出链路必须产出真实 .gpx）。
# 输出为空字符串表示通过，否则返回问题描述。
validate_no_fixture_data() {
  local dir="$1"
  local problems=""

  if grep -rEq --include='*.swift' 'shared/fixtures|\.tcx|sample[^"[:space:]]*\.gpx' "$dir" 2>/dev/null; then
    problems="$problems App 源码引用夹具/样例数据;"
  fi

  printf '%s' "$problems"
}

# 用户可见文案单一来源（String Catalog，zh-Hans）+ 三屏视图零裸英文；输出为空字符串表示通过。
validate_localization() {
  local root="$1"
  local problems=""
  local catalog="$root/ios/PurePace/Resources/Localizable.xcstrings"
  local spec="$root/ios/project.yml"

  if [ ! -s "$catalog" ]; then
    problems="$problems 缺少 ios/PurePace/Resources/Localizable.xcstrings;"
  else
    grep -Fq '"sourceLanguage" : "zh-Hans"' "$catalog" \
      || problems="$problems String Catalog sourceLanguage 必须为 zh-Hans;"
    local value
    for value in '"跑步"' '"历史"' '"设置"'; do
      grep -Fq "$value" "$catalog" || problems="$problems String Catalog 缺少文案 $value;"
    done
  fi

  if [ ! -f "$spec" ]; then
    problems="$problems 缺少 ios/project.yml;"
  else
    grep -Fq 'INFOPLIST_KEY_CFBundleDevelopmentRegion: zh-Hans' "$spec" \
      || problems="$problems project.yml 未声明 CFBundleDevelopmentRegion=zh-Hans;"
    grep -Fq 'knownRegions:' "$spec" || problems="$problems project.yml 未声明 knownRegions;"
  fi

  local view hits
  for view in ContentView.swift Run/RunView.swift History/HistoryView.swift \
    History/RunDetailView.swift Settings/SettingsView.swift; do
    if [ ! -f "$root/ios/PurePace/$view" ]; then
      problems="$problems 缺少 ios/PurePace/$view;"
      continue
    fi
    # 视图内直接写英文文案一律判失败（L10n 键与 identifier 不受影响）。
    hits="$(grep -nE '(Text|Label|Button|navigationTitle|accessibilityLabel)\("[A-Za-z]' \
      "$root/ios/PurePace/$view" || true)"
    [ -z "$hits" ] || problems="$problems ios/PurePace/$view 残留裸英文文案: $(printf '%s' "$hits" | tr '\n' ' ');"
  done

  printf '%s' "$problems"
}

# 设计 token 单一真源 + 三屏只引用 token + 主按钮可读标签；输出为空字符串表示通过。
validate_design_tokens() {
  local root="$1"
  local problems=""
  local token_file="$root/ios/PurePace/Design/DesignTokens.swift"
  local run_view="$root/ios/PurePace/Run/RunView.swift"
  local history_view="$root/ios/PurePace/History/HistoryView.swift"
  local settings_view="$root/ios/PurePace/Settings/SettingsView.swift"
  local detail_view="$root/ios/PurePace/History/RunDetailView.swift"
  local content_view="$root/ios/PurePace/ContentView.swift"

  local file
  for file in "$token_file" "$run_view" "$history_view" "$settings_view" "$detail_view" "$content_view"; do
    [ -f "$file" ] || problems="$problems 缺少 ${file#"$root"/};"
  done
  if [ -n "$problems" ]; then
    printf '%s' "$problems"
    return
  fi

  # token 定义必须唯一，且覆盖颜色 / 字号 / 间距 / 圆角 / 图标 / 最小触控尺寸。
  local token_definitions
  token_definitions="$(grep -rlE --include='*.swift' '^enum DesignTokens' "$root/ios/PurePace" 2>/dev/null | wc -l | tr -d ' ')"
  [ "$token_definitions" = "1" ] || problems="$problems Token 定义必须唯一，实际 ${token_definitions} 处;"
  local section
  for section in 'enum Colors' 'enum Typography' 'enum Spacing' 'enum Radius' 'enum Icon' 'enum Appearance' 'minTapTarget'; do
    grep -Fq "$section" "$token_file" || problems="$problems Token 缺少 ${section};"
  done
  grep -Eq 'minTapTarget: CGFloat = 44' "$token_file" || problems="$problems minTapTarget 必须为 44;"
  grep -Fq 'supportsDarkMode = true' "$token_file" \
    || problems="$problems 深色模式必须开启（supportsDarkMode = true）;"

  # 语义色必须 light/dark 成对：两侧计数一致且至少一组。
  local light_count dark_count
  light_count="$(grep -oE 'light:' "$token_file" | wc -l | tr -d ' ')"
  dark_count="$(grep -oE 'dark:' "$token_file" | wc -l | tr -d ' ')"
  if [ "$light_count" -lt 1 ] || [ "$light_count" != "$dark_count" ]; then
    problems="$problems 语义色 light/dark 未成对（light=${light_count} dark=${dark_count}）;"
  fi

  # 字面色值 / 零散字体修饰符：扫描四个视图 + ContentView + Design 下非 token 真源的组件文件。
  local style_files="$run_view $history_view $settings_view $detail_view $content_view"
  local design_file
  for design_file in "$root"/ios/PurePace/Design/*.swift; do
    [ -f "$design_file" ] || continue
    [ "$design_file" = "$token_file" ] && continue
    style_files="$style_files $design_file"
  done

  local hits
  for file in $style_files; do
    hits="$(grep -nE 'Color\(|Color\.|UIColor|#colorLiteral|\.foregroundStyle\(\.[A-Za-z]' "$file" || true)"
    [ -z "$hits" ] \
      || problems="$problems ${file#"$root"/} 含字面色值: $(printf '%s' "$hits" | tr '\n' ' ');"
    hits="$(grep -nE '\.font\(\.|\.fontWeight\(|\.fontDesign\(|\.lineSpacing\([0-9]' "$file" || true)"
    [ -z "$hits" ] \
      || problems="$problems ${file#"$root"/} 含零散字体修饰符: $(printf '%s' "$hits" | tr '\n' ' ');"
  done

  # 三屏不得出现样式字面量，且必须引用 token 与最小触控尺寸。
  for file in "$run_view" "$history_view" "$settings_view"; do
    if grep -Eq '\.system\(size: *[0-9]|spacing: *[0-9]|\.padding\([0-9]|minHeight: *[0-9]' "$file"; then
      problems="$problems ${file#"$root"/} 含样式字面量;"
    fi
    grep -Fq 'DesignTokens.' "$file" || problems="$problems ${file#"$root"/} 未引用 DesignTokens;"
    grep -Fq 'DesignTokens.minTapTarget' "$file" \
      || problems="$problems ${file#"$root"/} 未引用 minTapTarget;"
  done

  # 跑步页主/次层级：距离用 display，时长与当前配速用 primaryValue，平均配速与分段用 caption。
  grep -Fq 'DesignTokens.Typography.display' "$run_view" || problems="$problems 跑步页主信息未用 display 字号;"
  grep -Fq 'DesignTokens.Typography.primaryValue' "$run_view" || problems="$problems 跑步页未用 primaryValue 字号;"
  grep -Fq 'DesignTokens.Typography.caption' "$run_view" || problems="$problems 跑步页次信息未用 caption 字号;"
  grep -Fq 'DesignTokens.Colors.secondary' "$history_view" || problems="$problems 历史页次信息未用次要色;"

  # 四层结构：hero display → 次级指标 → 提示 → 底部 accent 主操作。
  grep -Fq 'safeAreaInset(edge: .bottom)' "$run_view" \
    || problems="$problems 跑步页主操作未底部锚定（safeAreaInset）;"
  grep -Fq 'DesignTokens.Colors.accent' "$run_view" || problems="$problems 跑步页未引用品牌主色 accent;"

  # 三态视觉：记录中 accent / 暂停 warning / 保存 success（改错一行必须判红）。
  grep -Fq 'case .running: return DesignTokens.Colors.accent' "$run_view" \
    || problems="$problems 记录态未用 accent;"
  grep -Fq 'case .paused: return DesignTokens.Colors.warning' "$run_view" \
    || problems="$problems 暂停态未用 warning;"
  grep -Fq 'if viewModel.didSave { return DesignTokens.Colors.success }' "$run_view" \
    || problems="$problems 保存态未用 success;"

  # 卡片面：历史列表与跑次详情统一 surface / Radius.card / separator，且不退回系统 grouped 默认观感。
  local card_token
  for file in "$history_view" "$detail_view"; do
    for card_token in 'DesignTokens.Colors.surface' 'DesignTokens.Radius.card' 'DesignTokens.Colors.separator'; do
      grep -Fq "$card_token" "$file" \
        || problems="$problems ${file#"$root"/} 缺少卡片 token $card_token;"
    done
    if grep -Eq '\.listStyle\(\.(insetGrouped|grouped)\)' "$file"; then
      problems="$problems ${file#"$root"/} 仍使用系统 grouped 列表观感;"
    fi
  done

  # 等宽数字：跑步页 ≥3（距离 / 主值 / 次值），历史行与详情各 ≥1。
  local mono_count
  mono_count="$(grep -c 'monospacedDigit()' "$run_view" || true)"
  [ "$mono_count" -ge 3 ] || problems="$problems 跑步页等宽数字少于 3 处（实际 ${mono_count}）;"
  mono_count="$(grep -c 'monospacedDigit()' "$history_view" || true)"
  [ "$mono_count" -ge 1 ] || problems="$problems 历史行缺少等宽数字;"
  mono_count="$(grep -c 'monospacedDigit()' "$detail_view" || true)"
  [ "$mono_count" -ge 1 ] || problems="$problems 详情数值缺少等宽数字;"

  # 可及 identifier 集合冻结：固定 33 项，逐项比对且总数必须相等。
  local expected_ids expected_count actual_ids actual_count
  expected_ids="history.empty history.row history.runAgain run.averagePace run.backgroundDegraded run.currentPace run.distance run.elapsed run.finish run.pause run.resume run.saved run.splits run.start run.telemetry run.viewHistory runDetail.activeDuration runDetail.averagePace runDetail.distance runDetail.endedAt runDetail.export runDetail.exportFailed runDetail.exported runDetail.root runDetail.share runDetail.splitRow runDetail.splits runDetail.splitsEmpty runDetail.startedAt settings.announcementToggle tab.history tab.run tab.settings"
  actual_ids="$( {
    grep -rhoE --include='*.swift' \
      'accessibilityIdentifier\("(run|runDetail|history|tab|settings)\.[A-Za-z0-9_.]+"\)' \
      "$root/ios/PurePace" 2>/dev/null || true
    grep -rhoE --include='*.swift' \
      'identifier: "(run|runDetail|history|tab|settings)\.[A-Za-z0-9_.]+"' \
      "$root/ios/PurePace" 2>/dev/null || true
  } | sed -E 's/.*"([^"]*)".*/\1/' | LC_ALL=C sort -u | tr '\n' ' ' | sed -e 's/ $//')"
  expected_count="$(printf '%s\n' $expected_ids | wc -l | tr -d ' ')"
  actual_count="$(printf '%s\n' $actual_ids | wc -l | tr -d ' ')"
  if [ "$expected_count" != "33" ]; then
    problems="$problems 冻结 identifier 清单必须为 33 项（实际 ${expected_count}）;"
  fi
  if [ "$actual_count" != "$expected_count" ]; then
    problems="$problems 可及 identifier 数量必须为 ${expected_count}（实际 ${actual_count}: ${actual_ids}）;"
  fi
  if [ "$actual_ids" != "$expected_ids" ]; then
    problems="$problems 可及 identifier 集合与冻结清单不一致（实际: ${actual_ids}）;"
  fi

  # 关键文案必须走 L10n 键（真实值在 Localizable.xcstrings，见 validate_localization）。
  local key
  for key in runActionStart runActionPause runActionResume runActionFinish; do
    grep -Fq "L10n.$key" "$run_view" || problems="$problems 跑步页缺少 L10n.$key;"
  done
  grep -Fq 'L10n.historyEmptyTitle' "$history_view" || problems="$problems 历史空态缺少标题键;"
  grep -Fq 'L10n.historyRunAgain' "$history_view" || problems="$problems 历史空态缺少 CTA 键;"
  grep -Fq 'L10n.settingsAnnouncementTitle' "$settings_view" || problems="$problems 设置页缺少播报开关文案键;"
  grep -Fq 'L10n.runDetailExportButton' "$detail_view" || problems="$problems 详情页缺少导出入口文案键;"

  # 主操作标签：四个互不相同且非空。
  if grep -Fq 'label: ""' "$run_view"; then
    problems="$problems 跑步页存在空 accessibilityLabel;"
  fi
  local label_count
  label_count="$(grep -oE 'label: L10n\.[A-Za-z0-9]+' "$run_view" | sort -u | wc -l | tr -d ' ')"
  [ "$label_count" -ge 4 ] || problems="$problems 跑步页主操作 accessibilityLabel 少于 4 个互不相同的非空值;"
  grep -Fq 'accessibilityLabel(Text(label))' "$run_view" || problems="$problems 跑步页主操作缺少 accessibilityLabel;"
  grep -Fq 'accessibilityLabel(Text(L10n.historyRunAgain))' "$history_view" \
    || problems="$problems 历史空态 CTA 缺少 accessibilityLabel;"
  grep -Fq 'accessibilityLabel(Text(L10n.runDetailExportLabel))' "$detail_view" \
    || problems="$problems 导出按钮缺少 accessibilityLabel;"

  # 可及标识：主操作 / 关键控件必须可被可及树按 identifier 定位。
  local control_pair
  for control_pair in \
    "$run_view:run.start" "$run_view:run.pause" "$run_view:run.resume" "$run_view:run.finish" \
    "$history_view:history.runAgain" "$history_view:history.row" \
    "$detail_view:runDetail.export" "$detail_view:runDetail.root" \
    "$settings_view:settings.announcementToggle"; do
    file="${control_pair%%:*}"
    local control_id="${control_pair##*:}"
    grep -Fq "accessibilityIdentifier(\"$control_id\")" "$file" \
      || problems="$problems ${file#"$root"/} 缺少可及标识 $control_id;"
  done

  # 首屏 / 工作流工具栏不得出现 demo / 示例入口按钮（演示态只允许启动参数门控注入）。
  if grep -Eq '(Button|ToolbarItem|NavigationLink|Label)[^"]*"[^"]*(示例|样例|Demo|demo)' \
    "$run_view" "$history_view" "$settings_view" "$detail_view" "$content_view"; then
    problems="$problems 首屏/工具栏出现 demo/示例入口;"
  fi

  # Tab 可读标签与标识：Label 文案走 L10n 键，tab.<name> 标识成对出现。
  local tab_pair
  for tab_pair in "tabRun:tab.run" "tabHistory:tab.history" "tabSettings:tab.settings"; do
    local tab_key="${tab_pair%%:*}"
    local tab_id="${tab_pair##*:}"
    grep -Fq "Label(L10n.$tab_key" "$content_view" \
      || problems="$problems ContentView 缺少 Tab 文案键 L10n.$tab_key;"
    grep -Fq "\"$tab_id\"" "$content_view" \
      || problems="$problems ContentView 缺少 Tab 标识 $tab_id;"
  done

  printf '%s' "$problems"
}

# project.yml 指定 target 段（2 空格缩进的 target 名，到下一个同级 target 为止）。
project_target_section() {
  local spec_file="$1" target="$2"
  awk -v target="$target" '
    index($0, "  " target ":") == 1 {flag=1; next}
    flag && /^  [A-Za-z_][A-Za-z0-9_]*:/ {flag=0}
    flag {print}
  ' "$spec_file" 2>/dev/null || true
}

# 段内 info.properties.UIBackgroundModes 数组取值（去掉缩进与行首 '-'，每行一个）。
project_background_mode_values() {
  printf '%s\n' "$1" | awk '
    /^[[:space:]]*UIBackgroundModes:[[:space:]]*$/ {flag=1; next}
    flag && /^[[:space:]]*-[[:space:]]*[^[:space:]]/ {
      line=$0
      sub(/^[[:space:]]*-[[:space:]]*/, "", line)
      sub(/[[:space:]]+$/, "", line)
      print line
      next
    }
    flag {flag=0}
  ' 2>/dev/null || true
}

# 测试侧音源静态契约：UITests 后台音频声明、runner 合成音资产、旧音源 id 清除、目标 id 常量钉死。
validate_uitests_music_source() {
  local root="$1"
  local spec_file="$root/ios/project.yml"
  local problems=""

  local uitests_modes
  uitests_modes="$(project_background_mode_values "$(project_target_section "$spec_file" "PurePaceUITests")")"
  if [ "$uitests_modes" != "audio" ]; then
    problems="$problems project.yml 的 PurePaceUITests target UIBackgroundModes 必须恰为 [audio]（实际 '${uitests_modes}'; 脚本内换行以空格分隔）;"
  fi

  local wav="$root/ios/PurePaceUITests/Fixtures/runner-music-loop.wav"
  if [ ! -s "$wav" ]; then
    problems="$problems 缺少 $root/ios/PurePaceUITests/Fixtures/runner-music-loop.wav（runner 自播合成音源）;"
  else
    local bytes
    bytes="$(wc -c < "$wav" | tr -d ' ')"
    if [ "$bytes" -gt 204800 ]; then
      problems="$problems runner-music-loop.wav 为 $bytes 字节，超过 204800 字节上限;"
    fi
  fi

  # 全仓旧音源 id 零命中（治理归档 .munk/** 除外：历史 change pack 是记录，不是可执行面）。
  if grep -rIl --exclude-dir=.git --exclude-dir=.build --exclude-dir=artifacts --exclude-dir=.munk \
    -e 'com\.apple\.MobileMusic' "$root" >/dev/null 2>&1; then
    problems="$problems 全仓仍存在 com.apple.Mobile""Music（旧音源 id 必须清除）;"
  fi

  local strategy_file="$root/ios/PurePaceUITests/MusicSource.swift"
  if [ ! -f "$strategy_file" ]; then
    problems="$problems 缺少 $root/ios/PurePaceUITests/MusicSource.swift;"
  elif ! grep -Fq 'static let defaultBundleIdentifier = "com.apple.Music"' "$strategy_file"; then
    problems="$problems MusicSource 常量 defaultBundleIdentifier 必须等于 com.apple.Music;"
  fi

  printf '%s' "$problems"
}

# 后台定位源码自检：复制真实源码后做单点破坏，验证断言非恒真。
background_source_selftest() {
  local label="$1" mutate="$2" sandbox="" out=""
  sandbox="$(mktemp -d "${TMPDIR:-/tmp}/purepace-check-ios-bg.XXXXXX")"
  mkdir -p "$sandbox/ios/PurePace/Location" "$sandbox/ios/PurePace/Run"
  cp ios/PurePace/Location/RunLocationSource.swift "$sandbox/ios/PurePace/Location/"
  cp ios/PurePace/Run/RunView.swift "$sandbox/ios/PurePace/Run/"
  "$mutate" "$sandbox"
  out="$(validate_background_location_source "$sandbox")"
  if [ -n "$out" ]; then
    pass "$label (self-test)"
  else
    fail "$label" "违规样本未被识别"
  fi
  rm -rf "$sandbox"
}

drop_background_enable() {
  sed -i '' '/allowsBackgroundLocationUpdates = true/d' "$1/ios/PurePace/Location/RunLocationSource.swift"
}
drop_background_reset() {
  sed -i '' '/allowsBackgroundLocationUpdates = false/d' "$1/ios/PurePace/Location/RunLocationSource.swift"
}
drop_always_request() {
  sed -i '' '/requestAlwaysAuthorization()/d' "$1/ios/PurePace/Location/RunLocationSource.swift"
}
drop_degraded_hint() {
  sed -i '' '/run.backgroundDegraded/d' "$1/ios/PurePace/Run/RunView.swift"
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

  # project.yml 定位配置正负反例（数组声明 + 禁止重复 INFOPLIST_KEY_UIBackgroundModes）
  local usage_block
  usage_block='    INFOPLIST_KEY_NSLocationWhenInUseUsageDescription: "跑步定位用途说明"\n    INFOPLIST_KEY_NSLocationAlwaysAndWhenInUseUsageDescription: "始终允许定位用途说明"\n'
  local modes_both
  modes_both='        UIBackgroundModes:\n          - location\n          - audio\n'
  local modes_only_location
  modes_only_location='        UIBackgroundModes:\n          - location\n'
  local modes_only_audio
  modes_only_audio='        UIBackgroundModes:\n          - audio\n'

  printf 'settings:\n  base:\n%b  PurePace:\n    info:\n      properties:\n%b' "$usage_block" "$modes_both" > "$tmp_dir/location-good.yml"
  printf 'settings:\n  base:\n%b  PurePace:\n    info:\n      properties:\n' "$usage_block" > "$tmp_dir/location-no-background.yml"
  printf 'settings:\n  base:\n    INFOPLIST_KEY_NSLocationWhenInUseUsageDescription: ""\n    INFOPLIST_KEY_NSLocationAlwaysAndWhenInUseUsageDescription: "始终允许定位用途说明"\n  PurePace:\n    info:\n      properties:\n%b' "$modes_both" > "$tmp_dir/location-empty-usage.yml"
  printf 'settings:\n  base:\n    INFOPLIST_KEY_NSLocationWhenInUseUsageDescription: "跑步定位用途说明"\n    INFOPLIST_KEY_NSLocationAlwaysAndWhenInUseUsageDescription: ""\n  PurePace:\n    info:\n      properties:\n%b' "$modes_both" > "$tmp_dir/location-empty-always-usage.yml"
  printf 'settings:\n  base:\n%b  PurePace:\n    info:\n      properties:\n%b' "$usage_block" "$modes_only_location" > "$tmp_dir/location-no-audio.yml"
  printf 'settings:\n  base:\n%b  PurePace:\n    info:\n      properties:\n%b' "$usage_block" "$modes_only_audio" > "$tmp_dir/location-no-location.yml"
  printf 'settings:\n  base:\n%b    INFOPLIST_KEY_UIBackgroundModes: location\n  PurePace:\n    info:\n      properties:\n%b' "$usage_block" "$modes_both" > "$tmp_dir/location-duplicate-setting.yml"

  mkdir -p "$tmp_dir/PurePace"
  printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0">\n<dict>\n\t<key>UIBackgroundModes</key>\n\t<array>\n\t\t<string>location</string>\n\t\t<string>audio</string>\n\t</array>\n</dict>\n</plist>\n' > "$tmp_dir/PurePace/Info.plist"
  check_ok "定位配置正例" "$(validate_location_config "$tmp_dir/location-good.yml")"
  check_fail "缺 UIBackgroundModes 数组反例" "$(validate_location_config "$tmp_dir/location-no-background.yml")"
  check_fail "用途说明为空反例" "$(validate_location_config "$tmp_dir/location-empty-usage.yml")"
  check_fail "Always 用途说明为空反例" "$(validate_location_config "$tmp_dir/location-empty-always-usage.yml")"
  check_fail "UIBackgroundModes 数组缺 audio 反例" "$(validate_location_config "$tmp_dir/location-no-audio.yml")"
  check_fail "UIBackgroundModes 数组缺 location 反例" "$(validate_location_config "$tmp_dir/location-no-location.yml")"
  check_fail "重复 INFOPLIST_KEY_UIBackgroundModes 反例" "$(validate_location_config "$tmp_dir/location-duplicate-setting.yml")"

  # 承载 UIBackgroundModes 的基础 Info.plist 正负反例
  mkdir -p "$tmp_dir/location-no-plist"
  printf 'settings:\n  base:\n%b  PurePace:\n    info:\n      properties:\n%b' "$usage_block" "$modes_both" > "$tmp_dir/location-no-plist/project.yml"
  check_fail "缺基础 Info.plist 反例" "$(validate_location_config "$tmp_dir/location-no-plist/project.yml")"

  mkdir -p "$tmp_dir/location-plist-no-audio/PurePace"
  printf 'settings:\n  base:\n%b  PurePace:\n    info:\n      properties:\n%b' "$usage_block" "$modes_both" > "$tmp_dir/location-plist-no-audio/project.yml"
  printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0">\n<dict>\n\t<key>UIBackgroundModes</key>\n\t<array>\n\t\t<string>location</string>\n\t</array>\n</dict>\n</plist>\n' > "$tmp_dir/location-plist-no-audio/PurePace/Info.plist"
  check_fail "基础 Info.plist 缺 audio 反例" "$(validate_location_config "$tmp_dir/location-plist-no-audio/project.yml")"

  mkdir -p "$tmp_dir/location-plist-no-location/PurePace"
  printf 'settings:\n  base:\n%b  PurePace:\n    info:\n      properties:\n%b' "$usage_block" "$modes_both" > "$tmp_dir/location-plist-no-location/project.yml"
  printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0">\n<dict>\n\t<key>UIBackgroundModes</key>\n\t<array>\n\t\t<string>audio</string>\n\t</array>\n</dict>\n</plist>\n' > "$tmp_dir/location-plist-no-location/PurePace/Info.plist"
  check_fail "基础 Info.plist 缺 location 反例" "$(validate_location_config "$tmp_dir/location-plist-no-location/project.yml")"

  # RunLocationSource 后台/Always 契约正负反例
  mkdir -p "$tmp_dir/bg-source/ios/PurePace/Location" "$tmp_dir/bg-source/ios/PurePace/Run"
  cp ios/PurePace/Location/RunLocationSource.swift "$tmp_dir/bg-source/ios/PurePace/Location/"
  cp ios/PurePace/Run/RunView.swift "$tmp_dir/bg-source/ios/PurePace/Run/"
  check_ok "后台定位源码正例" "$(validate_background_location_source "$tmp_dir/bg-source")"
  background_source_selftest "ac-bg-source-background-enable" drop_background_enable
  background_source_selftest "ac-bg-source-background-reset" drop_background_reset
  background_source_selftest "ac-bg-source-always-upgrade" drop_always_request
  background_source_selftest "ac-bg-source-degraded-hint" drop_degraded_hint

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

  # Settings 开关正负反例
  mkdir -p "$tmp_dir/settings-good"
  printf 'Toggle("每公里语音播报", isOn: .constant(true))\n  .accessibilityIdentifier("settings.announcementToggle")\n' \
    > "$tmp_dir/settings-good/SettingsView.swift"
  check_ok "Settings 真实开关正例" "$(validate_settings_view "$tmp_dir/settings-good/SettingsView.swift")"

  mkdir -p "$tmp_dir/settings-no-toggle"
  printf 'Text("本阶段暂无可配置项")\n' > "$tmp_dir/settings-no-toggle/SettingsView.swift"
  check_fail "Settings 缺 Toggle 反例" "$(validate_settings_view "$tmp_dir/settings-no-toggle/SettingsView.swift")"

  mkdir -p "$tmp_dir/settings-stepper"
  printf 'Toggle("每公里语音播报", isOn: .constant(true))\n  .accessibilityIdentifier("settings.announcementToggle")\nStepper("音量", value: .constant(1))\n' \
    > "$tmp_dir/settings-stepper/SettingsView.swift"
  check_fail "Settings 含 Stepper 反例" "$(validate_settings_view "$tmp_dir/settings-stepper/SettingsView.swift")"

  mkdir -p "$tmp_dir/settings-sample"
  printf 'Toggle("每公里语音播报", isOn: .constant(true))\n  .accessibilityIdentifier("settings.announcementToggle")\nText("示例 5.00 km")\n' \
    > "$tmp_dir/settings-sample/SettingsView.swift"
  check_fail "Settings 含示例数值反例" "$(validate_settings_view "$tmp_dir/settings-sample/SettingsView.swift")"

  # App 夹具引用正负反例（.gpx 扩展名字面量合法，仅禁止夹具/样例文件引用）
  mkdir -p "$tmp_dir/app-fixture-good"
  printf 'let ext = "gpx"\nlet target = directory.appendingPathExtension("gpx")\n' \
    > "$tmp_dir/app-fixture-good/RunExportState.swift"
  check_ok "App 无夹具引用正例" "$(validate_no_fixture_data "$tmp_dir/app-fixture-good")"

  mkdir -p "$tmp_dir/app-fixture-bad"
  printf 'let fixture = "shared/fixtures/sample-run.gpx"\n' \
    > "$tmp_dir/app-fixture-bad/RunExportState.swift"
  check_fail "App 引用夹具反例" "$(validate_no_fixture_data "$tmp_dir/app-fixture-bad")"

  # 本地化单一来源与视图零裸英文正负反例（正例直接复制真实源码）。
  local loc_good="$tmp_dir/localization-good"
  mkdir -p "$loc_good/ios/PurePace/Resources" "$loc_good/ios/PurePace/Run" \
    "$loc_good/ios/PurePace/History" "$loc_good/ios/PurePace/Settings"
  cp ios/PurePace/Resources/Localizable.xcstrings "$loc_good/ios/PurePace/Resources/"
  cp ios/project.yml "$loc_good/ios/project.yml"
  cp ios/PurePace/ContentView.swift "$loc_good/ios/PurePace/"
  cp ios/PurePace/Run/RunView.swift "$loc_good/ios/PurePace/Run/"
  cp ios/PurePace/History/HistoryView.swift "$loc_good/ios/PurePace/History/"
  cp ios/PurePace/History/RunDetailView.swift "$loc_good/ios/PurePace/History/"
  cp ios/PurePace/Settings/SettingsView.swift "$loc_good/ios/PurePace/Settings/"
  check_ok "本地化单一来源正例" "$(validate_localization "$loc_good")"

  local loc_bad="$tmp_dir/localization-bad"
  cp -R "$loc_good" "$loc_bad"
  printf '\nprivate let bareEnglish = Text("Settings")\n' \
    >> "$loc_bad/ios/PurePace/Settings/SettingsView.swift"
  check_fail "视图裸英文反例" "$(validate_localization "$loc_bad")"

  loc_bad="$tmp_dir/localization-no-catalog"
  cp -R "$loc_good" "$loc_bad"
  rm "$loc_bad/ios/PurePace/Resources/Localizable.xcstrings"
  check_fail "缺 String Catalog 反例" "$(validate_localization "$loc_bad")"

  # 设计 token 单一真源与三屏契约正负反例（正例直接复制真实源码）。
  local design_root="$tmp_dir/design-good"
  mkdir -p "$design_root/ios/PurePace/Design" "$design_root/ios/PurePace/Run" \
    "$design_root/ios/PurePace/History" "$design_root/ios/PurePace/Settings"
  cp ios/PurePace/Design/DesignTokens.swift "$design_root/ios/PurePace/Design/"
  cp ios/PurePace/Run/RunView.swift "$design_root/ios/PurePace/Run/"
  cp ios/PurePace/History/HistoryView.swift "$design_root/ios/PurePace/History/"
  cp ios/PurePace/History/RunDetailView.swift "$design_root/ios/PurePace/History/"
  cp ios/PurePace/Settings/SettingsView.swift "$design_root/ios/PurePace/Settings/"
  cp ios/PurePace/ContentView.swift "$design_root/ios/PurePace/"
  check_ok "设计 token 正例" "$(validate_design_tokens "$design_root")"

  local design_bad="$tmp_dir/design-no-token"
  cp -R "$design_root" "$design_bad"
  rm "$design_bad/ios/PurePace/Design/DesignTokens.swift"
  check_fail "缺设计 token 文件反例" "$(validate_design_tokens "$design_bad")"

  design_bad="$tmp_dir/design-magic"
  cp -R "$design_root" "$design_bad"
  printf '\nprivate let magicSpacing = VStack(spacing: 20) { EmptyView() }\n' \
    >> "$design_bad/ios/PurePace/Run/RunView.swift"
  check_fail "样式字面量反例" "$(validate_design_tokens "$design_bad")"

  design_bad="$tmp_dir/design-empty-label"
  cp -R "$design_root" "$design_bad"
  sed -i '' 's/label: L10n.runStartLabel/label: ""/' "$design_bad/ios/PurePace/Run/RunView.swift"
  check_fail "空 accessibilityLabel 反例" "$(validate_design_tokens "$design_bad")"

  design_bad="$tmp_dir/design-no-tab"
  cp -R "$design_root" "$design_bad"
  sed -i '' 's/"tab.settings"/"tab.missing"/' "$design_bad/ios/PurePace/ContentView.swift"
  check_fail "缺 Tab 标识反例" "$(validate_design_tokens "$design_bad")"

  design_bad="$tmp_dir/design-no-control-id"
  cp -R "$design_root" "$design_bad"
  sed -i '' 's/accessibilityIdentifier("run.start")/accessibilityIdentifier("run.start.removed")/' \
    "$design_bad/ios/PurePace/Run/RunView.swift"
  check_fail "主操作缺可及标识反例" "$(validate_design_tokens "$design_bad")"

  design_bad="$tmp_dir/design-demo-entry"
  cp -R "$design_root" "$design_bad"
  printf '\nprivate let demoEntry = Button("示例跑次") {}\n' \
    >> "$design_bad/ios/PurePace/ContentView.swift"
  check_fail "demo/示例入口反例" "$(validate_design_tokens "$design_bad")"

  design_bad="$tmp_dir/design-literal-color"
  cp -R "$design_root" "$design_bad"
  printf '\nprivate let magicColor = EmptyView().foregroundStyle(Color.red)\n' \
    >> "$design_bad/ios/PurePace/Settings/SettingsView.swift"
  check_fail "字面色值反例" "$(validate_design_tokens "$design_bad")"

  design_bad="$tmp_dir/design-scattered-font"
  cp -R "$design_root" "$design_bad"
  printf '\nprivate let magicFont = EmptyView().font(.system(size: 12))\n' \
    >> "$design_bad/ios/PurePace/History/RunDetailView.swift"
  check_fail "零散字体修饰符反例" "$(validate_design_tokens "$design_bad")"

  design_bad="$tmp_dir/design-dark-off"
  cp -R "$design_root" "$design_bad"
  sed -i '' 's/supportsDarkMode = true/supportsDarkMode = false/' \
    "$design_bad/ios/PurePace/Design/DesignTokens.swift"
  check_fail "深色模式关闭反例" "$(validate_design_tokens "$design_bad")"

  design_bad="$tmp_dir/design-no-surface"
  cp -R "$design_root" "$design_bad"
  sed -i '' 's/DesignTokens\.Colors\.surface/DesignTokens.Colors.background/g' \
    "$design_bad/ios/PurePace/History/HistoryView.swift"
  check_fail "移除卡片 surface 引用反例" "$(validate_design_tokens "$design_bad")"

  design_bad="$tmp_dir/design-wrong-running-tint"
  cp -R "$design_root" "$design_bad"
  sed -i '' 's/case \.running: return DesignTokens\.Colors\.accent/case .running: return DesignTokens.Colors.warning/' \
    "$design_bad/ios/PurePace/Run/RunView.swift"
  check_fail "记录态改错为 warning 反例" "$(validate_design_tokens "$design_bad")"

  design_bad="$tmp_dir/design-renamed-id"
  cp -R "$design_root" "$design_bad"
  sed -i '' 's/accessibilityIdentifier("run\.start")/accessibilityIdentifier("run.started")/' \
    "$design_bad/ios/PurePace/Run/RunView.swift"
  check_fail "identifier 重命名反例" "$(validate_design_tokens "$design_bad")"

  design_bad="$tmp_dir/design-extra-id"
  cp -R "$design_root" "$design_bad"
  printf '\nprivate let extraEntry = Button("扩展") {}\n.accessibilityIdentifier("run.extra")\n' \
    >> "$design_bad/ios/PurePace/Run/RunView.swift"
  check_fail "identifier 追加反例" "$(validate_design_tokens "$design_bad")"

  if [ "$failures" -ne 0 ]; then
    exit 1
  fi
  printf '[PASS] self-test (包/import/定位配置/Harness 清单/Settings 开关/设计 token/本地化 正负反例)\n'
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
# pbxproj 是生成物：既不能入库，也要在生成后被 .gitignore 覆盖。
tracked_pbxproj="$(git ls-files 2>/dev/null | grep -F 'project.pbxproj' || true)"
[ -z "$tracked_pbxproj" ] \
  || problems="$problems git 索引仍跟踪 project.pbxproj: $(printf '%s' "$tracked_pbxproj" | tr '\n' ' ');"
if ! git check-ignore -q "$pbxproj" 2>/dev/null; then
  problems="$problems .gitignore 未忽略生成物 $pbxproj;"
fi
# 游离 pbxproj：排除生成目录与已被 .gitignore 忽略的生成物后仍存在即失败。
stray_pbxproj=""
while IFS= read -r candidate; do
  [ -z "$candidate" ] && continue
  [ "$candidate" = "./$pbxproj" ] && continue
  case "$candidate" in
    ./ios/.build/*) continue ;;
  esac
  git check-ignore -q "$candidate" 2>/dev/null && continue
  stray_pbxproj="$stray_pbxproj $candidate"
done <<EOF
$(find . -name project.pbxproj -not -path './ios/.build/*' -print 2>/dev/null | head -20)
EOF
[ -z "$stray_pbxproj" ] || problems="$problems 存在额外 project.pbxproj:$stray_pbxproj;"
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
    pass "ac-corelocation-config-declared (用途说明非空 + 后台模式 location + audio、无重复 setting)"
  else
    fail "ac-corelocation-config-declared" "$location_problems"
  fi
fi

# ------------------------------------------------ 后台/Always 定位采集
background_problems="$(validate_background_location_source .)"
if [ -z "$background_problems" ]; then
  pass "ac-background-location-source (Always 升级 + 跑步态后台开关 + 降级提示)"
else
  fail "ac-background-location-source" "$background_problems"
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
live_sources="ios/PurePace/PurePaceApp.swift ios/PurePace/ContentView.swift ios/PurePace/Run/RunView.swift ios/PurePace/Run/RunSessionViewModel.swift ios/PurePace/Run/RunFormatting.swift ios/PurePace/Run/RunStorage.swift ios/PurePace/Run/RunTelemetry.swift ios/PurePace/Run/RunLifecycleTelemetry.swift ios/PurePace/Run/RunLaunchArguments.swift ios/PurePace/Location/RunLocationSource.swift ios/PurePace/Location/RunTestLocationSource.swift ios/PurePace/Location/SystemAuthorizationProbe.swift ios/PurePace/History/HistoryView.swift ios/PurePace/History/RunDetailView.swift ios/PurePace/History/RunDetailContent.swift ios/PurePace/History/RunExportState.swift ios/PurePace/Settings/SettingsView.swift ios/PurePace/Settings/AnnouncementSettingsStore.swift ios/PurePace/Audio/AnnouncementSpeaker.swift ios/PurePace/Audio/AudioSessionAdapter.swift ios/PurePace/Audio/AnnouncementTelemetry.swift"
for file in $live_sources; do
  [ -f "$file" ] || problems="$problems 缺少 $file;"
done
if [ -z "$problems" ]; then
  grep -Fq 'TabView' ios/PurePace/ContentView.swift || problems="$problems 首屏缺少 TabView;"
  for tab in tabRun tabHistory tabSettings; do
    grep -Fq "L10n.$tab" ios/PurePace/ContentView.swift \
      || problems="$problems 缺少 Tab 文案键 L10n.$tab;"
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
  # 锁屏/前后台遥测：四条通知 + 包自报（设备侧唯一来源）
  lifecycle_source="ios/PurePace/Run/RunLifecycleTelemetry.swift"
  for event in protectedDataWillBecomeUnavailable protectedDataDidBecomeAvailable didEnterBackground willEnterForeground; do
    grep -Fq "$event" "$lifecycle_source" || problems="$problems 生命周期遥测缺少事件 $event;"
  done
  grep -Fq 'RunLifecycleEvent' ios/PurePace/Run/RunTelemetry.swift || problems="$problems 遥测未内嵌 events;"
  grep -Fq 'UIBackgroundModes' ios/PurePace/Run/RunTelemetry.swift || problems="$problems 包自报未读取 UIBackgroundModes;"
  grep -Fq 'Bundle.main' ios/PurePace/Run/RunTelemetry.swift || problems="$problems 包自报未读运行中 Bundle.main;"
  # autoStart 解析必须 Release 可编译（无 DEBUG 门）且由 ContentView 接线
  launch_source="ios/PurePace/Run/RunLaunchArguments.swift"
  grep -Fq -- '-autoStartRecording' "$launch_source" || problems="$problems autoStart 解析器缺少启动参数;"
  if grep -Fq '#if DEBUG' "$launch_source"; then
    problems="$problems autoStart 解析器被 DEBUG 门包裹（Release 不可用）;"
  fi
  grep -Fq 'autoStartRecordingEnabled' ios/PurePace/ContentView.swift || problems="$problems ContentView 未传入 autoStart 解析结果;"
  grep -Fq 'didAutoStart' ios/PurePace/Run/RunSessionViewModel.swift || problems="$problems ViewModel 缺少 autoStart 一次性守卫;"
  # 无障碍标识（测试契约）
  for id in run.distance run.elapsed run.currentPace run.averagePace run.splits run.start run.pause run.resume run.finish run.saved run.telemetry; do
    grep -Fq "\"$id\"" ios/PurePace/Run/RunView.swift || problems="$problems 缺少无障碍标识 $id;"
  done
  # 播报偏好必须接线到 ViewModel 与真实播报器
  grep -Fq 'setAnnouncementsEnabled' ios/PurePace/ContentView.swift || problems="$problems ContentView 未同步播报开关;"
  grep -Fq 'update.announcements' ios/PurePace/Run/RunSessionViewModel.swift || problems="$problems ViewModel 未转发播报命令;"
  grep -Fq 'AVSpeechSynthesizer' ios/PurePace/Audio/AnnouncementSpeaker.swift || problems="$problems 播报器未使用 AVSpeechSynthesizer;"
  grep -Fq 'beginAnnouncement' ios/PurePace/Audio/AnnouncementSpeaker.swift || problems="$problems 播报器未激活音频会话;"
  # History / Settings 诚实态
  grep -Fq '"history.empty"' ios/PurePace/History/HistoryView.swift || problems="$problems History 缺少 history.empty 空态;"
  grep -Fq '"history.row"' ios/PurePace/History/HistoryView.swift || problems="$problems History 缺少 history.row 行标识;"
  grep -Fq 'archiveStore.list()' ios/PurePace/History/HistoryView.swift || problems="$problems History 未读取真实归档;"
  grep -Fq 'RunFormatting.paceText' ios/PurePace/History/HistoryView.swift || problems="$problems History 行未补平均配速;"
  grep -Fq 'RunDetailView(record:' ios/PurePace/History/HistoryView.swift || problems="$problems History 未接入跑次详情;"
  # 跑次详情：字段来自 RunRecord 与 RunDetailContent，稳定标识供 UI 测试
  grep -Fq 'RunDetailContent(record: record)' ios/PurePace/History/RunDetailView.swift || problems="$problems 详情页未使用 RunDetailContent;"
  for id in runDetail.root runDetail.startedAt runDetail.endedAt runDetail.distance runDetail.activeDuration runDetail.averagePace runDetail.splits runDetail.splitRow runDetail.splitsEmpty runDetail.export runDetail.exported runDetail.share runDetail.exportFailed; do
    grep -Fq "\"$id\"" ios/PurePace/History/RunDetailView.swift || problems="$problems 缺少详情无障碍标识 $id;"
  done
  # 导出必须经 RunGPXExporter 落盘，目录由 RunStorage 统一构造
  grep -Fq 'RunGPXExporter(directoryURL: exportDirectory' ios/PurePace/Run/RunStorage.swift || problems="$problems RunStorage 未统一构造 GPX 导出器/目录;"
  grep -Fq 'exporter.export(record)' ios/PurePace/History/RunExportState.swift || problems="$problems 导出动作未复用 RunGPXExporter;"
  grep -Fq 'isLandedGPXFile' ios/PurePace/History/RunExportState.swift || problems="$problems 导出未校验真实落盘;"
  grep -Fq 'stores.exporter' ios/PurePace/ContentView.swift || problems="$problems ContentView 未注入 GPX 导出器;"
  grep -Fq 'exporter: exporter' ios/PurePace/History/HistoryView.swift || problems="$problems History 未向详情透传导出能力;"
  grep -Fq 'record.startedAt' ios/PurePace/History/RunDetailContent.swift || problems="$problems 详情映射未取 startedAt;"
  grep -Fq 'record.splits' ios/PurePace/History/RunDetailContent.swift || problems="$problems 详情映射未取 splits;"
  # Settings：真实播报开关（禁止「暂无可配置项」/示例数值/Stepper/Slider）
  settings_problems="$(validate_settings_view ios/PurePace/Settings/SettingsView.swift)"
  [ -z "$settings_problems" ] || problems="$problems $settings_problems"
  # 无内置样例、无夹具引用、无假计时
  fixture_problems="$(validate_no_fixture_data ios/PurePace)"
  [ -z "$fixture_problems" ] || problems="$problems $fixture_problems"
  if grep -rEq --include='*.swift' 'Timer|DispatchQueue\.asyncAfter|CADisplayLink' ios/PurePace/Run; then
    problems="$problems Run 目录含定时器/假计时逻辑;"
  fi
fi
if [ -z "$problems" ]; then
  pass "ac-live-run-ui (Run/History/Settings + 真实定位数据源 + 无障碍标识)"
else
  fail "ac-live-run-ui" "$problems"
fi

# ------------------------------------------------ 设计 token 与三屏层级
design_problems="$(validate_design_tokens .)"
if [ -z "$design_problems" ]; then
  pass "ac-design-tokens (单一 token 真源 + 三屏引用 + 可读标签)"
else
  fail "ac-design-tokens" "$design_problems"
fi

# ------------------------------------------------ 本地化单一来源与零裸英文
localization_problems="$(validate_localization .)"
if [ -z "$localization_problems" ]; then
  pass "ac-visible-copy-zh-hans (String Catalog 单一来源 + 三屏零裸英文)"
else
  fail "ac-visible-copy-zh-hans" "$localization_problems"
fi

# ------------------------------------------------ 测试落点
problems=""
unit_tests="ios/PurePaceTests/RunSessionViewModelTests.swift ios/PurePaceTests/RunLocationSourceTests.swift ios/PurePaceTests/RunFormattingTests.swift ios/PurePaceTests/RunDetailContentTests.swift ios/PurePaceTests/RunExportStateTests.swift ios/PurePaceTests/AnnouncementSettingsStoreTests.swift ios/PurePaceTests/AnnouncementSpeakerTests.swift ios/PurePaceTests/AudioSessionAdapterTests.swift ios/PurePaceTests/RunTelemetryTests.swift ios/PurePaceTests/RunLifecycleTelemetryTests.swift ios/PurePaceTests/RunLaunchArgumentsTests.swift ios/PurePaceTests/DesignTokensTests.swift"
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
  for id in run.start run.pause run.resume run.finish run.saved run.telemetry history.row runDetail.root runDetail.startedAt runDetail.endedAt runDetail.distance runDetail.activeDuration runDetail.averagePace runDetail.splits runDetail.splitRow runDetail.splitsEmpty runDetail.export runDetail.exported runDetail.share runDetail.exportFailed settings.announcementToggle; do
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

# ------------------------------------------------ UI 测试定位源（launch-arg + DEBUG 门控）
ui_location_source_problems() {
  local root="$1" out="" debug_block="" test_count="" assert_count=""
  local test_source="$root/ios/PurePace/Location/RunTestLocationSource.swift"
  local content="$root/ios/PurePace/ContentView.swift"
  local ui="$root/ios/PurePaceUITests/RunFlowUITests.swift"
  local run_source="$root/ios/PurePace/Location/RunLocationSource.swift"

  if [ ! -f "$test_source" ]; then
    out="$out 缺少 $test_source;"
  else
    grep -Fq -- '#if DEBUG' "$test_source" || out="$out 测试定位源缺少 #if DEBUG 门控;"
    grep -Fq -- '#endif' "$test_source" || out="$out 测试定位源缺少 #endif;"
    grep -Fq -- 'RunLocationProviding' "$test_source" || out="$out 测试定位源未实现 RunLocationProviding;"
  fi
  if [ ! -f "$content" ]; then
    out="$out 缺少 $content;"
  else
    grep -Fq -- '-uiTestLocation' "$content" || out="$out ContentView 未按 -uiTestLocation 门控;"
    debug_block="$(awk '/^#if DEBUG/{flag=1;next}/^#else/{flag=0}/^#endif/{flag=0}flag' "$content")"
    grep -Fq -- 'RunTestLocationSource' <<< "$debug_block" \
      || out="$out ContentView 的 DEBUG 分支未注入测试定位源;"
    # 任何 RunTestLocationSource 引用都必须落在 #if DEBUG 区域内（含 #else 分支不得引用）。
    if ! python3 - "$content" <<'PY'
import sys

path = sys.argv[1]
stack = []
violations = 0
with open(path, encoding="utf-8") as handle:
    for line in handle:
        stripped = line.strip()
        if stripped.startswith("#if"):
            stack.append("debug" if stripped == "#if DEBUG" else "other")
        elif stripped.startswith("#else"):
            if stack and stack[-1] == "debug":
                stack[-1] = "other"
        elif stripped.startswith("#endif"):
            if stack:
                stack.pop()
        elif "RunTestLocationSource" in line and "debug" not in stack:
            violations += 1
sys.exit(1 if violations else 0)
PY
    then
      out="$out ContentView 在非 DEBUG 分支引用测试定位源;"
    fi
  fi
  if [ ! -f "$ui" ]; then
    out="$out 缺少 $ui;"
  else
    grep -Fq -- '-uiTestLocation' "$ui" || out="$out RunFlowUITests 未传 -uiTestLocation 启动参数;"
    grep -Fq 'func testStartFinishExportGPXArtifact' "$ui" \
      || out="$out RunFlowUITests 缺少全链路导出用例 testStartFinishExportGPXArtifact;"
    test_count="$(grep -cE '^[[:space:]]*func test[A-Za-z0-9_]*\(' "$ui" || true)"
    assert_count="$(grep -c -- 'XCTAssert' "$ui" || true)"
    [ "$test_count" -eq 5 ] || out="$out RunFlowUITests 用例数 ${test_count}（期望恰 5）;"
    [ "$assert_count" -ge 112 ] || out="$out RunFlowUITests XCTAssert ${assert_count} 次（期望 ≥112）;"
  fi
  if [ ! -f "$run_source" ]; then
    out="$out 缺少 $run_source;"
  else
    grep -Fq -- 'CLLocationManager' "$run_source" || out="$out RunLocationSource 生产定位契约被改;"
    grep -Fq -- 'requestWhenInUseAuthorization' "$run_source" || out="$out RunLocationSource 授权契约被改;"
  fi
  printf '%s' "$out"
}

problems="$(ui_location_source_problems .)"
if [ -z "$problems" ]; then
  pass "ac-ui-test-location-source (launch-arg + DEBUG 门控)"
else
  fail "ac-ui-test-location-source" "$problems"
fi

# 反例自检：去掉测试源的 #if DEBUG / 删 launch arg / 生产分支引用测试源 / 删断言 / 删用例，
# 每一种违规样本都必须被识别，证明断言非恒真。
ui_source_selftest() {
  local label="$1" mutate="$2" sandbox="" out=""
  sandbox="$(mktemp -d "${TMPDIR:-/tmp}/purepace-check-ios-uisrc.XXXXXX")"
  mkdir -p "$sandbox/ios/PurePace/Location" "$sandbox/ios/PurePaceUITests"
  cp ios/PurePace/Location/RunTestLocationSource.swift "$sandbox/ios/PurePace/Location/"
  cp ios/PurePace/Location/RunLocationSource.swift "$sandbox/ios/PurePace/Location/"
  cp ios/PurePace/ContentView.swift "$sandbox/ios/PurePace/"
  cp ios/PurePaceUITests/RunFlowUITests.swift "$sandbox/ios/PurePaceUITests/"
  "$mutate" "$sandbox"
  out="$(ui_location_source_problems "$sandbox")"
  if [ -n "$out" ]; then
    pass "$label (self-test)"
  else
    fail "$label" "违规样本未被识别"
  fi
  rm -rf "$sandbox"
}

no_debug_guard() {
  sed -i '' '/#if DEBUG/d; /#endif/d' "$1/ios/PurePace/Location/RunTestLocationSource.swift"
}
drop_launch_arg() {
  sed -i '' '/-uiTestLocation/d' "$1/ios/PurePaceUITests/RunFlowUITests.swift"
}
leak_test_source() {
  printf '\n#if DEBUG\nlet leaked = RunTestLocationSource()\n#endif\n' >> "$1/ios/PurePace/ContentView.swift"
  printf '\nfinal class LeakProbe { let source = RunTestLocationSource() }\n' >> "$1/ios/PurePace/ContentView.swift"
}
drop_assertions() {
  sed -i '' '/XCTAssert/d' "$1/ios/PurePaceUITests/RunFlowUITests.swift"
}
drop_ui_case() {
  sed -i '' '/func testAnnouncementTogglePersistsAcrossRelaunch/d' "$1/ios/PurePaceUITests/RunFlowUITests.swift"
}
drop_export_ui_case() {
  sed -i '' '/func testStartFinishExportGPXArtifact/d' "$1/ios/PurePaceUITests/RunFlowUITests.swift"
}

ui_source_selftest "ac-ui-test-location-source" no_debug_guard
ui_source_selftest "ac-ui-test-location-arg" drop_launch_arg
ui_source_selftest "ac-ui-test-source-debug-only" leak_test_source
ui_source_selftest "ac-ui-assertions-intact" drop_assertions
ui_source_selftest "ac-ui-test-count-intact" drop_ui_case
ui_source_selftest "ac-ui-export-case-intact" drop_export_ui_case

# ------------------------------------------------ 测试侧音源（runner 自播合成音 + 参数化策略）
# 构建产物读回：模拟器构建存在时才读（lint 门先于 build 门运行，缺失不是失败，但也不冒充通过）。
built_plist_modes() {
  python3 - "$1" <<'PY'
import plistlib
import sys
try:
    with open(sys.argv[1], "rb") as handle:
        doc = plistlib.load(handle)
    print(",".join(doc.get("UIBackgroundModes") or []))
except Exception:
    print("unreadable")
PY
}

validate_built_app_plists() {
  local root="$1"
  local problems=""
  local base="$root/.build/ios/Build/Products/Debug-iphonesimulator"
  local app_plist="$base/PurePace.app/Info.plist"
  local uitests_plist="$base/PurePaceUITests-Runner.app/PlugIns/PurePaceUITests.xctest/Info.plist"

  if [ -f "$app_plist" ]; then
    local app_modes
    app_modes="$(built_plist_modes "$app_plist")"
    if [ "$app_modes" != "location,audio" ]; then
      problems="$problems 产品包 Info.plist 的 UIBackgroundModes 必须恰为 [location, audio]（实际 '$app_modes'）;"
    fi
  fi

  if [ -f "$uitests_plist" ]; then
    local uitests_modes
    uitests_modes="$(built_plist_modes "$uitests_plist")"
    case ",$uitests_modes," in
      *,audio,*) ;;
      *) problems="$problems PurePaceUITests.xctest 的 Info.plist 未含 audio（实际 '$uitests_modes'）;" ;;
    esac
  fi

  printf '%s' "$problems"
}

music_source_selftest() {
  local label="$1" mutate="$2" sandbox="" out=""
  sandbox="$(mktemp -d "${TMPDIR:-/tmp}/purepace-check-ios-music.XXXXXX")"
  mkdir -p "$sandbox/ios/PurePaceUITests/Fixtures"
  cp ios/project.yml "$sandbox/ios/project.yml"
  cp ios/PurePaceUITests/MusicSource.swift "$sandbox/ios/PurePaceUITests/"
  cp ios/PurePaceUITests/Fixtures/runner-music-loop.wav "$sandbox/ios/PurePaceUITests/Fixtures/"
  "$mutate" "$sandbox"
  out="$(validate_uitests_music_source "$sandbox")"
  if [ -n "$out" ]; then
    pass "$label (self-test)"
  else
    fail "$label" "违规样本未被识别"
  fi
  rm -rf "$sandbox"
}

drop_uitests_background_audio() {
  python3 - "$1/ios/project.yml" <<'PY'
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as handle:
    text = handle.read()
needle = "  PurePaceUITests:\n"
index = text.index(needle)
head, tail = text[:index], text[index:]
tail = tail.replace("        UIBackgroundModes:\n          - audio\n", "", 1)
with open(path, "w", encoding="utf-8") as handle:
    handle.write(head + tail)
PY
}

grow_music_asset() {
  python3 - "$1/ios/PurePaceUITests/Fixtures/runner-music-loop.wav" <<'PY'
import sys

with open(sys.argv[1], "wb") as handle:
    handle.write(b"RIFF" + b"\x00" * 204800)
PY
}

inject_legacy_music_id() {
  printf '\n// legacy %s\n' "com.apple.Mobile""Music" >> "$1/ios/PurePaceUITests/MusicSource.swift"
}

wrong_music_bundle_id() {
  python3 - "$1/ios/PurePaceUITests/MusicSource.swift" <<'PY'
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as handle:
    text = handle.read()
good = "com.apple." + 'Music"'
bad = "com.example." + 'NotMusic"'
with open(path, "w", encoding="utf-8") as handle:
    handle.write(text.replace(good, bad, 1))
PY
}

built_plist_selftest() {
  local sandbox out
  sandbox="$(mktemp -d "${TMPDIR:-/tmp}/purepace-check-ios-builtplist.XXXXXX")"
  mkdir -p "$sandbox/.build/ios/Build/Products/Debug-iphonesimulator/PurePace.app" \
    "$sandbox/.build/ios/Build/Products/Debug-iphonesimulator/PurePaceUITests-Runner.app/PlugIns/PurePaceUITests.xctest"
  python3 - "$sandbox/.build/ios/Build/Products/Debug-iphonesimulator" <<'PY'
import os
import plistlib
import sys

base = sys.argv[1]
with open(os.path.join(base, "PurePaceUITests-Runner.app/PlugIns/PurePaceUITests.xctest/Info.plist"), "wb") as handle:
    plistlib.dump({"CFBundleIdentifier": "x.uitests", "UIBackgroundModes": ["audio"]}, handle)
with open(os.path.join(base, "PurePace.app/Info.plist"), "wb") as handle:
    plistlib.dump({"CFBundleIdentifier": "x.app", "UIBackgroundModes": ["location", "audio", "audio"]}, handle)
PY
  out="$(validate_built_app_plists "$sandbox")"
  if [ -n "$out" ]; then
    pass "ac-built-plist-readback (self-test)"
  else
    fail "ac-built-plist-readback" "违规样本未被识别"
  fi
  rm -rf "$sandbox"
}

music_source_selftest "ac-uitests-background-audio-only" drop_uitests_background_audio
music_source_selftest "ac-audio-asset-committed" grow_music_asset
music_source_selftest "ac-no-legacy-music-id" inject_legacy_music_id
music_source_selftest "ac-music-id-constant" wrong_music_bundle_id
built_plist_selftest

problems="$(validate_uitests_music_source .)"
if [ -z "$problems" ]; then
  pass "ac-uitests-music-source (UITests [audio] + 合成音资产 ≤200KB + 无旧 id + 常量 com.apple.Music)"
else
  fail "ac-uitests-music-source" "$problems"
fi

problems="$(validate_built_app_plists .)"
if [ -n "$problems" ]; then
  fail "ac-built-plist-readback" "$problems"
elif [ -f ".build/ios/Build/Products/Debug-iphonesimulator/PurePace.app/Info.plist" ]; then
  pass "ac-built-plist-readback (产品包 [location,audio] + UITests xctest 含 audio)"
else
  echo "[SKIP] ac-built-plist-readback: 无 .build/ios 模拟器构建产物（构建后复跑本门生效）" >&2
fi


# ------------------------------------------------ Release 确定性源（launch-arg 门控，默认关）
# 基础 Info.plist 只承载 UIBackgroundModes = [location, audio]，改动须同步本基线。
INFO_PLIST_SHA256="2b92134b1ab0dfd91b82bda01027df147a2233036b13ed21194fb39eda2642f6"

release_deterministic_problems() {
  local root="$1" out="" usage_keys="" expected_usage="" modes="" plist_sha=""
  local flag='-releaseDeterministicLocation'
  local release_source="$root/ios/PurePace/Location/ReleaseDeterministicLocationSource.swift"
  local selection="$root/ios/PurePace/Location/RunLocationSourceSelection.swift"
  local content="$root/ios/PurePace/ContentView.swift"
  local run_source="$root/ios/PurePace/Location/RunLocationSource.swift"
  local spec="$root/ios/project.yml"
  local plist="$root/ios/PurePace/Info.plist"
  local tests="$root/ios/PurePaceTests/ReleaseDeterministicLocationSourceTests.swift"
  local app_dir="$root/ios/PurePace"
  local ref_file=""
  local ui_file=""

  if [ ! -f "$release_source" ]; then
    out="$out 缺少 $release_source;"
  else
    grep -Fq 'RunLocationProviding' "$release_source" \
      || out="$out 确定性源未实现 RunLocationProviding;"
    # Release 候选包必须能编译到该类型，禁止整体退回 #if DEBUG。
    if grep -Fq -- '#if DEBUG' "$release_source"; then
      out="$out 确定性源被 #if DEBUG 关掉（Release 不可用）;"
    fi
    if grep -Eq '^import (CoreLocation|AVFoundation)' "$release_source"; then
      out="$out 确定性源 import 了 CoreLocation/AVFoundation;"
    fi
    if grep -Eq 'CLLocationManager|startUpdatingLocation|requestWhenInUseAuthorization|requestAlwaysAuthorization' "$release_source"; then
      out="$out 确定性源触碰真实授权/采集 API;"
    fi
    grep -Fq 'km-crossing' "$release_source" || out="$out 确定性源缺少 km-crossing 场景;"
    grep -Fq 'sampleSource: RunSampleSource { .simulated }' "$release_source" \
      || out="$out 确定性源未如实标记 simulated;"
    grep -Fq 'allowsBackgroundLocationUpdates: Bool { false }' "$release_source" \
      || out="$out 确定性源伪造了后台定位能力;"
    grep -Fq 'pausesLocationUpdatesAutomatically: Bool { false }' "$release_source" \
      || out="$out 确定性源伪造了自动暂停能力;"
  fi

  if [ ! -f "$selection" ]; then
    out="$out 缺少 $selection;"
  else
    if grep -Fq -- '#if DEBUG' "$selection"; then
      out="$out 选择逻辑依赖 #if DEBUG（Release 不可用）;"
    fi
    # 默认分支（无 flag/非法 flag）必须构造真实源且不打开调试遥测。
    grep -Fq 'return Selection(source: makeReal(), telemetryDebugEnabled: false)' "$selection" \
      || out="$out 选择器默认分支不再构造真实源;"
    grep -Fq 'return Selection(source: makeDeterministic(scenario), telemetryDebugEnabled: true)' "$selection" \
      || out="$out 选择器 flag 分支不再构造确定性源;"
  fi

  if [ ! -f "$content" ]; then
    out="$out 缺少 $content;"
  else
    grep -Fq 'RunLocationSourceSelection.select' "$content" \
      || out="$out ContentView 未接定位源选择器;"
    grep -Fq 'RunLocationSource()' "$content" \
      || out="$out ContentView 默认闭包未构造真实定位源;"
    grep -Fq 'RunTestLocationSource()' "$content" \
      || out="$out ContentView 删除了既有 Debug UI 用例定位源;"
  fi

  # 普通用户路径无注入入口：确定性源只许出现在 ContentView 与两个定位层文件。
  while IFS= read -r ref_file; do
    [ -z "$ref_file" ] && continue
    case "$ref_file" in
      "$app_dir/ContentView.swift"|"$release_source"|"$selection") ;;
      *) out="$out 普通用户路径引用了确定性源: ${ref_file#"$root"/};" ;;
    esac
  done <<< "$(grep -rlF --include='*.swift' 'ReleaseDeterministicLocationSource' "$app_dir" 2>/dev/null || true)"

  # flag 字符串只许留在定位层（确定性源 + 选择器）与 ContentView 入口，不得泄漏到 UI/Run/Settings。
  while IFS= read -r ref_file; do
    [ -z "$ref_file" ] && continue
    case "$ref_file" in
      "$release_source"|"$selection"|"$app_dir/ContentView.swift") ;;
      *) out="$out flag 泄漏到非定位层: ${ref_file#"$root"/};" ;;
    esac
  done <<< "$(grep -rlF --include='*.swift' -- "$flag" "$app_dir" 2>/dev/null || true)"

  # Release 音频用例必须用确定性源 flag，但 Debug 用例语义不得被替换：
  # 含该 flag 的 UI 测试文件必须同时保留 -uiTestLocation 与 #if DEBUG/#else 配置分支。
  while IFS= read -r ui_file; do
    [ -z "$ui_file" ] && continue
    if ! grep -Fq -- '-uiTestLocation' "$ui_file" \
      || ! grep -Fq -- '#if DEBUG' "$ui_file" \
      || ! grep -Fq -- '#else' "$ui_file"; then
      out="$out UI 测试出现 ${flag} 但未保留 Debug 用例语义: ${ui_file#"$root"/};"
    fi
  done <<< "$(grep -rlF --include='*.swift' -- "$flag" "$root/ios/PurePaceUITests" 2>/dev/null || true)"

  if [ -f "$run_source" ] && grep -Fq -- "$flag" "$run_source"; then
    out="$out 真实定位源出现确定性 flag;"
  fi

  if [ ! -f "$tests" ]; then
    out="$out 缺少 $tests;"
  else
    grep -Fq '@testable import PurePace' "$tests" || out="$out 确定性源单测未导入 App 模块;"
    grep -Fq 'XCTAssert' "$tests" || out="$out 确定性源单测无断言;"
    if grep -Eq '(Thread\.sleep|sleep\()' "$tests"; then
      out="$out 确定性源单测使用固定 sleep;"
    fi
  fi

  if [ ! -f "$spec" ]; then
    out="$out 缺少 $spec;"
  else
    # 无 flag 时不得引入额外权限声明：定位用途说明键恰为既有两条。
    usage_keys="$(grep -oE 'INFOPLIST_KEY_NS[A-Za-z]*UsageDescription' "$spec" | sort -u || true)"
    expected_usage="$(printf '%s\n' \
      INFOPLIST_KEY_NSLocationAlwaysAndWhenInUseUsageDescription \
      INFOPLIST_KEY_NSLocationWhenInUseUsageDescription | sort)"
    [ "$usage_keys" = "$expected_usage" ] \
      || out="$out project.yml 定位用途说明键被改动（期望恰为既有两条）;"
    modes="$(project_background_mode_values "$(project_target_section "$spec" "PurePace")")"
    [ "$modes" = "$(printf 'location\naudio')" ] \
      || out="$out project.yml PurePace target UIBackgroundModes 不再是 location+audio;"
  fi

  if [ ! -f "$plist" ]; then
    out="$out 缺少 $plist;"
  else
    plist_sha="$(shasum -a 256 "$plist" | awk '{print $1}')"
    if [ "$plist_sha" != "$INFO_PLIST_SHA256" ]; then
      out="$out ios/PurePace/Info.plist 已改动（权限/后台声明须零 diff）;"
    fi
  fi

  printf '%s' "$out"
}

problems="$(release_deterministic_problems .)"
if [ -z "$problems" ]; then
  pass "ac-release-deterministic-source (launch-arg 门控 + 默认关 + 权限零新增)"
else
  fail "ac-release-deterministic-source" "$problems"
fi

# 反例自检：把确定性源退回 #if DEBUG / 默认分支改回确定性源，两种违规样本都必须被识别。
release_deterministic_selftest() {
  local label="$1" mutate="$2" sandbox="" out=""
  sandbox="$(mktemp -d "${TMPDIR:-/tmp}/purepace-check-ios-reldet.XXXXXX")"
  mkdir -p "$sandbox/ios/PurePace/Location" "$sandbox/ios/PurePaceTests" "$sandbox/ios/PurePaceUITests"
  cp ios/PurePace/Location/ReleaseDeterministicLocationSource.swift \
    ios/PurePace/Location/RunLocationSourceSelection.swift \
    ios/PurePace/Location/RunLocationSource.swift \
    "$sandbox/ios/PurePace/Location/"
  cp ios/PurePace/ContentView.swift ios/PurePace/Info.plist "$sandbox/ios/PurePace/"
  cp ios/project.yml "$sandbox/ios/"
  cp ios/PurePaceTests/ReleaseDeterministicLocationSourceTests.swift "$sandbox/ios/PurePaceTests/"
  cp ios/PurePaceUITests/RunFlowUITests.swift "$sandbox/ios/PurePaceUITests/"
  "$mutate" "$sandbox"
  out="$(release_deterministic_problems "$sandbox")"
  if [ -n "$out" ]; then
    pass "$label (self-test)"
  else
    fail "$label" "违规样本未被识别"
  fi
  rm -rf "$sandbox"
}

debug_wrap_release_source() {
  local file="$1/ios/PurePace/Location/ReleaseDeterministicLocationSource.swift"
  printf '#if DEBUG\n' > "$file.tmp"
  cat "$file" >> "$file.tmp"
  printf '#endif\n' >> "$file.tmp"
  mv "$file.tmp" "$file"
}

default_branch_deterministic() {
  sed -i '' 's/Selection(source: makeReal(), telemetryDebugEnabled: false)/Selection(source: makeDeterministic(.kmCrossing), telemetryDebugEnabled: true)/' \
    "$1/ios/PurePace/Location/RunLocationSourceSelection.swift"
}

release_deterministic_selftest "ac-release-deterministic-release-available" debug_wrap_release_source
release_deterministic_selftest "ac-release-deterministic-default-real" default_branch_deterministic

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
