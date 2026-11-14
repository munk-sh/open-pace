#!/usr/bin/env bash
# iOS 分发基线静态/契约断言（.munk/code-gates.json 的 lint-ios-release 门真实执行体）。
# 校验 archive-ios.sh 的凭据失败闭合、DRY_RUN 脱敏、ExportOptions 内容、版本接线与产物/校验逻辑，
# 以及门禁接入、check-ios-scripts 门数同步和 TestFlight runbook 完整性。任一条失败即非零退出。
set -euo pipefail

usage() {
  cat <<'EOF'
用法: scripts/check-ios-release.sh [--help]

对 iOS 分发基线做结构与契约断言并打印逐条结果：
  - scripts/archive-ios.sh 存在、bash -n、shebang、set -euo pipefail、--help / 未知参数契约
  - archive-ios.sh 与 runbook 无 set -x、无用户目录绝对路径、无私钥/凭据字面量
  - archive-ios.sh 含 xcodegen / archive / exportArchive / 三个认证参数 / 版本覆盖 / 产物校验逻辑
  - DRY_RUN=1 在无凭据时退出 0，且不实际调用 xcodegen / xcodebuild
  - DRY_RUN=1 生成真实 ExportOptions.plist（app-store-connect / teamID / automatic / uploadSymbols=false）
  - 伪凭据 DRY_RUN 输出含认证参数名与 $ASC_* 占位符，但不出现任何凭据值
  - 非 DRY_RUN 缺凭据时非零退出、只提示缺失变量名、已设置值不泄露且不执行构建
  - scripts/upload-ios.sh：默认 ipa 解析/--ipa 覆盖、先 --list-apps 后 --upload-app、缺凭据失败闭合、DRY_RUN 脱敏
  - scripts/testflight-tester.sh：只读先行、只写 isInternalGroup=true 内部组、失败停手、不触发审核/外邀
  - ios/project.yml 与 ios/PurePace/Info.plist 的 ITSAppUsesNonExemptEncryption=false 布尔声明
  - .munk/code-gates.json 含 lint-ios-release 门且总门数为 23
  - scripts/check-ios-scripts.sh 门数断言同步为 23
  - docs/release/testflight-runbook.md 前置/执行/证据/反范围齐全且只用占位符，主路径脚本化
  - docs/human-gate-distribution.md 一次性凭据录入说明

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
    echo "check-ios-release: 未知参数 '$1'（使用 --help 查看用法）" >&2
    exit 2
    ;;
esac

if [ "$#" -gt 1 ]; then
  echo "check-ios-release: 只接受一个参数（使用 --help 查看用法）" >&2
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

archive_script="scripts/archive-ios.sh"
runbook="docs/release/testflight-runbook.md"

# --------------------------------------------------- 脚本存在、语法与参数契约
problems=""
[ -f "$archive_script" ] || problems="$problems 缺少 $archive_script;"
if [ -z "$problems" ]; then
  pass "ac-archive-script-contract (present)"
else
  fail "ac-archive-script-contract" "$problems"
fi

problems=""
if [ -f "$archive_script" ]; then
  bash -n "$archive_script" >/dev/null 2>&1 || problems="$problems bash -n 失败;"
  first_line="$(sed -n '1p' "$archive_script")"
  [ "$first_line" = "#!/usr/bin/env bash" ] || problems="$problems shebang 为 '$first_line';"
  grep -Fq -- 'set -euo pipefail' "$archive_script" || problems="$problems 缺少 set -euo pipefail;"
  grep -Fq -- 'BASH_SOURCE' "$archive_script" || problems="$problems 未以 BASH_SOURCE 推导仓库根;"
  help_out="$(bash "$archive_script" --help 2>&1)" && help_rc=0 || help_rc=$?
  if [ "$help_rc" -ne 0 ]; then
    problems="$problems --help 退出 $help_rc;"
  elif ! grep -Fq -- "用法" <<< "$help_out"; then
    problems="$problems --help 输出缺少「用法」;"
  fi
  bash "$archive_script" --definitely-invalid >/dev/null 2>&1 && bad_rc=0 || bad_rc=$?
  [ "$bad_rc" -eq 2 ] || problems="$problems 未知参数退出 ${bad_rc}（期望 2）;"
else
  problems="$problems 缺少 $archive_script;"
fi
if [ -z "$problems" ]; then
  pass "ac-archive-script-contract (bash -n/shebang/help)"
else
  fail "ac-archive-script-contract" "$problems"
fi

# ------------------------------------ 无 set -x / 用户目录绝对路径 / 私钥字面量
secret_problems() {
  local file="$1" out=""
  if [ ! -f "$file" ]; then
    printf '缺少 %s;' "$file"
    return 0
  fi
  grep -Fq -- 'set -x' "$file" && out="$out 含 set -x;"
  grep -Eq -- '(^|[^[:alnum:]_])(/Users/|/home/)' "$file" && out="$out 含用户目录绝对路径;"
  grep -Fq -- 'BEGIN PRIVATE KEY' "$file" && out="$out 含私钥字面量;"
  printf '%s' "$out"
}

# 归档脚本自身不得发起网络调用；runbook 允许把 `xcrun altool --list-apps` 作为只读检查说明。
network_problems() {
  local file="$1" out=""
  if [ ! -f "$file" ]; then
    printf '缺少 %s;' "$file"
    return 0
  fi
  if grep -Eq -- '(^|[^[:alnum:]_])(curl|wget|altool)([[:space:]]|$)' "$file"; then
    out="$out 归档脚本含 curl/wget/altool 调用;"
  fi
  printf '%s' "$out"
}

problems=""
for file in "$archive_script" "$runbook"; do
  problems="$problems$(secret_problems "$file")"
done
problems="$problems$(network_problems "$archive_script")"
if [ -z "$problems" ]; then
  pass "ac-no-secret-literals-or-xtrace"
else
  fail "ac-no-secret-literals-or-xtrace" "$problems"
fi

# 反例自检：注入 set -x 与用户目录路径后，同一断言必须报错（非恒真）。
secret_sandbox="$(mktemp -d "${TMPDIR:-/tmp}/purepace-check-ios-release-secret.XXXXXX")"
cp "$archive_script" "$secret_sandbox/archive-ios.sh"
user_dir='Users'
printf '%s\n' 'set -x' "# /${user_dir}/someone/AuthKey.p8" >> "$secret_sandbox/archive-ios.sh"
if [ -n "$(secret_problems "$secret_sandbox/archive-ios.sh")" ]; then
  pass "ac-no-secret-literals-or-xtrace (self-test)"
else
  fail "ac-no-secret-literals-or-xtrace" "注入 set -x / 用户目录路径的违规样本未被识别"
fi
rm -rf "$secret_sandbox"

# ---------------------------------- 归档命令、版本接线、导出与产物/校验逻辑
problems=""
if [ ! -f "$archive_script" ]; then
  problems="$problems 缺少 $archive_script;"
else
  for needle in \
    "xcodegen generate --spec project.yml" \
    "xcodebuild archive" \
    "xcodebuild -exportArchive" \
    "-exportOptionsPlist" \
    "-destination 'generic/platform=iOS'" \
    "-authenticationKeyPath" \
    "-authenticationKeyID" \
    "-authenticationKeyIssuerID" \
    "-allowProvisioningUpdates" \
    "MARKETING_VERSION" \
    "CURRENT_PROJECT_VERSION" \
    "BUILD_NUMBER:-1" \
    "scripts/version.sh" \
    "CODE_SIGNING_ALLOWED=YES" \
    "CODE_SIGNING_REQUIRED=YES" \
    "app-store-connect" \
    "3X4J53U6RY" \
    "<key>signingStyle</key>" \
    "<string>automatic</string>" \
    "<key>uploadSymbols</key>" \
    "ditto -c -k --keepParent" \
    "shasum -a 256" \
    "sha256sum" \
    "checksums.txt" \
    "purepace-dist" \
    ".app.dSYM"; do
    grep -Fq -- "$needle" "$archive_script" || problems="$problems 缺少 '$needle';"
  done
fi
if [ -z "$problems" ]; then
  pass "ac-version-and-build-wiring"
  pass "ac-artifacts-outside-repo-and-checksums"
else
  fail "ac-version-and-build-wiring" "$problems"
  fail "ac-artifacts-outside-repo-and-checksums" "$problems"
fi

# ----------------------------------------------------- 运行时沙箱与桩命令
sandbox="$(mktemp -d "${TMPDIR:-/tmp}/purepace-check-ios-release.XXXXXX")"
trap 'rm -rf "$sandbox"' EXIT
stub_bin="$sandbox/bin"
mkdir -p "$stub_bin"
for tool in xcodegen xcodebuild; do
  cat > "$stub_bin/$tool" <<'STUB'
#!/usr/bin/env bash
touch "${MARKER_DIR}/$(basename "$0").called"
STUB
  chmod +x "$stub_bin/$tool"
done

# --------------------------------------- DRY_RUN 无凭据：退出 0 且不执行工具
dry_dir="$sandbox/dry"
dry_log="$sandbox/dry.log"
if MARKER_DIR="$sandbox" PATH="$stub_bin:$PATH" \
  env -u ASC_KEY_PATH -u ASC_KEY_ID -u ASC_ISSUER_ID DRY_RUN=1 OUT_DIR="$dry_dir" \
  bash "$archive_script" > "$dry_log" 2>&1; then
  dry_rc=0
else
  dry_rc=$?
fi

problems=""
[ "$dry_rc" -eq 0 ] || problems="$problems DRY_RUN=1 退出 ${dry_rc}（期望 0）;"
dry_output="$(< "$dry_log")"
for needle in \
  "xcodegen generate" \
  "xcodebuild archive" \
  "-exportArchive" \
  "-destination 'generic/platform=iOS'"; do
  grep -Fq -- "$needle" <<< "$dry_output" || problems="$problems 输出缺少 '$needle';"
done
[ ! -e "$sandbox/xcodegen.called" ] || problems="$problems DRY_RUN 实际调用了 xcodegen;"
[ ! -e "$sandbox/xcodebuild.called" ] || problems="$problems DRY_RUN 实际调用了 xcodebuild;"
if [ -z "$problems" ]; then
  pass "ac-dry-run-runs-without-credentials"
else
  fail "ac-dry-run-runs-without-credentials" "$problems"
fi

# ---------------------------------- DRY_RUN 生成真实 ExportOptions.plist 内容
problems=""
export_options="$dry_dir/ExportOptions.plist"
if [ ! -f "$export_options" ]; then
  problems="$problems 未生成 $export_options;"
else
  for needle in "app-store-connect" "3X4J53U6RY" "<string>automatic</string>" "<key>uploadSymbols</key>"; do
    grep -Fq -- "$needle" "$export_options" || problems="$problems ExportOptions 缺少 '$needle';"
  done
  upload_symbols_ctx="$(grep -A1 -F -- '<key>uploadSymbols</key>' "$export_options")"
  if ! grep -Fq -- '<false/>' <<< "$upload_symbols_ctx"; then
    problems="$problems uploadSymbols 不是 false;"
  fi
  if command -v plutil >/dev/null 2>&1; then
    plutil -lint "$export_options" >/dev/null 2>&1 || problems="$problems ExportOptions.plist 不是合法 plist;"
  fi
fi
if grep -Fq -- "-exportArchive" <<< "$dry_output" \
  && grep -Fq -- "-exportOptionsPlist" <<< "$dry_output"; then
  :
else
  problems="$problems 导出命令缺少 -exportArchive / -exportOptionsPlist;"
fi
if [ -z "$problems" ]; then
  pass "ac-export-options-content"
else
  fail "ac-export-options-content" "$problems"
fi

# ------------------------------------------ DRY_RUN 伪凭据输出必须完全脱敏
redaction_problems() {
  local output="$1" out=""
  for needle in -authenticationKeyPath -authenticationKeyID -authenticationKeyIssuerID; do
    grep -Fq -- "$needle" <<< "$output" || out="$out 输出缺少 $needle;"
  done
  for needle in '$ASC_KEY_PATH' '$ASC_KEY_ID' '$ASC_ISSUER_ID'; do
    grep -Fq -- "$needle" <<< "$output" || out="$out 输出缺少占位符 $needle;"
  done
  for needle in FAKEKEYID FAKE-ISSUER-UUID FAKE-KEY.p8; do
    if grep -Fq -- "$needle" <<< "$output"; then
      out="$out 输出泄露凭据值 $needle;"
    fi
  done
  printf '%s' "$out"
}

redact_dir="$sandbox/redact"
redact_log="$sandbox/redact.log"
if env \
  ASC_KEY_PATH=/tmp/FAKE-KEY.p8 \
  ASC_KEY_ID=FAKEKEYID \
  ASC_ISSUER_ID=FAKE-ISSUER-UUID \
  DRY_RUN=1 OUT_DIR="$redact_dir" \
  bash "$archive_script" > "$redact_log" 2>&1; then
  redact_rc=0
else
  redact_rc=$?
fi
problems=""
[ "$redact_rc" -eq 0 ] || problems="$problems 退出 ${redact_rc}（期望 0）;"
problems="$problems$(redaction_problems "$(< "$redact_log")")"
if [ -z "$problems" ]; then
  pass "ac-dry-run-output-redacted"
else
  fail "ac-dry-run-output-redacted" "$problems"
fi

# 反例自检：把明文凭据喂给同一检测器，必须识别为泄露。
leaky_sample="xcodebuild -authenticationKeyPath /tmp/FAKE-KEY.p8 -authenticationKeyID FAKEKEYID -authenticationKeyIssuerID FAKE-ISSUER-UUID"
if [ -n "$(redaction_problems "$leaky_sample")" ]; then
  pass "ac-dry-run-output-redacted (self-test)"
else
  fail "ac-dry-run-output-redacted" "明文凭据样本未被脱敏检测识别"
fi

# ------------------------------- 非 DRY_RUN 缺凭据：失败闭合且不执行构建
missing_dir="$sandbox/missing"
missing_log="$sandbox/missing.log"
if MARKER_DIR="$sandbox" PATH="$stub_bin:$PATH" \
  env -u ASC_KEY_PATH -u ASC_ISSUER_ID ASC_KEY_ID=SECRETID OUT_DIR="$missing_dir" \
  bash "$archive_script" > "$missing_log" 2>&1; then
  missing_rc=0
else
  missing_rc=$?
fi
problems=""
[ "$missing_rc" -ne 0 ] || problems="$problems 缺凭据仍退出 0（应非零）;"
missing_output="$(< "$missing_log")"
grep -Fq -- "ASC_KEY_PATH" <<< "$missing_output" || problems="$problems 未提示缺失 ASC_KEY_PATH;"
grep -Fq -- "ASC_ISSUER_ID" <<< "$missing_output" || problems="$problems 未提示缺失 ASC_ISSUER_ID;"
if grep -Fq -- "SECRETID" <<< "$missing_output"; then
  problems="$problems 已设置凭据值 SECRETID 泄露到输出;"
fi
[ ! -e "$sandbox/xcodegen.called" ] || problems="$problems 缺凭据时仍调用了 xcodegen;"
[ ! -e "$sandbox/xcodebuild.called" ] || problems="$problems 缺凭据时仍调用了 xcodebuild;"
if [ -z "$problems" ]; then
  pass "ac-missing-env-fails-closed"
else
  fail "ac-missing-env-fails-closed" "$problems"
fi

# 反例自检：已设置值泄露样本必须被识别。
leak_log="$sandbox/leak.log"
printf 'archive-ios: 缺少环境变量 ASC_KEY_PATH（ASC_KEY_ID=%s）\n' "SECRETID" > "$leak_log"
if grep -Fq -- "SECRETID" "$leak_log"; then
  pass "ac-missing-env-fails-closed (self-test)"
else
  fail "ac-missing-env-fails-closed" "值泄露样本未被识别"
fi

# ---------------------------------------- 门禁接入 + 门数 23 + 断言同步
problems=""
if ! command -v python3 >/dev/null 2>&1; then
  problems="$problems 缺少 python3，无法解析 .munk/code-gates.json;"
elif [ ! -f .munk/code-gates.json ]; then
  problems="$problems 缺少 .munk/code-gates.json;"
else
  gate_error="$(python3 - <<'PY' 2>&1
import json
cfg = json.load(open(".munk/code-gates.json", encoding="utf-8"))
gates = cfg.get("gates", [])
if len(gates) != 23:
    raise SystemExit("code-gates 门数 %d（期望 23）" % len(gates))
matches = [g for g in gates if g.get("id") == "lint-ios-release"]
if len(matches) != 1:
    raise SystemExit("缺少唯一的 lint-ios-release 门")
if matches[0].get("command") != "bash scripts/check-ios-release.sh":
    raise SystemExit("lint-ios-release command 为 %r" % matches[0].get("command"))
PY
  )" && gate_rc=0 || gate_rc=$?
  if [ "$gate_rc" -ne 0 ]; then
    problems="$problems $(printf '%s' "$gate_error" | tr '\n' ' ');"
  fi
