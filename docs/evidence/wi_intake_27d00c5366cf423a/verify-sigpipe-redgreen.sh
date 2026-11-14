#!/usr/bin/env bash
# 证据脚本：清除 scripts/check-ios-shell.sh 的 SIGPIPE 伪红（红→绿 / 仍红两向）。
#
# 只读仓：不修改工作树（唯一写入是本脚本自身目录下的日志）；无网络；幂等。
# 默认 OLD_REF=5925310 取旧形态原文；取不到时退回内联旧形态字面量（README 会注明）。
#
# 用法：
#   bash docs/evidence/wi_intake_27d00c5366cf423a/verify-sigpipe-redgreen.sh [--help]
# 退出码：0 = 全部两向判据成立；1 = 有判据不符；2 = 用法/依赖错误。
set -euo pipefail

SCRIPT_REL='scripts/check-ios-shell.sh'
OLD_REF="${OLD_REF:-5925310}"
OUT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$OUT_DIR/../../.." && pwd)"
TARGET="$REPO_ROOT/$SCRIPT_REL"

GUARD_PATTERN='(^|[^|])\|[[:space:]]*(head|grep[[:space:]]+-[^|]*[qm])'

OLD_LOG="$OUT_DIR/old-form.log"
NEW_LOG="$OUT_DIR/new-form.log"
NEG_LOG="$OUT_DIR/negative-still-red.log"
GUARD_LOG="$OUT_DIR/guard-hits.log"
SUMMARY_LOG="$OUT_DIR/summary.log"
FULL_LOG="$OUT_DIR/check-ios-shell.log"
SELF_LOG="$OUT_DIR/check-ios-shell-self-test.log"

usage() {
  cat <<'USAGE'
verify-sigpipe-redgreen.sh — check-ios-shell.sh SIGPIPE 伪红证据重跑

用法：
  bash verify-sigpipe-redgreen.sh [--help]

环境变量：
  OLD_REF  旧形态来源 commit（默认 5925310）；取不到时退回内联旧形态字面量

行为：
  1) ac-no-early-exit-consumer-pipe 守卫：当前脚本 0 命中、基线 10 命中
  2) 红→绿：基线旧形态（首行即命中 + >64 KiB 尾巴）退出 141；改后新形态退出 0
  3) 仍红：新形态喂真缺 token 的 block / sed 两切片各一正一反，断言未被写空
  4) 全量脚本与 --self-test 单跑，日志落在本目录
只读仓、无网络、幂等；产物全部写在本目录。
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    -h | --help) usage; exit 0 ;;
    *) printf '未知参数: %s（用 --help）\n' "$1" >&2; exit 2 ;;
  esac
done

for bin in git grep sed awk mktemp; do
  command -v "$bin" >/dev/null 2>&1 || { printf '缺少依赖: %s\n' "$bin" >&2; exit 2; }
