#!/usr/bin/env bash
# ios/RunCore SwiftPM 包结构断言（.munk/code-gates.json 的 lint-ios-run-core 门真实执行体）。
# 逐条校验：包布局与平台声明、零第三方依赖、仅 Foundation、无平台框架/业务符号、
# 无夹具令牌、无写死版本字面值、测试为 XCTest、无 XcodeGen 产物，
# 以及 code-gates 三门与 test-ios.sh 的 RunCore 入口。任一条失败即非零退出。
# --self-test 在临时目录复制包并注入违规，反证同一批断言真的会失败。
set -euo pipefail

usage() {
  cat <<'EOF'
用法: scripts/check-ios-run-core.sh [--help] [--self-test]

对 ios/RunCore SwiftPM package 做结构断言并打印逐条结果：
  - Package.swift / Sources/PurePaceRunCore / Tests/PurePaceRunCoreTests 布局齐全
  - tools-version 6.0、包名 PurePaceRunCore、同时声明 iOS 17 与 macOS 14、
    只允许 PurePaceGpxTool 一个 executable target
  - 零第三方依赖（无 package 依赖声明；dump-package 的 dependencies 为空）
  - Sources 只 import Foundation
  - Sources 不含 CoreLocation/AVFoundation/AVAudioSession/SwiftUI/UIKit/URLSession/Timer 等
    平台框架或业务符号
  - ios/RunCore 内不出现夹具令牌（shared/fixtures、sample-run.gpx、sample-run.tcx）
  - ios/RunCore 内不出现根 VERSION 的字面值
  - Tests 使用 XCTest（不使用 Swift Testing）且至少含 1 个 test 方法
  - ios/RunCore 内不出现 XcodeGen 工程产物
  - .munk/code-gates.json 含 lint/build/test-ios-run-core 三门且命令为预期单一 argv
  - scripts/test-ios.sh 保留既有分支并追加 RunCore 的 swift test 入口

选项:
  -h, --help     显示本帮助并退出 0
  --self-test    在临时目录复制包并注入违规，验证断言真实失败后退出 0

退出码:
  0  全部断言通过（或 --self-test 反例自检通过）
  1  存在失败断言
  2  参数非法
EOF
}

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
cd "$repo_root"

run_self_test=0
case "${1:-}" in
  -h|--help)
    usage
    exit 0
    ;;
  --self-test)
    run_self_test=1
    ;;
  "")
    ;;
  *)
    echo "check-ios-run-core: 未知参数 '$1'（使用 --help 查看用法）" >&2
    exit 2
    ;;
esac

if [ "$#" -gt 1 ]; then
  echo "check-ios-run-core: 只接受一个参数（使用 --help 查看用法）" >&2
  exit 2
fi

package_dir="ios/RunCore"
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

version_value=""
if [ -f VERSION ]; then
  version_value="$(tr -d '\r\n' < VERSION)"
fi

# ------------------------------------------------------------------ 断言实现
# 每个 check_* 以包/仓库根为参数；通过时不输出并返回 0，失败时打印问题并返回 1。

check_layout() {
  local dir="$1" problems="" path
  for path in "$dir/Package.swift" "$dir/Sources/PurePaceRunCore" "$dir/Tests/PurePaceRunCoreTests"; do
    [ -e "$path" ] || problems="${problems} 缺少 ${path#"$dir"/};"
  done
  [ -z "$problems" ] || {
    printf '%s\n' "$problems"
    return 1
  }
}

