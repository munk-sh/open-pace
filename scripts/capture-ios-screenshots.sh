#!/usr/bin/env bash
# 界面证据采集：六屏 × 浅/深 + 结束态丢弃确认层共 14 张实取截图、六棵可及树、AX5 最大字号档实拍与布局实测。
#
# 只产证据，不改产品行为：
#   - 14 张 PNG 由 `ScreenshotEvidenceUITests` 在模拟器内 `XCUIScreen.main.screenshot()`
#     取图（`XCTAttachment` → `xcresulttool export attachments` 直接写入 docs/screenshots/），
#     不裁切、不改色、不再编码，也不做导出后改名（附件名即最终文件名）；
#   - 取图前先断言 `run.mapPreview` 在窗内与六屏 zh-Hans 文案，断言红则不产图；
#   - 可及树来自 `EvidenceCaptureUITests`（真实「开始 → 跑步中 → 结束 → 保存」链路，
#     不使用 `-screenshotHistoryDemo`，历史数据来自容器内真实归档）；
#   - 同一台模拟器、同一 runtime，UDID 由参数固定并写入所有命令。
set -euo pipefail

usage() {
  cat <<'EOF'
用法: scripts/capture-ios-screenshots.sh [--udid <udid>] [--stage <stage>]

在指定的一台模拟器上重出界面证据（14 张浅/深截图、可及树、AX5 实测）。

阶段:
  trees        运行 EvidenceCaptureUITests/testEvidenceTreesAndRealArchive：
               真实落盘一次跑次归档，并把六棵可及树导出到 docs/evidence/a11y/
  screenshots  依次设 light / dark 外观并各调起
               ScreenshotEvidenceUITests/testEvidenceScreensLight|Dark：
               7 张 × 2 = 14 张 PNG 直接导出到 docs/screenshots/（浅色 `<screen>.png`、
               深色 `<screen>-dark.png`），随后重写该目录 SHA256SUMS 并登记构建 head sha
  ax5          系统字号设为 accessibility-extra-extra-extra-large：
               导出四棵实测树与四张实拍图到 docs/evidence/evidence-freeze/ax5/，
               结束后还原原字号
  verify       只读校验已入库证据（14 张命名齐备、SHA 清单 14 行且 shasum -c 通过、
               旧 sha 零复用、可及树 6 棵、AX5 4+4、README 必填项）
  all          依次执行 trees → screenshots → ax5（默认）

选项:
  --udid <udid>  目标模拟器 UDID（默认 iPhone 16 / iOS 18.6 的固定 UDID）
  --stage <s>    见上（默认 all）
  -h, --help     显示本帮助并退出 0

环境变量:
  CAPTURE_ALLOW_DIRTY=1  允许在非 clean 工作树采集（仅本地调试；证据不入库）

前置: 已有 `xcodebuild build-for-testing` 产物（.build/ios），且归档已由 trees 阶段产生。
退出码: 0 成功；1 采集/校验失败；2 参数非法
EOF
}

udid="B3F00298-E08A-41E0-876E-6E8A75C730FD"
stage="all"

while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --udid)
      [ "$#" -ge 2 ] || { echo "capture-ios-screenshots: --udid 缺少取值" >&2; exit 2; }
      udid="$2"
      shift 2
      ;;
    --stage)
      [ "$#" -ge 2 ] || { echo "capture-ios-screenshots: --stage 缺少取值" >&2; exit 2; }
      stage="$2"
      shift 2
      ;;
    *)
      echo "capture-ios-screenshots: 未知参数 '$1'（使用 --help 查看用法）" >&2
      exit 2
      ;;
  esac
done

case "$stage" in
  trees|screenshots|ax5|verify|all) ;;
  *)
    echo "capture-ios-screenshots: 未知阶段 '$stage'（使用 --help 查看用法）" >&2
    exit 2
    ;;
esac

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
cd "$repo_root"

bundle_id="sh.munk.purepace"
scheme="PurePace"
project="ios/PurePace.xcodeproj"
derived=".build/ios"
work_dir=".build/evidence"
archive_snapshot="$work_dir/archive-snapshot"
shots_dir="docs/screenshots"
a11y_dir="docs/evidence/a11y"
ax5_dir="docs/evidence/evidence-freeze/ax5"
refresh_dir="docs/evidence/screenshot-refresh"
refresh_staging="$work_dir/screenshot-refresh"

# 本批 14 张：6 屏 × 浅/深 + 结束态丢弃确认层 浅/深（ac-screenshot-set-14）。
# 浅色附件名即 `<base>`，深色为 `<base>-dark`（导出时不做改名）。
screenshot_bases=(
  run-not-started run-running run-finished discard-confirmation
  history-list history-detail settings
)
screenshot_screens=(
  run-not-started run-running run-finished
  history-list history-detail settings
)