done
[ -f "$TARGET" ] || { printf '缺少 %s\n' "$TARGET" >&2; exit 2; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/sigpipe-redgreen.XXXXXX")"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

FAILED=0
LAST_OUT=""
LAST_RC=0

# 跑一条命令并记录「命令 + 退出码 + 期望」，不符即判红。
run_expect() { # log, label, expected-exit, cmd...
  local log="$1" label="$2" expected="$3"; shift 3
  local rc=0
  LAST_OUT="$("$@" 2>&1)" || rc=$?
  {
    printf -- '- %s\n' "$label"
    printf '  cmd: %s\n' "$*" | sed "s|$TMP|<tmp>|g"
    printf '  exit: %s（期望 %s）\n' "$rc" "$expected"
  } >> "$log"
  if [ -n "$LAST_OUT" ]; then
    printf '  output:\n' >> "$log"
    printf '%s\n' "$LAST_OUT" | sed -e "s|$TMP|<tmp>|g" -e 's/^/    /' >> "$log"
  fi
  if [ "$rc" -ne "$expected" ]; then
    printf '  !! 退出码不符：期望 %s 实得 %s\n' "$expected" "$rc" >> "$log"
    printf 'FAIL: %s（期望 exit %s，实得 %s）\n' "$label" "$expected" "$rc" >&2
    FAILED=1
  fi
  LAST_RC="$rc"
}

# 造 block：首行即命中 `static let durationState`，后接 >64 KiB 尾巴（SIGPIPE 稳定触发面）。
make_block() { # out-file, include-token(1/0)
  local out="$1" include="$2"
  {
    if [ "$include" = 1 ]; then
      printf '    static let durationState: TimeInterval = 0.30\n'
    fi
    printf '    static let durationShort: TimeInterval = 0.20\n'
    awk 'BEGIN { for (i = 0; i < 20000; i++) printf "    // sigpipe padding line %05d eeeeeeeeeeeeeeeeeeeeeeee\n", i }'
  } > "$out"
}

# 把「取旧形态原文 + 取新形态原文」都钉死在脚本里，避免手改字形。
if git -C "$REPO_ROOT" rev-parse --verify --quiet "$OLD_REF^{commit}" >/dev/null 2>&1; then
  git -C "$REPO_ROOT" show "$OLD_REF:$SCRIPT_REL" > "$TMP/baseline.sh"
  OLD_SOURCE="commit $OLD_REF:$SCRIPT_REL"
else
  cat > "$TMP/baseline.sh" <<'INLINE'
    printf '%s\n' "$group_block" | grep -Fq "static let $member" \
      || problems="$problems Token 缺少 $group.$member;"
INLINE
  OLD_SOURCE="内联旧形态字面量（$OLD_REF 不可读，README 已注明）"
fi

old_start="$(grep -nF 'grep -Fq "static let $member"' "$TMP/baseline.sh" | sed -n '1s/:.*//p')"
new_start="$(grep -nF 'grep -Fq "static let $member"' "$TARGET" | sed -n '1s/:.*//p')"
[ -n "$old_start" ] && [ -n "$new_start" ] || {
  printf '未定位到 token here-string / 旧管道行\n' >&2
  exit 1
}

build_probe() { # out-file, src-file, start
  local out="$1" src="$2" start="$3"
  {
    printf 'set -euo pipefail\n'
    printf 'problems=""\n'
    printf 'group=Motion\n'
    printf 'member=durationState\n'
    printf 'group_block="$(cat "$1")"\n'
    sed -n "${start},$((start + 1))p" "$src"
    printf 'printf "problems=[%%s]\\n" "$problems"\n'
  } > "$out"
}

build_bare() { # out-file, src-file, line
  local out="$1" src="$2" line="$3"
  {
    printf 'set -euo pipefail\n'
    printf 'group=Motion\n'
    printf 'member=durationState\n'
    printf 'group_block="$(cat "$1")"\n'
    sed -n "${line}p" "$src"
  } > "$out"
}

make_block "$TMP/block-hit.txt" 1
make_block "$TMP/block-miss.txt" 0

: > "$OLD_LOG"
: > "$NEW_LOG"
: > "$NEG_LOG"
: > "$GUARD_LOG"
: > "$SUMMARY_LOG"

# ---------------------------------------------------------------- 1) 守卫
{
  printf '== ac-no-early-exit-consumer-pipe ==\n'
  printf 'pattern: %s\n' "$GUARD_PATTERN"
  printf '旧形态真源: %s\n' "$OLD_SOURCE"
} > "$GUARD_LOG"

guard_current="$(grep -nE "$GUARD_PATTERN" "$TARGET" | sed -E 's/^[0-9]+://' | grep -vcE '^[[:space:]]*#' || true)"
guard_baseline="$(grep -nE "$GUARD_PATTERN" "$TMP/baseline.sh" | sed -E 's/^[0-9]+://' | grep -vcE '^[[:space:]]*#' || true)"
{
  printf '当前 %s 命中数（剔除注释行）: %s（期望 0）\n' "$SCRIPT_REL" "$guard_current"
  printf '基线命中数（剔除注释行）: %s（期望 10）\n' "$guard_baseline"
  printf '基线命中行（文件:行 → 现形态）：\n'
  grep -nE "$GUARD_PATTERN" "$TMP/baseline.sh" | sed 's/^/  /'
} >> "$GUARD_LOG"
if [ "$guard_current" -ne 0 ] || [ "$guard_baseline" -ne 10 ]; then
  printf 'FAIL: 守卫命中数 a=%s b=%s（期望 0 / 10）\n' "$guard_current" "$guard_baseline" >&2
  FAILED=1
fi
printf 'guard: current=%s baseline=%s\n' "$guard_current" "$guard_baseline" >> "$SUMMARY_LOG"

# ------------------------------------------------------- 2) 红→绿（旧 → 新）
{
  printf '== 旧形态（%s）==\n' "$OLD_SOURCE"
  printf 'block: %s 字节，首行即命中，尾巴 >64 KiB\n' "$(wc -c < "$TMP/block-hit.txt" | tr -d ' ')"
  printf '旧形态首行（逐字来源）：\n'
  sed -n "${old_start}p" "$TMP/baseline.sh" | sed 's/^/  /'
  printf '旧形态两行（逐字来源）：\n'
  sed -n "${old_start},$((old_start + 1))p" "$TMP/baseline.sh" | sed 's/^/  /'
  printf '(单跑管道时仅去掉行尾续行符 `\`，其余字形逐字不变)\n'
} > "$OLD_LOG"

build_bare "$TMP/old_bare.sh" "$TMP/baseline.sh" "$old_start"
run_expect "$OLD_LOG" '旧形态单跑管道（pipefail 下 printf 收 SIGPIPE）' 141 bash "$TMP/old_bare.sh" "$TMP/block-hit.txt"
old_pipe_rc="$LAST_RC"

build_probe "$TMP/old_pair.sh" "$TMP/baseline.sh" "$old_start"
run_expect "$OLD_LOG" '旧形态两行（|| problems=）→ token 明明存在却写缺项（假红）' 0 bash "$TMP/old_pair.sh" "$TMP/block-hit.txt"
old_pair_out="$LAST_OUT"
case "$old_pair_out" in
  *'Token 缺少 Motion.durationState'*) printf '  假红判定文案：%s\n' "$old_pair_out" >> "$OLD_LOG" ;;
  *)
    printf '  !! 旧形态未复现假红（block 未触发 SIGPIPE？）\n' >> "$OLD_LOG"
    printf 'FAIL: 旧形态未复现假红\n' >&2
    FAILED=1
    ;;