check_package_shape() {
  local dir="$1" problems="" needle="" executable_count=""
  if [ ! -f "$dir/Package.swift" ]; then
    printf '%s\n' " 缺少 Package.swift"
    return 1
  fi
  for needle in \
    "// swift-tools-version: 6.0" \
    'name: "PurePaceRunCore"' \
    '.library(name: "PurePaceRunCore"' \
    ".iOS(.v17)" \
    ".macOS(.v14)" \
    "PurePaceRunCoreTests"; do
    grep -Fq -- "${needle}" "$dir/Package.swift" || problems="${problems} 缺少 '${needle}';"
  done
  if grep -Fq -- ".executableTarget" "$dir/Package.swift"; then
    if ! grep -Fq -- '.executableTarget(name: "PurePaceGpxTool"' "$dir/Package.swift"; then
      problems="${problems} 出现非 PurePaceGpxTool 的 executable target;"
    fi
    executable_count="$(grep -Fc -- ".executableTarget" "$dir/Package.swift" || true)"
    if [ "${executable_count}" -gt 1 ]; then
      problems="${problems} executable target 多于一个;"
    fi
  fi
  [ -z "$problems" ] || {
    printf '%s\n' "$problems"
    return 1
  }
}

check_zero_deps() {
  local dir="$1" problems="" deps_json=""
  if [ ! -f "$dir/Package.swift" ]; then
    printf '%s\n' " 缺少 Package.swift"
    return 1
  fi
  if grep -Eq '\.package[[:space:]]*\(|url:|path:' "$dir/Package.swift"; then
    printf '%s\n' " Package.swift 出现 package 依赖声明"
    return 1
  fi
  if ! deps_json="$(swift package dump-package --package-path "$dir" 2>&1)"; then
    printf '%s\n' " swift package dump-package 执行失败"
    return 1
  fi
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
      problems="${problems} dump-package 的 dependencies 非空;"
    fi
  elif ! printf '%s' "$deps_json" | tr -d '[:space:]' | grep -Fq '"dependencies":[]'; then
    problems="${problems} 无法确认 dump-package 的 dependencies 为空;"
  fi
  [ -z "$problems" ] || {
    printf '%s\n' "$problems"
    return 1
  }
}

check_foundation_only() {
  local dir="$1" problems="" file="" imports="" module=""
  if [ -d "$dir/Sources" ]; then
    while IFS= read -r file; do
      [ -z "$file" ] && continue
      imports="$(grep -hE '^[[:space:]]*import[[:space:]]+' "$file" 2>/dev/null \
        | sed -E 's/^[[:space:]]*import[[:space:]]+//' | sort -u || true)"
      for module in $imports; do
        case "$module" in
          Foundation) ;;
          PurePaceRunCore)
            case "$file" in
              "$dir/Sources/PurePaceGpxTool/"*) ;;
              *) problems="${problems} ${file#"$dir"/} 出现非白名单 import '${module}';" ;;
            esac
            ;;
          *) problems="${problems} ${file#"$dir"/} 出现非白名单 import '${module}';" ;;
        esac
      done
    done <<< "$(find "$dir/Sources" -name '*.swift' 2>/dev/null || true)"
  fi
  [ -z "$problems" ] || {
    printf '%s\n' "$problems"
    return 1
  }
}

check_no_platform_symbols() {
  local dir="$1" hits=""
  if [ ! -d "$dir/Sources" ]; then
    printf '%s\n' " 缺少 Sources 目录"
    return 1
  fi
  hits="$(grep -rnE \
    'CoreLocation|CLLocationManager|AVFoundation|AVFAudio|AVAudioSession|CoreMotion|MapKit|HealthKit|SwiftUI|UIKit|UserNotifications|URLSession|CoreData|SQLite|SwiftData|Timer' \
    "$dir/Sources" 2>/dev/null || true)"
  if [ -n "$hits" ]; then
    printf '%s\n' " 命中平台/业务符号: $(printf '%s' "$hits" | tr '\n' ' ')"
    return 1
  fi
}

check_no_fixture_tokens() {
  local dir="$1" token hits="" problems=""
  for token in "shared/fixtures" "sample-run.gpx" "sample-run.tcx"; do
    hits="$(grep -rnF --exclude-dir=.build --exclude-dir=.swiftpm -- "${token}" "$dir" 2>/dev/null || true)"
    [ -z "$hits" ] || problems="${problems} 出现夹具令牌 '${token}': $(printf '%s' "$hits" | tr '\n' ' ');"
  done
  [ -z "$problems" ] || {
    printf '%s\n' "$problems"
    return 1
  }
}