# 本批之前一轮（cbebc19 批次）的 14 个旧 sha，取自刷新前的 docs/screenshots/SHA256SUMS。
# verify 阶段逐张比对：新 14 张不得与其中任何一个相同（ac-no-reuse-prev-batch）。
old_shot_shas=(
  1b62989ebe29f070a873e4c67815acaeaf9a5ba38b7594aab884ec8285621aae
  448eb7c933ed820daa0b415a55bd2cff5586ba4a8fc3be0b01a172906845b67d
  261a9c594245b1534dfcc634bc22fe0146823554528f6f6cc89a5ed310a67c17
  65dca19d8b8e503f83f0f8b40a10ad22b5d03ab7410eb58f5b74fe8134502a9a
  adf7fee347e72a9205ebfb653886dae1c02dcc5b20ff92557a3f14228702085b
  80028ad0e7d6e99005943d2e77906def51568b165fff8447aaa06f4a338d83b9
  c5f31dad9f5f37bd96143ca1239a8fc8c330ebdbc614a41a9d42101436a681e9
  c10554ea187349b2c48c49d0081d5a2120ec2bf5f9bf63d37338c408e4652677
  07b5b175c8b5c760515218bd0b7b99611a40886123b7281537801233cbd3f803
  af06a2bc504b70b0396921c6c3b7cf682b51f93632cf8296e39601de5f205fd0
  143896f88c14477d259d0c0412fa59624cfe7274a264f43cc7411a62abb69074
  f9f38251c7bb3b2aa3648d07caf56754a73882242dcd841e73a472c7e97d3b66
  3be45b5ba7446c14e950ec6e2df37c041d6d36f7b8d6b90c19b5b2d09b1d8910
  bb604f077c0631b460c0355fa726933a15e4121d2c03562be0c44eb1063692ae
)

mkdir -p "$work_dir" "$shots_dir" "$a11y_dir" "$ax5_dir" "$refresh_staging"
capture_log="$refresh_staging/capture.log"
: >"$capture_log"

# 构建基线在任何阶段写文件之前取：trees 会重写 docs/evidence/a11y，之后 git status 不再干净。
capture_head_sha="$(git rev-parse HEAD)"
capture_tree_sha="$(git rev-parse HEAD^{tree})"
capture_worktree_status="$(git status --porcelain)"

say() {
  printf '%s\n' "$*"
  printf '%s\n' "$*" >>"$capture_log"
}
fail() {
  printf 'capture-ios-screenshots: %s\n' "$*" >&2
  printf 'capture-ios-screenshots: %s\n' "$*" >>"$capture_log"
  exit 1
}

# ------------------------------------------------ 设备与进程

boot_device() {
  xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1 || {
    xcrun simctl boot "$udid" >/dev/null 2>&1 || true
    xcrun simctl bootstatus "$udid" -b >/dev/null
  }
}

app_container() {
  xcrun simctl get_app_container "$udid" "$bundle_id" data 2>/dev/null
}

clear_checkpoint() {
  local container
  container="$(app_container)" || return 0
  # 只清理中断态 checkpoint（Library/Caches/active-run.jsonl），不触碰 Documents/Runs 归档。
  if [ -f "$container/Library/Caches/active-run.jsonl" ]; then
    rm "$container/Library/Caches/active-run.jsonl"
    say "info: 已清理中断态 checkpoint"
  fi
}

set_appearance() {
  xcrun simctl ui "$udid" appearance "$1" >/dev/null
}

launch_app() {
  xcrun simctl terminate "$udid" "$bundle_id" >/dev/null 2>&1 || true
  xcrun simctl launch "$udid" "$bundle_id" "$@" >/dev/null
}

shot() {
  local name="$1"
  xcrun simctl io "$udid" screenshot "$shots_dir/$name.png" >/dev/null
  local size
  size="$(sips -g pixelWidth -g pixelHeight "$shots_dir/$name.png" | awk '/pixelWidth|pixelHeight/{printf "%s ", $2}')"
  say "shot: docs/screenshots/$name.png（${size}px）"
}

# ------------------------------------------------ 截图导出