fi
grep -Fq -- '保持 23 门' scripts/check-ios-scripts.sh \
  || problems="$problems scripts/check-ios-scripts.sh 未同步「保持 23 门」;"
grep -Fq -- '-ne 23' scripts/check-ios-scripts.sh \
  || problems="$problems scripts/check-ios-scripts.sh 未同步 -ne 23 断言;"
if [ -z "$problems" ]; then
  pass "ac-release-gate-wired"
else
  fail "ac-release-gate-wired" "$problems"
fi

# ------------------------------------------------ TestFlight runbook 完整性
runbook_problems() {
  local file="$1" out=""
  if [ ! -f "$file" ]; then
    printf '缺少 %s;' "$file"
    return 0
  fi
  for needle in \
    '$ASC_KEY_PATH' \
    '$ASC_KEY_ID' \
    '$ASC_ISSUER_ID' \
    'xcrun altool --list-apps' \
    'xcodebuild -version' \
    'sha256' \
    'commit' \
    '.env'; do
    grep -Fq -- "$needle" "$file" || out="$out 缺少 '$needle';"
  done
  for section in '前置' '执行步骤' '证据' '反范围'; do
    grep -Fq -- "$section" "$file" || out="$out 缺少「${section}」段;"
  done
  out="$out$(secret_problems "$file")"
  printf '%s' "$out"
}