check_no_version_literal() {
  local dir="$1" hits=""
  if [ -z "$version_value" ]; then
    printf '%s\n' " 根 VERSION 不可用，无法校验字面值"
    return 1
  fi
  hits="$(grep -rnF --exclude-dir=.build --exclude-dir=.swiftpm -- "${version_value}" "$dir" 2>/dev/null || true)"
  if [ -n "$hits" ]; then
    printf '%s\n' " 出现版本字面值 '${version_value}': $(printf '%s' "$hits" | tr '\n' ' ')"
    return 1
  fi
}

check_xctest_only() {
  local dir="$1" problems="" test_count=""
  if [ ! -d "$dir/Tests" ]; then
    printf '%s\n' " 缺少 Tests 目录"
    return 1
  fi
  test_count="$(grep -rhE '^[[:space:]]*func[[:space:]]+test[A-Za-z0-9_]*[[:space:]]*\(' "$dir/Tests" 2>/dev/null | wc -l | tr -d ' ')"
  [ "${test_count}" -ge 1 ] || problems="${problems} 未找到 test 方法;"
  grep -rqE '^[[:space:]]*import[[:space:]]+XCTest' "$dir/Tests" 2>/dev/null || problems="${problems} 未 import XCTest;"
  if grep -rqE '^[[:space:]]*import[[:space:]]+Testing' "$dir/Tests" 2>/dev/null; then
    problems="${problems} 使用了 Swift Testing，需改用 XCTest;"
  fi
  [ -z "$problems" ] || {
    printf '%s\n' "$problems"
    return 1
  }
}

check_no_xcodegen() {
  local dir="$1" problems="" path="" stray=""
  for path in "$dir/project.yml" "$dir/PurePace.xcodeproj" "$dir/project.pbxproj"; do
    [ ! -e "$path" ] || problems="${problems} 出现 XcodeGen 产物 ${path#"$dir"/};"
  done
  stray="$(find "$dir" -name project.pbxproj -not -path '*/.build/*' -not -path '*/.swiftpm/*' 2>/dev/null || true)"
  [ -z "$stray" ] || problems="${problems} 出现 pbxproj: $(printf '%s' "$stray" | tr '\n' ' ');"
  [ -z "$problems" ] || {
    printf '%s\n' "$problems"
    return 1
  }
}

check_gates() {
  local dir="$1" gates_file="$1/.munk/code-gates.json" problems=""
  if [ ! -f "$gates_file" ]; then
    printf '%s\n' " 缺少 .munk/code-gates.json"
    return 1
  fi
  if command -v node >/dev/null 2>&1; then
    if ! node -e '
      const fs = require("fs");
      const doc = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
      const expected = {
        "lint-ios-run-core": "bash scripts/check-ios-run-core.sh",
        "build-ios-run-core": "swift build --package-path ios/RunCore",
        "test-ios-run-core": "swift test --package-path ios/RunCore",
        "check-gpx-export": "bash scripts/check-gpx-export.sh"
      };
      const gates = new Map((doc.gates || []).map((gate) => [gate.id, gate.command]));
      const bad = [];
      for (const id of Object.keys(expected)) {
        if (!gates.has(id)) bad.push("缺少门 " + id);
        else if (gates.get(id) !== expected[id]) bad.push(id + " 的 command 为 " + gates.get(id));
      }
      for (const [id, command] of gates) {
        if (typeof command !== "string" || /&&|\|\||\||;|>|</.test(command)) {
          bad.push(id + " 的 command 含 shell 分隔符/重定向");
        }
      }
      if (bad.length) {
        console.error(bad.join("; "));
        process.exit(1);
      }
    ' "$gates_file"; then
      problems="${problems} 门禁定义不符合预期;"
    fi
  else
    for pair in \
      '"lint-ios-run-core"' \
      '"build-ios-run-core"' \
      '"test-ios-run-core"' \
      '"check-gpx-export"' \
      '"bash scripts/check-ios-run-core.sh"' \
      '"swift build --package-path ios/RunCore"' \
      '"swift test --package-path ios/RunCore"' \
      '"bash scripts/check-gpx-export.sh"'; do
      grep -Fq -- "${pair}" "$gates_file" || problems="${problems} 缺少 ${pair};"
    done
  fi
  [ -z "$problems" ] || {
    printf '%s\n' "$problems"
    return 1
  }
}