# 把 `ScreenshotEvidenceUITests` 的 PNG 附件按附件名直接落到 docs/screenshots/：
# 附件名即最终文件名（浅色 `<screen>` / 深色 `<screen>-dark`），导出过程不裁切、不再编码、不改名。
export_shots() { # <xcresult> <name>...
  local bundle="$1"
  shift
  local att_dir
  att_dir="$(mktemp -d "$work_dir/shots-XXXXXX")"
  xcrun xcresulttool export attachments --path "$bundle" --output-path "$att_dir" >/dev/null
  python3 - "$att_dir" "$shots_dir" "$@" <<'PY'
import json
import os
import shutil
import sys

att_dir, out_dir = sys.argv[1], sys.argv[2]
expected = sys.argv[3:]
with open(os.path.join(att_dir, "manifest.json"), "r", encoding="utf-8") as handle:
    manifest = json.load(handle)

available = []
for test in manifest if isinstance(manifest, list) else []:
    for attachment in test.get("attachments", []) or []:
        exported = attachment.get("exportedFileName")
        suggested = attachment.get("suggestedHumanReadableName") or ""
        if exported and suggested.endswith(".png"):
            available.append((suggested, exported))

os.makedirs(out_dir, exist_ok=True)
missing = []
for name in expected:
    match = None
    for suggested, exported in available:
        if suggested == name + ".png" or suggested.startswith(name + "_"):
            match = exported
            break
    if not match:
        missing.append(name)
        continue
    shutil.copyfile(os.path.join(att_dir, match), os.path.join(out_dir, name + ".png"))
    print("shot: %s/%s.png" % (out_dir, name))
if missing:
    print("missing attachments: %s" % ", ".join(missing), file=sys.stderr)
    sys.exit(1)
PY

  # 逐张登记导出结果（ac-screenshot-set-14：capture.log 14 条 shot 行 + 像素尺寸）。
  local name size
  for name in "$@"; do
    [ -f "$shots_dir/$name.png" ] || continue
    size="$(sips -g pixelWidth -g pixelHeight "$shots_dir/$name.png" \
      | awk '/pixelWidth|pixelHeight/{printf "%s ", $2}')"
    say "shot: docs/screenshots/$name.png（${size}px）"
  done
}

# ------------------------------------------------ 可及树导出

export_trees() { # <xcresult> <out_dir> <name>...
  local bundle="$1"
  local out_dir="$2"
  shift 2
  local att_dir
  att_dir="$(mktemp -d "$work_dir/att-XXXXXX")"
  xcrun xcresulttool export attachments --path "$bundle" --output-path "$att_dir" >/dev/null
  python3 - "$att_dir" "$out_dir" "$@" <<'PY'
import json
import os
import shutil
import sys

att_dir, out_dir = sys.argv[1], sys.argv[2]
expected = sys.argv[3:]
with open(os.path.join(att_dir, "manifest.json"), "r", encoding="utf-8") as handle:
    manifest = json.load(handle)

available = []
for test in manifest if isinstance(manifest, list) else []:
    for attachment in test.get("attachments", []) or []:
        exported = attachment.get("exportedFileName")
        suggested = attachment.get("suggestedHumanReadableName") or ""
        if exported and suggested.endswith(".txt"):
            available.append((suggested, exported))

os.makedirs(out_dir, exist_ok=True)
missing = []
for name in expected:
    match = None
    for suggested, exported in available:
        if suggested == name or suggested.startswith(name + "_"):
            match = exported
            break
    if not match:
        missing.append(name)
        continue
    shutil.copyfile(os.path.join(att_dir, match), os.path.join(out_dir, name + ".txt"))
    print("tree: %s/%s.txt" % (out_dir, name))
if missing:
    print("missing attachments: %s" % ", ".join(missing), file=sys.stderr)
    sys.exit(1)
PY
}

run_ui_test() { # <method> <result_bundle>
  local method="$1"
  local bundle="$2"
  xcodebuild test-without-building \
    -project "$project" \
    -scheme "$scheme" \
    -destination "platform=iOS Simulator,id=$udid" \
    -derivedDataPath "$derived" \
    -only-testing:"PurePaceUITests/EvidenceCaptureUITests/$method" \
    -resultBundlePath "$bundle" \
    CODE_SIGNING_ALLOWED=NO
}

# ------------------------------------------------ SHA256SUMS