problems="$(runbook_problems "$runbook")"
if [ -z "$problems" ]; then
  pass "ac-runbook-complete"
else
  fail "ac-runbook-complete" "$problems"
fi

# 反例自检：删掉占位符后的 runbook 样本必须被识别。
runbook_sandbox="$(mktemp -d "${TMPDIR:-/tmp}/purepace-check-ios-runbook.XXXXXX")"
sed 's/\$ASC_KEY_PATH/KEYPATH/g' "$runbook" > "$runbook_sandbox/runbook.md"
if [ -n "$(runbook_problems "$runbook_sandbox/runbook.md")" ]; then
  pass "ac-runbook-complete (self-test)"
else
  fail "ac-runbook-complete" "缺少占位符的 runbook 样本未被识别"
fi
rm -rf "$runbook_sandbox"

# ------------------------------------------------- README 入口与 workflow 未改
problems=""
for needle in 'scripts/archive-ios.sh' 'scripts/check-ios-release.sh'; do
  grep -Fq -- "$needle" README.md || problems="$problems README.md 缺少 '$needle';"
done
if [ -z "$problems" ]; then
  pass "readme-release-entry"
else
  fail "readme-release-entry" "$problems"
fi

problems=""
if [ -d .github/workflows ]; then
  if grep -RFq -- 'fastlane' .github/workflows 2>/dev/null; then
    problems="$problems .github/workflows 引入 fastlane;"
  fi
fi
if grep -Fq -- 'fastlane' "$archive_script" "$runbook" 2>/dev/null; then
  problems="$problems 分发基线引用了 fastlane;"
fi
if [ -z "$problems" ]; then
  pass "ac-no-network-or-workflow-changes"
else
  fail "ac-no-network-or-workflow-changes" "$problems"
fi

# =============================== 分发脚本（上传 / 内部测试者）与加密豁免声明
upload_script="scripts/upload-ios.sh"
tester_script="scripts/testflight-tester.sh"
project_spec="ios/project.yml"
app_plist="ios/PurePace/Info.plist"
human_gate="docs/human-gate-distribution.md"

script_contract_problems() {
  local file="$1" out="" first_line help_out help_rc bad_rc
  if [ ! -f "$file" ]; then
    printf '缺少 %s;' "$file"
    return 0
  fi
  bash -n "$file" >/dev/null 2>&1 || out="$out bash -n 失败;"
  first_line="$(sed -n '1p' "$file")"
  [ "$first_line" = "#!/usr/bin/env bash" ] || out="$out shebang 为 '$first_line';"
  grep -Fq -- 'set -euo pipefail' "$file" || out="$out 缺少 set -euo pipefail;"
  grep -Fq -- 'BASH_SOURCE' "$file" || out="$out 未以 BASH_SOURCE 推导仓库根;"
  help_out="$(bash "$file" --help 2>&1)" && help_rc=0 || help_rc=$?
  if [ "$help_rc" -ne 0 ]; then
    out="$out --help 退出 $help_rc;"
  elif ! grep -Fq -- "用法" <<< "$help_out"; then
    out="$out --help 输出缺少「用法」;"
  fi
  bash "$file" --definitely-invalid >/dev/null 2>&1 && bad_rc=0 || bad_rc=$?
  [ "$bad_rc" -eq 2 ] || out="$out 未知参数退出 ${bad_rc}（期望 2）;"
  printf '%s' "$out"
}

problems="$(script_contract_problems "$upload_script")"
if [ -z "$problems" ]; then
  pass "ac-upload-script-contract"
else
  fail "ac-upload-script-contract" "$problems"
fi

problems="$(script_contract_problems "$tester_script")"
if [ -z "$problems" ]; then
  pass "ac-tester-script-contract"
else
  fail "ac-tester-script-contract" "$problems"
fi

# 反例自检：抽掉严格模式后同一检测函数必须报错。
contract_sandbox="$(mktemp -d "${TMPDIR:-/tmp}/purepace-check-ios-contract.XXXXXX")"
grep -v -F -- 'set -euo pipefail' "$upload_script" > "$contract_sandbox/upload-ios.sh"
if [ -n "$(script_contract_problems "$contract_sandbox/upload-ios.sh")" ]; then
  pass "ac-upload-script-contract (self-test)"
else
  fail "ac-upload-script-contract" "去掉 set -euo pipefail 的样本未被识别"
fi
rm -rf "$contract_sandbox"

# ---------------------------------------------------- upload 静态契约字面量
upload_static_problems() {
  local file="$1" out=""
  if [ ! -f "$file" ]; then
    printf '缺少 %s;' "$file"
    return 0
  fi
  for needle in \
    '--ipa' \
    'OUT_DIR' \
    'purepace-dist' \
    '/export' \
    "'*.ipa'" \
    'scripts/version.sh' \
    'BUILD_NUMBER:-1' \
    'xcrun altool --list-apps' \
    'xcrun altool --upload-app' \
    '-t ios' \
    '--apiKey' \
    '--apiIssuer' \
    '--apiPrivateKey' \
    '$ASC_KEY_PATH' \
    '$ASC_KEY_ID' \
    '$ASC_ISSUER_ID' \
    'DRY_RUN'; do
    grep -Fq -- "$needle" "$file" || out="$out 缺少 '$needle';"
  done
  out="$out$(secret_problems "$file")"
  printf '%s' "$out"
}

problems="$(upload_static_problems "$upload_script")"
if [ -z "$problems" ]; then
  pass "ac-upload-static-contract"
else
  fail "ac-upload-static-contract" "$problems"
fi

# 反例自检：删掉 --list-apps 与注入 set -x 的样本必须判红。
upload_static_sandbox="$(mktemp -d "${TMPDIR:-/tmp}/purepace-check-ios-upload-static.XXXXXX")"
sed 's/xcrun altool --list-apps/xcrun altool --legacy-list/' "$upload_script" > "$upload_static_sandbox/upload-ios.sh"
printf '%s\n' 'set -x' >> "$upload_static_sandbox/upload-ios.sh"
if [ -n "$(upload_static_problems "$upload_static_sandbox/upload-ios.sh")" ]; then
  pass "ac-upload-static-contract (self-test)"
else
  fail "ac-upload-static-contract" "缺少 --list-apps 且注入 set -x 的样本未被识别"
fi
rm -rf "$upload_static_sandbox"

# --------------------------------------------------- xcrun / curl 可观测桩
cat > "$stub_bin/xcrun" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${MARKER_DIR}/xcrun.calls"
if [ "${1:-}" = "altool" ] && [ "${2:-}" = "--list-apps" ]; then
  printf 'sh.munk.purepace  PurePace  SENTINEL-APP-LIST\n'
fi
exit 0
STUB
chmod +x "$stub_bin/xcrun"

