#!/usr/bin/env bash
# 第 5 波证据冻结：六屏浅/深实取 simctl 截图、六棵可及树、AX5 最大字号档实拍与布局实测。
#
# 只产证据，不改产品行为：
#   - 截图一律由 `xcrun simctl io <udid> screenshot` 在宿主实取，不裁切、不改色、不再编码；
#   - 可及树来自 `EvidenceCaptureUITests`（真实「开始 → 跑步中 → 结束 → 保存」链路，
#     不使用 `-screenshotHistoryDemo`，历史数据来自容器内真实归档）；
#   - 同一台模拟器、同一 runtime，UDID 由参数固定并写入所有命令。
set -euo pipefail

usage() {
  cat <<'EOF'
用法: scripts/capture-ios-screenshots.sh [--udid <udid>] [--stage <stage>]

在指定的一台模拟器上重出第 5 波证据（浅/深截图、可及树、AX5 实测）。

阶段:
  trees        运行 EvidenceCaptureUITests/testEvidenceTreesAndRealArchive：
               真实落盘一次跑次归档，并把六棵可及树导出到 docs/evidence/a11y/
  screenshots  六屏 × 浅/深 = 12 张 simctl 截图写入 docs/screenshots/，
               随后重写该目录 SHA256SUMS 的哈希行（保留文件头部注释区）
  ax5          系统字号设为 accessibility-extra-extra-extra-large：
               导出四棵实测树与四张实拍图到 docs/evidence/evidence-freeze/ax5/，
               结束后还原原字号
  all          依次执行 trees → screenshots → ax5（默认）

选项:
  --udid <udid>  目标模拟器 UDID（默认 iPhone 16 / iOS 18.6 的固定 UDID）
  --stage <s>    见上（默认 all）
  -h, --help     显示本帮助并退出 0

前置: 已有 `xcodebuild build-for-testing` 产物（.build/ios），且归档已由 trees 阶段产生。
退出码: 0 成功；1 采集失败；2 参数非法
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
  trees|screenshots|ax5|all) ;;
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

say() { printf '%s\n' "$*"; }
fail() {
  printf 'capture-ios-screenshots: %s\n' "$*" >&2
  exit 1
}

mkdir -p "$work_dir" "$shots_dir" "$a11y_dir" "$ax5_dir"

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

write_sha256sums() {
  local file="$shots_dir/SHA256SUMS"
  local tmp="$file.tmp"
  if [ ! -f "$file" ]; then
    {
      echo "# PurePace 界面截图校验清单（docs/screenshots/）"
      echo "#"
      echo "# 校验（在仓库根执行）：shasum -a 256 -c docs/screenshots/SHA256SUMS"
      echo "# 生成（在仓库根执行）：shasum -a 256 docs/screenshots/*.png"
      echo "#"
    } >"$file"
  fi
  awk '/^[0-9a-f][0-9a-f]*  docs\//{exit} {print}' "$file" >"$tmp"
  shasum -a 256 "$shots_dir"/*.png >>"$tmp"
  mv "$tmp" "$file"
  say "info: 已重写 $file（覆盖目录内全部 PNG）"
}

# ------------------------------------------------ 阶段：六屏可及树 + 真实归档

stage_trees() {
  say "== trees: EvidenceCaptureUITests/testEvidenceTreesAndRealArchive（UDID $udid）"
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
  mkdir -p "$archive_snapshot"
  cp -R "$container/Documents/Runs/." "$archive_snapshot/"
  say "snapshot: $archive_snapshot（$(find "$archive_snapshot" -type f | wc -l | tr -d ' ') 个文件）"
}

restore_archive() {
  local container count
  container="$(app_container)" || fail "App 未安装，无法还原归档"
  count="$(find "$archive_snapshot" -type f 2>/dev/null | wc -l | tr -d ' ')"
  [ "$count" -ge 1 ] || fail "归档快照为空（$archive_snapshot），先跑 trees 阶段"
  mkdir -p "$container/Documents/Runs"
  cp -R "$archive_snapshot/." "$container/Documents/Runs/"
  say "restore: 已还原真实归档到 $container/Documents/Runs（$count 个文件）"
}

stage_screenshots() {
  say "== screenshots: 六屏 × 浅/深（UDID $udid）"
  boot_device
  restore_archive
  require_archive
  local original_appearance
  original_appearance="$(xcrun simctl ui "$udid" appearance)"

  set_appearance light
  clear_checkpoint
  launch_app -uiTestLocation
  sleep 5
  shot run-not-started

  set_appearance dark
  clear_checkpoint
  launch_app -uiTestLocation
  sleep 5
  shot run-not-started-dark

  # 跑步中 + 结束总结：同一进程先取运行中，再由 `-screenshotRunFinished`（DEBUG-only）
  # 在真实采样 30s 后自动结束到待保存决策态。
  set_appearance light
  clear_checkpoint
  launch_app -uiTestLocation -autoStartRecording -screenshotRunFinished
  sleep 20
  shot run-running
  sleep 25
  shot run-finished

  set_appearance dark
  clear_checkpoint
  launch_app -uiTestLocation -autoStartRecording -screenshotRunFinished
  sleep 20
  shot run-running-dark
  sleep 25
  shot run-finished-dark

  set_appearance light
  launch_app -uiTestLocation -screenshotInitialTab history
  sleep 6
  shot history-list
  launch_app -uiTestLocation -screenshotInitialTab history -screenshotOpenRunDetail
  sleep 6
  shot history-detail
  launch_app -uiTestLocation -screenshotInitialTab settings
  sleep 5
  shot settings

  set_appearance dark
  launch_app -uiTestLocation -screenshotInitialTab history
  sleep 6
  shot history-list-dark
  launch_app -uiTestLocation -screenshotInitialTab history -screenshotOpenRunDetail
  sleep 6
  shot history-detail-dark
  launch_app -uiTestLocation -screenshotInitialTab settings
  sleep 5
  shot settings-dark

  xcrun simctl terminate "$udid" "$bundle_id" >/dev/null 2>&1 || true
  set_appearance "$original_appearance"
  write_sha256sums
}

# ------------------------------------------------ 阶段：AX5 实测

stage_ax5() {
  say "== ax5: content_size accessibility-extra-extra-extra-large（UDID $udid）"
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

case "$stage" in
  trees) stage_trees ;;
  screenshots) stage_screenshots ;;
  ax5) stage_ax5 ;;
  all)
    stage_trees
    stage_screenshots
    stage_ax5
    ;;
esac

say "done: $stage"
