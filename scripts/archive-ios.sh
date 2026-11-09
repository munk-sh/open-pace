#!/usr/bin/env bash
# iOS 分发归档入口：xcodegen 生成工程 → xcodebuild archive → xcodebuild -exportArchive。
# 凭据只从环境变量读取，脚本从不打印其值；DRY_RUN=1 只回显脱敏命令且不触网。
# 产物一律落在仓外（默认 ${TMPDIR:-/tmp}/purepace-dist/<version>-<build>），并输出 sha256。
set -euo pipefail

usage() {
  cat <<'EOF'
用法: scripts/archive-ios.sh [--help]

生成可上传 App Store Connect 的归档与导出产物，全程不执行上传：
  1. 在 ios/ 内执行 xcodegen generate --spec project.yml（project.yml 是唯一真源）
  2. xcodebuild archive -destination 'generic/platform=iOS'，MARKETING_VERSION 来自
     scripts/version.sh，CURRENT_PROJECT_VERSION 来自 BUILD_NUMBER（缺省 1），均以命令行覆盖
  3. xcodebuild -exportArchive，ExportOptions 写入仓外 OUT_DIR
  4. 复制 .app / .app.dSYM、打 zip、计算 sha256 并写入 checksums.txt

环境变量:
  ASC_KEY_PATH             App Store Connect API 私钥 .p8 绝对路径（必须放在仓库外）
  ASC_KEY_ID               API Key ID
  ASC_ISSUER_ID            API Issuer ID
  BUILD_NUMBER             CURRENT_PROJECT_VERSION，缺省 1
  OUT_DIR                  产物目录，缺省 ${TMPDIR:-/tmp}/purepace-dist/<version>-<build>
  DRY_RUN=1                不要求凭据，只生成 ExportOptions.plist 并回显脱敏命令；
                           不执行 xcodegen / xcodebuild、不发起网络调用，退出 0

凭据只以变量方式传入 xcodebuild；缺失时脚本只打印缺失变量名并非零退出。
本脚本不执行上传、不创建 App Store Connect 记录、不写 .env。

选项:
  -h, --help   显示本帮助并退出 0

退出码:
  0  归档/导出完成，或 DRY_RUN=1 回显成功
  1  凭据缺失、命令失败或产物缺失
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
    echo "archive-ios: 未知参数 '$1'（使用 --help 查看用法）" >&2
    exit 2
    ;;
esac

if [ "$#" -gt 1 ]; then
  echo "archive-ios: 只接受一个参数（使用 --help 查看用法）" >&2
  exit 2
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
cd "$repo_root"

ios_dir="ios"
project_path="$ios_dir/PurePace.xcodeproj"
spec_path="$ios_dir/project.yml"
scheme="PurePace"
team_id="3X4J53U6RY"
dry_run="${DRY_RUN:-0}"

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
      printf 'archive-ios: 缺少环境变量 %s\n' "$var" >&2
    done
    exit 1
  fi
fi

marketing_version="$(bash scripts/version.sh)"
build_number="${BUILD_NUMBER:-1}"
case "$build_number" in
  ''|*[!0-9]*)
    echo "archive-ios: BUILD_NUMBER 必须是非负整数" >&2
    exit 1
    ;;
esac

out_dir="${OUT_DIR:-${TMPDIR:-/tmp}/purepace-dist/${marketing_version}-${build_number}}"
archive_path="$out_dir/PurePace.xcarchive"
export_path="$out_dir/export"
export_options="$out_dir/ExportOptions.plist"

mkdir -p "$out_dir"

# ExportOptions 为非敏感配置，DRY_RUN 也真实生成，便于静态门断言内容。
cat > "$export_options" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>app-store-connect</string>
  <key>teamID</key>
  <string>${team_id}</string>
  <key>signingStyle</key>
  <string>automatic</string>
  <key>uploadSymbols</key>
  <false/>
</dict>
</plist>
EOF

if [ "$dry_run" = "1" ]; then
  printf 'info: OUT_DIR=%s\n' "$out_dir"
  printf 'info: 已生成 %s\n' "$export_options"
  cat <<'DRYRUN'