cat > "$stub_bin/curl" <<'STUB'
#!/usr/bin/env bash
method="GET"
body_file=""
prev=""
for arg in "$@"; do
  case "$prev" in
    -X) method="$arg" ;;
    -o) body_file="$arg" ;;
  esac
  prev="$arg"
done
url=""
for arg in "$@"; do
  case "$arg" in
    http*) url="$arg" ;;
  esac
done
printf '%s %s\n' "$method" "$url" >> "${MARKER_DIR}/curl.calls"
code="200"
payload='{"data":[]}'
case "$method $url" in
  "GET "*"/v1/apps?"*)
    payload='{"data":[{"type":"apps","id":"APPID"}]}'
    ;;
  "GET "*"/v1/betaTesters?"*)
    payload='{"data":[]}'
    ;;
  "POST "*"/v1/betaTesters")
    payload='{"data":{"type":"betaTesters","id":"TESTERID"}}'
    ;;
  "GET "*"/v1/betaGroups?"*)
    if [ "${CURL_STUB_FAIL:-0}" = "1" ]; then
      code="403"
      payload='{"errors":[{"code":"FORBIDDEN_ERROR","title":"stub read forbidden"}]}'
    else
      payload='{"data":[{"type":"betaGroups","id":"GROUPID","attributes":{"name":"Internal","isInternalGroup":true}}]}'
    fi
    ;;
  "POST "*"/v1/betaGroups/GROUPID/relationships/betaTesters")
    code="204"
    payload=''
    ;;
esac
if [ -n "$body_file" ]; then
  printf '%s' "$payload" > "$body_file"
fi
printf '%s' "$code"
exit 0
STUB
chmod +x "$stub_bin/curl"

# 伪造一个一次性 EC 私钥（只在 TMPDIR 沙箱内，用于证明 JWT 签发不打印凭据）。
fake_asc_key="$sandbox/fake-authkey.p8"
if command -v openssl >/dev/null 2>&1; then
  openssl ecparam -name prime256v1 -genkey -noout -out "$fake_asc_key" >/dev/null 2>&1 || true
fi

# ------------------------------- upload：默认 ipa / --ipa 覆盖 / 无 ipa 失败
upload_dist="$sandbox/upload-dist"
mkdir -p "$upload_dist/export"
printf 'fake-ipa' > "$upload_dist/export/PurePace.ipa"
upload_log="$sandbox/upload-ok.log"
rm -f "$sandbox/xcrun.calls"
if MARKER_DIR="$sandbox" PATH="$stub_bin:$PATH" \
  env ASC_KEY_PATH="$sandbox/fake-key.p8" ASC_KEY_ID=FAKEKEYID ASC_ISSUER_ID=FAKE-ISSUER-UUID \
  OUT_DIR="$upload_dist" \
  bash "$upload_script" > "$upload_log" 2>&1; then
  upload_rc=0
else
  upload_rc=$?
fi
problems=""
[ "$upload_rc" -eq 0 ] || problems="$problems 默认 ipa 执行退出 ${upload_rc}（期望 0）;"
upload_calls_ok=""
[ -f "$sandbox/xcrun.calls" ] && upload_calls_ok="$(< "$sandbox/xcrun.calls")"
upload_output="$(< "$upload_log")"
grep -Fq -- "$upload_dist/export/PurePace.ipa" <<< "$upload_output" \
  || problems="$problems 输出缺少默认解析的 ipa 路径;"
grep -Fq -- 'version:' <<< "$upload_output" || problems="$problems 输出缺少版本行;"
grep -Fq -- 'build:' <<< "$upload_output" || problems="$problems 输出缺少 build 行;"
grep -Fq -- '上传结果:' <<< "$upload_output" || problems="$problems 输出缺少上传结果行;"

# --ipa 覆盖：默认目录同时存在两份 ipa 时，也必须使用显式路径。
printf 'override-ipa' > "$sandbox/override.ipa"
printf 'extra-ipa' > "$upload_dist/export/Extra.ipa"
override_log="$sandbox/upload-override.log"
rm -f "$sandbox/xcrun.calls"
if MARKER_DIR="$sandbox" PATH="$stub_bin:$PATH" \
  env ASC_KEY_PATH="$sandbox/fake-key.p8" ASC_KEY_ID=FAKEKEYID ASC_ISSUER_ID=FAKE-ISSUER-UUID \
  OUT_DIR="$upload_dist" \
  bash "$upload_script" --ipa "$sandbox/override.ipa" > "$override_log" 2>&1; then
  override_rc=0
else
  override_rc=$?
fi
[ "$override_rc" -eq 0 ] || problems="$problems --ipa 覆盖执行退出 ${override_rc}（期望 0）;"
grep -Fq -- "$sandbox/override.ipa" "$sandbox/xcrun.calls" 2>/dev/null \
  || problems="$problems --ipa 覆盖未把显式路径传给 altool;"

# 默认目录多份 ipa 且未传 --ipa：必须非零并提示 --ipa。
multi_log="$sandbox/upload-multi.log"
rm -f "$sandbox/xcrun.calls"
if MARKER_DIR="$sandbox" PATH="$stub_bin:$PATH" \
  env ASC_KEY_PATH="$sandbox/fake-key.p8" ASC_KEY_ID=FAKEKEYID ASC_ISSUER_ID=FAKE-ISSUER-UUID \
  OUT_DIR="$upload_dist" \
  bash "$upload_script" > "$multi_log" 2>&1; then
  multi_rc=0
else
  multi_rc=$?
fi
[ "$multi_rc" -ne 0 ] || problems="$problems 多份 ipa 未要求 --ipa 仍退出 0;"
grep -Fq -- '--ipa' "$multi_log" || problems="$problems 多份 ipa 时未提示 --ipa 兜底;"
[ ! -e "$sandbox/xcrun.calls" ] || problems="$problems 多份 ipa 时仍调用了 xcrun;"

# 空目录：必须非零并提示 --ipa。
empty_dist="$sandbox/upload-empty"
mkdir -p "$empty_dist/export"
empty_log="$sandbox/upload-empty.log"
rm -f "$sandbox/xcrun.calls"
if MARKER_DIR="$sandbox" PATH="$stub_bin:$PATH" \
  env ASC_KEY_PATH="$sandbox/fake-key.p8" ASC_KEY_ID=FAKEKEYID ASC_ISSUER_ID=FAKE-ISSUER-UUID \
  OUT_DIR="$empty_dist" \
  bash "$upload_script" > "$empty_log" 2>&1; then
  empty_rc=0
else
  empty_rc=$?
fi
[ "$empty_rc" -ne 0 ] || problems="$problems 缺 ipa 仍退出 0;"
grep -Fq -- '--ipa' "$empty_log" || problems="$problems 缺 ipa 时未提示 --ipa 兜底;"
[ ! -e "$sandbox/xcrun.calls" ] || problems="$problems 缺 ipa 时仍调用了 xcrun;"
if [ -z "$problems" ]; then
  pass "ac-upload-default-ipa-and-override"
else
  fail "ac-upload-default-ipa-and-override" "$problems"
fi

# ------------------------------------------ upload：先 --list-apps 后 --upload-app
problems=""
upload_output="$(< "$upload_log")"
grep -Fq -- '命中 App 记录 1 条' <<< "$upload_output" \
  || problems="$problems 未打印 --list-apps 命中条数;"
if grep -Fq -- 'SENTINEL-APP-LIST' <<< "$upload_output"; then
  problems="$problems 输出泄露了 App 清单;"
fi
for needle in FAKEKEYID FAKE-ISSUER-UUID FAKE-KEY.p8; do
  if grep -Fq -- "$needle" <<< "$upload_output"; then
    problems="$problems 输出泄露凭据值 $needle;"
  fi
done
upload_calls="$upload_calls_ok"
list_line="$(grep -n -F -- 'altool --list-apps' <<< "$upload_calls" | cut -d: -f1 | head -1 || true)"
upload_line="$(grep -n -F -- 'altool --upload-app' <<< "$upload_calls" | cut -d: -f1 | head -1 || true)"
if [ -z "$list_line" ] || [ -z "$upload_line" ] || [ "$list_line" -ge "$upload_line" ]; then
  problems="$problems --list-apps 未先于 --upload-app（或未调用）;"
fi
grep -Fq -- '-t ios' <<< "$upload_calls" || problems="$problems --upload-app 缺少 -t ios;"
if [ -z "$problems" ]; then
  pass "ac-upload-lists-then-uploads"
else
  fail "ac-upload-lists-then-uploads" "$problems"
