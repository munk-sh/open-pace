#!/usr/bin/env bash
# Android 测试入口：显式校验 JDK 21 后真实执行 gradlew testDebugUnitTest（零模拟器），
# 运行前清理上一次结果目录保证只以本次产物为准，并按测试类区分「纯 JVM 单测」与
# 「Robolectric / Compose UI 测试」分别计数；两类各 ≥1 且无 failures/errors 才算通过。
set -euo pipefail

usage() {
  cat <<'EOF'
用法: scripts/test-android.sh [--help]

真实执行 Android JVM 单测套件（testDebugUnitTest，不需要模拟器/真机）：
  - 显式校验 JDK 21（JAVA_HOME 不可用时回退 `/usr/libexec/java_home -v 21` 探测），
    不依赖系统默认 java；
  - 校验 Android SDK 可用（ANDROID_HOME / ANDROID_SDK_ROOT，或已存在的
    android/local.properties 的 sdk.dir），不写 local.properties；
  - 运行前清理 android/app/build/test-results/testDebugUnitTest，旧结果不参与判定；
  - 经有界重试函数执行 gradle -p android testDebugUnitTest（仅网络/下载类失败最多重试 3 次）；
  - 解析本次 JUnit XML，输出累计 tests / failures / errors 与两类用例数：
      * 纯 JVM 单测（不含 Robolectric / Compose 规则的测试类）
      * Robolectric / Compose UI 测试（RobolectricTestRunner / createComposeRule /
        createAndroidComposeRule）
    两类各 ≥1、failures 与 errors 均为 0 才算通过。

选项:
  -h, --help   显示本帮助并退出 0

退出码:
  0  测试通过且两类用例各 ≥1、无失败
  1  环境缺失、测试失败、存在 failures/errors、某类用例为 0 或结果不可读
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
    echo "test-android: 未知参数 '$1'（使用 --help 查看用法）" >&2
    exit 2
    ;;
esac

if [ "$#" -gt 1 ]; then
  echo "test-android: 只接受一个参数（使用 --help 查看用法）" >&2
  exit 2
fi

# 以脚本自身位置推导仓库根，保证在任意 cwd 下运行结果一致。
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
cd "$repo_root"

ensure_jdk21() {
  local detected java_bin raw major
  if [ -z "${JAVA_HOME:-}" ] || [ ! -x "${JAVA_HOME}/bin/java" ]; then
    unset JAVA_HOME
    if [ -x /usr/libexec/java_home ]; then
      detected="$(/usr/libexec/java_home -v 21 2>/dev/null || true)"
      if [ -n "$detected" ] && [ -x "$detected/bin/java" ]; then
        export JAVA_HOME="$detected"
        echo "info: JAVA_HOME 未设置或不可用，回退 /usr/libexec/java_home -v 21 → $JAVA_HOME"
      fi
    fi
  fi

  if [ -n "${JAVA_HOME:-}" ] && [ -x "${JAVA_HOME}/bin/java" ]; then
    java_bin="${JAVA_HOME}/bin/java"
  else
    java_bin="$(command -v java 2>/dev/null || true)"
  fi
  if [ -z "$java_bin" ] || [ ! -x "$java_bin" ]; then
    echo "error: 找不到可用的 java，请安装 JDK 21 并设置 JAVA_HOME" >&2
    return 1
  fi

  raw="$("$java_bin" -version 2>&1 | sed -n '1p')"
  major="$(printf '%s' "$raw" | sed -n 's/.*version "\([0-9][0-9]*\).*/\1/p')"
  if [ "$major" != "21" ]; then
    echo "error: 需要 JDK 21，当前为 '$raw'（JAVA_HOME=${JAVA_HOME:-<unset>}）；请把 JAVA_HOME 指向 JDK 21" >&2
    return 1
  fi
  echo "info: JDK 21 ($raw)"
}

ensure_android_sdk() {
  if [ -n "${ANDROID_HOME:-}" ] && [ -d "$ANDROID_HOME" ]; then
    echo "info: ANDROID_HOME=$ANDROID_HOME"
    return 0
  fi
  if [ -n "${ANDROID_SDK_ROOT:-}" ] && [ -d "$ANDROID_SDK_ROOT" ]; then
    export ANDROID_HOME="$ANDROID_SDK_ROOT"
    echo "info: ANDROID_HOME=${ANDROID_HOME}（来自 ANDROID_SDK_ROOT）"
    return 0
  fi
  if [ -f android/local.properties ] && grep -q '^sdk\.dir=' android/local.properties 2>/dev/null; then
    echo "info: 使用 android/local.properties 的 sdk.dir"
    return 0
  fi
  echo "error: 未找到 Android SDK，请设置 ANDROID_HOME（或 ANDROID_SDK_ROOT），或在 android/local.properties 写 sdk.dir（不入库）" >&2
  return 1
}

# gradlew 调用统一入口：仅对网络/下载类失败做有界重试（1 + 最多 3 次尝试），
# 非网络失败立即返回；输出经 tee 实时打印，最终失败原样透传 gradle 退出码。
gradle_with_retry() {
  local task="$1"
  local attempt=1
  local max_attempts=4
  local log_file status=0
  log_file="$(mktemp "${TMPDIR:-/tmp}/purepace-gradle-retry.XXXXXX")"
  while :; do
    echo "info: gradle ${task} 第 ${attempt}/${max_attempts} 次尝试" >&2
    status=0
    bash android/gradlew -p android "$task" 2>&1 | tee "$log_file" || status=${PIPESTATUS[0]}
    if [ "$status" -eq 0 ]; then
      rm -f "$log_file"
      return 0
    fi
    if ! grep -Eqi 'Could not download|Could not resolve|Read timed out|Connect timed out|Connection refused|UnknownHostException|SSLException|HTTP 5[0-9][0-9]|network is unreachable' "$log_file"; then
      echo "warn: gradle ${task} 非网络类失败，不重试（退出码 ${status}）" >&2
      rm -f "$log_file"
      return "$status"
    fi
    if [ "$attempt" -ge "$max_attempts" ]; then
      echo "warn: gradle ${task} 网络类失败已达 ${max_attempts} 次尝试上限，放弃重试（退出码 ${status}）" >&2
      rm -f "$log_file"
      return "$status"
    fi
    echo "warn: gradle ${task} 第 ${attempt} 次尝试命中网络类失败，1 秒后重试" >&2
    sleep 1
    attempt=$((attempt + 1))
  done
}

if [ ! -f android/gradlew ]; then
  echo "error: 缺少 android/gradlew，无法执行 testDebugUnitTest" >&2
  exit 1
fi

ensure_jdk21
ensure_android_sdk

results_dir="android/app/build/test-results/testDebugUnitTest"
# 只以本次运行结果为准：旧 result XML（含预置的伪造结果）在运行前整体移除。
rm -rf "$results_dir"

echo "info: gradle testDebugUnitTest（有界重试：网络类失败最多重试 3 次）"
gradle_status=0
gradle_with_retry testDebugUnitTest || gradle_status=$?

if [ "$gradle_status" -ne 0 ]; then
  echo "error: testDebugUnitTest 失败（退出码 ${gradle_status}）" >&2
fi

if [ ! -d "$results_dir" ]; then
  echo "error: testDebugUnitTest 未产出结果目录 ${results_dir}（gradle 退出码 ${gradle_status}）" >&2
  exit 1
fi

xml_files=()
for f in "$results_dir"/*.xml; do
  [ -f "$f" ] || continue
  xml_files+=("$f")
done
if [ "${#xml_files[@]}" -eq 0 ]; then
  echo "error: ${results_dir} 下没有本次运行的 *.xml 结果（gradle 退出码 ${gradle_status}）" >&2
  exit 1
fi

# 从测试源码区分两类测试类：含 Robolectric / Compose 规则标记的类为
# Robolectric/Compose UI 测试，其余为纯 JVM 单测。
test_classes=""
while IFS= read -r kt; do
  [ -f "$kt" ] || continue
  pkg="$(sed -n 's/^package[[:space:]][[:space:]]*\([^[:space:];]*\).*/\1/p' "$kt" | sed -n '1p')"
  kind="jvm"
  if grep -Eq 'RobolectricTestRunner|createComposeRule|createAndroidComposeRule' "$kt"; then
    kind="robolectric"
  fi
  declared="$(sed -n 's/^class[[:space:]][[:space:]]*\([A-Za-z0-9_]*\).*/\1/p' "$kt")"
  if [ -z "$declared" ]; then
    declared="$(basename "$kt" .kt)"
  fi
  while IFS= read -r cls; do
    [ -n "$cls" ] || continue
    if [ -n "$pkg" ]; then
      fqcn="$pkg.$cls"
    else
      fqcn="$cls"
    fi
    test_classes="$test_classes$fqcn|$kind"$'\n'
  done <<< "$declared"
done < <(find android/app/src/test -type f -name '*.kt' -print 2>/dev/null || true)

suite_attr() {
  local line="$1" name="$2"
  printf '%s' "$line" | sed -n "s/.*[[:space:]]${name}=\"\([0-9][0-9]*\)\".*/\1/p"
}

suite_class() {
  local line="$1"
  printf '%s' "$line" | sed -n 's/.*[[:space:]]name="\([^"]*\)".*/\1/p'
}

class_kind() {
  local cls="$1"
  printf '%s' "$test_classes" | awk -F'|' -v c="$cls" '$1 == c { print $2; exit }'
}

total_tests=0
total_failures=0
total_errors=0
total_skipped=0
jvm_tests=0
robo_tests=0
unknown=""

for f in "${xml_files[@]}"; do
  suite_line="$(grep -m1 -o '<testsuite [^>]*>' "$f" 2>/dev/null || true)"
  if [ -z "$suite_line" ]; then
    unknown="$unknown $(basename "$f")(无 testsuite 标签);"
    continue
  fi
  suite_tests="$(suite_attr "$suite_line" tests)"
  suite_failures="$(suite_attr "$suite_line" failures)"
  suite_errors="$(suite_attr "$suite_line" errors)"
  suite_skipped="$(suite_attr "$suite_line" skipped)"
  : "${suite_tests:=0}" "${suite_failures:=0}" "${suite_errors:=0}" "${suite_skipped:=0}"

  total_tests=$((total_tests + suite_tests))
  total_failures=$((total_failures + suite_failures))
  total_errors=$((total_errors + suite_errors))
  total_skipped=$((total_skipped + suite_skipped))

  cls="$(suite_class "$suite_line")"
  kind="$(class_kind "$cls")"
  case "$kind" in
    jvm)
      jvm_tests=$((jvm_tests + suite_tests))
      ;;
    robolectric)
      robo_tests=$((robo_tests + suite_tests))
      ;;
    *)
      unknown="$unknown ${cls:-$(basename "$f")};"
      ;;
  esac
