#!/usr/bin/env bash
# iOS 上传入口：先只读 xcrun altool --list-apps，再用 altool --upload-app 上传导出 ipa。
# 凭据只从 ASC_KEY_PATH / ASC_KEY_ID / ASC_ISSUER_ID 读取，脚本从不打印其值；
# DRY_RUN=1 只回显脱敏命令、不触碰网络；永不写 .p8 / .env 或任何凭据文件。
set -euo pipefail

usage() {
  cat <<'EOF'
用法: scripts/upload-ios.sh [--ipa <路径>] [--help]

把 scripts/archive-ios.sh 导出的 ipa 上传到 App Store Connect：
  1. 只读校验：xcrun altool --list-apps（只打印命中 App 记录条数，不打印清单）
  2. 上传：xcrun altool --upload-app -f <ipa> -t ios
  3. 打印 ipa 路径、版本与 build、上传结果

默认 ipa 取自 ${TMPDIR:-/tmp}/purepace-dist/<version>-<build>/export 下唯一的 *.ipa；
版本来自 scripts/version.sh，build 来自 BUILD_NUMBER（缺省 1），目录可用 OUT_DIR 覆盖。

环境变量:
  ASC_KEY_PATH             App Store Connect API 私钥 .p8 绝对路径（必须放在仓库外）
  ASC_KEY_ID               API Key ID
  ASC_ISSUER_ID            API Issuer ID
  BUILD_NUMBER             build 号，缺省 1
  OUT_DIR                  产物目录，缺省 ${TMPDIR:-/tmp}/purepace-dist/<version>-<build>
  DRY_RUN=1                不要求凭据，只回显脱敏命令；不发起任何网络调用，退出 0

凭据只以参数方式传给 altool；缺失时脚本只打印缺失变量名并非零退出。
本脚本不写 .p8 / .env / 凭据文件，不提交审核、不发 TestFlight 邀请。

选项:
  --ipa <路径>   覆盖默认 ipa 解析（文件必须存在）
  -h, --help     显示本帮助并退出 0

退出码:
  0  上传成功，或 DRY_RUN=1 回显成功
  1  凭据缺失、ipa 缺失、命令失败或上传失败
  2  参数非法
EOF
}

ipa_override=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --ipa)
      if [ "$#" -lt 2 ]; then
        echo "upload-ios: --ipa 需要一个路径参数（使用 --help 查看用法）" >&2
        exit 2
      fi
      ipa_override="$2"
      shift 2
      ;;
    --ipa=*)
      ipa_override="${1#--ipa=}"
      shift
      ;;
    *)
      echo "upload-ios: 未知参数 '$1'（使用 --help 查看用法）" >&2
      exit 2
      ;;
  esac
done

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
cd "$repo_root"

dry_run="${DRY_RUN:-0}"
bundle_id="sh.munk.purepace"

# 凭据必填校验只输出变量名，绝不打印变量值；DRY_RUN 下跳过（不展开任何凭据）。
if [ "$dry_run" != "1" ]; then
  missing_credentials=""
  for var in ASC_KEY_PATH ASC_KEY_ID ASC_ISSUER_ID; do
    if [ -z "$(printenv "$var" 2>/dev/null || true)" ]; then
      missing_credentials="$missing_credentials $var"
    fi
  done
  if [ -n "$missing_credentials" ]; then
    for var in $missing_credentials; do
      printf 'upload-ios: 缺少环境变量 %s\n' "$var" >&2
    done
    exit 1
  fi
fi

marketing_version="$(bash scripts/version.sh)"
build_number="${BUILD_NUMBER:-1}"
case "$build_number" in
  ''|*[!0-9]*)
    echo "upload-ios: BUILD_NUMBER 必须是非负整数" >&2
    exit 1
    ;;
esac

out_dir="${OUT_DIR:-${TMPDIR:-/tmp}/purepace-dist/${marketing_version}-${build_number}}"
export_dir="$out_dir/export"