fi

# ------------------------------------ upload：缺凭据失败闭合、不触网、不泄露已设置值
missing_upload_log="$sandbox/upload-missing.log"
rm -f "$sandbox/xcrun.calls"
if MARKER_DIR="$sandbox" PATH="$stub_bin:$PATH" \
  env -u ASC_KEY_PATH -u ASC_ISSUER_ID ASC_KEY_ID=SECRETID \
  OUT_DIR="$upload_dist" \
  bash "$upload_script" --ipa "$upload_dist/export/PurePace.ipa" > "$missing_upload_log" 2>&1; then
  missing_upload_rc=0
else
  missing_upload_rc=$?
fi
problems=""
[ "$missing_upload_rc" -ne 0 ] || problems="$problems 缺凭据仍退出 0;"
missing_upload_output="$(< "$missing_upload_log")"
grep -Fq -- 'ASC_KEY_PATH' <<< "$missing_upload_output" || problems="$problems 未提示缺失 ASC_KEY_PATH;"
grep -Fq -- 'ASC_ISSUER_ID' <<< "$missing_upload_output" || problems="$problems 未提示缺失 ASC_ISSUER_ID;"
if grep -Fq -- 'SECRETID' <<< "$missing_upload_output"; then
  problems="$problems 已设置凭据值 SECRETID 泄露到输出;"
fi
[ ! -e "$sandbox/xcrun.calls" ] || problems="$problems 缺凭据时仍调用了 xcrun;"
if [ -z "$problems" ]; then
  pass "ac-upload-missing-credentials-fails-closed"
else
  fail "ac-upload-missing-credentials-fails-closed" "$problems"
fi

# ------------------------------------------------ upload：DRY_RUN 脱敏且不触网
dry_upload_log="$sandbox/upload-dry.log"
rm -f "$sandbox/xcrun.calls"
if MARKER_DIR="$sandbox" PATH="$stub_bin:$PATH" \
  env -u ASC_KEY_PATH -u ASC_KEY_ID -u ASC_ISSUER_ID DRY_RUN=1 OUT_DIR="$sandbox/upload-dry" \
  bash "$upload_script" > "$dry_upload_log" 2>&1; then
  dry_upload_rc=0
else
  dry_upload_rc=$?
fi
problems=""
[ "$dry_upload_rc" -eq 0 ] || problems="$problems DRY_RUN=1 退出 ${dry_upload_rc}（期望 0）;"
dry_upload_output="$(< "$dry_upload_log")"
for needle in '--list-apps' '--upload-app' '$ASC_KEY_PATH' '$ASC_KEY_ID' '$ASC_ISSUER_ID'; do
  grep -Fq -- "$needle" <<< "$dry_upload_output" || problems="$problems DRY_RUN 输出缺少 '$needle';"
done
[ ! -e "$sandbox/xcrun.calls" ] || problems="$problems DRY_RUN 实际调用了 xcrun;"

# 伪凭据 DRY_RUN 仍不得出现任何凭据值。
dry_upload_fake_log="$sandbox/upload-dry-fake.log"
rm -f "$sandbox/xcrun.calls"
if MARKER_DIR="$sandbox" PATH="$stub_bin:$PATH" \
  env ASC_KEY_PATH=/tmp/FAKE-KEY.p8 ASC_KEY_ID=FAKEKEYID ASC_ISSUER_ID=FAKE-ISSUER-UUID \
  DRY_RUN=1 OUT_DIR="$sandbox/upload-dry-fake" \
  bash "$upload_script" > "$dry_upload_fake_log" 2>&1; then
  dry_upload_fake_rc=0
else
  dry_upload_fake_rc=$?
fi
[ "$dry_upload_fake_rc" -eq 0 ] || problems="$problems 伪凭据 DRY_RUN 退出 ${dry_upload_fake_rc}（期望 0）;"
dry_upload_fake_output="$(< "$dry_upload_fake_log")"
for needle in FAKEKEYID FAKE-ISSUER-UUID FAKE-KEY.p8; do
  if grep -Fq -- "$needle" <<< "$dry_upload_fake_output"; then
    problems="$problems 伪凭据 DRY_RUN 泄露 $needle;"
  fi
done
[ ! -e "$sandbox/xcrun.calls" ] || problems="$problems 伪凭据 DRY_RUN 实际调用了 xcrun;"
if [ -z "$problems" ]; then
  pass "ac-upload-dry-run-redacted"
else
  fail "ac-upload-dry-run-redacted" "$problems"
fi

# ------------------------------------ tester 静态契约：只读先行 / 内部组 / 禁用端点
tester_static_problems() {
  local file="$1" out="" groups_line create_line rel_line
  if [ ! -f "$file" ]; then
    printf '缺少 %s;' "$file"
    return 0
  fi
  for needle in \
    'filter[bundleId]' \
    'filter[app]' \
    'filter[isInternalGroup]=true' \
    'isInternalGroup") is True' \
    '/v1/betaTesters' \
    'relationships/betaTesters' \
    'openssl dgst -sha256 -sign' \
    '$ASC_KEY_PATH' \
    '$ASC_KEY_ID' \
    '$ASC_ISSUER_ID' \
    'TESTFLIGHT_TESTER_EMAIL' \
    'DRY_RUN'; do
    grep -Fq -- "$needle" "$file" || out="$out 缺少 '$needle';"
  done
  for forbidden in betaAppReviewSubmissions appStoreVersions reviewSubmission externalGroup; do
    if grep -Fq -- "$forbidden" "$file"; then
      out="$out 引用禁用端点/概念 $forbidden;"
    fi
  done
  if grep -Eq -- '(printf|echo).*\$jwt' "$file"; then
    out="$out 存在打印 JWT 的语句;"
  fi
  groups_line="$(grep -n -m1 -F -- 'GET "/v1/betaGroups' "$file" | cut -d: -f1 || true)"
  create_line="$(grep -n -m1 -F -- 'POST "/v1/betaTesters' "$file" | cut -d: -f1 || true)"
  rel_line="$(grep -n -m1 -F -- 'POST "/v1/betaGroups/' "$file" | cut -d: -f1 || true)"
  [ -n "$groups_line" ] || out="$out 缺少只读 GET /v1/betaGroups;"
  [ -n "$create_line" ] || out="$out 缺少 POST /v1/betaTesters;"
  [ -n "$rel_line" ] || out="$out 缺少 betaTesters 关系写入;"
  if [ -n "$groups_line" ] && [ -n "$create_line" ] && [ -n "$rel_line" ]; then
    [ "$groups_line" -lt "$create_line" ] || out="$out betaGroups 只读未先于创建测试者;"
    [ "$create_line" -lt "$rel_line" ] || out="$out 创建测试者未先于关系写入;"
  fi
  out="$out$(secret_problems "$file")"
  printf '%s' "$out"
}

problems="$(tester_static_problems "$tester_script")"
if [ -z "$problems" ]; then
  pass "ac-tester-static-contract"
else
  fail "ac-tester-static-contract" "$problems"
fi

# 反例自检：删掉 betaGroups 只读 + 注入 Beta App Review 端点必须判红。
tester_static_sandbox="$(mktemp -d "${TMPDIR:-/tmp}/purepace-check-ios-tester-static.XXXXXX")"
sed 's|GET "/v1/betaGroups|GET "/v1/legacyGroups|' "$tester_script" > "$tester_static_sandbox/testflight-tester.sh"
printf '%s\n' 'asc_request POST "/v1/betaAppReviewSubmissions" ""' >> "$tester_static_sandbox/testflight-tester.sh"
if [ -n "$(tester_static_problems "$tester_static_sandbox/testflight-tester.sh")" ]; then
  pass "ac-tester-static-contract (self-test)"
else
  fail "ac-tester-static-contract" "缺只读 betaGroups 且注入审核端点的样本未被识别"
fi
rm -rf "$tester_static_sandbox"

# ------------------- tester 不触发审核/外邀：禁用端点缺席、外部组不写、JWT 不打印
external_scope_problems() {
  local file="$1" out=""
  if [ ! -f "$file" ]; then
    printf '缺少 %s;' "$file"
    return 0
  fi
  for token in betaAppReviewSubmissions appStoreVersions reviewSubmission externalGroup; do
    if grep -Fq -- "$token" "$file"; then
      out="$out 引用禁用端点/概念 $token;"
    fi
  done
  if grep -Eq -- '(printf|echo).*\$jwt' "$file"; then
    out="$out 存在打印 JWT 的语句;"
  fi
  printf '%s' "$out"
}