check_test_ios_entry() {
  local dir="$1" script_path="$1/scripts/test-ios.sh" problems="" needle
  if [ ! -f "$script_path" ]; then
    printf '%s\n' " 缺少 scripts/test-ios.sh"
    return 1
  fi
  for needle in \
    "xcodebuild test" \
    "swift test --package-path ios/Core" \
    "swift test --package-path ios/RunCore" \
    "blocked:"; do
    grep -Fq -- "${needle}" "$script_path" || problems="${problems} 缺少 '${needle}';"
  done
  [ -z "$problems" ] || {
    printf '%s\n' "$problems"
    return 1
  }
}

assert_check() {
  local fn="$1" dir="$2" out="" rc=0
  out="$("$fn" "$dir")" && rc=0 || rc=$?
  if [ "$rc" -eq 0 ]; then
    pass "$fn"
  else
    fail "$fn" "$out"
  fi
}

copy_package() {
  local src="$1" dst="$2"
  mkdir -p "$dst"
  cp "$src/Package.swift" "$dst/Package.swift"
  cp -R "$src/Sources" "$dst/Sources"
  cp -R "$src/Tests" "$dst/Tests"
}

# --------------------------------------------------------------- --self-test
run_self_test() {
  local tmp="" pkg="" case_dir="" out="" fn=""
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/check-ios-run-core.XXXXXX")"
  # shellcheck disable=SC2064
  trap "rm -rf '${tmp}'" EXIT

  pkg="${tmp}/clean"
  copy_package "$package_dir" "$pkg"
  for fn in \
    check_layout \
    check_package_shape \
    check_zero_deps \
    check_foundation_only \
    check_no_platform_symbols \
    check_no_fixture_tokens \
    check_no_version_literal \
    check_xctest_only \
    check_no_xcodegen; do
    out="$("$fn" "$pkg")" && {
      pass "self-test/clean/$fn"
      continue
    }
    fail "self-test/clean/$fn" "干净副本不应失败: ${out}"
  done

  # 反例 1：注入 import UIKit，仅 Foundation 与平台符号两条断言必须失败。
  case_dir="${tmp}/case-uikit"
  copy_package "$package_dir" "$case_dir"
  printf '\nimport UIKit\n' >> "${case_dir}/Sources/PurePaceRunCore/InjectedLeak.swift"
  expect_failure "import-UIKit" "$case_dir" check_foundation_only check_no_platform_symbols

  # 反例 2：注入第三方 package 依赖，零依赖断言必须失败。
  case_dir="${tmp}/case-package"
  copy_package "$package_dir" "$case_dir"
  cat > "${case_dir}/Package.swift" <<'EOF'
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PurePaceRunCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "PurePaceRunCore", targets: ["PurePaceRunCore"])],
    dependencies: [.package(url: "https://example.com/dep.git", from: "1.0.0")],
    targets: [
        .target(name: "PurePaceRunCore"),
        .testTarget(name: "PurePaceRunCoreTests", dependencies: ["PurePaceRunCore"])
    ]
)
EOF
  expect_failure "package-dependency" "$case_dir" check_zero_deps

  # 反例 6：注入第二个 executable target，包形状断言必须失败。
  case_dir="${tmp}/case-second-executable"
  copy_package "$package_dir" "$case_dir"
  cat > "${case_dir}/Package.swift" <<'EOF'
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PurePaceRunCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "PurePaceRunCore", targets: ["PurePaceRunCore"])],
    targets: [
        .target(name: "PurePaceRunCore"),
        .executableTarget(name: "PurePaceGpxTool", dependencies: ["PurePaceRunCore"]),
        .executableTarget(name: "InjectedTool"),
        .testTarget(name: "PurePaceRunCoreTests", dependencies: ["PurePaceRunCore"])
    ]
)
EOF
  expect_failure "second-executable" "$case_dir" check_package_shape

  # 反例 7：把唯一 executable target 改名，包形状断言必须失败。
  case_dir="${tmp}/case-renamed-executable"
  copy_package "$package_dir" "$case_dir"
  cat > "${case_dir}/Package.swift" <<'EOF'
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PurePaceRunCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "PurePaceRunCore", targets: ["PurePaceRunCore"])],
    targets: [
        .target(name: "PurePaceRunCore"),
        .executableTarget(name: "InjectedTool"),
        .testTarget(name: "PurePaceRunCoreTests", dependencies: ["PurePaceRunCore"])
    ]
)
EOF
  expect_failure "renamed-executable" "$case_dir" check_package_shape

  # 反例 3：注入根 VERSION 字面值，版本断言必须失败。
  case_dir="${tmp}/case-version"
  copy_package "$package_dir" "$case_dir"
  printf '\n// 版本 %s\n' "${version_value}" >> "${case_dir}/Sources/PurePaceRunCore/InjectedVersion.swift"
  expect_failure "version-literal" "$case_dir" check_no_version_literal

  # 反例 4：注入夹具令牌，夹具断言必须失败。
  case_dir="${tmp}/case-fixture"
  copy_package "$package_dir" "$case_dir"
  printf '\n// 夹具 shared/fixtures\n' >> "${case_dir}/Sources/PurePaceRunCore/InjectedFixture.swift"
  expect_failure "fixture-token" "$case_dir" check_no_fixture_tokens

  # 反例 5：注入 Swift Testing，XCTest 断言必须失败。
  case_dir="${tmp}/case-testing"
  copy_package "$package_dir" "$case_dir"
  printf '\nimport Testing\n' >> "${case_dir}/Tests/PurePaceRunCoreTests/InjectedTesting.swift"
  expect_failure "swift-testing" "$case_dir" check_xctest_only
}

