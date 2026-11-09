#!/usr/bin/env bash
# 版本号读取的唯一入口：读取仓库根 VERSION 文件并输出。
# 任何 README、构建脚本、工程配置需要版本号时，都必须经由本脚本，不得写死。
set -euo pipefail

usage() {
  cat <<'EOF'
用法: scripts/version.sh [--tools] [--help]

无参数：读取仓库根 VERSION 文件并输出其内容（x.y.z，无 v 前缀）。
这是仓库内获取版本号的唯一入口；脚本不接受版本号参数，也不缓存结果。

--tools：在无参契约之外，追加输出根 VERSION 与 Xcode / Swift / JDK / Gradle 版本摘要。
工具缺失时该行显式标注「未就绪」，不报错、不伪造版本。

选项:
  -h, --help   显示本帮助并退出 0

退出码:
  0  输出成功
  1  VERSION 缺失、为空或格式非法
  2  参数非法
EOF
}

mode="bare"
case "${1:-}" in
  -h|--help)
    usage
    exit 0
    ;;
  "")
    ;;
  --tools)
    mode="tools"
    ;;
  *)
    echo "version: 未知参数 '$1'（使用 --help 查看用法）" >&2
    exit 2
    ;;
esac

if [ "$#" -gt 1 ]; then
  echo "version: 只接受一个参数（使用 --help 查看用法）" >&2
  exit 2
fi

# 以脚本自身位置推导仓库根，保证在任意 cwd 下运行结果一致。
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
version_file="$repo_root/VERSION"

if [ ! -f "$version_file" ]; then
  echo "version: 缺少 $version_file" >&2
  exit 1
fi

version="$(tr -d '\r\n' < "$version_file")"

if [ -z "$version" ]; then
  echo "version: $version_file 为空" >&2
  exit 1
fi

if ! grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' <<< "$version"; then
  echo "version: $version_file 内容不是 x.y.z 格式: $version" >&2
  exit 1
fi

if [ "$mode" = "bare" ]; then
  printf '%s\n' "$version"
  exit 0
fi

# --tools：只输出真实可取得的工具版本；缺失时显式「未就绪」，不伪造版本。
xcode_line="$(xcodebuild -version 2>/dev/null | sed -n 's/^Xcode \([0-9][0-9.]*\).*/\1/p' | head -n 1 || true)"
if [ -z "$xcode_line" ]; then
  xcode_line="未就绪（xcodebuild 不可用）"
fi

swift_version="$(swift --version 2>/dev/null | sed -n 's/.*Apple Swift version \([0-9][0-9.]*\).*/\1/p' | head -n 1 || true)"
if [ -z "$swift_version" ]; then
  swift_line="未就绪（swift 不可用）"
else
  swift_line="Apple Swift version $swift_version"
fi

jdk_line="$(java -version 2>&1 | sed -n '1s/[[:space:]]*$//p' || true)"
if [ -z "$jdk_line" ]; then
  jdk_line="未就绪（java 不可用）"
fi

# Gradle 版本离线取自 wrapper 配置，绝不启动 JVM 或触网；缺失/无法解析时显式「未就绪」。
gradle_wrapper_properties="$repo_root/android/gradle/wrapper/gradle-wrapper.properties"
gradle_line=""
if [ -f "$gradle_wrapper_properties" ]; then
  gradle_distribution_url="$(sed -n 's/^distributionUrl[[:space:]]*=[[:space:]]*//p' "$gradle_wrapper_properties" | tr -d '\r' | head -n 1)"
  gradle_version="$(printf '%s' "$gradle_distribution_url" | sed -n 's/.*gradle-\([0-9][0-9.]*\)-.*\.zip$/\1/p' | head -n 1)"
  if [ -n "$gradle_version" ]; then
    gradle_line="$gradle_version"
  fi
fi
if [ -z "$gradle_line" ]; then
  gradle_line="未就绪（缺少或无法解析 android/gradle/wrapper/gradle-wrapper.properties）"
fi

printf 'VERSION: %s\n' "$version"
printf 'Xcode: %s\n' "$xcode_line"
printf 'Swift: %s\n' "$swift_line"
printf 'JDK: %s\n' "$jdk_line"
printf 'Gradle: %s\n' "$gradle_line"