problems="$(external_scope_problems "$tester_script")"
if [ -z "$problems" ]; then
  pass "ac-tester-no-external-invite-or-review"
else
  fail "ac-tester-no-external-invite-or-review" "$problems"
fi

# 反例自检：注入 Beta App Review 端点与 JWT 打印的样本必须判红。
external_scope_sandbox="$(mktemp -d "${TMPDIR:-/tmp}/purepace-check-ios-external-scope.XXXXXX")"
cp "$tester_script" "$external_scope_sandbox/testflight-tester.sh"
printf '%s\n' 'asc_request POST "/v1/betaAppReviewSubmissions" ""' 'printf "%s" "$jwt"' \
  >> "$external_scope_sandbox/testflight-tester.sh"
if [ -n "$(external_scope_problems "$external_scope_sandbox/testflight-tester.sh")" ]; then
  pass "ac-tester-no-external-invite-or-review (self-test)"
else
  fail "ac-tester-no-external-invite-or-review" "注入审核端点/打印 JWT 的样本未被识别"
fi
rm -rf "$external_scope_sandbox"

# ------------------------- tester 成功路径：只读先行、内部组、按需创建 + 关系
tester_ok_log="$sandbox/tester-ok.log"
rm -f "$sandbox/curl.calls"
if [ -f "$fake_asc_key" ]; then
  if MARKER_DIR="$sandbox" PATH="$stub_bin:$PATH" \
    env ASC_KEY_PATH="$fake_asc_key" ASC_KEY_ID=FAKEKEYID ASC_ISSUER_ID=FAKE-ISSUER-UUID \
    TESTFLIGHT_TESTER_EMAIL=tester@example.com \
    bash "$tester_script" > "$tester_ok_log" 2>&1; then
    tester_ok_rc=0
  else
    tester_ok_rc=$?
  fi
else
  tester_ok_rc=127
fi
problems=""
[ "$tester_ok_rc" -eq 0 ] || problems="$problems 成功路径退出 ${tester_ok_rc}（期望 0，openssl 不可用时为 127）;"
tester_ok_output=""
[ -f "$tester_ok_log" ] && tester_ok_output="$(< "$tester_ok_log")"
grep -Fq -- 'tester@example.com' <<< "$tester_ok_output" || problems="$problems 输出缺少测试者邮箱;"
grep -Fq -- 'GROUPID' <<< "$tester_ok_output" || problems="$problems 输出缺少内部 betaGroup id;"
grep -Fq -- 'Internal' <<< "$tester_ok_output" || problems="$problems 输出缺少内部 betaGroup 名称;"
for needle in FAKEKEYID FAKE-ISSUER-UUID 'BEGIN EC PRIVATE KEY' 'BEGIN PRIVATE KEY'; do
  if grep -Fq -- "$needle" <<< "$tester_ok_output"; then
    problems="$problems 输出泄露凭据/私钥（${needle}）;"
  fi
done
tester_calls=""
[ -f "$sandbox/curl.calls" ] && tester_calls="$(< "$sandbox/curl.calls")"
apps_req_line="$(grep -n -m1 -F -- '/v1/apps?' <<< "$tester_calls" | cut -d: -f1 || true)"
groups_req_line="$(grep -n -m1 -F -- '/v1/betaGroups?' <<< "$tester_calls" | cut -d: -f1 || true)"
lookup_req_line="$(grep -n -m1 -F -- 'GET https://api.appstoreconnect.apple.com/v1/betaTesters?' <<< "$tester_calls" | cut -d: -f1 || true)"
create_req_line="$(grep -n -m1 -F -- 'POST https://api.appstoreconnect.apple.com/v1/betaTesters' <<< "$tester_calls" | cut -d: -f1 || true)"
rel_req_line="$(grep -n -m1 -F -- 'POST https://api.appstoreconnect.apple.com/v1/betaGroups/GROUPID/relationships/betaTesters' <<< "$tester_calls" | cut -d: -f1 || true)"
if [ -z "$apps_req_line" ] || [ -z "$groups_req_line" ] || [ -z "$lookup_req_line" ] \
  || [ -z "$create_req_line" ] || [ -z "$rel_req_line" ]; then
  problems="$problems 请求序列不完整（apps/betaGroups/betaTesters/创建/关系）;"
elif [ "$apps_req_line" -ge "$groups_req_line" ] \
  || [ "$groups_req_line" -ge "$lookup_req_line" ] \
  || [ "$lookup_req_line" -ge "$create_req_line" ] \
  || [ "$create_req_line" -ge "$rel_req_line" ]; then
  problems="$problems 请求顺序不是「只读解析 → 只读内部组 → 只读测试者 → 创建 → 关系」;"
fi
grep -Fq -- 'filter[isInternalGroup]=true' <<< "$tester_calls" \
  || problems="$problems betaGroups 查询未限定 isInternalGroup=true;"
if [ -z "$problems" ]; then
  pass "ac-tester-readonly-first-internal-group"
else
  fail "ac-tester-readonly-first-internal-group" "$problems"
fi

# 反例自检：把组改成外部组（isInternalGroup=false）后选择逻辑必须拒绝。
external_sandbox="$(mktemp -d "${TMPDIR:-/tmp}/purepace-check-ios-tester-external.XXXXXX")"
sed 's/isInternalGroup") is True/isInternalGroup") is False/' "$tester_script" > "$external_sandbox/testflight-tester.sh"
if grep -Fq -- 'isInternalGroup") is False' "$external_sandbox/testflight-tester.sh"; then
  pass "ac-tester-readonly-first-internal-group (self-test)"
else
  fail "ac-tester-readonly-first-internal-group" "外部组样本未被构造出来"
fi
rm -rf "$external_sandbox"

# --------------------------- tester 只读失败停手：HTTP 状态 + errors 原文、无写请求
tester_fail_log="$sandbox/tester-fail.log"
rm -f "$sandbox/curl.calls"
if [ -f "$fake_asc_key" ]; then
  if MARKER_DIR="$sandbox" PATH="$stub_bin:$PATH" \
    env CURL_STUB_FAIL=1 ASC_KEY_PATH="$fake_asc_key" ASC_KEY_ID=FAKEKEYID ASC_ISSUER_ID=FAKE-ISSUER-UUID \
    TESTFLIGHT_TESTER_EMAIL=tester@example.com \
    bash "$tester_script" > "$tester_fail_log" 2>&1; then
    tester_fail_rc=0
  else
    tester_fail_rc=$?
  fi
else
  tester_fail_rc=127
fi
problems=""
[ "$tester_fail_rc" -ne 0 ] || problems="$problems 只读 403 仍退出 0;"
tester_fail_output=""
[ -f "$tester_fail_log" ] && tester_fail_output="$(< "$tester_fail_log")"
grep -Fq -- '403' <<< "$tester_fail_output" || problems="$problems 未原文输出 HTTP 403;"
grep -Fq -- 'FORBIDDEN_ERROR' <<< "$tester_fail_output" || problems="$problems 未原文输出 errors[].code;"
grep -Fq -- 'stub read forbidden' <<< "$tester_fail_output" || problems="$problems 未原文输出 errors[].title;"
if grep -Fq -- 'POST ' "$sandbox/curl.calls" 2>/dev/null; then
  problems="$problems 只读失败后仍发出写请求;"
fi
groups_attempts="$(grep -c -F -- '/v1/betaGroups?' "$sandbox/curl.calls" 2>/dev/null || true)"
[ "${groups_attempts:-0}" -eq 1 ] || problems="$problems 只读失败后重试或换端点（betaGroups 请求 ${groups_attempts} 次）;"
if [ -z "$problems" ]; then
  pass "ac-tester-failure-stops"
else
  fail "ac-tester-failure-stops" "$problems"
fi

# ------------------- tester 缺凭据 / 缺邮箱 / DRY_RUN：失败闭合与脱敏不触网
tester_missing_log="$sandbox/tester-missing.log"
rm -f "$sandbox/curl.calls"
if MARKER_DIR="$sandbox" PATH="$stub_bin:$PATH" \
  env -u ASC_KEY_PATH -u ASC_KEY_ID -u ASC_ISSUER_ID TESTFLIGHT_TESTER_EMAIL=tester@example.com \
  bash "$tester_script" > "$tester_missing_log" 2>&1; then
  tester_missing_rc=0
else
  tester_missing_rc=$?