expect_failure() {
  local label="$1" dir="$2" fn="" out=""
  shift 2
  for fn in "$@"; do
    out="$("$fn" "$dir")" && {
      fail "self-test/${label}/${fn}" "注入违规后仍通过"
      continue
    }
    pass "self-test/${label}/${fn}"
  done
}

# ------------------------------------------------------------------- 执行
if [ "$run_self_test" -eq 1 ]; then
  run_self_test
else
  assert_check check_layout "$package_dir"
  assert_check check_package_shape "$package_dir"
  assert_check check_zero_deps "$package_dir"
  assert_check check_foundation_only "$package_dir"
  assert_check check_no_platform_symbols "$package_dir"
  assert_check check_no_fixture_tokens "$package_dir"
  assert_check check_no_version_literal "$package_dir"
  assert_check check_xctest_only "$package_dir"
  assert_check check_no_xcodegen "$package_dir"
  assert_check check_gates "$repo_root"
  assert_check check_test_ios_entry "$repo_root"
fi

printf '\n%d 项断言，%d 项失败\n' "$CHECKS" "$FAILURES"
if [ "$FAILURES" -ne 0 ]; then
  exit 1
fi
if [ "$run_self_test" -eq 1 ]; then
  printf 'ios/RunCore self-test OK\n'
else
  printf 'ios/RunCore OK\n'
fi