info: xcodegen generate --spec project.yml（cwd=ios/）
info: xcodebuild archive -project ios/PurePace.xcodeproj -scheme PurePace -destination 'generic/platform=iOS' -archivePath "$OUT_DIR/PurePace.xcarchive" -derivedDataPath "$OUT_DIR/DerivedData" MARKETING_VERSION="$MARKETING_VERSION" CURRENT_PROJECT_VERSION="$CURRENT_PROJECT_VERSION" CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=3X4J53U6RY CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=YES -allowProvisioningUpdates -authenticationKeyPath "$ASC_KEY_PATH" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID"
info: xcodebuild -exportArchive -archivePath "$OUT_DIR/PurePace.xcarchive" -exportPath "$OUT_DIR/export" -exportOptionsPlist "$OUT_DIR/ExportOptions.plist" -allowProvisioningUpdates -authenticationKeyPath "$ASC_KEY_PATH" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID"
info: DRY_RUN=1 已跳过 xcodegen / xcodebuild 实际执行（无网络访问）
DRYRUN
  exit 0
fi

# 版本真源同步：MARKETING_VERSION 来自根 VERSION，不写 project.yml。
if [ -f scripts/sync-ios-version.sh ]; then
  bash scripts/sync-ios-version.sh
fi

printf 'info: xcodegen generate --spec project.yml（cwd=ios/）\n'
(
  cd "$ios_dir"
  xcodegen generate --spec project.yml
)

printf 'info: xcodebuild archive（OUT_DIR=%s）\n' "$out_dir"
xcodebuild archive \
  -project "$project_path" \
  -scheme "$scheme" \
  -destination 'generic/platform=iOS' \
  -archivePath "$archive_path" \
  -derivedDataPath "$out_dir/DerivedData" \
  MARKETING_VERSION="$marketing_version" \
  CURRENT_PROJECT_VERSION="$build_number" \
  CODE_SIGN_STYLE=Automatic \
  DEVELOPMENT_TEAM="$team_id" \
  CODE_SIGNING_ALLOWED=YES \
  CODE_SIGNING_REQUIRED=YES \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$ASC_KEY_PATH" \
  -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID"

printf 'info: xcodebuild -exportArchive（OUT_DIR=%s）\n' "$out_dir"
xcodebuild -exportArchive \
  -archivePath "$archive_path" \
  -exportPath "$export_path" \
  -exportOptionsPlist "$export_options" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$ASC_KEY_PATH" \
  -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID"

app_src="$archive_path/Products/Applications/PurePace.app"
dsym_src="$archive_path/dSYMs/PurePace.app.dSYM"
app_dst="$out_dir/PurePace.app"
dsym_dst="$out_dir/PurePace.app.dSYM"
app_zip="$out_dir/PurePace.app.zip"
dsym_zip="$out_dir/PurePace.app.dSYM.zip"

if [ ! -d "$app_src" ]; then
  printf 'archive-ios: 归档中未找到 %s\n' "$app_src" >&2
  exit 1
fi
if [ ! -d "$dsym_src" ]; then
  printf 'archive-ios: 归档中未找到 %s\n' "$dsym_src" >&2
  exit 1
fi

rm -rf "$app_dst" "$dsym_dst" "$app_zip" "$dsym_zip"
cp -R "$app_src" "$app_dst"
cp -R "$dsym_src" "$dsym_dst"
ditto -c -k --keepParent "$app_dst" "$app_zip"
ditto -c -k --keepParent "$dsym_dst" "$dsym_zip"

sha256_file() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    echo "archive-ios: 缺少 shasum / sha256sum，无法计算校验和" >&2
    return 1
  fi
}

app_sha="$(sha256_file "$app_zip")"
dsym_sha="$(sha256_file "$dsym_zip")"

printf 'zip: %s\n' "$app_zip"
printf 'sha256: %s\n' "$app_sha"
printf 'app: %s\n' "$app_dst"
printf 'dSYM: %s\n' "$dsym_dst"
printf 'dSYM zip: %s\n' "$dsym_zip"
printf 'dSYM sha256: %s\n' "$dsym_sha"
printf 'export: %s\n' "$export_path"

{
  printf '%s  %s\n' "$app_sha" "PurePace.app.zip"
  printf '%s  %s\n' "$dsym_sha" "PurePace.app.dSYM.zip"
} > "$out_dir/checksums.txt"

printf 'info: 校验和已写入 %s\n' "$out_dir/checksums.txt"