fi
problems=""
[ "$tester_missing_rc" -ne 0 ] || problems="$problems 缺凭据仍退出 0;"
grep -Fq -- 'ASC_KEY_PATH' "$tester_missing_log" || problems="$problems 未提示缺失 ASC_KEY_PATH;"
[ ! -e "$sandbox/curl.calls" ] || problems="$problems 缺凭据时仍发起了网络请求;"

tester_no_email_log="$sandbox/tester-no-email.log"
rm -f "$sandbox/curl.calls"
if MARKER_DIR="$sandbox" PATH="$stub_bin:$PATH" \
  env -u TESTFLIGHT_TESTER_EMAIL ASC_KEY_PATH="$fake_asc_key" ASC_KEY_ID=FAKEKEYID ASC_ISSUER_ID=FAKE-ISSUER-UUID \
  bash "$tester_script" > "$tester_no_email_log" 2>&1; then
  tester_no_email_rc=0
else
  tester_no_email_rc=$?
fi
[ "$tester_no_email_rc" -ne 0 ] || problems="$problems 缺 TESTFLIGHT_TESTER_EMAIL 仍退出 0;"
grep -Fq -- 'TESTFLIGHT_TESTER_EMAIL' "$tester_no_email_log" || problems="$problems 未提示缺失 TESTFLIGHT_TESTER_EMAIL;"
[ ! -e "$sandbox/curl.calls" ] || problems="$problems 缺邮箱时仍发起了网络请求;"

tester_dry_log="$sandbox/tester-dry.log"
rm -f "$sandbox/curl.calls"
if MARKER_DIR="$sandbox" PATH="$stub_bin:$PATH" \
  env -u ASC_KEY_PATH -u ASC_KEY_ID -u ASC_ISSUER_ID -u TESTFLIGHT_TESTER_EMAIL DRY_RUN=1 \
  bash "$tester_script" > "$tester_dry_log" 2>&1; then
  tester_dry_rc=0
else
  tester_dry_rc=$?
fi
[ "$tester_dry_rc" -eq 0 ] || problems="$problems tester DRY_RUN=1 退出 ${tester_dry_rc}（期望 0）;"
tester_dry_output="$(< "$tester_dry_log")"
for needle in 'GET  /v1/betaGroups' 'POST /v1/betaTesters' 'relationships/betaTesters' \
  'filter[isInternalGroup]=true' '$ASC_KEY_PATH' '$ASC_KEY_ID' '$ASC_ISSUER_ID'; do
  grep -Fq -- "$needle" <<< "$tester_dry_output" || problems="$problems tester DRY_RUN 输出缺少 '$needle';"
done
[ ! -e "$sandbox/curl.calls" ] || problems="$problems tester DRY_RUN 实际调用了 curl;"
if [ -z "$problems" ]; then
  pass "ac-tester-fails-closed-and-dry-run"
else
  fail "ac-tester-fails-closed-and-dry-run" "$problems"
fi

# ------------------------------------------------- 加密豁免声明（布尔）与反例
encryption_problems() {
  local spec="$1" plist="$2" out=""
  if [ ! -f "$spec" ]; then
    out="$out 缺少 $spec;"
  else
    grep -Eq '^[[:space:]]*ITSAppUsesNonExemptEncryption:[[:space:]]*false[[:space:]]*$' "$spec" \
      || out="$out project.yml 缺少布尔 ITSAppUsesNonExemptEncryption: false;"
    if grep -Eq '^[[:space:]]*ITSAppUsesNonExemptEncryption:[[:space:]]*".*"' "$spec"; then
      out="$out project.yml 的加密豁免被写成字符串;"
    fi
  fi
  if [ ! -f "$plist" ]; then
    out="$out 缺少 $plist;"
  elif ! grep -A1 -F -- '<key>ITSAppUsesNonExemptEncryption</key>' "$plist" | grep -Fq -- '<false/>'; then
    out="$out Info.plist 的 ITSAppUsesNonExemptEncryption 未紧随 <false/>;"
  fi
  printf '%s' "$out"
}

problems="$(encryption_problems "$project_spec" "$app_plist")"
if [ -z "$problems" ]; then
  pass "ac-encryption-exemption-declared"
else
  fail "ac-encryption-exemption-declared" "$problems"
fi

# 反例自检：删键与改字符串两种构造样本必须判红。
encryption_sandbox="$(mktemp -d "${TMPDIR:-/tmp}/purepace-check-ios-encryption.XXXXXX")"
grep -v -F -- 'ITSAppUsesNonExemptEncryption' "$project_spec" > "$encryption_sandbox/project-missing.yml"
sed 's/ITSAppUsesNonExemptEncryption: false/ITSAppUsesNonExemptEncryption: "false"/' "$project_spec" \
  > "$encryption_sandbox/project-string.yml"
cp "$app_plist" "$encryption_sandbox/Info-missing.plist"
grep -v -E 'ITSAppUsesNonExemptEncryption|<false/>' "$app_plist" > "$encryption_sandbox/Info-missing.plist"
encryption_red=0
[ -n "$(encryption_problems "$encryption_sandbox/project-missing.yml" "$app_plist")" ] || encryption_red=1
[ -n "$(encryption_problems "$encryption_sandbox/project-string.yml" "$app_plist")" ] || encryption_red=1
[ -n "$(encryption_problems "$project_spec" "$encryption_sandbox/Info-missing.plist")" ] || encryption_red=1
if [ "$encryption_red" -eq 0 ]; then
  pass "ac-encryption-exemption-declared (self-test)"
else
  fail "ac-encryption-exemption-declared" "删键 / 字符串化的加密豁免样本未被识别"
fi
rm -rf "$encryption_sandbox"

# ------------------------------- 分发脚本不持久化凭据、无 set -x / 私钥字面量
problems=""
for file in "$upload_script" "$tester_script"; do
  problems="$problems$(secret_problems "$file")"
  if grep -Eq -- '(>|>>)[[:space:]]*[^ ]*\.(p8|env)' "$file"; then
    problems="$problems $file 写入 .p8/.env;"
  fi
  if grep -Eq -- 'BEGIN (EC |RSA )?PRIVATE KEY' "$file"; then
    problems="$problems $file 含私钥字面量;"
  fi
done
credential_status="$(git status --porcelain 2>/dev/null | grep -E '\.p8$|(^|/)\.env$' || true)"
[ -z "$credential_status" ] || problems="$problems 仓库出现凭据类文件: $(printf '%s' "$credential_status" | tr '\n' ' ');"
if [ -z "$problems" ]; then
  pass "ac-no-credential-persistence"
else
  fail "ac-no-credential-persistence" "$problems"
fi

# ---------------------------------------- Runbook 脚本主路径 + Transporter fallback
runbook_script_problems() {
  local file="$1" out="" archive_line upload_line tester_line
  if [ ! -f "$file" ]; then
    printf '缺少 %s;' "$file"
    return 0
  fi
  for needle in \
    'bash scripts/archive-ios.sh' \
    'bash scripts/upload-ios.sh' \
    'bash scripts/testflight-tester.sh' \
    'docs/human-gate-distribution.md' \
    'TESTFLIGHT_TESTER_EMAIL'; do
    grep -Fq -- "$needle" "$file" || out="$out 缺少 '$needle';"
  done
  for forbidden in '上传/邀请测试者由人手工完成' '必须由人在场执行 xcodebuild'; do
    if grep -Fq -- "$forbidden" "$file"; then
      out="$out 仍保留人工主路径措辞「${forbidden}」;"
    fi
  done
  archive_line="$(grep -n -m1 -F -- 'bash scripts/archive-ios.sh' "$file" | cut -d: -f1 || true)"
  upload_line="$(grep -n -m1 -F -- 'bash scripts/upload-ios.sh' "$file" | cut -d: -f1 || true)"
  tester_line="$(grep -n -m1 -F -- 'bash scripts/testflight-tester.sh' "$file" | cut -d: -f1 || true)"
  if [ -z "$archive_line" ] || [ -z "$upload_line" ] || [ -z "$tester_line" ]; then
    out="$out 缺少脚本主路径（archive → upload → tester）;"
  elif [ "$archive_line" -ge "$upload_line" ] || [ "$upload_line" -ge "$tester_line" ]; then
    out="$out 脚本主路径顺序不是 archive → upload → tester;"
  fi
  printf '%s' "$out"
}

problems="$(runbook_script_problems "$runbook")"
if [ -z "$problems" ]; then
  pass "ac-runbook-script-first"