# 默认解析 export 目录下唯一的 *.ipa；显式 --ipa 直接覆盖并校验文件存在。
resolve_ipa() {
  if [ -n "$ipa_override" ]; then
    if [ ! -f "$ipa_override" ]; then
      printf 'upload-ios: --ipa 指向的文件不存在: %s\n' "$ipa_override" >&2
      return 1
    fi
    printf '%s' "$ipa_override"
    return 0
  fi
  if [ ! -d "$export_dir" ]; then
    printf 'upload-ios: 未找到导出目录 %s；可先运行 scripts/archive-ios.sh，或用 --ipa <路径> 指定 ipa\n' "$export_dir" >&2
    return 1
  fi
  local candidates=() found
  while IFS= read -r found; do
    [ -n "$found" ] && candidates+=("$found")
  done < <(find "$export_dir" -maxdepth 1 -type f -name '*.ipa' | LC_ALL=C sort)
  if [ "${#candidates[@]}" -eq 0 ]; then
    printf 'upload-ios: %s 下未找到 *.ipa；可先运行 scripts/archive-ios.sh，或用 --ipa <路径> 指定 ipa\n' "$export_dir" >&2
    return 1
  fi
  if [ "${#candidates[@]}" -gt 1 ]; then
    printf 'upload-ios: %s 下存在多个 *.ipa（%d 个）；请用 --ipa <路径> 明确指定\n' "$export_dir" "${#candidates[@]}" >&2
    return 1
  fi
  printf '%s' "${candidates[0]}"
}

count_matching_apps() {
  local output="$1" count
  count="$(printf '%s\n' "$output" | grep -c -F -- "$bundle_id" || true)"
  printf '%s' "${count:-0}"
}

if [ "$dry_run" = "1" ]; then
  if [ -n "$ipa_override" ]; then
    dry_ipa="$ipa_override"
  else
    dry_ipa="$(resolve_ipa 2>/dev/null || printf '%s' '<ipa 未找到，可用 --ipa 指定>')"
  fi
  printf 'info: ipa=%s\n' "$dry_ipa"
  printf 'info: version=%s build=%s\n' "$marketing_version" "$build_number"
  cat <<'DRYRUN'
info: [DRY_RUN] xcrun altool --list-apps --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID" --apiPrivateKey "$ASC_KEY_PATH"
info: [DRY_RUN] xcrun altool --upload-app -f "$IPA_PATH" -t ios --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID" --apiPrivateKey "$ASC_KEY_PATH"
info: [DRY_RUN] 以上命令未执行（无网络访问）
DRYRUN
  exit 0
fi

ipa_path="$(resolve_ipa)" || exit 1
[ -f "$ipa_path" ] || {
  printf 'upload-ios: ipa 不存在: %s\n' "$ipa_path" >&2
  exit 1
}

printf 'info: 只读校验 xcrun altool --list-apps（bundle id %s）\n' "$bundle_id"
list_output=""
if list_output="$(xcrun altool --list-apps \
  --apiKey "$ASC_KEY_ID" \
  --apiIssuer "$ASC_ISSUER_ID" \
  --apiPrivateKey "$ASC_KEY_PATH" 2>&1)"; then
  :
else
  list_rc=$?
  printf 'upload-ios: altool --list-apps 失败（退出 %s），未执行上传\n' "$list_rc" >&2
  exit 1
fi
printf 'info: --list-apps 命中 App 记录 %s 条\n' "$(count_matching_apps "$list_output")"

printf 'info: 上传 %s 到 App Store Connect\n' "$ipa_path"
if xcrun altool --upload-app \
  -f "$ipa_path" \
  -t ios \
  --apiKey "$ASC_KEY_ID" \
  --apiIssuer "$ASC_ISSUER_ID" \
  --apiPrivateKey "$ASC_KEY_PATH"; then
  upload_result="成功"
else
  upload_rc=$?
  printf 'upload-ios: altool --upload-app 失败（退出 %s）\n' "$upload_rc" >&2
  exit 1
fi

printf 'ipa: %s\n' "$ipa_path"
printf 'version: %s\n' "$marketing_version"
printf 'build: %s\n' "$build_number"
printf '上传结果: %s\n' "$upload_result"
