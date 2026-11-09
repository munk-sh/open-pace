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
    grep -Fq -- "gradle_with_retry $task" "$file" || out="$out 未经 gradle_with_retry 调用 $task;"
  fi

  printf '%s' "$out"
}

problems=""
for name in build-android.sh test-android.sh; do
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
      "test-ios": "bash scripts/test-ios.sh --unit-only",
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
  task="$arg"
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
  printf '%s\n' '<testsuite name="com.chaxiu.purepace.FakeJvmTest" tests="1" failures="0" errors="0" skipped="0"></testsuite>' > android/app/build/test-results/testDebugUnitTest/TEST-com.chaxiu.purepace.FakeJvmTest.xml
  printf '%s\n' '<testsuite name="com.chaxiu.purepace.FakeRobolectricTest" tests="1" failures="0" errors="0" skipped="0"></testsuite>' > android/app/build/test-results/testDebugUnitTest/TEST-com.chaxiu.purepace.FakeRobolectricTest.xml
fi
exit 0
STUBGRADLE

mkdir -p "$retry_root/android/app/src/test/java/com/chaxiu/purepace"
printf '%s\n' 'package com.chaxiu.purepace' 'class FakeJvmTest' \
  > "$retry_root/android/app/src/test/java/com/chaxiu/purepace/FakeJvmTest.kt"
printf '%s\n' 'package com.chaxiu.purepace' '// RobolectricTestRunner' 'class FakeRobolectricTest' \
  > "$retry_root/android/app/src/test/java/com/chaxiu/purepace/FakeRobolectricTest.kt"

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

printf '\n%d 项断言，%d 项失败\n' "$CHECKS" "$FAILURES"
if [ "$FAILURES" -ne 0 ]; then
  exit 1
fi
printf 'android scripts OK\n'
