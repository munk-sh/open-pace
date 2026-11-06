#!/usr/bin/env bash
# ios/Core SwiftPM 包结构断言（.munk/code-gates.json 的 lint-ios-core 门真实执行体）。
# 逐条校验：包布局与平台声明、零第三方依赖、仅系统 import、无业务/平台能力、
# 无写死版本字面值、测试为 XCTest、包内无 XcodeGen 产物。任一条失败即非零退出。
set -euo pipefail

usage() {
  cat <<'EOF'
用法: scripts/check-ios-core.sh [--help]

对 ios/Core SwiftPM package 做结构断言并打印逐条结果：
  - Package.swift / Sources/PurePaceCore / Tests/PurePaceCoreTests 布局齐全
  - tools-version 6.0、包名 PurePaceCore、同时声明 iOS 17.0 与 macOS 14
  - 零第三方依赖（无 .package(url:/path:)，dump-package 的 dependencies 为空）
  - Sources 只 import 系统框架（白名单 Foundation）
  - Sources 不含定位/音频/运动/地图/健康/网络/持久化等业务或平台能力
  - ios/Core 内不出现根 VERSION 的字面值
  - Tests 使用 XCTest（不使用 Swift Testing）且至少含 1 个 test 方法
  - ios/Core 内不出现 XcodeGen 工程产物（project.yml / .xcodeproj / pbxproj）

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
    echo "check-ios-core: 未知参数 '$1'（使用 --help 查看用法）" >&2
    exit 2
    ;;
esac

if [ "$#" -gt 1 ]; then
  echo "check-ios-core: 只接受一个参数（使用 --help 查看用法）" >&2
  exit 2
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
cd "$repo_root"

package_dir="ios/Core"
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

# ------------------------------------------------------------- 包布局
problems=""
for path in \
  "$package_dir/Package.swift" \
  "$package_dir/Sources/PurePaceCore" \
  "$package_dir/Tests/PurePaceCoreTests"; do
  [ -e "$path" ] || problems="$problems 缺少 $path;"
done
if [ -z "$problems" ]; then
  pass "ac-core-package-layout"
else
  fail "ac-core-package-layout" "$problems"
fi

# ------------------------------------------------- 包声明（tools/platforms）
problems=""
if [ -f "$package_dir/Package.swift" ]; then
  for needle in \
    "// swift-tools-version: 6.0" \
    'name: "PurePaceCore"' \
    ".iOS(.v17)" \
    ".macOS(.v14)" \
    "PurePaceCoreTests"; do
    grep -Fq -- "$needle" "$package_dir/Package.swift" || problems="$problems 缺少 '$needle';"
  done
else
  problems="$problems 缺少 Package.swift;"
fi
if [ -z "$problems" ]; then
  pass "ac-core-package-shape"
else
  fail "ac-core-package-shape" "$problems"
fi

# --------------------------------------------------------- 零第三方依赖
problems=""
if [ -f "$package_dir/Package.swift" ]; then
  if grep -Eq '\.package[[:space:]]*\(|url:|path:' "$package_dir/Package.swift"; then
    problems="$problems Package.swift 出现 package 依赖声明;"
  fi
  if deps_json="$(swift package dump-package --package-path "$package_dir" 2>&1)"; then
    if command -v node >/dev/null 2>&1; then
      if ! printf '%s' "$deps_json" | node -e '
        let raw = "";
        process.stdin.on("data", (chunk) => { raw += chunk; });
        process.stdin.on("end", () => {
          const pkg = JSON.parse(raw);
          const deps = pkg.dependencies;
          process.exit(Array.isArray(deps) && deps.length === 0 ? 0 : 1);
        });
      '; then
        problems="$problems dump-package 的 dependencies 非空;"
      fi
    elif ! printf '%s' "$deps_json" | tr -d '[:space:]' | grep -Fq '"dependencies":[]'; then
      problems="$problems 无法确认 dump-package 的 dependencies 为空;"
    fi
  else
    problems="$problems swift package dump-package 执行失败;"
  fi
else
  problems="$problems 缺少 Package.swift;"
fi
if [ -z "$problems" ]; then
  pass "ac-no-thirdparty-deps"
else
  fail "ac-no-thirdparty-deps" "$problems"
fi

# ----------------------------------------------------- 仅系统框架 import
problems=""
imports=""
if [ -d "$package_dir/Sources" ]; then
  imports="$(grep -rhE '^[[:space:]]*import[[:space:]]+' "$package_dir/Sources" 2>/dev/null \
    | sed -E 's/^[[:space:]]*import[[:space:]]+//' | sort -u || true)"
fi
for module in $imports; do
  case "$module" in
    Foundation) ;;
    *) problems="$problems Sources 出现非白名单 import '$module';" ;;
  esac
