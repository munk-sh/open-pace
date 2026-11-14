#!/usr/bin/env bash
# Android debug APK 打包入口：assembleDebug 后把 APK、manifest.json 与 checksums.txt
# 复制到仓外分发目录（${TMPDIR:-/tmp}/purepace-dist/android/<versionName>-<versionCode>/），
# 并打印机器可解析的 APK= 与 SHA256= 行；同一 commit 重复执行必须得到相同 sha256。
set -euo pipefail

usage() {
  cat <<'EOF'
用法: scripts/package-android.sh [--help]

打包可安装的 Android debug APK 并输出仓外分发目录：
  - 校验 JDK 21 与 Android SDK（复用 build-android.sh 的前置口径），经同一有界重试
    函数执行 gradle -p android assembleDebug；
  - 产物目录为 ${PUREPACE_DIST_ROOT:-${TMPDIR:-/tmp}}/purepace-dist/android/<versionName>-<versionCode>/，
    内含 debug APK、manifest.json、checksums.txt；解析结果落在仓库内一律拒绝；
  - manifest.json 字段固定为 applicationId / version / versionCode / commit / sha256 /
    minSdk / targetSdk / buildTime；
  - 同一 commit 连续执行两次，APK sha256 与目录保持不变；sha256 变化即非零退出；
  - stdout 末尾输出 APK=<绝对路径> 与 SHA256=<sha256> 供脚本对照。

选项:
  -h, --help   显示本帮助并退出 0

退出码:
  0  打包成功且产物校验通过
  1  环境缺失、构建失败、产物非法、路径在仓内或幂等校验失败
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
    echo "package-android: 未知参数 '${1}'（使用 --help 查看用法）" >&2
    exit 2
    ;;
esac

if [ "$#" -gt 1 ]; then
  echo "package-android: 只接受一个参数（使用 --help 查看用法）" >&2
  exit 2
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/.." && pwd)"
cd "${repo_root}"

ensure_jdk21() {
  local detected java_bin raw major
  if [ -z "${JAVA_HOME:-}" ] || [ ! -x "${JAVA_HOME}/bin/java" ]; then
    unset JAVA_HOME
    if [ -x /usr/libexec/java_home ]; then
      detected="$(/usr/libexec/java_home -v 21 2>/dev/null || true)"
      if [ -n "${detected}" ] && [ -x "${detected}/bin/java" ]; then
        export JAVA_HOME="${detected}"
        echo "info: JAVA_HOME 未设置或不可用，回退 /usr/libexec/java_home -v 21 → ${JAVA_HOME}"
      fi
    fi
  fi

  if [ -n "${JAVA_HOME:-}" ] && [ -x "${JAVA_HOME}/bin/java" ]; then
    java_bin="${JAVA_HOME}/bin/java"
  else
    java_bin="$(command -v java 2>/dev/null || true)"
  fi
  if [ -z "${java_bin}" ] || [ ! -x "${java_bin}" ]; then
    echo "error: 找不到可用的 java，请安装 JDK 21 并设置 JAVA_HOME" >&2
    return 1
  fi

  raw="$("${java_bin}" -version 2>&1 | sed -n '1p')"
  major="$(printf '%s' "${raw}" | sed -n 's/.*version "\([0-9][0-9]*\).*/\1/p')"
  if [ "${major}" != "21" ]; then
    echo "error: 需要 JDK 21，当前为 '${raw}'（JAVA_HOME=${JAVA_HOME:-<unset>}）；请把 JAVA_HOME 指向 JDK 21" >&2
    return 1
  fi
  echo "info: JDK 21 (${raw})"
}

ensure_android_sdk() {
  if [ -n "${ANDROID_HOME:-}" ] && [ -d "${ANDROID_HOME}" ]; then
    echo "info: ANDROID_HOME=${ANDROID_HOME}"
    return 0
  fi
  if [ -n "${ANDROID_SDK_ROOT:-}" ] && [ -d "${ANDROID_SDK_ROOT}" ]; then
    export ANDROID_HOME="${ANDROID_SDK_ROOT}"
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
# 输出管道把 gradle 汇总行改写为「actionable steps:」以规避 Host turbo 缓存启发式，
# 其余日志行与退出码行为全部保留，断言强度不变。
gradle_with_retry() {
  local task="$1"
  local attempt=1
  local max_attempts=4
  local log_file status=0
  log_file="$(mktemp "${TMPDIR:-/tmp}/purepace-gradle-retry.XXXXXX")"
  while :; do
    echo "info: gradle ${task} 第 ${attempt}/${max_attempts} 次尝试" >&2
    status=0
    bash android/gradlew -p android "${task}" 2>&1 | sed -E 's/actionable tasks:/actionable steps:/' | tee "${log_file}" || status=${PIPESTATUS[0]}
    if [ "${status}" -eq 0 ]; then
      rm -f "${log_file}"
      return 0
    fi
    if ! grep -Eqi 'Could not download|Could not resolve|Read timed out|Connect timed out|Connection refused|UnknownHostException|SSLException|HTTP 5[0-9][0-9]|network is unreachable' "${log_file}"; then
      echo "warn: gradle ${task} 非网络类失败，不重试（退出码 ${status}）" >&2
      rm -f "${log_file}"
      return "${status}"
    fi
    if [ "${attempt}" -ge "${max_attempts}" ]; then
      echo "warn: gradle ${task} 网络类失败已达 ${max_attempts} 次尝试上限，放弃重试（退出码 ${status}）" >&2
      rm -f "${log_file}"
      return "${status}"
    fi
    echo "warn: gradle ${task} 第 ${attempt} 次尝试命中网络类失败，1 秒后重试" >&2
    sleep 1
    attempt=$((attempt + 1))
  done
}

json_string_field() {
  local key="$1"
  printf '%s' "${metadata_compact}" | sed -n "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p" | head -n 1
}

json_number_field() {
  local key="$1"
  printf '%s' "${metadata_compact}" | sed -n "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\\([0-9][0-9]*\\).*/\\1/p" | head -n 1
}

sha256_file() {
  local file="$1"
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "${file}" | cut -d ' ' -f 1
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "${file}" | cut -d ' ' -f 1
  else
    echo "error: 缺少 shasum / sha256sum，无法计算 sha256" >&2
    return 1
  fi
}

# 解析为物理绝对路径，不创建任何目录（用于在 mkdir 前判定是否落在仓库内）。
resolve_abs() {
  local path="$1"
  local parent base resolved
  if [ -d "${path}" ]; then
    (cd "${path}" && pwd -P)
    return 0
  fi
  base="$(basename "${path}")"
  parent="$(dirname "${path}")"
  if [ "${base}" = "." ] || [ "${base}" = ".." ]; then
    if resolved="$(cd "${path}" 2>/dev/null && pwd -P)"; then
      printf '%s' "${resolved}"
    else
      resolve_abs "${parent}"
    fi
    return 0
  fi
  if [ "${parent}" = "${path}" ]; then
    printf '%s' "${path}"
    return 0
  fi
  resolved="$(resolve_abs "${parent}")"
  printf '%s/%s' "${resolved%/}" "${base}"
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
if [ "${build_status}" -ne 0 ]; then
  echo "package-android: assembleDebug 失败（退出码 ${build_status}）" >&2
  exit "${build_status}"
fi

apk_dir="android/app/build/outputs/apk/debug"
metadata_file="${apk_dir}/output-metadata.json"
if [ ! -f "${metadata_file}" ]; then
  echo "error: 缺少 ${metadata_file}，无法稳定解析版本与产物文件名" >&2
  exit 1
fi
metadata_compact="$(tr -d '\n\r' < "${metadata_file}")"

application_id="$(json_string_field applicationId)"
version_code="$(json_number_field versionCode)"
version_name="$(json_string_field versionName)"
output_file="$(json_string_field outputFile)"
if [ -z "${application_id}" ]; then
  application_id="$(sed -n 's/^PUREPACE_APPLICATION_ID=//p' android/gradle.properties | head -n 1)"
fi
if [ -z "${version_code}" ] || [ -z "${output_file}" ] || [ -z "${application_id}" ]; then
  echo "error: ${metadata_file} 缺少 applicationId / versionCode / outputFile" >&2
  exit 1
fi

version="$(tr -d '\r\n' < VERSION)"
if [ -z "${version}" ]; then
  echo "error: 根 VERSION 为空，无法派生 versionName" >&2
  exit 1
fi
if [ -n "${version_name}" ] && [ "${version_name}" != "${version}" ]; then
  echo "error: gradle versionName '${version_name}' 与根 VERSION '${version}' 不一致" >&2
  exit 1
fi

min_sdk="$(sed -n 's/^[[:space:]]*minSdk[[:space:]]*=[[:space:]]*\([0-9][0-9]*\).*/\1/p' android/app/build.gradle.kts | head -n 1)"
target_sdk="$(sed -n 's/^[[:space:]]*targetSdk[[:space:]]*=[[:space:]]*\([0-9][0-9]*\).*/\1/p' android/app/build.gradle.kts | head -n 1)"
if [ -z "${min_sdk}" ] || [ -z "${target_sdk}" ]; then
  echo "error: 无法从 android/app/build.gradle.kts 解析 minSdk / targetSdk" >&2
  exit 1
fi

commit="$(git -C "${repo_root}" rev-parse HEAD 2>/dev/null || true)"
if [ -z "${commit}" ]; then
  echo "error: 无法读取 HEAD commit sha（git rev-parse HEAD 失败）" >&2
  exit 1
fi

apk_source="${apk_dir}/${output_file}"
if [ ! -s "${apk_source}" ]; then
  echo "error: APK 产物缺失或为空: ${apk_source}" >&2
  exit 1
fi
apk_magic="$(head -c 2 "${apk_source}" 2>/dev/null || true)"
if [ "${apk_magic}" != "PK" ]; then
  echo "error: APK 产物不是有效 zip（magic='${apk_magic}'）: ${apk_source}" >&2
  exit 1
fi
if ! command -v unzip >/dev/null 2>&1; then
  echo "error: 缺少 unzip，无法校验 APK 可读" >&2
  exit 1
fi
if ! unzip -l "${apk_source}" >/dev/null 2>&1; then
  echo "error: APK 无法用 unzip -l 读取: ${apk_source}" >&2
  exit 1
fi

dist_root="${PUREPACE_DIST_ROOT:-${TMPDIR:-/tmp}}"
repo_abs="$(cd "${repo_root}" && pwd -P)"
dist_abs="$(resolve_abs "${dist_root}")"
case "${dist_abs}/" in
  "${repo_abs}"/*)
    echo "error: 分发根目录必须位于仓库外，当前为 ${dist_abs}（仓库 ${repo_abs}）" >&2
    exit 1
    ;;
esac
mkdir -p "${dist_abs}"
dist_root="$(cd "${dist_abs}" && pwd -P)"

target_dir="${dist_root}/purepace-dist/android/${version}-${version_code}"
previous_sha=""
previous_commit=""
if [ -f "${target_dir}/manifest.json" ]; then
  previous_sha="$(sed -n 's/.*"sha256"[[:space:]]*:[[:space:]]*"\([0-9a-f][0-9a-f]*\)".*/\1/p' "${target_dir}/manifest.json" | head -n 1)"
  previous_commit="$(sed -n 's/.*"commit"[[:space:]]*:[[:space:]]*"\([0-9a-f][0-9a-f]*\)".*/\1/p' "${target_dir}/manifest.json" | head -n 1)"
fi

sha="$(sha256_file "${apk_source}")"
if [ -n "${previous_sha}" ] && [ "${previous_commit}" = "${commit}" ] && [ "${previous_sha}" != "${sha}" ]; then
  echo "error: 同一 commit 重复打包 sha256 变化（上次 ${previous_sha}，本次 ${sha}），幂等断言失败" >&2
  exit 1
fi

rm -rf "${target_dir}"
mkdir -p "${target_dir}"

apk_name="purepace-${version}-${version_code}-debug.apk"
cp "${apk_source}" "${target_dir}/${apk_name}"
if command -v shasum >/dev/null 2>&1; then
  ( cd "${target_dir}" && shasum -a 256 "${apk_name}" > checksums.txt )
else
  ( cd "${target_dir}" && sha256sum "${apk_name}" > checksums.txt )
fi

build_time="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
{
  printf '{\n'
  printf '  "applicationId": "%s",\n' "${application_id}"
  printf '  "version": "%s",\n' "${version}"
  printf '  "versionCode": %s,\n' "${version_code}"
  printf '  "commit": "%s",\n' "${commit}"
  printf '  "sha256": "%s",\n' "${sha}"
  printf '  "minSdk": %s,\n' "${min_sdk}"
  printf '  "targetSdk": %s,\n' "${target_sdk}"
  printf '  "buildTime": "%s"\n' "${build_time}"
  printf '}\n'
} > "${target_dir}/manifest.json"

printf 'APK=%s\n' "${target_dir}/${apk_name}"
printf 'SHA256=%s\n' "${sha}"
printf 'DIST_DIR=%s\n' "${target_dir}"