done

echo "info: 纯 JVM 单测: $jvm_tests 例"
echo "info: Robolectric/Compose UI 测试: $robo_tests 例"
echo "info: 累计 tests=$total_tests failures=$total_failures errors=$total_errors skipped=$total_skipped"

status=0
if [ "$gradle_status" -ne 0 ]; then
  echo "error: testDebugUnitTest 失败（退出码 ${gradle_status}）" >&2
  status=1
fi
if [ "$total_failures" -ne 0 ] || [ "$total_errors" -ne 0 ]; then
  echo "error: 存在失败用例（failures=$total_failures errors=${total_errors}）" >&2
  status=1
fi
if [ -n "$unknown" ]; then
  echo "error: 结果中有无法归类到 test 源码的测试类:$unknown" >&2
  status=1
fi
if [ "$jvm_tests" -lt 1 ]; then
  echo "error: 纯 JVM 单测为 0 例（要求 ≥1）" >&2
  status=1
fi
if [ "$robo_tests" -lt 1 ]; then
  echo "error: Robolectric/Compose UI 测试为 0 例（要求 ≥1）" >&2
  status=1
fi
if [ "$total_tests" -lt 2 ]; then
  echo "error: 累计用例数 $total_tests < 2" >&2
  status=1
fi

if [ "$status" -ne 0 ]; then
  exit 1
fi
echo "info: Android 测试通过（JVM $jvm_tests 例 + Robolectric/Compose $robo_tests 例）"