done
if [ -z "$problems" ]; then
  pass "ac-system-imports-only"
else
  fail "ac-system-imports-only" "$problems"
fi

# ------------------------------------------- 无业务/平台能力实现与 import
problems=""
if [ -d "$package_dir/Sources" ]; then
  hits="$(grep -rnE \
    'CoreLocation|CLLocationManager|AVFoundation|AVAudioSession|CoreMotion|MapKit|HealthKit|Timer|GPX|TCX|URLSession|SwiftUI|UIKit|CoreData|SQLite' \
    "$package_dir/Sources" 2>/dev/null || true)"
  if [ -n "$hits" ]; then
    problems="$problems 命中业务/平台符号: $(printf '%s' "$hits" | tr '\n' ' ')"
  fi
else
  problems="$problems 缺少 Sources 目录;"
fi
if [ -z "$problems" ]; then
  pass "ac-no-business-implementation"
else
  fail "ac-no-business-implementation" "$problems"
fi

# ----------------------------------------------------- 无写死版本字面值
problems=""
version_value=""
if [ -f VERSION ]; then
  version_value="$(tr -d '\r\n' < VERSION)"
fi
if [ -z "$version_value" ]; then
  problems="$problems VERSION 不可用，无法校验字面值;"
else
  hits="$(grep -rnF --exclude-dir=.build --exclude-dir=.swiftpm -- "$version_value" "$package_dir" 2>/dev/null || true)"
  if [ -n "$hits" ]; then
    problems="$problems 出现版本字面值 '$version_value': $(printf '%s' "$hits" | tr '\n' ' ')"
  fi
fi
if [ -z "$problems" ]; then
  pass "ac-no-version-literal"
else
  fail "ac-no-version-literal" "$problems"
fi

# ------------------------------------------------------- XCTest 用例存在
problems=""
if [ -d "$package_dir/Tests" ]; then
  test_count="$(grep -rhE '^[[:space:]]*func[[:space:]]+test[A-Za-z0-9_]*[[:space:]]*\(' "$package_dir/Tests" 2>/dev/null | wc -l | tr -d ' ')"
  [ "$test_count" -ge 1 ] || problems="$problems 未找到 test 方法;"
  if ! grep -rqE '^[[:space:]]*import[[:space:]]+XCTest' "$package_dir/Tests" 2>/dev/null; then
    problems="$problems 未 import XCTest;"
  fi
  if grep -rqE '^[[:space:]]*import[[:space:]]+Testing' "$package_dir/Tests" 2>/dev/null; then
    problems="$problems 使用了 Swift Testing，需改用 XCTest;"
  fi
else
  problems="$problems 缺少 Tests 目录;"
fi
if [ -z "$problems" ]; then
  pass "ac-xctest-cases-present"
else
  fail "ac-xctest-cases-present" "$problems"
fi

# ------------------------------------------ 包内无 XcodeGen 工程产物
problems=""
for path in \
  "$package_dir/project.yml" \
  "$package_dir/PurePace.xcodeproj" \
  "$package_dir/project.pbxproj"; do
  [ ! -e "$path" ] || problems="$problems 出现 XcodeGen 产物 $path;"
done
if [ -z "$problems" ]; then
  stray="$(find "$package_dir" -name project.pbxproj -not -path '*/.build/*' -not -path '*/.swiftpm/*' 2>/dev/null || true)"
  [ -z "$stray" ] || problems="$problems 出现 pbxproj: $(printf '%s' "$stray" | tr '\n' ' ')"
fi
if [ -z "$problems" ]; then
  pass "ac-no-xcodegen-artifacts"
else
  fail "ac-no-xcodegen-artifacts" "$problems"
fi

printf '\n%d 项断言，%d 项失败\n' "$CHECKS" "$FAILURES"
if [ "$FAILURES" -ne 0 ]; then
  exit 1
fi
printf 'ios/Core OK\n'