esac
printf 'old-form: pipe_exit=%s pair_exit=0 pair_out=%s\n' "$old_pipe_rc" "$old_pair_out" >> "$SUMMARY_LOG"

{
  printf '== 新形态（%s 当前 :%s）==\n' "$SCRIPT_REL" "$new_start"
  printf '新形态两行（逐字来源）：\n'
  sed -n "${new_start},$((new_start + 1))p" "$TARGET" | sed 's/^/  /'
  printf 'here-string 形态自检：\n'
} > "$NEW_LOG"
for needle in \
  'grep -Fq "static let $member" <<< "$group_block"' \
  "grep -Fq 'supportsDarkMode = true' <<< \"\$appearance_block\"" \
  'Token 缺少 $group.$member;' \
  'Appearance.supportsDarkMode 必须为 true;'; do
  if grep -Fq "$needle" "$TARGET"; then
    printf '  [ok] %s\n' "$needle" >> "$NEW_LOG"
  else
    printf '  [missing] %s\n' "$needle" >> "$NEW_LOG"
    printf 'FAIL: 缺 %s\n' "$needle" >&2
    FAILED=1
  fi
done

build_bare "$TMP/new_bare.sh" "$TARGET" "$new_start"
run_expect "$NEW_LOG" '新形态单跑（here-string，无 SIGPIPE 面）' 0 bash "$TMP/new_bare.sh" "$TMP/block-hit.txt"
new_pipe_rc="$LAST_RC"

build_probe "$TMP/new_pair.sh" "$TARGET" "$new_start"
run_expect "$NEW_LOG" '新形态两行（同一 block）→ 无缺项（绿）' 0 bash "$TMP/new_pair.sh" "$TMP/block-hit.txt"
new_pair_out="$LAST_OUT"
case "$new_pair_out" in
  'problems=[]') ;;
  *)
    printf '  !! 新形态在命中 block 上留下判定：%s\n' "$new_pair_out" >> "$NEW_LOG"
    printf 'FAIL: 新形态误判 %s\n' "$new_pair_out" >&2
    FAILED=1
    ;;
esac
printf 'new-form: pipe_exit=%s pair_out=%s\n' "$new_pipe_rc" "$new_pair_out" >> "$SUMMARY_LOG"

# ------------------------------------------------------------- 3) 仍红判据
{
  printf '== 新形态喂真缺 token 的 block（删掉 static let durationState）==\n'
} > "$NEG_LOG"

build_bare "$TMP/new_bare_miss.sh" "$TARGET" "$new_start"
run_expect "$NEG_LOG" '新形态单跑（缺 token）→ 非 0（1）' 1 bash "$TMP/new_bare_miss.sh" "$TMP/block-miss.txt"
neg_bare_rc="$LAST_RC"

