#!/usr/bin/env bash
# Android 侧结构/契约断言（.munk/code-gates.json 的 lint-android 门真实执行体）。
# 校验三个新脚本的 bash 严格模式与参数契约、Android 工程结构（applicationId 单点、
# minSdk/compileSdk/JDK、版本派生、wrapper 固定、无业务实现、无跨端框架）、
# code-gates 完整性与既有非 Android 门零改动，并内置反例自检证明断言不是恒真。
set -euo pipefail

usage() {
  cat <<'EOF'
用法: scripts/check-android.sh [--help]

对 Android 侧脚本与工程结构逐条断言并打印 PASS/FAIL：
  - ac-script-help-and-strict   build/test/check 三个 Android 脚本 bash -n 通过、shebang 为
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
  - ac-check-android-gates-integrity
                                .munk/code-gates.json 可解析、id 唯一、无空转/串接命令，
                                Android 三门指向三个新脚本，既有非 Android 门 id 与 command 零改动
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

android_scripts="build-android.sh test-android.sh check-android.sh"

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
  elif ! printf '%s' "$help_out" | grep -Fq -- "用法"; then
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
  hits="$(grep -rIn --exclude-dir=build --exclude-dir=.gradle --exclude-dir=.kotlin -- 'com.chaxiu.purepace' "$android_dir" 2>/dev/null || true)"
  count=0
  if [ -n "$hits" ]; then
    count="$(printf '%s\n' "$hits" | wc -l | tr -d ' ')"
  fi
  [ "$count" -eq 1 ] || problems="$problems 字面值 com.chaxiu.purepace 在 android/ 出现 $count 次（期望 1，仅 gradle.properties）;"
  if [ -f "$android_dir/gradle.properties" ]; then
    grep -Eq '^PUREPACE_APPLICATION_ID=com\.chaxiu\.purepace$' "$android_dir/gradle.properties" \
      || problems="$problems android/gradle.properties 缺少唯一 PUREPACE_APPLICATION_ID=com.chaxiu.purepace 定义;"
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
    -E 'GPX|TCX|GpxParser|TcxParser|TextToSpeech|MediaPlayer|AudioTrack|LocationManager|FusedLocationProvider|CountDownTimer|TimerTask|Export|RunSession|History(Store|Repo|Repository|ViewModel|Screen)' \
    "$android_dir/app/src/main" 2>/dev/null || true)"
  [ -z "$hits" ] || problems="$problems src/main 出现业务实现痕迹: $(printf '%s' "$hits" | tr '\n' ' ');"
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
      "build-android": "bash scripts/build-android.sh",
      "test-android": "bash scripts/test-android.sh"
    };
    for (const [id, cmd] of Object.entries(androidGates)) {
      if (map[id] !== cmd) bad("Android 门 " + id + " 应为 " + cmd + "，实际 " + (map[id] || "<缺失>"));
    }
    const unchanged = {
      "lint": "bash -n scripts/version.sh",
      "lint-baseline": "bash -n scripts/check-baseline.sh",
      "lint-ios-core": "bash scripts/check-ios-core.sh",
      "lint-ios-scripts": "bash scripts/check-ios-scripts.sh",
      "lint-ios-shell": "bash scripts/check-ios-shell.sh",
      "build-ios-core": "swift build --package-path ios/Core",
      "build-ios": "bash scripts/build-ios.sh",
      "test-ios-core": "swift test --package-path ios/Core",
      "test-ios": "bash scripts/test-ios.sh",
      "test": "bash scripts/check-baseline.sh",
      "check-shared": "bash scripts/check-shared.sh"
    };
    for (const [id, cmd] of Object.entries(unchanged)) {
      if (map[id] !== cmd) bad("既有非 Android 门 " + id + " 被改动：期望 " + cmd + "，实际 " + (map[id] || "<缺失>") + "");
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
printf '\nPUREPACE_APPLICATION_ID_ECHO=com.chaxiu.purepace\n' >> "$sandbox/android/gradle.properties"
if negative_out="$(check_android_structure "$sandbox" 2>&1)"; then
  negative_rc=0
else
  negative_rc=$?
fi
if [ "$negative_rc" -eq 0 ]; then
  negative_problems="$negative_problems 注入第二个 applicationId 未 FAIL;"
elif ! printf '%s' "$negative_out" | grep -Fq -- '[FAIL] ac-check-android-application-id'; then
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
elif ! printf '%s' "$negative_out" | grep -Fq -- '[FAIL] ac-check-android-sdk-jdk'; then
  negative_problems="$negative_problems 注入 compileSdk=35 未命中 ac-check-android-sdk-jdk FAIL;"
fi

if [ -z "$negative_problems" ]; then
  pass "ac-check-android-negative-path"
else
  fail "ac-check-android-negative-path" "$negative_problems"
fi

printf '\n%d 项断言，%d 项失败\n' "$CHECKS" "$FAILURES"
if [ "$FAILURES" -ne 0 ]; then
  exit 1
fi
printf 'android scripts OK\n'
