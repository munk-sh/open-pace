#!/usr/bin/env bash
# Android 侧结构/契约断言（.munk/code-gates.json 的 lint-android 门真实执行体）。
# 校验 Android 脚本的 bash 严格模式与参数契约、Android 工程结构（applicationId 单点、
# minSdk/compileSdk/JDK、版本派生、wrapper 固定、无业务实现、无跨端框架）、同意门与政策
# 文案单一真源、打包产物契约、code-gates 完整性与既有非 Android 门零改动，并内置反例
# 自检证明断言不是恒真。
set -euo pipefail

usage() {
  cat <<'EOF'
用法: scripts/check-android.sh [--help]

对 Android 侧脚本与工程结构逐条断言并打印 PASS/FAIL：
  - ac-script-help-and-strict   build/test/check/package 四个 Android 脚本 bash -n 通过、shebang 为
                                #!/usr/bin/env bash、正文含 set -euo pipefail、以 BASH_SOURCE
                                推导仓库根；--help 退出 0 且含「用法」，未知参数退出 2
  - ac-check-android-application-id
                                applicationId 字面值在 android/ 仅 1 处，位于
                                android/gradle.properties 的单一 property
  - ac-check-android-sdk-jdk    compileSdk 36 / minSdk 26 / Java 与 Kotlin 目标 21，无写死
                                JDK 绝对路径，android/local.properties 未入库
  - ac-check-android-version    versionName 每次配置期读仓库根 VERSION，不写死、无 cat VERSION
  - ac-check-android-wrapper    gradle-wrapper.jar 非空且为 jar，distributionUrl 为固定版本
  - ac-check-android-no-business Manifest 无定位/前台服务/录音权限，src/main 无计时器、
                                GPS/GPX/TCX、音频/TTS、历史/导出实现，依赖无 RN/Flutter/CMP
  - ac-consent-gate-contract    同意门组件、标签、资源 key、撤回入口与 SharedPreferences
                                持久化接口齐全，四条关键文案命中资源
  - ac-consent-copy-from-strings
                                同意门/关于页 Kotlin 源码零中文裸字面量、可见文案零内联字符串
  - ac-policy-single-source-sync
                                strings.xml 政策正文逐段等于 docs/privacy/privacy-policy-zh-Hans.md
  - ac-policy-bundled-no-network
                                Manifest 权限集合与改动前一致（无 uses-permission），政策渲染无网络调用
  - ac-package-path-and-layout / ac-package-manifest-fields / ac-package-checksums-match /
    ac-package-idempotent-same-commit / ac-package-no-hardcoded-credentials /
    ac-package-existing-dir-sibling / ac-package-existing-dir-monotonic /
    ac-package-existing-dir-red-proof / ac-package-cli-contract-preserved / ac-package-red-proofs
                                沙箱 stub gradle 打包：仓外目录布局、manifest 字段集合、checksums
                                对照、同 commit 幂等、零明文凭据；干净环境用固定名目录，既有版本
                                目录存在时改用递增兄弟目录（-b2、-b3）且既有文件 sha256 逐字不变、
                                去守卫副本必然覆盖既有目录、--help / 未知参数契约，并逐条取红
  - ac-check-android-gates-integrity
                                .munk/code-gates.json 可解析、id 唯一、无空转/串接命令，
                                Android 四个门（build/test/lint/package）各自指向对应脚本命令，
                                全量既有非 Android 门 id 与 command 零改动，id 集合不得增减
  - ac-android-gradle-bounded-retry
                                build/test 的 gradlew 调用必须经同一个有界重试函数，且只对
                                网络/下载类失败最多重试 3 次（1 + 3 次尝试）
  - ac-check-android-retry-cases
                                沙箱 stub gradlew 验证：非网络失败只尝试 1 次、网络失败恰好 4 次
                                后非零退出、第 2 次成功则继续原有产物校验
  - ac-check-android-negative-path
                                沙箱复制最小样本并注入「applicationId 出现两处」「compileSdk
                                不等于 36」反例，必须分别 FAIL 并非零退出

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
    echo "check-android: 未知参数 '$1'（使用 --help 查看用法）" >&2
    exit 2
    ;;
esac

if [ "$#" -gt 1 ]; then
  echo "check-android: 只接受一个参数（使用 --help 查看用法）" >&2
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

android_scripts="build-android.sh test-android.sh check-android.sh package-android.sh"

# ------------------------------------------------- 脚本存在、语法与严格模式
problems=""
for name in $android_scripts; do
  [ -f "scripts/$name" ] || problems="$problems 缺少 scripts/$name;"
done
if [ -z "$problems" ]; then
  pass "ac-script-help-and-strict (present)"
else
  fail "ac-script-help-and-strict" "$problems"
fi

problems=""
for name in $android_scripts; do
  [ -f "scripts/$name" ] || continue
  bash -n "scripts/$name" >/dev/null 2>&1 || problems="$problems scripts/$name bash -n 失败;"
done
if [ -z "$problems" ]; then
  pass "ac-script-help-and-strict (bash -n)"
else
  fail "ac-script-help-and-strict" "$problems"
fi

problems=""
for name in $android_scripts; do
  [ -f "scripts/$name" ] || continue
  first_line="$(sed -n '1p' "scripts/$name")"
  [ "$first_line" = "#!/usr/bin/env bash" ] || problems="$problems scripts/$name shebang 为 '$first_line';"
  grep -Fq -- 'set -euo pipefail' "scripts/$name" || problems="$problems scripts/$name 缺少 set -euo pipefail;"
  grep -Fq -- 'BASH_SOURCE' "scripts/$name" || problems="$problems scripts/$name 未以 BASH_SOURCE 推导仓库根;"
done
if [ -z "$problems" ]; then
  pass "ac-script-help-and-strict (shebang/set/BASH_SOURCE)"
else
  fail "ac-script-help-and-strict" "$problems"
fi

problems=""
for name in $android_scripts; do
  [ -f "scripts/$name" ] || continue
  help_out="$(bash "scripts/$name" --help 2>&1)" && help_rc=0 || help_rc=$?
  if [ "$help_rc" -ne 0 ]; then
    problems="$problems scripts/$name --help 退出 $help_rc;"
  elif ! grep -Fq -- "用法" <<< "$help_out"; then
    problems="$problems scripts/$name --help 输出缺少「用法」;"
  fi
  bash "scripts/$name" --definitely-invalid >/dev/null 2>&1 && bad_rc=0 || bad_rc=$?
  [ "$bad_rc" -eq 2 ] || problems="$problems scripts/$name 未知参数退出 ${bad_rc}（期望 2）;"
done
if [ -z "$problems" ]; then
  pass "ac-script-help-and-strict (help/strict args)"
else
  fail "ac-script-help-and-strict" "$problems"
fi

# ------------------------------ gradlew 有界重试静态断言（两个 Android 脚本）
gradle_retry_static_problems() {
  local file="$1" task="$2" out="" inv_lines inv_count inv_line fn_start fn_end pattern
  if [ ! -f "$file" ]; then
    printf '缺少 %s;' "$file"
    return 0
  fi
  grep -Fq -- 'gradle_with_retry() {' "$file" || out="$out 缺少 gradle_with_retry 函数;"
  grep -Fq -- 'max_attempts=4' "$file" || out="$out 重试尝试上限不是 4（1 次 + 3 次重试）;"

  inv_lines="$(grep -nE '^[[:space:]]*bash android/gradlew' "$file" | cut -d: -f1 || true)"
  inv_count=0
  if [ -n "$inv_lines" ]; then
    inv_count="$(printf '%s\n' "$inv_lines" | wc -l | tr -d ' ')"
  fi
  if [ "$inv_count" -ne 1 ]; then
    out="$out 存在 ${inv_count} 处裸 gradlew 调用（期望恰好 1 处，位于重试函数内）;"
  else
    inv_line="$inv_lines"
    fn_start="$(grep -nE '^gradle_with_retry\(\) \{' "$file" | cut -d: -f1 | head -n 1)"
    fn_end=""
    if [ -n "$fn_start" ]; then
      fn_end="$(awk -v s="$fn_start" 'NR > s && /^\}/{ print NR; exit }' "$file")"
    fi
    if [ -z "$fn_start" ] || [ -z "$fn_end" ] || [ "$inv_line" -le "$fn_start" ] || [ "$inv_line" -ge "$fn_end" ]; then
      out="$out gradlew 调用不在 gradle_with_retry 函数体内;"
    fi
  fi

  for pattern in 'Could not download' 'Could not resolve' 'Read timed out' 'Connection refused' 'HTTP 5'; do
    grep -Fq -- "$pattern" "$file" || out="$out 缺少网络失败特征 '$pattern';"
  done

  if [ "$task" = "assembleDebug" ]; then
    grep -Fq -- 'gradle_with_retry assembleDebug' "$file" || out="$out 未经 gradle_with_retry 调用 assembleDebug;"
  else
    # 单测任务必须 --rerun：结果目录先被清理，任务若判 UP-TO-DATE 就不会产出结果。
    grep -Fq -- "gradle_with_retry $task --rerun" "$file" || out="$out 未经 gradle_with_retry 以 --rerun 调用 ${task}（UP-TO-DATE 时不产出结果目录）;"
    grep -Fq -- 'bash android/gradlew -p android "$task" "$@"' "$file" || out="$out gradlew 调用未透传额外参数（\"\$@\"）;"
  fi

  printf '%s' "$out"
}

problems=""
for name in build-android.sh test-android.sh package-android.sh; do
  static_task="assembleDebug"
  if [ "$name" = "test-android.sh" ]; then
    static_task="testDebugUnitTest"
  fi
  file_problems="$(gradle_retry_static_problems "scripts/$name" "$static_task")"
  if [ -n "$file_problems" ]; then
    problems="$problems scripts/$name:$file_problems"
  fi
done
if [ -z "$problems" ]; then
  pass "ac-android-gradle-bounded-retry (static)"
else
  fail "ac-android-gradle-bounded-retry" "$problems"
fi

# 反例自检：删除重试函数后的违规样本必须被同一静态断言识别（非恒真）。
static_sandbox="$(mktemp -d "${TMPDIR:-/tmp}/purepace-check-android-static.XXXXXX")"
sed '/^gradle_with_retry() {/,/^}/d' scripts/build-android.sh > "$static_sandbox/bad.sh"
if [ -n "$(gradle_retry_static_problems "$static_sandbox/bad.sh" assembleDebug)" ]; then
  pass "ac-android-gradle-bounded-retry (self-test)"
else
  fail "ac-android-gradle-bounded-retry" "删除重试函数的违规样本未被静态断言识别"
fi
# 反例自检：去掉 testDebugUnitTest 的 --rerun / 停止透传额外参数，必须被同一静态断言识别。
sed 's/gradle_with_retry testDebugUnitTest --rerun/gradle_with_retry testDebugUnitTest/' scripts/test-android.sh > "$static_sandbox/no-rerun.sh"
sed 's|bash android/gradlew -p android "$task" "$@"|bash android/gradlew -p android "$task"|' scripts/test-android.sh > "$static_sandbox/no-args.sh"
if [ -n "$(gradle_retry_static_problems "$static_sandbox/no-rerun.sh" testDebugUnitTest)" ] \
  && [ -n "$(gradle_retry_static_problems "$static_sandbox/no-args.sh" testDebugUnitTest)" ]; then
  pass "ac-android-test-rerun (self-test)"
else
  fail "ac-android-test-rerun" "去掉 --rerun 或停止透传额外参数的违规样本未被静态断言识别"
fi
rm -rf "$static_sandbox"

# ------------------------------- Android 工程结构断言（可对任意 --root 等价样本运行）
check_android_structure() {
  local root="$1"
  local base_failures="$FAILURES"
  local android_dir="$root/android"
  local build_file="$android_dir/app/build.gradle.kts"
  local manifest="$android_dir/app/src/main/AndroidManifest.xml"
  local problems hits count magic jdk_hits cat_hits

  # applicationId 单点
  problems=""
  hits="$(grep -rIn --exclude-dir=build --exclude-dir=.gradle --exclude-dir=.kotlin -- 'sh.munk.purepace' "$android_dir" 2>/dev/null || true)"
  count=0
  if [ -n "$hits" ]; then
    count="$(printf '%s\n' "$hits" | wc -l | tr -d ' ')"
  fi
  [ "$count" -eq 1 ] || problems="$problems 字面值 sh.munk.purepace 在 android/ 出现 $count 次（期望 1，仅 gradle.properties）;"
  if [ -f "$android_dir/gradle.properties" ]; then
    grep -Eq '^PUREPACE_APPLICATION_ID=sh\.munk\.purepace$' "$android_dir/gradle.properties" \
      || problems="$problems android/gradle.properties 缺少唯一 PUREPACE_APPLICATION_ID=sh.munk.purepace 定义;"
  else
    problems="$problems 缺少 android/gradle.properties;"
  fi
  if [ -z "$problems" ]; then
    pass "ac-check-android-application-id"
  else
    fail "ac-check-android-application-id" "$problems"
  fi

  # compileSdk / minSdk / JDK 21 / 无写死 JDK 绝对路径
  problems=""
  if [ ! -f "$build_file" ]; then
    problems="$problems 缺少 android/app/build.gradle.kts;"
  else
    grep -Eq 'compileSdk[[:space:]]*=[[:space:]]*36([[:space:]]|$)' "$build_file" \
      || problems="$problems compileSdk 未固定为 36;"
    grep -Eq 'minSdk[[:space:]]*=[[:space:]]*26([[:space:]]|$)' "$build_file" \
      || problems="$problems minSdk 未固定为 26;"
    grep -Eq 'JavaVersion\.VERSION_21' "$build_file" \
      || problems="$problems Java 编译目标不是 21;"
    grep -Eq 'jvmToolchain\([[:space:]]*21[[:space:]]*\)' "$build_file" \
      || problems="$problems Kotlin jvmToolchain 不是 21;"
  fi
  jdk_hits="$(grep -rIn --exclude-dir=build --exclude-dir=.gradle --exclude-dir=.kotlin \
    -E '/Library/Java/JavaVirtualMachines|/usr/lib/jvm/|org\.gradle\.java\.home' "$android_dir" 2>/dev/null || true)"
  [ -z "$jdk_hits" ] || problems="$problems android/ 出现写死的 JDK 绝对路径: $(printf '%s' "$jdk_hits" | tr '\n' ' ');"
  if [ -z "$problems" ]; then
    pass "ac-check-android-sdk-jdk"
  else
    fail "ac-check-android-sdk-jdk" "$problems"
  fi

  # versionName 由仓库根 VERSION 配置期派生
  problems=""
  [ -f "$root/VERSION" ] || problems="$problems 缺少仓库根 VERSION;"
  if [ ! -f "$build_file" ]; then
    problems="$problems 缺少 android/app/build.gradle.kts;"
  else
    grep -Fq -- 'rootProject.file("../VERSION")' "$build_file" \
      || problems="$problems versionName 未从仓库根 VERSION 派生;"
    grep -Fq -- 'readText()' "$build_file" \
      || problems="$problems 未在配置期读取 VERSION 内容;"
    grep -Eq 'versionName[[:space:]]*=[[:space:]]*repoVersion' "$build_file" \
      || problems="$problems versionName 未绑定 repoVersion;"
    if grep -Eq 'versionName[[:space:]]*=[[:space:]]*"' "$build_file"; then
      problems="$problems versionName 出现写死字面值;"
    fi
  fi
  cat_hits="$(grep -rIn --exclude-dir=build --exclude-dir=.gradle --exclude-dir=.kotlin \
    -F -- 'cat VERSION' "$android_dir" 2>/dev/null || true)"
  [ -z "$cat_hits" ] || problems="$problems android/ 出现 'cat VERSION' 字面值;"
  if [ -z "$problems" ]; then
    pass "ac-check-android-version"
  else
    fail "ac-check-android-version" "$problems"
  fi

  # wrapper 固定版本且 jar 有效
  problems=""
  if [ ! -s "$android_dir/gradle/wrapper/gradle-wrapper.jar" ]; then
    problems="$problems 缺少非空 android/gradle/wrapper/gradle-wrapper.jar;"
  else
    magic="$(head -c 2 "$android_dir/gradle/wrapper/gradle-wrapper.jar" 2>/dev/null || true)"
    [ "$magic" = "PK" ] || problems="$problems gradle-wrapper.jar 不是有效 jar（magic='$magic'）;"
  fi
  if [ ! -f "$android_dir/gradle/wrapper/gradle-wrapper.properties" ]; then
    problems="$problems 缺少 android/gradle/wrapper/gradle-wrapper.properties;"
  else
    grep -Eq '^distributionUrl=.*gradle-[0-9]+\.[0-9]+(\.[0-9]+)?-(bin|all)\.zip$' \
      "$android_dir/gradle/wrapper/gradle-wrapper.properties" \
      || problems="$problems distributionUrl 未指向固定版本 gradle zip;"
    if grep -Eqi 'latest|snapshot' "$android_dir/gradle/wrapper/gradle-wrapper.properties" \
      || grep -Fq -- '+' "$android_dir/gradle/wrapper/gradle-wrapper.properties"; then
      problems="$problems distributionUrl 含 latest/SNAPSHOT/+ 等浮动标记;"
    fi
  fi
  if [ -z "$problems" ]; then
    pass "ac-check-android-wrapper"
  else
    fail "ac-check-android-wrapper" "$problems"
  fi

  # 无业务实现、无跨端框架
  problems=""
  if [ ! -f "$manifest" ]; then
    problems="$problems 缺少 android/app/src/main/AndroidManifest.xml;"
  else
    for perm in ACCESS_FINE_LOCATION ACCESS_COARSE_LOCATION ACCESS_BACKGROUND_LOCATION FOREGROUND_SERVICE RECORD_AUDIO; do
      if grep -Fq -- "$perm" "$manifest"; then
        problems="$problems Manifest 出现业务权限 $perm;"
      fi
    done
  fi
  hits="$(grep -rIn --exclude-dir=build --exclude-dir=.gradle --exclude-dir=.kotlin \
    --include='*.kt' --include='*.java' \
    -E 'GPX|TCX|GpxParser|TcxParser|TextToSpeech|MediaPlayer|AudioTrack|LocationManager|FusedLocationProvider|CountDownTimer|TimerTask|Export|RunSession|History(Store|Repo|Repository|ViewModel|Screen)' \
    "$android_dir/app/src/main" 2>/dev/null || true)"
  [ -z "$hits" ] || problems="$problems src/main 源码出现业务实现痕迹: $(printf '%s' "$hits" | tr '\n' ' ');"
  hits="$(grep -rIn --exclude-dir=build --exclude-dir=.gradle --exclude-dir=.kotlin \
    --include='*.gradle.kts' --include='*.gradle' --include='gradle.properties' \
    -E 'react-native|com\.facebook\.react|io\.flutter|flutter|org\.jetbrains\.compose|compose-multiplatform' \
    "$android_dir" 2>/dev/null || true)"
  [ -z "$hits" ] || problems="$problems 依赖/配置出现跨端框架痕迹: $(printf '%s' "$hits" | tr '\n' ' ');"
  if [ -z "$problems" ]; then
    pass "ac-check-android-no-business"
  else
    fail "ac-check-android-no-business" "$problems"
  fi

  return $((FAILURES - base_failures))
}

check_android_structure "$repo_root"

# ------------------------------------- android/local.properties 未入库 + gitignore 覆盖
problems=""
if [ -f .gitignore ]; then
  grep -Fq -- 'android/local.properties' .gitignore \
    || problems="$problems .gitignore 未忽略 android/local.properties;"
else
  problems="$problems 缺少 .gitignore;"
fi
if git rev-parse --git-dir >/dev/null 2>&1; then
  if git ls-files --error-unmatch android/local.properties >/dev/null 2>&1; then
    problems="$problems android/local.properties 已被 git 跟踪;"
  fi
fi
if [ -z "$problems" ]; then
  pass "ac-check-android-sdk-jdk (local.properties 未入库)"
else
  fail "ac-check-android-sdk-jdk" "$problems"
fi

# ------------------------------------------------- .munk/code-gates.json 完整性
if ! command -v node >/dev/null 2>&1; then
  fail "ac-check-android-gates-integrity" "缺少 node，无法解析 .munk/code-gates.json"
elif [ ! -f .munk/code-gates.json ]; then
  fail "ac-check-android-gates-integrity" "缺少 .munk/code-gates.json"
else
  gate_error="$(node -e '
    const fs = require("fs");
    const bad = (m) => { console.error(m); process.exit(1); };
    let cfg;
    try { cfg = JSON.parse(fs.readFileSync(".munk/code-gates.json", "utf8")); }
    catch (e) { bad("JSON 解析失败: " + e.message); }
    if (cfg.version !== 1) bad("version 必须为 1");
    if (!Array.isArray(cfg.gates) || cfg.gates.length === 0) bad("gates 必须是非空数组");
    const ids = cfg.gates.map((g) => g.id);
    if (new Set(ids).size !== ids.length) bad("门 id 不唯一");
    for (const g of cfg.gates) {
      if (typeof g.command !== "string" || g.command.trim() === "") bad("门 " + g.id + " 的 command 为空");
      if (/[&|;<>`]|\n/.test(g.command)) bad("门 " + g.id + " 的 command 含 shell 分隔符或重定向: " + g.command);
      if (/^\s*(echo|true|:)\b/.test(g.command)) bad("门 " + g.id + " 是占位/空转命令: " + g.command);
      if (g.cwd !== ".") bad("门 " + g.id + " 的 cwd 必须为 .");
    }
    const map = Object.fromEntries(cfg.gates.map((g) => [g.id, g.command]));
    const androidGates = {
      "lint-android": "bash scripts/check-android.sh",
      "lint-android-workflow": "bash scripts/check-android-workflow.sh",
      "build-android": "bash scripts/build-android.sh",
      "test-android": "bash scripts/test-android.sh",
      "package-android": "bash scripts/package-android.sh"
    };
    for (const [id, cmd] of Object.entries(androidGates)) {
      if (map[id] !== cmd) bad("Android 门 " + id + " 应为 " + cmd + "，实际 " + (map[id] || "<缺失>"));
    }
    const unchanged = {
      "lint": "bash -n scripts/version.sh",
      "lint-baseline": "bash -n scripts/check-baseline.sh",
      "lint-ios-core": "bash scripts/check-ios-core.sh",
      "lint-ios-scripts": "bash scripts/check-ios-scripts.sh",
      "lint-ios-release": "bash scripts/check-ios-release.sh",
      "lint-ios-shell": "bash scripts/check-ios-shell.sh",
      "lint-ios-workflow": "bash scripts/check-ios-workflow.sh",
      "lint-ios-run-core": "bash scripts/check-ios-run-core.sh",
      "build-ios-core": "swift build --package-path ios/Core",
      "build-ios-run-core": "swift build --package-path ios/RunCore",
      "build-ios": "bash scripts/build-ios.sh",
      "test-ios-core": "swift test --package-path ios/Core",
      "test-ios-run-core": "swift test --package-path ios/RunCore",
      "test-ios": "bash scripts/test-ios.sh --unit-only",
      "test": "bash scripts/check-baseline.sh",
      "check-shared": "bash scripts/check-shared.sh",
      "check-gpx-export": "bash scripts/check-gpx-export.sh",
      "check-shell-expansion": "bash scripts/check-shell-expansion.sh"
    };
    for (const [id, cmd] of Object.entries(unchanged)) {
      if (map[id] !== cmd) bad("既有非 Android 门 " + id + " 被改动：期望 " + cmd + "，实际 " + (map[id] || "<缺失>") + "");
    }
    const expectedIds = [...Object.keys(androidGates), ...Object.keys(unchanged)].sort();
    if (JSON.stringify(ids.slice().sort()) !== JSON.stringify(expectedIds)) {
      bad("门 id 集合与约定不一致（不得新增/删除约定外的门）: " + ids.join(","));
    }
  ' 2>&1)" && gate_ok=1 || gate_ok=0
  if [ "$gate_ok" -eq 1 ]; then
    pass "ac-check-android-gates-integrity"
  else
    fail "ac-check-android-gates-integrity" "$(printf '%s' "$gate_error" | tr '\n' ' ')"
  fi
fi

# ---------------------------------------------------------- 反例自检（非恒真）
sandbox="$(mktemp -d "${TMPDIR:-/tmp}/purepace-check-android.XXXXXX")"
cleanup_sandbox() {
  rm -rf "$sandbox"
}
trap cleanup_sandbox EXIT

sandbox_copy() {
  local src="$1" dest="$2"
  [ -e "$src" ] || return 0
  mkdir -p "$(dirname "$dest")"
  cp -R "$src" "$dest"
}

sandbox_copy VERSION "$sandbox/VERSION"
sandbox_copy android/gradle.properties "$sandbox/android/gradle.properties"
sandbox_copy android/settings.gradle.kts "$sandbox/android/settings.gradle.kts"
sandbox_copy android/build.gradle.kts "$sandbox/android/build.gradle.kts"
sandbox_copy android/gradlew "$sandbox/android/gradlew"
sandbox_copy android/app/build.gradle.kts "$sandbox/android/app/build.gradle.kts"
sandbox_copy android/app/src/main/AndroidManifest.xml "$sandbox/android/app/src/main/AndroidManifest.xml"
sandbox_copy android/app/src/main/java "$sandbox/android/app/src/main/java"
sandbox_copy android/app/src/test/java "$sandbox/android/app/src/test/java"
sandbox_copy android/gradle/wrapper/gradle-wrapper.jar "$sandbox/android/gradle/wrapper/gradle-wrapper.jar"
sandbox_copy android/gradle/wrapper/gradle-wrapper.properties "$sandbox/android/gradle/wrapper/gradle-wrapper.properties"

negative_problems=""

if negative_out="$(check_android_structure "$sandbox" 2>&1)"; then
  negative_rc=0
else
  negative_rc=$?
fi
[ "$negative_rc" -eq 0 ] || negative_problems="$negative_problems 沙箱基线样本未通过结构断言（$negative_rc 项失败）;"

# 反例 1：applicationId 字面值出现第二处
printf '\nPUREPACE_APPLICATION_ID_ECHO=sh.munk.purepace\n' >> "$sandbox/android/gradle.properties"
if negative_out="$(check_android_structure "$sandbox" 2>&1)"; then
  negative_rc=0
else
  negative_rc=$?
fi
if [ "$negative_rc" -eq 0 ]; then
  negative_problems="$negative_problems 注入第二个 applicationId 未 FAIL;"
elif ! grep -Fq -- '[FAIL] ac-check-android-application-id' <<< "$negative_out"; then
  negative_problems="$negative_problems 注入第二个 applicationId 未命中 ac-check-android-application-id FAIL;"
fi

# 恢复 gradle.properties 后注入 compileSdk 反例
sandbox_copy android/gradle.properties "$sandbox/android/gradle.properties"
if [ -f android/app/build.gradle.kts ]; then
  sed 's/compileSdk[[:space:]]*=[[:space:]]*36/compileSdk = 35/' \
    android/app/build.gradle.kts > "$sandbox/android/app/build.gradle.kts"
fi
if negative_out="$(check_android_structure "$sandbox" 2>&1)"; then
  negative_rc=0
else
  negative_rc=$?
fi
if [ "$negative_rc" -eq 0 ]; then
  negative_problems="$negative_problems 注入 compileSdk=35 未 FAIL;"
elif ! grep -Fq -- '[FAIL] ac-check-android-sdk-jdk' <<< "$negative_out"; then
  negative_problems="$negative_problems 注入 compileSdk=35 未命中 ac-check-android-sdk-jdk FAIL;"
fi

if [ -z "$negative_problems" ]; then
  pass "ac-check-android-negative-path"
else
  fail "ac-check-android-negative-path" "$negative_problems"
fi

# ------------------- 有界重试行为反例（沙箱 stub，离线、无网络、不碰仓库）
retry_root="$sandbox/retry"
mkdir -p "$retry_root/scripts" "$retry_root/android"
cp scripts/build-android.sh "$retry_root/scripts/build-android.sh"
cp scripts/test-android.sh "$retry_root/scripts/test-android.sh"

mkdir -p "$retry_root/fake-jdk/bin" "$retry_root/fake-sdk"
cat > "$retry_root/fake-jdk/bin/java" <<'FAKEJAVA'
#!/usr/bin/env bash
echo 'openjdk version "21.0.1" 2024-01-15'
FAKEJAVA
chmod +x "$retry_root/fake-jdk/bin/java"

cat > "$retry_root/android/gradlew" <<'STUBGRADLE'
#!/usr/bin/env bash
set -u
mode="${PUREPACE_STUB_MODE:-network}"
counter="${PUREPACE_STUB_COUNTER:?counter required}"
task=""
for arg in "$@"; do
  case "$arg" in
    assembleDebug|testDebugUnitTest) task="$arg" ;;
  esac
done
attempt=0
if [ -f "$counter" ]; then
  attempt="$(cat "$counter")"
fi
attempt=$((attempt + 1))
printf '%s\n' "$attempt" > "$counter"
case "$mode" in
  network)
    echo "Could not download https://services.gradle.org/distributions/gradle-8.14.3-all.zip: HTTP 504 Gateway Timeout" >&2
    exit 5
    ;;
  buildfail)
    echo "e: compile error without network marker" >&2
    exit 3
    ;;
  success2)
    if [ "$attempt" -lt 2 ]; then
      echo "Could not download https://services.gradle.org/distributions/gradle-8.14.3-all.zip: HTTP 504 Gateway Timeout" >&2
      exit 5
    fi
    ;;
  *)
    echo "unknown stub mode" >&2
    exit 9
    ;;
esac
if [ "$task" = "assembleDebug" ]; then
  mkdir -p android/app/build/outputs/apk/debug
  printf 'fake-apk\n' > android/app/build/outputs/apk/debug/app-debug.apk
elif [ "$task" = "testDebugUnitTest" ]; then
  mkdir -p android/app/build/test-results/testDebugUnitTest
  printf '%s\n' '<testsuite name="sh.munk.purepace.FakeJvmTest" tests="1" failures="0" errors="0" skipped="0"></testsuite>' > android/app/build/test-results/testDebugUnitTest/TEST-sh.munk.purepace.FakeJvmTest.xml
  printf '%s\n' '<testsuite name="sh.munk.purepace.FakeRobolectricTest" tests="1" failures="0" errors="0" skipped="0"></testsuite>' > android/app/build/test-results/testDebugUnitTest/TEST-sh.munk.purepace.FakeRobolectricTest.xml
fi
exit 0
STUBGRADLE

mkdir -p "$retry_root/android/app/src/test/java/sh/munk/purepace"
printf '%s\n' 'package sh.munk.purepace' 'class FakeJvmTest' \
  > "$retry_root/android/app/src/test/java/sh/munk/purepace/FakeJvmTest.kt"
printf '%s\n' 'package sh.munk.purepace' '// RobolectricTestRunner' 'class FakeRobolectricTest' \
  > "$retry_root/android/app/src/test/java/sh/munk/purepace/FakeRobolectricTest.kt"

retry_counter="$retry_root/attempts.txt"

run_retry_case() {
  local script="$1" mode="$2"
  rm -f "$retry_counter"
  rm -rf "$retry_root/android/app/build"
  (
    cd "$retry_root" || exit 1
    PUREPACE_STUB_MODE="$mode" \
      PUREPACE_STUB_COUNTER="$retry_counter" \
      JAVA_HOME="$retry_root/fake-jdk" \
      ANDROID_HOME="$retry_root/fake-sdk" \
      PATH="$retry_root/fake-jdk/bin:$PATH" \
      bash "scripts/$script"
  ) >"$retry_root/${script}.${mode}.log" 2>&1
  return $?
}

retry_attempts=0

retry_problems=""

# 反例 A：非网络失败立即失败，只尝试 1 次，退出码原样透传
if run_retry_case build-android.sh buildfail; then retry_rc=0; else retry_rc=$?; fi
retry_attempts="$(cat "$retry_counter" 2>/dev/null || echo 0)"
retry_log="$retry_root/build-android.sh.buildfail.log"
if [ "$retry_rc" -ne 3 ]; then
  retry_problems="$retry_problems build-android 非网络失败退出码 ${retry_rc}（期望 3）;"
fi
if [ "$retry_attempts" -ne 1 ]; then
  retry_problems="$retry_problems build-android 非网络失败尝试 ${retry_attempts} 次（期望 1）;"
fi
grep -Fq -- '非网络类失败' "$retry_log" || retry_problems="$retry_problems build-android 未打印非网络失败提示;"

# 反例 B：网络类失败每次命中，恰好 1 + 3 次尝试后原样非零退出
if run_retry_case build-android.sh network; then retry_rc=0; else retry_rc=$?; fi
retry_attempts="$(cat "$retry_counter" 2>/dev/null || echo 0)"
retry_log="$retry_root/build-android.sh.network.log"
if [ "$retry_rc" -ne 5 ]; then
  retry_problems="$retry_problems build-android 网络失败退出码 ${retry_rc}（期望 5）;"
fi
if [ "$retry_attempts" -ne 4 ]; then
  retry_problems="$retry_problems build-android 网络失败尝试 ${retry_attempts} 次（期望 4）;"
fi
grep -Fq -- '4/4 次尝试' "$retry_log" || retry_problems="$retry_problems build-android 未打印 4/4 次尝试;"
grep -Fq -- '尝试上限' "$retry_log" || retry_problems="$retry_problems build-android 未打印放弃重试提示;"

# 反例 C：第 2 次尝试成功，重试后继续原有 APK 产物校验
if run_retry_case build-android.sh success2; then retry_rc=0; else retry_rc=$?; fi
retry_attempts="$(cat "$retry_counter" 2>/dev/null || echo 0)"
retry_log="$retry_root/build-android.sh.success2.log"
if [ "$retry_rc" -ne 0 ]; then
  retry_problems="$retry_problems build-android 第 2 次成功仍退出 ${retry_rc};"
fi
if [ "$retry_attempts" -ne 2 ]; then
  retry_problems="$retry_problems build-android 第 2 次成功尝试 ${retry_attempts} 次（期望 2）;"
fi
if [ ! -s "$retry_root/android/app/build/outputs/apk/debug/app-debug.apk" ]; then
  retry_problems="$retry_problems build-android 第 2 次成功后未校验到 APK 产物;"
fi

# 反例 D：test-android 网络失败恰好 4 次尝试后以 1 结束并打印失败信息
if run_retry_case test-android.sh network; then retry_rc=0; else retry_rc=$?; fi
retry_attempts="$(cat "$retry_counter" 2>/dev/null || echo 0)"
retry_log="$retry_root/test-android.sh.network.log"
if [ "$retry_rc" -ne 1 ]; then
  retry_problems="$retry_problems test-android 网络失败退出码 ${retry_rc}（期望 1）;"
fi
if [ "$retry_attempts" -ne 4 ]; then
  retry_problems="$retry_problems test-android 网络失败尝试 ${retry_attempts} 次（期望 4）;"
fi
grep -Fq -- 'testDebugUnitTest 失败' "$retry_log" || retry_problems="$retry_problems test-android 未打印 testDebugUnitTest 失败;"

# 反例 E：test-android 第 2 次成功，继续原有 test-results 与用例计数校验
if run_retry_case test-android.sh success2; then retry_rc=0; else retry_rc=$?; fi
retry_attempts="$(cat "$retry_counter" 2>/dev/null || echo 0)"
retry_log="$retry_root/test-android.sh.success2.log"
if [ "$retry_rc" -ne 0 ]; then
  retry_problems="$retry_problems test-android 第 2 次成功仍退出 ${retry_rc};"
fi
if [ "$retry_attempts" -ne 2 ]; then
  retry_problems="$retry_problems test-android 第 2 次成功尝试 ${retry_attempts} 次（期望 2）;"
fi
grep -Fq -- 'Android 测试通过' "$retry_log" || retry_problems="$retry_problems test-android 第 2 次成功后未走原成功路径;"

if [ -z "$retry_problems" ]; then
  pass "ac-check-android-retry-cases"
else
  fail "ac-check-android-retry-cases" "$retry_problems"
fi


# ==================================================== 同意门 / 政策 / 打包契约断言
policy_sync_problems() {
  local md_path="$1" xml_path="$2"
  node - "${md_path}" "${xml_path}" <<'POLICY'
const fs = require('fs');
const [mdPath, xmlPath] = process.argv.slice(2);
const norm = (value) => value.replace(/\s+/g, ' ').trim();
const md = fs.readFileSync(mdPath, 'utf8');
const paragraphs = md
  .split(/\r?\n\s*\r?\n/)
  .map(norm)
  .filter(Boolean)
  .filter((line) => !/^#{1,6}\s/.test(line));
const xml = fs.readFileSync(xmlPath, 'utf8');
const array = xml.match(/<string-array name="privacy_policy_paragraphs">([\s\S]*?)<\/string-array>/);
if (!array) {
  console.log('strings.xml 缺少 privacy_policy_paragraphs');
  process.exit(1);
}
const unescape = (value) => value
  .replace(/&lt;/g, '<')
  .replace(/&gt;/g, '>')
  .replace(/&quot;/g, '"')
  .replace(/&apos;/g, "'")
  .replace(/&amp;/g, '&');
const items = [...array[1].matchAll(/<item>([\s\S]*?)<\/item>/g)].map((match) => norm(unescape(match[1])));
if (items.length !== paragraphs.length) {
  console.log(`政策段数不一致：md=${paragraphs.length} strings.xml=${items.length}`);
  process.exit(1);
}
for (let index = 0; index < paragraphs.length; index += 1) {
  if (paragraphs[index] !== items[index]) {
    console.log(`政策第 ${index + 1} 段与真源不一致`);
    process.exit(1);
  }
}
process.exit(0);
POLICY
}

consent_copy_problems() {
  local source_dir="$1"
  node - "${source_dir}" <<'COPY'
const fs = require('fs');
const path = require('path');
const root = process.argv[2];
const files = [];
(function walk(dir) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) walk(full);
    else if (full.endsWith('.kt')) files.push(full);
  }
})(root);
const problems = [];
for (const file of files) {
  const text = fs.readFileSync(file, 'utf8');
  if (/[\u3400-\u9fff]/.test(text)) problems.push(`${file}: CJK literal`);
  text.split('\n').forEach((line, index) => {
    if (/\b(text|contentDescription)\s*=\s*"/.test(line)) {
      problems.push(`${file}:${index + 1}: inline user copy`);
    }
  });
}
if (problems.length > 0) {
  console.log(problems.join('; '));
  process.exit(1);
}
process.exit(0);
COPY
}

hardcoded_credential_hits() {
  grep -En 'storePassword|keyPassword|signingConfig|--ks-pass|--storepass' "$1" 2>/dev/null || true
}

sha256_file_check() {
  local file="$1"
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "${file}" | cut -d ' ' -f 1
  else
    sha256sum "${file}" | cut -d ' ' -f 1
  fi
}

verify_package_manifest() {
  local manifest="$1" commit="$2" version="$3" version_code="$4"
  node - "${manifest}" "${commit}" "${version}" "${version_code}" <<'MANIFEST'
const fs = require('fs');
const [file, commit, version, versionCode] = process.argv.slice(2);
if (!fs.existsSync(file)) {
  console.log('缺少 manifest.json');
  process.exit(1);
}
let manifest;
try {
  manifest = JSON.parse(fs.readFileSync(file, 'utf8'));
} catch (error) {
  console.log('manifest.json 无法解析: ' + error.message);
  process.exit(1);
}
const expected = ['applicationId', 'buildTime', 'commit', 'minSdk', 'sha256', 'targetSdk', 'version', 'versionCode'].sort();
const actual = Object.keys(manifest).sort();
if (JSON.stringify(actual) !== JSON.stringify(expected)) {
  console.log('manifest.json 字段集合不符: ' + actual.join(','));
  process.exit(1);
}
if (manifest.applicationId !== 'sh.munk.purepace') {
  console.log('applicationId 不符: ' + manifest.applicationId);
  process.exit(1);
}
if (manifest.version !== version) {
  console.log('version 不符: ' + manifest.version);
  process.exit(1);
}
if (String(manifest.versionCode) !== versionCode) {
  console.log('versionCode 不符: ' + manifest.versionCode);
  process.exit(1);
}
if (manifest.commit !== commit) {
  console.log('commit 不符: ' + manifest.commit);
  process.exit(1);
}
if (!/^[0-9a-f]{64}$/.test(String(manifest.sha256))) {
  console.log('sha256 形态不符: ' + manifest.sha256);
  process.exit(1);
}
if (manifest.minSdk !== 26 || manifest.targetSdk !== 36) {
  console.log('minSdk/targetSdk 不符: ' + manifest.minSdk + '/' + manifest.targetSdk);
  process.exit(1);
}
if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/.test(String(manifest.buildTime))) {
  console.log('buildTime 不是 ISO-8601 UTC: ' + manifest.buildTime);
  process.exit(1);
}
process.exit(0);
MANIFEST
}

verify_package_checksums() {
  local dir="$1" apk_name="$2"
  local checksums="${dir}/checksums.txt"
  if [ ! -s "${checksums}" ]; then
    echo "checksums.txt 缺失或为空"
    return 1
  fi
  local expected actual
  expected="$(cut -d ' ' -f 1 "${checksums}" | head -n 1)"
  actual="$(sha256_file_check "${dir}/${apk_name}")"
  if [ "${expected}" != "${actual}" ]; then
    echo "checksums.txt sha256 与 APK 实测不一致"
    return 1
  fi
  ( cd "${dir}" && if command -v shasum >/dev/null 2>&1; then
      shasum -a 256 -c checksums.txt >/dev/null 2>&1
    else
      sha256sum -c checksums.txt >/dev/null 2>&1
    fi )
}

# ---------------------------------------------------------------- 同意门静态契约
consent_dir="android/app/src/main/java/dev/purepace"
strings_file="android/app/src/main/res/values/strings.xml"
problems=""
for name in ConsentContract.kt ConsentStore.kt PurePaceApp.kt MainActivity.kt; do
  [ -f "${consent_dir}/${name}" ] || problems="${problems} 缺少 ${consent_dir}/${name};"
done
if [ ! -f "${strings_file}" ]; then
  problems="${problems} 缺少 ${strings_file};"
fi
if [ -f "${consent_dir}/ConsentContract.kt" ]; then
  grep -Fq -- 'evaluateStart' "${consent_dir}/ConsentContract.kt" || problems="${problems} ConsentContract 缺少 evaluateStart;"
  for tag in CONSENT_ROOT_TAG BLOCKED_REASON_TAG AGREE_TAG DECLINE_TAG WITHDRAW_TAG; do
    grep -Fq -- "${tag}" "${consent_dir}/ConsentContract.kt" || problems="${problems} ConsentContract 缺少 ${tag};"
  done
fi
if [ -f "${consent_dir}/ConsentStore.kt" ]; then
  grep -Fq -- 'interface ConsentStore' "${consent_dir}/ConsentStore.kt" || problems="${problems} ConsentStore 不是可注入接口;"
  grep -Fq -- 'SharedPreferences' "${consent_dir}/ConsentStore.kt" || problems="${problems} ConsentStore 未用 SharedPreferences 持久化;"
fi
if [ -f "${consent_dir}/PurePaceApp.kt" ]; then
  grep -Fq -- 'stringResource' "${consent_dir}/PurePaceApp.kt" || problems="${problems} 同意门/关于页未使用 stringResource;"
  grep -Fq -- 'privacy_policy_paragraphs' "${consent_dir}/PurePaceApp.kt" || problems="${problems} 关于页未渲染随包政策正文;"
  grep -Fq -- 'WITHDRAW_CONFIRM_TAG' "${consent_dir}/PurePaceApp.kt" || problems="${problems} 关于页缺少撤回确认入口;"
fi
if [ -f "${strings_file}" ]; then
  for key in consent_title consent_body_sensitive consent_body_local consent_body_refuse consent_body_withdraw consent_agree consent_decline consent_blocked_reason consent_role_primary consent_role_secondary privacy_policy_paragraphs; do
    grep -Fq -- "name=\"${key}\"" "${strings_file}" || problems="${problems} strings.xml 缺少 ${key};"
  done
  for phrase in '敏感个人信息' '只存在本机' '可以拒绝' '可随时撤回'; do
    grep -Fq -- "${phrase}" "${strings_file}" || problems="${problems} strings.xml 缺少关键条目「${phrase}」;"
  done
fi
if [ -z "${problems}" ]; then
  pass "ac-consent-gate-contract"
else
  fail "ac-consent-gate-contract" "${problems}"
fi

# ------------------------------------------------- 同意门 Kotlin 零裸文案 + 反例
if copy_out="$(consent_copy_problems "${consent_dir}" 2>&1)"; then
  pass "ac-consent-copy-from-strings"
else
  fail "ac-consent-copy-from-strings" "$(printf '%s' "${copy_out}" | tr '\n' ' ')"
fi
copy_sandbox="${sandbox}/consent-copy"
mkdir -p "${copy_sandbox}"
cp -R "${consent_dir}/." "${copy_sandbox}/"
printf '\nval leakedCopy = "裸中文文案"\n' >> "${copy_sandbox}/ConsentContract.kt"
if consent_copy_problems "${copy_sandbox}" >/dev/null 2>&1; then
  fail "ac-consent-copy-from-strings (self-test)" "注入中文裸字面量后未被判红"
else
  pass "ac-consent-copy-from-strings (self-test)"
fi

# ------------------------------------------------------- 政策单一真源 / 随包
policy_md="docs/privacy/privacy-policy-zh-Hans.md"
if [ ! -f "${policy_md}" ]; then
  fail "ac-policy-single-source-sync" "缺少政策真源 ${policy_md}"
elif [ ! -f "${strings_file}" ]; then
  fail "ac-policy-single-source-sync" "缺少 ${strings_file}"
elif policy_out="$(policy_sync_problems "${policy_md}" "${strings_file}" 2>&1)"; then
  second_source_hits="$(find docs -type f -name '*.md' ! -path 'docs/privacy/*' -exec grep -Fl -- '本政策说明我们如何处理你的轨迹与跑步数据' {} + 2>/dev/null || true)"
  policy_count="$(find docs/privacy -type f -name '*.md' 2>/dev/null | wc -l | tr -d ' ')"
  if [ -n "${second_source_hits}" ]; then
    fail "ac-policy-single-source-sync" "仓内存在第二份政策正文: $(printf '%s' "${second_source_hits}" | tr '\n' ' ')"
  elif [ "${policy_count}" -ne 1 ]; then
    fail "ac-policy-single-source-sync" "docs/privacy 下政策正文文件数为 ${policy_count}（期望 1）"
  else
    pass "ac-policy-single-source-sync"
  fi
else
  fail "ac-policy-single-source-sync" "$(printf '%s' "${policy_out}" | tr '\n' ' ')"
fi
policy_sandbox="${sandbox}/privacy-policy-zh-Hans.md"
cp "${policy_md}" "${policy_sandbox}"
sed 's/仅本机存储/仅保存在本地/' "${policy_md}" > "${policy_sandbox}.tampered"
sed -e 's/仅保存在本地/仅本机存储/' -e 's/敏感个人信息/个人位置信息/' "${policy_sandbox}.tampered" > "${policy_sandbox}.tampered2"
if cmp -s "${policy_md}" "${policy_sandbox}.tampered"; then
  fail "ac-policy-single-source-sync (self-test)" "篡改样本与真源相同（sed 未命中，反例退化为空转）"
elif cmp -s "${policy_md}" "${policy_sandbox}.tampered2"; then
  fail "ac-policy-single-source-sync (self-test)" "篡改样本 2 与真源相同（sed 未命中，反例退化为空转）"
elif policy_sync_problems "${policy_md}" "${strings_file}" >/dev/null 2>&1 \
  && ! policy_sync_problems "${policy_sandbox}.tampered" "${strings_file}" >/dev/null 2>&1 \
  && ! policy_sync_problems "${policy_sandbox}.tampered2" "${strings_file}" >/dev/null 2>&1; then
  pass "ac-policy-single-source-sync (self-test)"
else
  fail "ac-policy-single-source-sync" "沙箱改真源任一段后未被判红"
fi

problems=""
manifest_file="android/app/src/main/AndroidManifest.xml"
if [ ! -f "${manifest_file}" ]; then
  problems="${problems} 缺少 ${manifest_file};"
else
  if grep -Fq -- '<uses-permission' "${manifest_file}"; then
    problems="${problems} Manifest 新增了 uses-permission（政策必须随包渲染，不申请网络权限）;"
  fi
fi
network_hits="$(grep -rIn --exclude-dir=build --exclude-dir=.gradle --exclude-dir=.kotlin \
  -E 'HttpURLConnection|OkHttp|java\.net\.|WebView|INTERNET' "${consent_dir}" 2>/dev/null || true)"
[ -z "${network_hits}" ] || problems="${problems} 政策/同意门渲染路径出现网络调用: $(printf '%s' "${network_hits}" | tr '\n' ' ');"
if [ -z "${problems}" ]; then
  pass "ac-policy-bundled-no-network"
else
  fail "ac-policy-bundled-no-network" "${problems}"
fi

# ------------------------------------------------- 门接线（ac-gates-package-wired）
gates_package_wired_problem() {
  node - "$1" <<'GATE'
const fs = require('fs');
const file = process.argv[2];
let cfg;
try {
  cfg = JSON.parse(fs.readFileSync(file, 'utf8'));
} catch (error) {
  console.log('JSON 解析失败: ' + error.message);
  process.exit(1);
}
const gates = Array.isArray(cfg.gates) ? cfg.gates : [];
const hits = gates.filter((gate) => gate.id === 'package-android');
if (hits.length !== 1) {
  console.log(`package-android 门数量 ${hits.length}（期望 1）`);
  process.exit(1);
}
const gate = hits[0];
if (gate.command !== 'bash scripts/package-android.sh') {
  console.log('package-android command 不符: ' + gate.command);
  process.exit(1);
}
if (gate.cwd !== '.') {
  console.log('package-android cwd 不是 .');
  process.exit(1);
}
process.exit(0);
GATE
}

gates_without_package="${sandbox}/code-gates-without-package.json"
node - ".munk/code-gates.json" "${gates_without_package}" <<'STRIP'
const fs = require('fs');
const [source, target] = process.argv.slice(2);
const cfg = JSON.parse(fs.readFileSync(source, 'utf8'));
cfg.gates = cfg.gates.filter((gate) => gate.id !== 'package-android');
fs.writeFileSync(target, JSON.stringify(cfg, null, 2));
STRIP
if ! gates_package_wired_problem .munk/code-gates.json >/dev/null 2>&1; then
  fail "ac-gates-package-wired" "package-android 门缺失或命令/ cwd 不符"
elif gates_package_wired_problem "${gates_without_package}" >/dev/null 2>&1; then
  fail "ac-gates-package-wired" "沙箱删除 package-android 门后未被判红"
else
  pass "ac-gates-package-wired"
fi

# ------------------------------------------------------ 打包脚本静态 + 行为反例
package_script="scripts/package-android.sh"
problems=""
if [ ! -f "${package_script}" ]; then
  problems="${problems} 缺少 ${package_script};"
else
  grep -Fq -- 'PUREPACE_DIST_ROOT' "${package_script}" || problems="${problems} 未支持 PUREPACE_DIST_ROOT 覆盖;"
  grep -Fq -- 'purepace-dist/android' "${package_script}" || problems="${problems} 未按约定拼装分发目录;"
  grep -Fq -- 'manifest.json' "${package_script}" || problems="${problems} 未写 manifest.json;"
  grep -Fq -- 'checksums.txt' "${package_script}" || problems="${problems} 未写 checksums.txt;"
  grep -Fq -- 'printf '\''APK=%s' "${package_script}" || problems="${problems} 未打印 APK= 行;"
  grep -Fq -- 'printf '\''SHA256=%s' "${package_script}" || problems="${problems} 未打印 SHA256= 行;"
  grep -Fq -- 'shasum -a 256' "${package_script}" || problems="${problems} 未用 shasum -a 256;"
  grep -Fq -- '仓库外' "${package_script}" || problems="${problems} 未拒绝仓内分发路径;"
fi
if [ -z "${problems}" ]; then
  pass "ac-package-script-contract"
else
  fail "ac-package-script-contract" "${problems}"
fi

pkg_root="${sandbox}/package"
mkdir -p "${pkg_root}/scripts" "${pkg_root}/android/app/build" "${pkg_root}/fake-jdk/bin" "${pkg_root}/fake-sdk"
cp "${package_script}" "${pkg_root}/scripts/package-android.sh"
cp VERSION "${pkg_root}/VERSION"
cp android/app/build.gradle.kts "${pkg_root}/android/app/build.gradle.kts"
cp android/gradle.properties "${pkg_root}/android/gradle.properties"
cat > "${pkg_root}/fake-jdk/bin/java" <<'FAKEJAVA'
#!/usr/bin/env bash
echo 'openjdk version "21.0.1" 2024-01-15'
FAKEJAVA
chmod +x "${pkg_root}/fake-jdk/bin/java"
cat > "${pkg_root}/android/gradlew" <<'STUBGRADLE'
#!/usr/bin/env bash
set -u
mode="${PUREPACE_STUB_MODE:-ok}"
counter="${PUREPACE_STUB_COUNTER:?counter required}"
task=""
for arg in "$@"; do
  case "$arg" in
    assembleDebug) task="assembleDebug" ;;
  esac
done
if [ "${task}" != "assembleDebug" ]; then
  echo "package stub only handles assembleDebug" >&2
  exit 9
fi
attempt=0
if [ -f "${counter}" ]; then
  attempt="$(cat "${counter}")"
fi
attempt=$((attempt + 1))
printf '%s\n' "${attempt}" > "${counter}"
out_dir="android/app/build/outputs/apk/debug"
mkdir -p "${out_dir}"
rm -f "${out_dir}/app-debug.apk"
work="$(mktemp -d "${TMPDIR:-/tmp}/purepace-package-stub.XXXXXX")"
if [ "${mode}" = "emptyapk" ]; then
  : > "${out_dir}/app-debug.apk"
else
  if [ "${mode}" = "varysha" ]; then
    printf 'apk-%s\n' "${attempt}" > "${work}/payload.txt"
  else
    printf 'stable-apk\n' > "${work}/payload.txt"
  fi
  touch -t 198001010000 "${work}/payload.txt"
  apk_abs="$(pwd)/${out_dir}/app-debug.apk"
  if command -v zip >/dev/null 2>&1; then
    ( cd "${work}" && zip -X -q "${apk_abs}" payload.txt )
  else
    jar cf "${apk_abs}" -C "${work}" payload.txt
  fi
fi
rm -rf "${work}"
version="$(tr -d '\r\n' < VERSION)"
printf '{"version":3,"applicationId":"sh.munk.purepace","variantName":"debug","elements":[{"versionCode":1,"versionName":"%s","outputFile":"app-debug.apk"}]}\n' "${version}" > "${out_dir}/output-metadata.json"
exit 0
STUBGRADLE
chmod +x "${pkg_root}/android/gradlew"
git init -q "${pkg_root}"
git -C "${pkg_root}" -c user.email=check@example.invalid -c user.name=check add VERSION
git -C "${pkg_root}" -c user.email=check@example.invalid -c user.name=check commit -q -m init
pkg_commit="$(git -C "${pkg_root}" rev-parse HEAD)"
pkg_version="$(tr -d '\r\n' < VERSION)"
pkg_counter="${pkg_root}/attempts.txt"

# 在沙箱 pkg_root 内按给定脚本路径与参数运行（脚本参数透传给被测脚本；
# 沙箱脚本仍以自身 BASH_SOURCE 推导仓库根，因此副本须放在 pkg_root/scripts/ 下）。
run_package_script() {
  local script_path="$1" mode="$2" dist_root="$3" log_name="$4" rc=0
  shift 4
  (
    cd "${pkg_root}" || exit 1
    PUREPACE_DIST_ROOT="${dist_root}" \
      PUREPACE_STUB_MODE="${mode}" \
      PUREPACE_STUB_COUNTER="${pkg_counter}" \
      JAVA_HOME="${pkg_root}/fake-jdk" \
      ANDROID_HOME="${pkg_root}/fake-sdk" \
      PATH="${pkg_root}/fake-jdk/bin:${PATH}" \
      bash "${script_path}" "$@"
  ) > "${pkg_root}/${log_name}.log" 2>&1 || rc=$?
  return "${rc}"
}

run_package_case() {
  local mode="$1" dist_root="$2" log_name="$3"
  shift 3
  run_package_script scripts/package-android.sh "${mode}" "${dist_root}" "${log_name}" "$@"
}

# 预置「既有版本目录」现场：哨兵文件 + 旧 checksums.txt + 旧 manifest.json。
# 旧 manifest 写的是一个「陌生」commit（全 0）与占位 sha256，因此同 commit 幂等断言
# 不会被误触发：这里的断言只可能来自「既有目录是否被改动 / 是否改用兄弟目录」。
seed_existing_target() {
  local dist_root="$1"
  local target="${dist_root}/purepace-dist/android/${pkg_version}-1"
  mkdir -p "${target}"
  printf 'sentinel-keep-me\n' > "${target}/sentinel.txt"
  printf 'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff  stale.apk\n' > "${target}/checksums.txt"
  cat > "${target}/manifest.json" <<'SEEDMANIFEST'
{
  "applicationId": "sh.munk.purepace",
  "version": "seed",
  "versionCode": 1,
  "commit": "0000000000000000000000000000000000000000",
  "sha256": "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
  "minSdk": 26,
  "targetSdk": 36,
  "buildTime": "1970-01-01T00:00:00Z"
}
SEEDMANIFEST
  printf '%s' "${target}"
}
seed_manifest_commit="0000000000000000000000000000000000000000"
seed_manifest_build_time="1970-01-01T00:00:00Z"

layout_problems=""
manifest_problems=""
checksums_problems=""
idempotent_problems=""
credential_problems=""
red_proofs_problems=""
red_empty=0
red_checksum=0
red_inside=0
red_credential=0
red_idempotent=0

rm -f "${pkg_counter}"
ok_dist="${sandbox}/dist-ok"
if run_package_case ok "${ok_dist}" "ok-first"; then ok_rc=0; else ok_rc=$?; fi
ok_target="${ok_dist}/purepace-dist/android/${pkg_version}-1"
ok_apk_name="purepace-${pkg_version}-1-debug.apk"
if [ "${ok_rc}" -ne 0 ]; then
  layout_problems="${layout_problems} 正常打包退出 ${ok_rc};"
elif [ ! -d "${ok_target}" ]; then
  layout_problems="${layout_problems} 产物目录 ${ok_target} 不存在;"
else
  case "${ok_target}/" in
    "${pkg_root}"/*) layout_problems="${layout_problems} 产物目录落在仓库内 ${ok_target};" ;;
  esac
  dir_count="$(find "${ok_dist}/purepace-dist/android" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')"
  [ "${dir_count}" -eq 1 ] || layout_problems="${layout_problems} 分发目录数量 ${dir_count}（期望 1）;"
  apk_path="${ok_target}/${ok_apk_name}"
  if [ ! -s "${apk_path}" ]; then
    layout_problems="${layout_problems} APK 缺失或为空 ${apk_path};"
  elif ! unzip -l "${apk_path}" >/dev/null 2>&1; then
    layout_problems="${layout_problems} APK 无法用 unzip -l 读取;"
  fi
  [ -f "${ok_target}/manifest.json" ] || layout_problems="${layout_problems} 缺少 manifest.json;"
  [ -s "${ok_target}/checksums.txt" ] || layout_problems="${layout_problems} 缺少 checksums.txt;"
  ok_stdout_apk="$(grep -m1 '^APK=' "${pkg_root}/ok-first.log" | sed 's/^APK=//' || true)"
  ok_stdout_sha="$(grep -m1 '^SHA256=' "${pkg_root}/ok-first.log" | sed 's/^SHA256=//' || true)"
  ok_target_phys="$(cd "${ok_target}" && pwd -P)"
  [ "${ok_stdout_apk}" = "${ok_target_phys}/${ok_apk_name}" ] || layout_problems="${layout_problems} stdout APK= 与产物路径不一致;"
  [ -n "${ok_stdout_sha}" ] || layout_problems="${layout_problems} stdout 缺少 SHA256= 行;"
  if manifest_out="$(verify_package_manifest "${ok_target}/manifest.json" "${pkg_commit}" "${pkg_version}" 1 2>&1)"; then
    :
  else
    manifest_problems="${manifest_problems} $(printf '%s' "${manifest_out}" | tr '\n' ' ');"
  fi
  manifest_sha="$(sed -n 's/.*"sha256"[[:space:]]*:[[:space:]]*"\([0-9a-f][0-9a-f]*\)".*/\1/p' "${ok_target}/manifest.json" | head -n 1)"
  actual_sha="$(sha256_file_check "${apk_path}")"
  [ "${manifest_sha}" = "${actual_sha}" ] || manifest_problems="${manifest_problems} manifest sha256 与 APK 实测不一致;"
  [ "${ok_stdout_sha}" = "${actual_sha}" ] || manifest_problems="${manifest_problems} stdout SHA256= 与 APK 实测不一致;"
  if checksums_out="$(verify_package_checksums "${ok_target}" "${ok_apk_name}" 2>&1)"; then
    :
  else
    checksums_problems="${checksums_problems} $(printf '%s' "${checksums_out}" | tr '\n' ' ');"
  fi
  cp "${ok_target}/checksums.txt" "${ok_target}/checksums.bak"
  tamper_line="$(cut -d ' ' -f 1 "${ok_target}/checksums.txt" | head -n 1)"
  tamper_first="${tamper_line:0:1}"
  case "${tamper_first}" in
    a) tamper_flip="b" ;;
    *) tamper_flip="a" ;;
  esac
  tampered="${tamper_flip}${tamper_line:1}"
  rest="$(cut -d ' ' -f 2- "${ok_target}/checksums.txt" | head -n 1)"
  printf '%s  %s\n' "${tampered}" "${rest}" > "${ok_target}/checksums.txt"
  if verify_package_checksums "${ok_target}" "${ok_apk_name}" >/dev/null 2>&1; then
    checksums_problems="${checksums_problems} 篡改 checksums.txt 后未被判红;"
  else
    red_checksum=1
  fi
  mv "${ok_target}/checksums.bak" "${ok_target}/checksums.txt"

  if run_package_case ok "${ok_dist}" "ok-second"; then second_rc=0; else second_rc=$?; fi
  second_sha="$(grep -m1 '^SHA256=' "${pkg_root}/ok-second.log" | sed 's/^SHA256=//' || true)"
  second_stdout_dist="$(grep -m1 '^DIST_DIR=' "${pkg_root}/ok-second.log" | sed 's/^DIST_DIR=//' || true)"
  dir_count="$(find "${ok_dist}/purepace-dist/android" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')"
  [ "${second_rc}" -eq 0 ] || idempotent_problems="${idempotent_problems} 第二次打包退出 ${second_rc};"
  [ "${second_sha}" = "${actual_sha}" ] || idempotent_problems="${idempotent_problems} 同 commit 第二次 sha256 变化;"
  [ "${dir_count}" -eq 2 ] || idempotent_problems="${idempotent_problems} 第二次打包后目录数 ${dir_count}（期望 2：基名 + -b2）;"
  [ "${second_stdout_dist}" = "$(cd "${ok_target}-b2" 2>/dev/null && pwd -P)" ] || idempotent_problems="${idempotent_problems} 第二次 STD_DIR= 不是 -b2 兄弟目录;"
  [ "$(sha256_file_check "${ok_target}/${ok_apk_name}")" = "${actual_sha}" ] || idempotent_problems="${idempotent_problems} 第二次打包改写了既有基名目录的 APK;"

  if run_package_case varysha "${ok_dist}" "varysha"; then vary_rc=0; else vary_rc=$?; fi
  if [ "${vary_rc}" -eq 0 ]; then
    idempotent_problems="${idempotent_problems} 第二轮产物 sha 变化未被判红;"
  elif grep -Fq -- '幂等' "${pkg_root}/varysha.log"; then
    red_idempotent=1
  else
    idempotent_problems="${idempotent_problems} sha 变化反例未命中幂等断言;"
  fi
fi

# ------------- 既有 <versionName>-<versionCode> 目录：不动它，改用递增兄弟目录
existing_problems=""
monotonic_problems=""
existing_red_proof_problems=""
cli_problems=""
red_existing=0

existing_dist="${sandbox}/dist-existing"
existing_base="$(seed_existing_target "${existing_dist}")"
base_sentinel_sha="$(sha256_file_check "${existing_base}/sentinel.txt")"
base_checksums_sha="$(sha256_file_check "${existing_base}/checksums.txt")"
base_manifest_sha="$(sha256_file_check "${existing_base}/manifest.json")"
if run_package_case ok "${existing_dist}" "existing-sibling"; then existing_rc=0; else existing_rc=$?; fi
sibling_dir="${existing_base}-b2"
sibling_apk="${sibling_dir}/purepace-${pkg_version}-1-debug.apk"
sibling_stdout_dist="$(grep -m1 '^DIST_DIR=' "${pkg_root}/existing-sibling.log" | sed 's/^DIST_DIR=//' || true)"
sibling_stdout_sha="$(grep -m1 '^SHA256=' "${pkg_root}/existing-sibling.log" | sed 's/^SHA256=//' || true)"
if [ "${existing_rc}" -ne 0 ]; then
  existing_problems="${existing_problems} 既有基名目录存在时打包退出 ${existing_rc};"
elif [ ! -d "${sibling_dir}" ]; then
  existing_problems="${existing_problems} 未改用 -b2 兄弟目录 ${sibling_dir};"
elif [ "${sibling_stdout_dist}" != "$(cd "${sibling_dir}" && pwd -P)" ]; then
  existing_problems="${existing_problems} stdout DIST_DIR= 不是本次实际输出目录;"
elif [ ! -s "${sibling_apk}" ]; then
  existing_problems="${existing_problems} 兄弟目录 APK 缺失或为空;"
elif [ ! -f "${sibling_dir}/manifest.json" ] || [ ! -s "${sibling_dir}/checksums.txt" ]; then
  existing_problems="${existing_problems} 兄弟目录缺少 manifest.json / checksums.txt;"
elif [ -z "${sibling_stdout_sha}" ] || [ "${sibling_stdout_sha}" != "$(sha256_file_check "${sibling_apk}")" ]; then
  existing_problems="${existing_problems} 兄弟目录 stdout SHA256= 与 APK 实测不一致;"
elif ! grep -Fq -- "${sibling_stdout_sha}" "${sibling_dir}/checksums.txt"; then
  existing_problems="${existing_problems} 兄弟目录 checksums.txt 未指向新产物 sha256;"
elif [ "$(sha256_file_check "${existing_base}/sentinel.txt")" != "${base_sentinel_sha}" ]; then
  existing_problems="${existing_problems} 既有目录哨兵文件字节被改写;"
elif [ "$(sha256_file_check "${existing_base}/checksums.txt")" != "${base_checksums_sha}" ]; then
  existing_problems="${existing_problems} 既有目录 checksums.txt 字节被改写;"
elif [ "$(sha256_file_check "${existing_base}/manifest.json")" != "${base_manifest_sha}" ]; then
  existing_problems="${existing_problems} 既有目录 manifest.json 字节被改写;"
elif [ -e "${existing_base}/${ok_apk_name}" ]; then
  existing_problems="${existing_problems} 既有目录被写入本次 APK（应为独立兄弟目录）;"
fi

# 序号单调：再跑一次必须落到 -b3，且 -b2 与基名目录字节不变
if run_package_case ok "${existing_dist}" "existing-sibling-second"; then existing2_rc=0; else existing2_rc=$?; fi
second_sibling_dir="${existing_base}-b3"
first_sibling_apk_sha="$(sha256_file_check "${sibling_apk}" 2>/dev/null || true)"
second_sibling_stdout_dist="$(grep -m1 '^DIST_DIR=' "${pkg_root}/existing-sibling-second.log" | sed 's/^DIST_DIR=//' || true)"
if [ "${existing2_rc}" -ne 0 ]; then
  monotonic_problems="${monotonic_problems} 第二次既有目录打包退出 ${existing2_rc};"
elif [ ! -d "${second_sibling_dir}" ]; then
  monotonic_problems="${monotonic_problems} 未按「已存在最大序号 + 1」改用 -b3;"
elif [ "${second_sibling_stdout_dist}" != "$(cd "${second_sibling_dir}" && pwd -P)" ]; then
  monotonic_problems="${monotonic_problems} 第二次 stdout DIST_DIR= 与 -b3 不一致;"
elif [ ! -s "${second_sibling_dir}/purepace-${pkg_version}-1-debug.apk" ]; then
  monotonic_problems="${monotonic_problems} -b3 兄弟目录 APK 缺失或为空;"
elif [ "$(sha256_file_check "${sibling_apk}")" != "${first_sibling_apk_sha}" ]; then
  monotonic_problems="${monotonic_problems} -b2 兄弟目录 APK 被第二次运行改写;"
elif [ "$(sha256_file_check "${existing_base}/manifest.json")" != "${base_manifest_sha}" ]; then
  monotonic_problems="${monotonic_problems} 基名目录 manifest.json 被第二次运行改写;"
fi

# 去守卫反例：删掉守卫块后同一现场会覆盖基名目录 → 既有字节必然变化（红由守卫触发）
guard_copy="${pkg_root}/scripts/package-android-noguard.sh"
if [ "$(grep -c -- 'guard-begin: preserve-existing-dist' "${package_script}" || true)" -lt 1 ] || \
   [ "$(grep -c -- 'guard-end: preserve-existing-dist' "${package_script}" || true)" -lt 1 ]; then
  existing_red_proof_problems="${existing_red_proof_problems} 生产脚本缺少 guard-begin/guard-end 标记，无法做去守卫自检;"
else
  sed '/# guard-begin: preserve-existing-dist/,/# guard-end: preserve-existing-dist/d' \
    "${pkg_root}/scripts/package-android.sh" > "${guard_copy}"
  if [ "$(grep -c -- 'preserve-existing-dist' "${guard_copy}" || true)" -ne 0 ]; then
    existing_red_proof_problems="${existing_red_proof_problems} 去守卫副本仍含守卫标记（删除未生效）;"
  elif ! bash -n "${guard_copy}" >/dev/null 2>&1; then
    existing_red_proof_problems="${existing_red_proof_problems} 去守卫副本 bash -n 失败（删除破坏了语法，反例不可信）;"
  fi
  noguard_dist="${sandbox}/dist-noguard"
  noguard_base="$(seed_existing_target "${noguard_dist}")"
  noguard_checksums_sha="$(sha256_file_check "${noguard_base}/checksums.txt")"
  noguard_manifest_sha="$(sha256_file_check "${noguard_base}/manifest.json")"
  if run_package_script scripts/package-android-noguard.sh ok "${noguard_dist}" "noguard-existing"; then
    noguard_rc=0
  else
    noguard_rc=$?
  fi
  if [ "${noguard_rc}" -ne 0 ]; then
    existing_red_proof_problems="${existing_red_proof_problems} 去守卫副本未变绿（退出 ${noguard_rc}，红因存疑）;"
  elif [ "$(sha256_file_check "${noguard_base}/checksums.txt")" = "${noguard_checksums_sha}" ] && \
       [ "$(sha256_file_check "${noguard_base}/manifest.json")" = "${noguard_manifest_sha}" ]; then
    existing_red_proof_problems="${existing_red_proof_problems} 去守卫副本没有覆盖既有基名目录（反例不成立）;"
  else
    red_existing=1
  fi
fi

help_out="$(cd "${pkg_root}" && bash scripts/package-android.sh --help 2>&1)" && help_rc=0 || help_rc=$?
if [ "${help_rc}" -ne 0 ]; then
  cli_problems="${cli_problems} --help 退出 ${help_rc};"
elif ! grep -Fq -- '兄弟目录' <<< "${help_out}"; then
  cli_problems="${cli_problems} --help 文本未说明兄弟目录语义;"
elif ! grep -Fq -- '-b<N>' <<< "${help_out}"; then
  cli_problems="${cli_problems} --help 文本缺少 -b<N> 序号命名;"
fi
(cd "${pkg_root}" && bash scripts/package-android.sh --bogus >/dev/null 2>&1) && bogus_rc=0 || bogus_rc=$?
[ "${bogus_rc}" -eq 2 ] || cli_problems="${cli_problems} 未知参数退出 ${bogus_rc}（期望 2）;"
if grep -Fq -- '--force' "${package_script}"; then
  cli_problems="${cli_problems} 生产脚本仍要求 --force（零参数必须可过门）;"
fi
if run_package_case ok "${pkg_root}/cli-inside-dist" "cli-inside-path"; then cli_inside_rc=0; else cli_inside_rc=$?; fi
if [ "${cli_inside_rc}" -eq 0 ]; then
  cli_problems="${cli_problems} PUREPACE_DIST_ROOT 指向仓库内未被拒绝;"
elif ! grep -Fq -- '仓库外' "${pkg_root}/cli-inside-path.log"; then
  cli_problems="${cli_problems} 仓内路径反例未命中仓库外断言;"
fi
grep -Fq -- '仓库外' "${package_script}" || cli_problems="${cli_problems} 仓内分发路径断言缺失;"

empty_dist="${sandbox}/dist-empty"
if run_package_case emptyapk "${empty_dist}" "empty-apk"; then empty_rc=0; else empty_rc=$?; fi
if [ "${empty_rc}" -eq 0 ]; then
  layout_problems="${layout_problems} 空 APK 未判红;"
elif grep -Eq 'APK|为空' "${pkg_root}/empty-apk.log"; then
  red_empty=1
else
  layout_problems="${layout_problems} 空 APK 反例未命中 APK 校验;"
fi

if run_package_case ok "${pkg_root}/inside-dist" "inside-path"; then inside_rc=0; else inside_rc=$?; fi
if [ "${inside_rc}" -eq 0 ]; then
  layout_problems="${layout_problems} PUREPACE_DIST_ROOT 指向仓库内未被拒绝;"
elif grep -Fq -- '仓库外' "${pkg_root}/inside-path.log"; then
  red_inside=1
else
  layout_problems="${layout_problems} 仓内路径反例未命中仓库外断言;"
fi

real_credentials="$(hardcoded_credential_hits "${package_script}")"
[ -z "${real_credentials}" ] || credential_problems="${credential_problems} 生产脚本命中明文凭据: $(printf '%s' "${real_credentials}" | tr '\n' ' ');"
bad_package_script="${sandbox}/bad-package-android.sh"
cp "${package_script}" "${bad_package_script}"
printf '\n# --ks-pass=plaintext\n' >> "${bad_package_script}"
if [ -n "$(hardcoded_credential_hits "${bad_package_script}")" ]; then
  red_credential=1
else
  credential_problems="${credential_problems} 注入明文口令后未被判红;"
fi

[ "${red_empty}" -eq 1 ] || red_proofs_problems="${red_proofs_problems} 空 APK 反例未取红（ac-package-path-and-layout）;"
[ "${red_checksum}" -eq 1 ] || red_proofs_problems="${red_proofs_problems} 篡改 checksums 反例未取红（ac-package-checksums-match）;"
[ "${red_inside}" -eq 1 ] || red_proofs_problems="${red_proofs_problems} 仓内分发路径反例未取红（ac-package-path-and-layout）;"
[ "${red_credential}" -eq 1 ] || red_proofs_problems="${red_proofs_problems} 明文口令反例未取红（ac-package-no-hardcoded-credentials）;"
[ "${red_idempotent}" -eq 1 ] || red_proofs_problems="${red_proofs_problems} 第二次 sha 变化反例未取红（ac-package-idempotent-same-commit）;"

if [ -z "${layout_problems}" ]; then
  pass "ac-package-path-and-layout"
else
  fail "ac-package-path-and-layout" "${layout_problems}"
fi
if [ -z "${manifest_problems}" ]; then
  pass "ac-package-manifest-fields"
else
  fail "ac-package-manifest-fields" "${manifest_problems}"
fi
if [ -z "${checksums_problems}" ]; then
  pass "ac-package-checksums-match"
else
  fail "ac-package-checksums-match" "${checksums_problems}"
fi
if [ -z "${idempotent_problems}" ]; then
  pass "ac-package-idempotent-same-commit"
else
  fail "ac-package-idempotent-same-commit" "${idempotent_problems}"
fi
if [ -z "${credential_problems}" ]; then
  pass "ac-package-no-hardcoded-credentials"
else
  fail "ac-package-no-hardcoded-credentials" "${credential_problems}"
fi
if [ -z "${red_proofs_problems}" ]; then
  pass "ac-package-red-proofs"
else
  fail "ac-package-red-proofs" "${red_proofs_problems}"
fi
if [ -z "${existing_problems}" ]; then
  pass "ac-package-existing-dir-sibling"
else
  fail "ac-package-existing-dir-sibling" "${existing_problems}"
fi
if [ -z "${monotonic_problems}" ]; then
  pass "ac-package-existing-dir-monotonic"
else
  fail "ac-package-existing-dir-monotonic" "${monotonic_problems}"
fi
if [ -z "${existing_red_proof_problems}" ] && [ "${red_existing}" -eq 1 ]; then
  pass "ac-package-existing-dir-red-proof"
else
  fail "ac-package-existing-dir-red-proof" "${existing_red_proof_problems} 去守卫反例未取红;"
fi
if [ -z "${cli_problems}" ]; then
  pass "ac-package-cli-contract-preserved"
else
  fail "ac-package-cli-contract-preserved" "${cli_problems}"
fi

printf '\n%d 项断言，%d 项失败\n' "$CHECKS" "$FAILURES"
if [ "$FAILURES" -ne 0 ]; then
  exit 1
fi
printf 'android scripts OK\n'