build_probe "$TMP/new_pair_miss.sh" "$TARGET" "$new_start"
run_expect "$NEG_LOG" '新形态两行（缺 token）→ 打印缺项判定' 0 bash "$TMP/new_pair_miss.sh" "$TMP/block-miss.txt"
neg_out="$LAST_OUT"
case "$neg_out" in
  *'Token 缺少 Motion.durationState'*) printf '  缺项判定文案：%s\n' "$neg_out" >> "$NEG_LOG" ;;
  *)
    printf '  !! 缺 token 未判红：%s\n' "$neg_out" >> "$NEG_LOG"
    printf 'FAIL: 缺 token 未判红\n' >&2
    FAILED=1
    ;;
esac
printf 'negative-token: bare_exit=%s pair_out=%s\n' "$neg_bare_rc" "$neg_out" >> "$SUMMARY_LOG"

# sed 切片一：可读 label（函数体逐字抽取后对合成 root 实跑）
fn_start="$(grep -nF 'identifier_has_readable_label() {' "$TARGET" | sed -n '1s/:.*//p')"
fn_end="$(awk -v s="$fn_start" 'NR > s && $0 == "}" { print NR; exit }' "$TARGET")"
[ -n "$fn_start" ] && [ -n "$fn_end" ] || { printf '未定位 identifier_has_readable_label\n' >&2; exit 1; }
eval "$(sed -n "${fn_start},${fn_end}p" "$TARGET")"

mkdir -p "$TMP/root-pos/ios/PurePace" "$TMP/root-neg/ios/PurePace"
cat > "$TMP/root-pos/ios/PurePace/Probe.swift" <<'SWIFT'
struct ProbeView: View {
    var body: some View {
        Text("probe").accessibilityIdentifier("run.probe")
            .accessibilityLabel(Text(L10n.runTitle))
    }
}
SWIFT
cat > "$TMP/root-neg/ios/PurePace/Probe.swift" <<'SWIFT'
struct ProbeView: View {
    var body: some View {
        Text("probe").accessibilityIdentifier("run.probe")
            .accessibilityLabel(Text("probe"))
    }
}
SWIFT
{
  printf '== sed 切片一：identifier_has_readable_label（%s:%s-%s 逐字抽取）==\n' "$SCRIPT_REL" "$fn_start" "$fn_end"
} >> "$NEG_LOG"
run_expect "$NEG_LOG" '正例：±4 行内有 L10n 可读 label → 0' 0 identifier_has_readable_label "$TMP/root-pos" run.probe
run_expect "$NEG_LOG" '反例：同窗口无 L10n 键 → 1（断言未写空）' 1 identifier_has_readable_label "$TMP/root-neg" run.probe
printf 'negative-label: pos=0 neg=1\n' >> "$SUMMARY_LOG"

# sed 切片二：onMapCameraChange 回写（块逐字抽取，喂真实文件与注入副本）
cam_start="$(grep -nF 'camera_window="$(sed -n' "$TARGET" | sed -n '1s/:.*//p')"
cam_end="$(awk -v s="$cam_start" 'NR > s && $0 == "  fi" { print NR; exit }' "$TARGET")"
[ -n "$cam_start" ] && [ -n "$cam_end" ] || { printf '未定位 camera_window 块\n' >&2; exit 1; }
{
  printf 'set -euo pipefail\n'
  printf 'problems=""\n'
  printf 'map_shell="$1"\n'
  sed -n "${cam_start},${cam_end}p" "$TARGET"
  printf 'printf "problems=[%%s]\\n" "$problems"\n'
} > "$TMP/cam_probe.sh"

MAP_SHELL="$REPO_ROOT/ios/PurePace/Track/TrackMapView.swift"
[ -f "$MAP_SHELL" ] || { printf '缺少 ios/PurePace/Track/TrackMapView.swift\n' >&2; exit 2; }
cp "$MAP_SHELL" "$TMP/TrackMapView.injected.swift"
cat >> "$TMP/TrackMapView.injected.swift" <<'SWIFT'

        .onMapCameraChange { context in
            cameraPosition = context.region.center
        }
SWIFT
{
  printf '== sed 切片二：onMapCameraChange 回写检查（%s:%s-%s 逐字抽取）==\n' "$SCRIPT_REL" "$cam_start" "$cam_end"
  printf '块内 sed 窗口：%s\n' "$(sed -n "${cam_start}p" "$TARGET" | sed 's/^  //')"
} >> "$NEG_LOG"
run_expect "$NEG_LOG" '反例：真实 TrackMapView.swift → 无回写（problems 空）' 0 bash "$TMP/cam_probe.sh" "$MAP_SHELL"
real_cam_out="$LAST_OUT"
run_expect "$NEG_LOG" '正例：注入 cameraPosition = 的副本 → 有回写（problems 非空）' 0 bash "$TMP/cam_probe.sh" "$TMP/TrackMapView.injected.swift"
inj_cam_out="$LAST_OUT"
case "$real_cam_out" in
  'problems=[]') ;;
  *)
    printf '  !! 真实文件被误判为有回写：%s\n' "$real_cam_out" >> "$NEG_LOG"
    printf 'FAIL: 真实 TrackMapView 误判 %s\n' "$real_cam_out" >&2
    FAILED=1
    ;;