write_sha256sums() { # <构建 head sha> <构建 tree sha>
  local head_sha="${1:-unknown}"
  local tree_sha="${2:-unknown}"
  local file="$shots_dir/SHA256SUMS"
  local tmp="$file.tmp"
  {
    echo "# PurePace 界面截图校验清单（docs/screenshots/）"
    echo "#"
    echo "# 校验（在仓库根执行）：shasum -a 256 -c docs/screenshots/SHA256SUMS"
    echo "# 生成（在仓库根执行）：shasum -a 256 docs/screenshots/*.png"
    echo "#"
    echo "# 构建 head sha（本批 14 张均由该 commit 的构建产出，实取 git rev-parse HEAD）：${head_sha}"
    echo "# 构建 tree sha（实取 git rev-parse HEAD^{tree}）：${tree_sha}"
    echo "# 采集时 HEAD（实取 git rev-parse HEAD，采集阶段工作树零 diff）：$(git rev-parse HEAD)"
    echo "# 归属 workItem：wi_intake_a7e3a95c0d6f61bb（V1.2 配色终版：accent #FF6B00 / danger #F53A48）"
    echo "# 除色 token 外零布局 diff：本批仅色 token 与派生证据变化，无布局/间距/字号/圆角改动。"
    echo "# 逐图断言 / 旧新 sha 对照 / 并排对照 / 日志：docs/evidence/screenshot-refresh/README.md"
    echo "# 浅/深并排对照（7 张）：docs/screenshots/side-by-side/ 及其 SHA256SUMS"
    echo "#"
    echo "# 新增或替换截图后必须同步更新本文件：sha256 与最近改动 commit 全 sha 一律实取，不许猜。"
    echo "#"
  } >"$tmp"
  shasum -a 256 "$shots_dir"/*.png >>"$tmp"
  mv "$tmp" "$file"
  say "info: 已重写 ${file}（14 张 PNG + 构建 head sha ${head_sha} / tree sha ${tree_sha}）"
}

# ------------------------------------------------ 阶段：六屏可及树 + 真实归档

stage_trees() {
  say "== trees: EvidenceCaptureUITests/testEvidenceTreesAndRealArchive（UDID ${udid}）"
  boot_device
  # 空容器起步，保证归档里只有本次真实链路产生的跑次。
  xcrun simctl uninstall "$udid" "$bundle_id" >/dev/null 2>&1 || true
  local bundle="$work_dir/trees-$(date +%Y%m%d%H%M%S).xcresult"
  run_ui_test testEvidenceTreesAndRealArchive "$bundle"
  export_trees "$bundle" "$a11y_dir" \
    01-run-not-started 02-run-running 03-run-finished \
    04-history-list 05-history-detail 06-settings
  xcrun simctl privacy "$udid" grant location-always "$bundle_id" >/dev/null 2>&1 || true
  local container
  container="$(app_container)" || fail "未找到 App 容器"
  say "archive: $container/Documents/Runs"
  ls -l "$container/Documents/Runs"
  snapshot_archive
}

# ------------------------------------------------ 阶段：12 张浅/深截图

require_archive() {
  local container
  container="$(app_container)" || fail "App 未安装，先跑 trees 阶段"
  [ -d "$container/Documents/Runs" ] || fail "容器内无 Documents/Runs，先跑 trees 阶段产生真实归档"
  local count
  count="$(find "$container/Documents/Runs" -type f | wc -l | tr -d ' ')"
  [ "$count" -ge 1 ] || fail "容器内归档为空，先跑 trees 阶段"
  say "info: 复用真实归档 $container/Documents/Runs（$count 个文件）"
}

# UI 用例重新安装 App 会换掉数据容器，故把 trees 阶段产出的真实归档先快照、再按需还原；
# 还原的仍是同一份归档文件（同名同内容），不产生第二条跑次。
snapshot_archive() {
  local container
  container="$(app_container)" || fail "未找到 App 容器"
  [ -d "$container/Documents/Runs" ] || fail "容器内无 Documents/Runs"
  # 快照必须只含本次真实链路产生的归档：先清空上次残留，避免旧跑次混进截图/树。
  rm -rf "$archive_snapshot"
  mkdir -p "$archive_snapshot"
  cp -R "$container/Documents/Runs/." "$archive_snapshot/"
  say "snapshot: ${archive_snapshot}（$(find "$archive_snapshot" -type f | wc -l | tr -d ' ') 个文件）"
}

restore_archive() {
  local container count
  container="$(app_container)" || fail "App 未安装，无法还原归档"
  count="$(find "$archive_snapshot" -type f 2>/dev/null | wc -l | tr -d ' ')"
  [ "$count" -ge 1 ] || fail "归档快照为空（${archive_snapshot}），先跑 trees 阶段"
  mkdir -p "$container/Documents/Runs"
  cp -R "$archive_snapshot/." "$container/Documents/Runs/"
  say "restore: 已还原真实归档到 $container/Documents/Runs（$count 个文件）"
}

# 一次外观的完整截图取证：浅/深共用同一测试驱动，只有系统外观不同。
run_screenshot_appearance() { # <light|dark> <method>
  local appearance="$1"
  local method="$2"
  local bundle="$work_dir/screenshots-${appearance}.xcresult"
  local log="$refresh_staging/xcodebuild-${appearance}.log"
  local names=("${screenshot_bases[@]}")
  if [ "$appearance" = "dark" ]; then
    names=("${screenshot_bases[@]/%/-dark}")
  fi
  rm -rf "$bundle"
  set_appearance "$appearance"
  say "== screenshots[${appearance}]: ScreenshotEvidenceUITests/${method}（UDID ${udid}）"
  xcodebuild test-without-building \
    -project "$project" \
    -scheme "$scheme" \
    -destination "platform=iOS Simulator,id=$udid" \
    -derivedDataPath "$derived" \
    -only-testing:"PurePaceUITests/ScreenshotEvidenceUITests/$method" \
    -resultBundlePath "$bundle" \
    CODE_SIGNING_ALLOWED=NO >"$log" 2>&1 || {
      say "xcodebuild ${appearance} 失败，日志尾部："
      tail -40 "$log" | while IFS= read -r line; do say "  ${line}"; done
      fail "ScreenshotEvidenceUITests/${method} 未通过（日志 ${log}）"
    }
  export_shots "$bundle" "${names[@]}"
  say "info: ${appearance} 外部 xcresult ${bundle}，日志 ${log}"
}

# 宿主侧复核测试日志里的证据标记：六屏 zh-Hans 全绿、两屏地图断言各一条、确认层一条。
assert_screenshot_log() { # <light|dark> <log>
  local appearance="$1"
  local log="$2"
  local screen ok expected_map=0 shot_ok=0 shot_name
  for screen in "${screenshot_bases[@]}"; do
    shot_name="$screen"
    [ "$appearance" = "dark" ] && shot_name="${screen}-dark"
    ok="$(grep -cx "evidence-shot screen=${shot_name}" "$log" || true)"
    [ "$ok" -ge 1 ] || fail "日志缺 evidence-shot screen=${shot_name} 行（${log}）"
    shot_ok=$((shot_ok + 1))
  done
  say "assert: evidence-shot ${shot_ok}/14 ✓（${appearance}）"
  for screen in "${screenshot_screens[@]}"; do
    ok="$(grep -c "ac-visible-copy-zh-hans screen=${screen} labels=.* violations=0 " "$log" || true)"
    [ "$ok" -ge 1 ] || fail "日志缺 ${screen} 的 violations=0 行（${log}）"
    say "assert: ac-visible-copy-zh-hans screen=${screen} violations=0 ✓（${appearance}）"
  done
  for screen in run-finished history-detail; do
    ok="$(grep -c "evidence-map screen=${screen} identifier=run.mapPreview frame=" "$log" || true)"
    [ "$ok" -ge 1 ] || fail "日志缺 ${screen} 的 evidence-map 行（${log}）"
    say "assert: evidence-map screen=${screen} ✓（${appearance}）"
    expected_map=$((expected_map + 1))
  done
  ok="$(grep -c "evidence-discard sheet=discardRequest buttons=2" "$log" || true)"
  [ "$ok" -ge 1 ] || fail "日志缺确认层断言行（${log}）"
  ok="$(grep -c "evidence-inline-hint hint=.* maxHeight=" "$log" || true)"
  [ "$ok" -ge 1 ] || fail "日志缺 B1 inline 胶囊实测行（${log}）"
  say "assert: evidence-inline-hint ✓（${appearance}）"
  ok="$(grep -c "evidence-c2-discard screenHeight=.* sheetTop=.* sheetHeight=" "$log" || true)"
  [ "$ok" -ge 1 ] || fail "日志缺 C2 确认层实测行（${log}）"
  say "assert: evidence-c2-discard ✓（${appearance}，地图断言 ${expected_map} 条）"
}

stage_screenshots() {
  say "== screenshots: 六屏 × 浅/深 + 结束态丢弃确认（14 张，UDID ${udid}）"
  local head_sha status head
  head_sha="$capture_head_sha"
  head="$(printf '%s' "$head_sha" | cut -c1-7)"
  status="$capture_worktree_status"
  if [ -n "$status" ]; then
    if [ "${CAPTURE_ALLOW_DIRTY:-0}" = "1" ]; then
      say "warn: 工作树非 clean（CAPTURE_ALLOW_DIRTY=1，仅供调试）：$(printf '%s' "$status" | head -5)"
    else
      fail "工作树非 clean，截图不满足 ac-all-fresh-from-head（先提交再采；本地调试可设 CAPTURE_ALLOW_DIRTY=1）"
    fi
  fi
  say "build head sha: ${head_sha} (${head})"

  local runner="$derived/Build/Products/Debug-iphonesimulator/PurePaceUITests-Runner.app"
  [ -d "$runner" ] || fail "未找到 UI Runner（${runner}），先跑 xcodebuild build-for-testing（见 docs/evidence/screenshot-refresh/README.md）"

  boot_device
  xcrun simctl privacy "$udid" grant location-always "$bundle_id" >/dev/null 2>&1 || true
  local original_appearance
  original_appearance="$(xcrun simctl ui "$udid" appearance)"
  say "appearance: before=${original_appearance}（采集结束后还原）"

  run_screenshot_appearance light testEvidenceScreensLight || {
    set_appearance "$original_appearance"
    fail "浅色取证失败"
  }
  assert_screenshot_log light "$refresh_staging/xcodebuild-light.log"
  run_screenshot_appearance dark testEvidenceScreensDark || {
    set_appearance "$original_appearance"
    fail "深色取证失败"
  }
  assert_screenshot_log dark "$refresh_staging/xcodebuild-dark.log"

  xcrun simctl terminate "$udid" "$bundle_id" >/dev/null 2>&1 || true
  set_appearance "$original_appearance"
  say "appearance: after=$(xcrun simctl ui "$udid" appearance)"
  write_sha256sums "$head_sha" "$capture_tree_sha"
  local compose="scripts/compose-ios-screenshots-side-by-side.sh"
  [ -f "$compose" ] || fail "缺少并排合成脚本 ${compose}"
  bash "$compose"
  say "info: 已重出 7 张浅/深并排对照（docs/screenshots/side-by-side/）"
}

# ------------------------------------------------ 阶段：AX5 实测

stage_ax5() {
  say "== ax5: content_size accessibility-extra-extra-extra-large（UDID ${udid}）"
  boot_device
  restore_archive
  require_archive
  local before after original_appearance
  original_appearance="$(xcrun simctl ui "$udid" appearance)"
  before="$(xcrun simctl ui "$udid" content_size)"
  xcrun simctl ui "$udid" content_size accessibility-extra-extra-extra-large >/dev/null
  after="$(xcrun simctl ui "$udid" content_size)"
  say "content_size: before=$before after=$after"

  set_appearance light
  clear_checkpoint
  local bundle="$work_dir/ax5-$(date +%Y%m%d%H%M%S).xcresult"
  run_ui_test testEvidenceAx5Layout "$bundle"
  export_trees "$bundle" "$ax5_dir" \
    ax5-01-run-not-started ax5-03-run-finished ax5-05-history-detail ax5-06-settings

  # UI 用例重新安装 App 会换掉数据容器：还原同一份真实归档，供 AX5 详情实拍。
  restore_archive
  clear_checkpoint
  launch_app -uiTestLocation
  sleep 5
  xcrun simctl io "$udid" screenshot "$ax5_dir/ax5-run-not-started.png" >/dev/null

  clear_checkpoint
  launch_app -uiTestLocation -autoStartRecording -screenshotRunFinished
  sleep 40
  xcrun simctl io "$udid" screenshot "$ax5_dir/ax5-run-finished.png" >/dev/null

  launch_app -uiTestLocation -screenshotInitialTab history -screenshotOpenRunDetail
  sleep 8
  xcrun simctl io "$udid" screenshot "$ax5_dir/ax5-history-detail.png" >/dev/null

  launch_app -uiTestLocation -screenshotInitialTab settings
  sleep 5
  xcrun simctl io "$udid" screenshot "$ax5_dir/ax5-settings.png" >/dev/null

  xcrun simctl terminate "$udid" "$bundle_id" >/dev/null 2>&1 || true
  xcrun simctl ui "$udid" content_size "$before" >/dev/null
  say "content_size 还原: $(xcrun simctl ui "$udid" content_size)"
  set_appearance "$original_appearance"
  shasum -a 256 "$ax5_dir"/*.png "$ax5_dir"/*.txt | sed "s#  $ax5_dir/#  #"
}

# ------------------------------------------------ 证据日志发布

publish_refresh_artifacts() {
  mkdir -p "$refresh_dir"
  cp "$capture_log" "$refresh_dir/capture.log"
  local appearance log
  for appearance in light dark; do
    log="$refresh_staging/xcodebuild-${appearance}.log"
    if [ -f "$log" ]; then
      cp "$log" "$refresh_dir/xcodebuild-${appearance}.log"
    fi
  done
  say "info: 证据日志已发布到 ${refresh_dir}/（capture.log + xcodebuild-light.log + xcodebuild-dark.log）"
}

# ------------------------------------------------ 阶段：已入库证据自检

stage_verify() {
  say "== verify: 已入库证据自检（14 张截图 / SHA 清单 / 旧 sha 零复用 / 可及树 / AX5 / README）"
  local failures=0 count name file pair tree identifier path hash_lines

  # 1) 14 张 PNG，命名齐备且目录内无多余图片
  count="$(find "$shots_dir" -maxdepth 1 -type f -name '*.png' | wc -l | tr -d ' ')"
  if [ "$count" != "14" ]; then
    say "verify: docs/screenshots 期望 14 张 PNG，实际 ${count}"
    failures=$((failures + 1))
  fi
  for name in "${screenshot_bases[@]}"; do
    for file in "${name}" "${name}-dark"; do
      if [ ! -f "$shots_dir/${file}.png" ]; then
        say "verify: 缺 ${file}.png"
        failures=$((failures + 1))
      fi
    done
  done
  local shot_lines
  shot_lines="$(grep -cE '^shot: docs/screenshots/[^/]+\.png（[0-9]+ [0-9]+ px）$' "$refresh_dir/capture.log" 2>/dev/null || true)"
  if [ "${shot_lines:-0}" != "14" ]; then
    say "verify: capture.log 期望 14 条 shot 行（含像素尺寸），实际 ${shot_lines:-0}"
    failures=$((failures + 1))
  fi

  # 2) SHA256SUMS 恰 14 行哈希 + 头部登记 40 位构建 head sha + shasum -c 通过
  hash_lines="$(grep -cE '^[0-9a-f]{64}  docs/screenshots/[^/]+\.png$' "$shots_dir/SHA256SUMS" || true)"
  if [ "$hash_lines" != "14" ]; then
    say "verify: SHA256SUMS 期望 14 行哈希，实际 ${hash_lines}"
    failures=$((failures + 1))
  fi
  if ! grep -qE '^# 构建 head sha.*[0-9a-f]{40}' "$shots_dir/SHA256SUMS"; then
    say "verify: SHA256SUMS 头部未登记构建 head sha"
    failures=$((failures + 1))
  fi
  local registered_head registered_tree actual_tree
  registered_head="$(grep -oE '^# 构建 head sha.*[0-9a-f]{40}' "$shots_dir/SHA256SUMS" | grep -oE '[0-9a-f]{40}$' || true)"
  registered_tree="$(grep -oE '^# 构建 tree sha.*[0-9a-f]{40}' "$shots_dir/SHA256SUMS" | grep -oE '[0-9a-f]{40}$' || true)"
  actual_tree="$(git rev-parse HEAD^{tree})"
  if [ -z "$registered_tree" ]; then
    say "verify: SHA256SUMS 头部未登记构建 tree sha"
    failures=$((failures + 1))
  fi
  if [ -n "$registered_head" ] && ! grep -q -- "$registered_head" "$refresh_dir/README.md" 2>/dev/null; then
    say "verify: README 未记录与 SHA256SUMS 相同的构建 head sha ${registered_head}"
    failures=$((failures + 1))
  fi
  if [ -n "$registered_tree" ] && ! grep -q -- "$registered_tree" "$refresh_dir/README.md" 2>/dev/null; then
    say "verify: README 未记录与 SHA256SUMS 相同的构建 tree sha ${registered_tree}"
    failures=$((failures + 1))
  fi
  say "info: 构建绑定 head=${registered_head:-missing} tree=${registered_tree:-missing}（当前 HEAD tree=${actual_tree}）"
  if ! shasum -a 256 -c "$shots_dir/SHA256SUMS" >/dev/null 2>&1; then
    say "verify: shasum -a 256 -c docs/screenshots/SHA256SUMS 未通过"
    failures=$((failures + 1))
  fi

  # 3) 新图与上一轮 14 个旧 sha 零重合（ac-no-reuse-prev-batch）
  local new_shas old
  new_shas="$(shasum -a 256 "$shots_dir"/*.png)"
  for old in "${old_shot_shas[@]}"; do
    if printf '%s\n' "$new_shas" | grep -q "^${old} "; then
      say "verify: 新图与旧 sha ${old} 相同（疑似复用旧图）"
      failures=$((failures + 1))
    fi
  done

  # 4) 六棵可及树：命名齐备 + 主操作 identifier 存在且 label 非空
  count="$(find "$a11y_dir" -maxdepth 1 -type f -name '*.txt' | wc -l | tr -d ' ')"
  if [ "$count" != "6" ]; then
    say "verify: docs/evidence/a11y 期望 6 棵可及树，实际 ${count}"
    failures=$((failures + 1))
  fi
  for pair in \
    01-run-not-started:run.start 02-run-running:run.pause 03-run-finished:run.save \
    04-history-list:history.row 05-history-detail:runDetail.export 06-settings:settings.announcementToggle; do
    tree="${pair%%:*}"
    identifier="${pair##*:}"
    path="$a11y_dir/${tree}.txt"
    if [ ! -f "$path" ]; then
      say "verify: 缺可及树 ${path}"
      failures=$((failures + 1))
      continue
    fi
    if ! grep -qE "identifier: '${identifier}', label: '[^']+'" "$path"; then
      say "verify: ${path} 缺 ${identifier} 或 label 为空"
      failures=$((failures + 1))
    fi
  done

  # 5) AX5：4 张实拍 + 4 棵实测树，日志记录 content_size before/after 且已还原
  count="$(find "$ax5_dir" -maxdepth 1 -type f -name '*.png' | wc -l | tr -d ' ')"
  if [ "$count" != "4" ]; then
    say "verify: ${ax5_dir} 期望 4 张 AX5 实拍，实际 ${count}"
    failures=$((failures + 1))
  fi
  count="$(find "$ax5_dir" -maxdepth 1 -type f -name '*.txt' | wc -l | tr -d ' ')"
  if [ "$count" != "4" ]; then
    say "verify: ${ax5_dir} 期望 4 棵 AX5 实测树，实际 ${count}"
    failures=$((failures + 1))
  fi
  if ! grep -q 'content_size: before=' "$refresh_dir/capture.log"; then
    say "verify: capture.log 缺 content_size before/after 记录"
    failures=$((failures + 1))
  fi
  if ! grep -q 'content_size 还原: ' "$refresh_dir/capture.log"; then
    say "verify: capture.log 缺 content_size 还原记录"
    failures=$((failures + 1))
  fi

  # 6) 浅/深并排对照：7 张 `<screen>-side-by-side.png`，宽 = 2×浅色宽、高 = 浅色高，
  #    目录内无多余 PNG，SHA256SUMS 7 行且 shasum -c 通过（ac-side-by-side-7）。
  local side_dir="$shots_dir/side-by-side" side_name light_w light_h dark_w dark_h side_w side_h side_lines
  count="$(find "$side_dir" -maxdepth 1 -type f -name '*.png' 2>/dev/null | wc -l | tr -d ' ')"
  if [ "$count" != "7" ]; then
    say "verify: ${side_dir} 期望 7 张并排图，实际 ${count}"
    failures=$((failures + 1))
  fi
  for name in "${screenshot_bases[@]}"; do
    side_name="${name}-side-by-side"
    if [ ! -f "$side_dir/${side_name}.png" ]; then
      say "verify: 缺并排图 ${side_dir}/${side_name}.png"
      failures=$((failures + 1))
      continue
    fi
    read -r light_w light_h < <(sips -g pixelWidth -g pixelHeight "$shots_dir/${name}.png" \
      | awk '/pixelWidth/{w=$2} /pixelHeight/{h=$2} END{print w, h}')
    read -r dark_w dark_h < <(sips -g pixelWidth -g pixelHeight "$shots_dir/${name}-dark.png" \
      | awk '/pixelWidth/{w=$2} /pixelHeight/{h=$2} END{print w, h}')
    read -r side_w side_h < <(sips -g pixelWidth -g pixelHeight "$side_dir/${side_name}.png" \
      | awk '/pixelWidth/{w=$2} /pixelHeight/{h=$2} END{print w, h}')
    if [ "$side_w" != "$((light_w * 2))" ] || [ "$side_h" != "$light_h" ] \
      || [ "$dark_w" != "$light_w" ] || [ "$dark_h" != "$light_h" ]; then
      say "verify: ${side_name} 尺寸不符（side=${side_w}x${side_h} light=${light_w}x${light_h} dark=${dark_w}x${dark_h}）"
      failures=$((failures + 1))
    fi
  done
  side_lines="$(grep -cE '^[0-9a-f]{64}  docs/screenshots/side-by-side/[^/]+\.png$' "$side_dir/SHA256SUMS" 2>/dev/null || true)"
  if [ "$side_lines" != "7" ]; then
    say "verify: ${side_dir}/SHA256SUMS 期望 7 行哈希，实际 ${side_lines:-0}"
    failures=$((failures + 1))
  fi
  if ! shasum -a 256 -c "$side_dir/SHA256SUMS" >/dev/null 2>&1; then
    say "verify: shasum -a 256 -c ${side_dir}/SHA256SUMS 未通过"
    failures=$((failures + 1))
  fi

  # 7) README / 证据 SHA 清单 / 仓内唯一确认层
  if [ ! -f "$refresh_dir/README.md" ]; then
    say "verify: 缺 ${refresh_dir}/README.md"
    failures=$((failures + 1))
  else
    for token in '构建 head sha' 'ScreenshotEvidenceUITests.swift' 'capture.log' \
      'xcodebuild-light.log' 'xcodebuild-dark.log' 'run.mapPreview' '肉眼' '14' \
      'side-by-side' 'evidence-inline-hint' 'evidence-c2-discard'; do
      if ! grep -q -- "$token" "$refresh_dir/README.md"; then
        say "verify: README 缺必填项 '${token}'"
        failures=$((failures + 1))
      fi
    done
  fi
  if ! shasum -a 256 -c "$refresh_dir/SHA256SUMS" >/dev/null 2>&1; then
    say "verify: shasum -a 256 -c ${refresh_dir}/SHA256SUMS 未通过"
    failures=$((failures + 1))
  fi
  local sheet_count
  sheet_count="$(grep -rho '\.sheet(' ios/PurePace | wc -l | tr -d ' ')"
  if [ "$sheet_count" != "1" ]; then
    say "verify: 仓内 .sheet( 期望恰 1 处（结束态丢弃确认层），实际 ${sheet_count}"
    failures=$((failures + 1))
  fi

  [ "$failures" -eq 0 ] || fail "verify: ${failures} 项未通过"
  say "verify: OK（14 张 PNG / 14 行 SHA / 旧 sha 零复用 / 7 张并排 / 6 棵可及树 / AX5 4+4 / README 必填项齐）"
}

case "$stage" in
  trees) stage_trees ;;
  screenshots)
    stage_screenshots
    publish_refresh_artifacts
    ;;
  ax5) stage_ax5 ;;
  verify) stage_verify ;;
  all)
    stage_trees
    stage_screenshots
    publish_refresh_artifacts
    stage_ax5
    publish_refresh_artifacts
    ;;
esac

say "done: $stage"
