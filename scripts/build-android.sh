#!/usr/bin/env bash
# Android 构建入口：显式校验 JDK 21 与 Android SDK 后，真实执行 gradlew assembleDebug，
# 成功时校验并打印非空 APK 产物。构建失败、缺产物或产物为空一律非零退出，不自造成功行。
set -euo pipefail

usage() {
  cat <<'EOF'
用法: scripts/build-android.sh [--help]

真实构建 Android debug APK：
  - 显式校验 JDK 21（JAVA_HOME 不可用时回退 `/usr/libexec/java_home -v 21` 探测），
    不依赖系统默认 java；
  - 校验 Android SDK 可用（ANDROID_HOME / ANDROID_SDK_ROOT，或已存在的
    android/local.properties 的 sdk.dir），不写 local.properties、不硬编码绝对路径；
  - 经有界重试函数执行 gradle -p android assembleDebug（仅网络/下载类失败最多重试 3 次）；
  - 成功时校验 android/app/build/outputs/apk/debug/*.apk 至少一个且非空，并打印真实
    产物路径（路径按字典序稳定输出，可重复执行）。

选项:
  -h, --help   显示本帮助并退出 0

退出码:
  0  assembleDebug 成功且校验到非空 APK
  1  环境缺失、构建失败、产物缺失或产物为空
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
    echo "build-android: 未知参数 '$1'（使用 --help 查看用法）" >&2
    exit 2
    ;;
esac

if [ "$#" -gt 1 ]; then
  echo "build-android: 只接受一个参数（使用 --help 查看用法）" >&2
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
  echo "error: 缺少 android/gradlew，无法执行 assembleDebug" >&2
  exit 1
fi

ensure_jdk21
ensure_android_sdk

echo "info: gradle assembleDebug（有界重试：网络类失败最多重试 3 次）"
build_status=0
gradle_with_retry assembleDebug || build_status=$?
if [ "$build_status" -ne 0 ]; then
  echo "build-android: assembleDebug 失败（退出码 ${build_status}）" >&2
  exit "$build_status"
fi

apk_dir="android/app/build/outputs/apk/debug"
shopt -s nullglob
apks=("$apk_dir"/*.apk)
shopt -u nullglob
if [ "${#apks[@]}" -eq 0 ]; then
  echo "build-android: assembleDebug 报告成功但 $apk_dir 下没有 *.apk 产物" >&2
  exit 1
fi

sorted_apks="$(printf '%s\n' "${apks[@]}" | LC_ALL=C sort)"
while IFS= read -r apk; do
  [ -n "$apk" ] || continue
  if [ ! -s "$apk" ]; then
    echo "error: APK 产物为空: $apk" >&2
    exit 1
  fi
  echo "info: APK 产物 $apk ($(wc -c < "$apk" | tr -d ' ') bytes)"
done <<< "$sorted_apks"