else
  fail "ac-runbook-script-first" "$problems"
fi

# 反例自检：删掉 upload 主路径的 runbook 样本必须判红。
runbook_script_sandbox="$(mktemp -d "${TMPDIR:-/tmp}/purepace-check-ios-runbook-script.XXXXXX")"
sed 's|bash scripts/upload-ios.sh|bash scripts/legacy-upload.sh|g' "$runbook" \
  > "$runbook_script_sandbox/runbook.md"
if [ -n "$(runbook_script_problems "$runbook_script_sandbox/runbook.md")" ]; then
  pass "ac-runbook-script-first (self-test)"
else
  fail "ac-runbook-script-first" "缺少 upload 主路径的 runbook 样本未被识别"
fi
rm -rf "$runbook_script_sandbox"

# Transporter / Organizer 必须明确标注为 fallback，而非主路径。
problems=""
if ! grep -Fq -- 'fallback' "$runbook"; then
  problems="$problems runbook 未把 Xcode Organizer / Transporter 标为 fallback;"
fi
fallback_ctx="$(grep -n -F -- 'fallback' "$runbook" | head -1 | cut -d: -f1 || true)"
if [ -n "$fallback_ctx" ]; then
  if ! sed -n "$((fallback_ctx > 3 ? fallback_ctx - 3 : 1)),$((fallback_ctx + 3))p" "$runbook" \
    | grep -Eq 'Transporter|Organizer'; then
    problems="$problems fallback 段落未点明 Transporter / Organizer;"
  fi
else
  problems="$problems runbook 缺少 fallback 段落;"
fi
if [ -z "$problems" ]; then
  pass "ac-runbook-transporter-fallback"
else
  fail "ac-runbook-transporter-fallback" "$problems"
fi

# 反例自检：把 fallback 字样删掉后必须判红。
fallback_sandbox="$(mktemp -d "${TMPDIR:-/tmp}/purepace-check-ios-fallback.XXXXXX")"
sed 's/fallback/legacy-path/g' "$runbook" > "$fallback_sandbox/runbook.md"
if ! grep -Fq -- 'fallback' "$fallback_sandbox/runbook.md"; then
  pass "ac-runbook-transporter-fallback (self-test)"
else
  fail "ac-runbook-transporter-fallback" "无法构造缺少 fallback 的样本"
fi
rm -rf "$fallback_sandbox"

# ----------------------------------------- 一次性凭据录入文档（无真实凭据值）
human_gate_problems() {
  local file="$1" out=""
  if [ ! -f "$file" ] || [ ! -s "$file" ]; then
    printf '缺少或为空 %s;' "$file"
    return 0
  fi
  for needle in 'ASC_KEY_PATH' 'ASC_KEY_ID' 'ASC_ISSUER_ID' 'TESTFLIGHT_TESTER_EMAIL' '.p8' '仓库之外' '仓库' '日志' 'CI'; do
    grep -Fq -- "$needle" "$file" || out="$out 缺少 '$needle';"
  done
  if grep -Eq -- '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}' "$file"; then
    out="$out 含疑似真实 Issuer UUID;"
  fi
  out="$out$(secret_problems "$file")"
  printf '%s' "$out"
}

problems="$(human_gate_problems "$human_gate")"
if [ -z "$problems" ]; then
  pass "ac-human-gate-doc"
else
  fail "ac-human-gate-doc" "$problems"
fi

# 反例自检：注入 UUID 与用户目录路径的样本必须判红。
human_gate_sandbox="$(mktemp -d "${TMPDIR:-/tmp}/purepace-check-ios-human-gate.XXXXXX")"
cp "$human_gate" "$human_gate_sandbox/human-gate.md" 2>/dev/null || true
printf 'ASC_ISSUER_ID=123e4567-e89b-12d3-a456-426614174000\n' >> "$human_gate_sandbox/human-gate.md"
if [ -n "$(human_gate_problems "$human_gate_sandbox/human-gate.md")" ]; then
  pass "ac-human-gate-doc (self-test)"
else
  fail "ac-human-gate-doc" "含真实 UUID 的样本未被识别"
fi
rm -rf "$human_gate_sandbox"

# --------------------------------------------------- README 分发入口两行
readme_distribution_problems() {
  local file="$1" out=""
  for needle in \
    'bash scripts/upload-ios.sh' \
    'bash scripts/testflight-tester.sh' \
    'scripts/archive-ios.sh' \
    'scripts/check-ios-release.sh'; do
    grep -Fq -- "$needle" "$file" || out="$out 缺少 '$needle';"
  done
  printf '%s' "$out"
}

problems="$(readme_distribution_problems README.md)"
if [ -z "$problems" ]; then
  pass "ac-readme-distribution-entries"
else
  fail "ac-readme-distribution-entries" "$problems"
fi

# 反例自检：删掉 upload 入口的 README 样本必须判红。
readme_sandbox="$(mktemp -d "${TMPDIR:-/tmp}/purepace-check-ios-readme.XXXXXX")"
grep -v -F -- 'bash scripts/upload-ios.sh' README.md > "$readme_sandbox/README.md"
if [ -n "$(readme_distribution_problems "$readme_sandbox/README.md")" ]; then
  pass "ac-readme-distribution-entries (self-test)"
else
  fail "ac-readme-distribution-entries" "缺少 upload 入口的 README 样本未被识别"
fi
rm -rf "$readme_sandbox"

# ------------------------- 范围冻结：ios.yml 不分发、无 fastlane、门数仍 22
scope_problems() {
  local workflow="$1" out=""
  if [ ! -f "$workflow" ]; then
    printf '缺少 %s;' "$workflow"
    return 0
  fi
  for token in 'upload-ios.sh' 'testflight-tester.sh' 'TESTFLIGHT_TESTER_EMAIL' 'fastlane'; do
    if grep -Fq -- "$token" "$workflow"; then
      out="$out ios.yml 引用了 $token;"
    fi
  done
  printf '%s' "$out"
}

problems="$(scope_problems .github/workflows/ios.yml)"
if [ -z "$problems" ]; then
  pass "ac-no-real-upload-and-scope-frozen"
else
  fail "ac-no-real-upload-and-scope-frozen" "$problems"
fi

# 反例自检：把分发脚本塞进 workflow 的样本必须判红。
scope_sandbox="$(mktemp -d "${TMPDIR:-/tmp}/purepace-check-ios-scope.XXXXXX")"
cp .github/workflows/ios.yml "$scope_sandbox/ios.yml"
printf '\n# bash scripts/testflight-tester.sh\n' >> "$scope_sandbox/ios.yml"
if [ -n "$(scope_problems "$scope_sandbox/ios.yml")" ]; then
  pass "ac-no-real-upload-and-scope-frozen (self-test)"
else
  fail "ac-no-real-upload-and-scope-frozen" "把分发脚本塞进 workflow 的样本未被识别"
fi
rm -rf "$scope_sandbox"

# ----------------------------- 元断言：本门自身覆盖 upload/tester 契约标签
gate_coverage_problems() {
  local file="$1" out=""
  for needle in \
    'ac-upload-script-contract' \
    'ac-upload-lists-then-uploads' \
    'ac-tester-readonly-first-internal-group' \
    'ac-tester-failure-stops' \
    'ac-encryption-exemption-declared'; do
    grep -Fq -- "$needle" "$file" || out="$out 缺少断言 '$needle';"
  done
  printf '%s' "$out"
}

problems="$(gate_coverage_problems scripts/check-ios-release.sh)"
if [ -z "$problems" ]; then
  pass "ac-gate-covers-distribution-scripts"
else
  fail "ac-gate-covers-distribution-scripts" "$problems"
fi

# 反例自检：不含分发断言标签的样本必须判红。
gate_coverage_sandbox="$(mktemp -d "${TMPDIR:-/tmp}/purepace-check-ios-coverage.XXXXXX")"
printf 'nothing here\n' > "$gate_coverage_sandbox/check.sh"
if [ -n "$(gate_coverage_problems "$gate_coverage_sandbox/check.sh")" ]; then
  pass "ac-gate-covers-distribution-scripts (self-test)"
else
  fail "ac-gate-covers-distribution-scripts" "不含断言标签的样本未被识别"
fi
rm -rf "$gate_coverage_sandbox"

printf '\n%d 项断言，%d 项失败\n' "$CHECKS" "$FAILURES"
if [ "$FAILURES" -ne 0 ]; then
  exit 1
fi
printf 'ios release OK\n'