esac
case "$inj_cam_out" in
  *'cameraPosition'*) ;;
  *)
    printf '  !! 注入 cameraPosition = 未被判出\n' >> "$NEG_LOG"
    printf 'FAIL: 注入回写未判出 %s\n' "$inj_cam_out" >&2
    FAILED=1
    ;;
esac
printf 'negative-camera: real=%s injected=%s\n' "$real_cam_out" "$inj_cam_out" >> "$SUMMARY_LOG"

# ------------------------------------------- 4) 全量脚本 / --self-test 显式单跑
full_rc=0
( cd "$REPO_ROOT" && bash scripts/check-ios-shell.sh ) > "$FULL_LOG" 2>&1 || full_rc=$?
self_rc=0
( cd "$REPO_ROOT" && bash scripts/check-ios-shell.sh --self-test ) > "$SELF_LOG" 2>&1 || self_rc=$?

full_pass="$(grep -c '^\[PASS\]' "$FULL_LOG" || true)"
full_fail="$(grep -c '^\[FAIL\]' "$FULL_LOG" || true)"
full_assert="$(sed -n 's/^\([0-9][0-9]*\) 项断言，\([0-9][0-9]*\) 项失败$/\1 \2/p' "$FULL_LOG" | sed -n '1p')"
self_assert="$(sed -n 's/^\([0-9][0-9]*\) 项断言，\([0-9][0-9]*\) 项失败$/\1 \2/p' "$SELF_LOG" | sed -n '1p')"

{
  printf 'check-ios-shell.sh: exit=%s [PASS]=%s [FAIL]=%s 断言=%s\n' "$full_rc" "$full_pass" "$full_fail" "${full_assert:-未解析}"
  printf 'check-ios-shell.sh --self-test: exit=%s 断言=%s 末行=%s\n' "$self_rc" "${self_assert:-未解析}" "$(sed -n '$p' "$SELF_LOG")"
} >> "$SUMMARY_LOG"

[ "$full_rc" -eq 0 ] || { printf 'FAIL: 全量脚本 exit %s\n' "$full_rc" >&2; FAILED=1; }
[ "$full_fail" -eq 0 ] || { printf 'FAIL: 全量脚本 [FAIL] %s 项\n' "$full_fail" >&2; FAILED=1; }
[ "$full_pass" -ge 32 ] || { printf 'FAIL: 全量断言数 %s < 32\n' "$full_pass" >&2; FAILED=1; }
grep -Fq '[PASS] ac-design-tokens' "$FULL_LOG" || { printf 'FAIL: 缺 [PASS] ac-design-tokens\n' >&2; FAILED=1; }
grep -Fq 'ios shell OK' "$FULL_LOG" || { printf 'FAIL: 缺 ios shell OK\n' >&2; FAILED=1; }

[ "$self_rc" -eq 0 ] || { printf 'FAIL: --self-test exit %s\n' "$self_rc" >&2; FAILED=1; }
grep -Fq 'self-test OK' "$SELF_LOG" || { printf 'FAIL: 缺 self-test OK\n' >&2; FAILED=1; }
[ "$(sed -n '$p' "$SELF_LOG")" = 'self-test OK' ] || { printf 'FAIL: --self-test 末行非 self-test OK\n' >&2; FAILED=1; }

printf '\n== summary ==\n'
cat "$SUMMARY_LOG"
if [ "$FAILED" -ne 0 ]; then
  printf 'evidence: FAIL（见 %s）\n' "$OUT_DIR" >&2
  exit 1
fi
printf 'evidence: OK（两向判据全部成立）\n'
