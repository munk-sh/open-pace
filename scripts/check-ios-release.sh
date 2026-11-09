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
  - .munk/code-gates.json 含 lint-ios-release 门且总门数为 24
  - scripts/check-ios-scripts.sh 门数断言同步为 24
  - docs/release/testflight-runbook.md 前置/执行/证据/反范围齐全且只用占位符

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
  elif ! printf '%s' "$help_out" | grep -Fq -- "用法"; then
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
printf '%s\n' 'set -x' '# /Users/someone/AuthKey.p8' >> "$secret_sandbox/archive-ios.sh"
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
  printf '%s' "$dry_output" | grep -Fq -- "$needle" || problems="$problems 输出缺少 '$needle';"
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
  if ! grep -A1 -F -- '<key>uploadSymbols</key>' "$export_options" | grep -Fq -- '<false/>'; then
    problems="$problems uploadSymbols 不是 false;"
  fi
  if command -v plutil >/dev/null 2>&1; then
    plutil -lint "$export_options" >/dev/null 2>&1 || problems="$problems ExportOptions.plist 不是合法 plist;"
  fi
fi
if printf '%s' "$dry_output" | grep -Fq -- "-exportArchive" \
  && printf '%s' "$dry_output" | grep -Fq -- "-exportOptionsPlist"; then
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
    printf '%s' "$output" | grep -Fq -- "$needle" || out="$out 输出缺少 $needle;"
  done
  for needle in '$ASC_KEY_PATH' '$ASC_KEY_ID' '$ASC_ISSUER_ID'; do
    printf '%s' "$output" | grep -Fq -- "$needle" || out="$out 输出缺少占位符 $needle;"
  done
  for needle in FAKEKEYID FAKE-ISSUER-UUID FAKE-KEY.p8; do
    if printf '%s' "$output" | grep -Fq -- "$needle"; then
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
printf '%s' "$missing_output" | grep -Fq -- "ASC_KEY_PATH" || problems="$problems 未提示缺失 ASC_KEY_PATH;"
printf '%s' "$missing_output" | grep -Fq -- "ASC_ISSUER_ID" || problems="$problems 未提示缺失 ASC_ISSUER_ID;"
if printf '%s' "$missing_output" | grep -Fq -- "SECRETID"; then
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

# ---------------------------------------- 门禁接入 + 门数 24 + 断言同步
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
if len(gates) != 24:
    raise SystemExit("code-gates 门数 %d（期望 24）" % len(gates))
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
grep -Fq -- '保持 24 门' scripts/check-ios-scripts.sh \
  || problems="$problems scripts/check-ios-scripts.sh 未同步「保持 24 门」;"
grep -Fq -- '-ne 24' scripts/check-ios-scripts.sh \
  || problems="$problems scripts/check-ios-scripts.sh 未同步 -ne 24 断言;"
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

printf '\n%d 项断言，%d 项失败\n' "$CHECKS" "$FAILURES"
if [ "$FAILURES" -ne 0 ]; then
  exit 1
fi
printf 'ios release OK\n'
