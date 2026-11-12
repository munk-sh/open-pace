#!/usr/bin/env bash
# V1.2 界面返工设计稿：在 iPhone 16 模拟器上真实渲染 20 张 393×852pt PNG。
#
# 单次执行 = 构建 Debug App → 安装 → 逐个变体 `simctl launch --console-pty` → 轮询
# `designDraft.ready` 就绪标记 → `simctl io screenshot` → 汇总 render.log / manifest.md /
# SHA256SUMS / heights.tsv。变体号与 `docs/design-draft-v12/manifest.md` 一一对应。
#
# 用法: scripts/capture-design-draft-v12.sh [--udid <udid>] [--only <group>] [--skip-build]
#       详见 --help。只写 docs/design-draft-v12/，不改任何生产文件。
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
cd "$repo_root"

bundle_id="sh.munk.purepace"
shots_dir="docs/design-draft-v12"
udid=""
only="all"
skip_build=0
settle_seconds="${SETTLE_SECONDS:-3}"

usage() {
  cat <<'EOF'
用法: scripts/capture-design-draft-v12.sh [--udid <udid>] [--only <group>] [--skip-build]

在 iOS 模拟器（iPhone 16 / 393×852pt / @3x）上真实渲染 V1.2 设计稿静态图，
输出到 docs/design-draft-v12/：20 张 PNG + render.log + manifest.md + SHA256SUMS + heights.tsv。

参数:
  --udid <udid>   指定已安装的模拟器 UDID（缺省取 iPhone 16 的可用设备）
  --only <group>  只跑一组：all（默认）/ a / b / c / b2-expanded
  --skip-build    复用 .build/ios 里已构建的 Debug App，不重新 xcodebuild
  -h, --help      显示本帮助并退出 0

前置: macOS + Xcode，且本机可 `xcrun simctl`；构建由 scripts/build-ios.sh 完成。
校验: 在仓库根执行 `shasum -a 256 -c docs/design-draft-v12/SHA256SUMS` 应全部 OK。
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --udid)
      [ "$#" -ge 2 ] || { echo "capture-design-draft-v12: --udid 缺少取值" >&2; exit 2; }
      udid="$2"
      shift 2
      ;;
    --only)
      [ "$#" -ge 2 ] || { echo "capture-design-draft-v12: --only 缺少取值" >&2; exit 2; }
      only="$2"
      shift 2
      ;;
    --skip-build)
      skip_build=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "capture-design-draft-v12: 未知参数 '$1'（使用 --help 查看用法）" >&2
      exit 2
      ;;
  esac
done

case "$only" in
  all|a|b|c|b2-expanded) ;;
  *)
    echo "capture-design-draft-v12: --only 只接受 all/a/b/c/b2-expanded" >&2
    exit 2
    ;;
esac

say() { printf 'capture-design-draft-v12: %s\n' "$*" >&2; }
fail() { printf 'capture-design-draft-v12: %s\n' "$*" >&2; exit 1; }

if [ -z "$udid" ]; then
  udid="$(xcrun simctl list devices available \
    | awk -F '[()]' '/iPhone 16 \(/ { print $2; exit }')"
fi
[ -n "$udid" ] || fail "未找到可用 iPhone 16 模拟器（用 --udid 指定）"

app_path=".build/ios/Build/Products/Debug-iphonesimulator/PurePace.app"
if [ "$skip_build" = "1" ]; then
  [ -d "$app_path" ] || fail "缺少 ${app_path}（去掉 --skip-build 重新构建）"
else
  say "构建 Debug App（scripts/build-ios.sh）"
  bash scripts/build-ios.sh >/dev/null || fail "scripts/build-ios.sh 失败"
fi

mkdir -p "$shots_dir"
staging=".build/design-draft-v12"
mkdir -p "$staging"
render_log="$shots_dir/render.log"
: >"$render_log"

say "安装 App 到 UDID $udid"
xcrun simctl bootstatus "$udid" -b >/dev/null 2>&1 || xcrun simctl boot "$udid" >/dev/null
xcrun simctl install "$udid" "$app_path"
# 设计稿不请求定位，但清一次授权状态，避免系统权限弹窗压住截图。
xcrun simctl privacy "$udid" grant location-always "$bundle_id" >/dev/null 2>&1 || true

# 变体清单：variant|appearance|输出文件名（空 = 只量测，不出图）
shots=(
  "a1-run-not-started|light|a1-run-not-started"
  "a1-run-running|light|a1-run-running"
  "a1-run-finished|light|a1-run-finished"
  "a1-history-list|light|a1-history-list"
  "a1-history-detail|light|a1-history-detail"
  "a1-settings|light|a1-settings"
  "a2-run-not-started|light|a2-run-not-started"
  "a2-run-running|light|a2-run-running"
  "a2-run-finished|light|a2-run-finished"
  "a2-history-list|light|a2-history-list"
  "a2-history-detail|light|a2-history-detail"
  "a2-settings|light|a2-settings"
  "b1-finished|light|b1-finished-light"
  "b1-finished|dark|b1-finished-dark"
  "b2-finished|light|b2-finished-light"
  "b2-finished|dark|b2-finished-dark"
  "b2-finished-expanded|light|"
  "c1-discard|light|c1-discard-light"
  "c1-discard|dark|c1-discard-dark"
  "c2-discard|light|c2-discard-light"
  "c2-discard|dark|c2-discard-dark"
)

group_of() {
  case "$1" in
    a*) echo a ;;
    b*) echo b ;;
    c*) echo c ;;
    *) echo other ;;
  esac
}

selected() {
  case "$only" in
    all) return 0 ;;
    b2-expanded) [ "$1" = "b2-finished-expanded" ] ;;
    *) [ "$(group_of "$1")" = "$only" ] ;;
  esac
}

capture() {
  local variant="$1" appearance="$2" out="$3"
  local log="$staging/$variant-$appearance.log"
  xcrun simctl ui "$udid" appearance "$appearance" >/dev/null 2>&1 || true
  xcrun simctl terminate "$udid" "$bundle_id" >/dev/null 2>&1 || true
  : >"$log"
  xcrun simctl launch --console-pty "$udid" "$bundle_id" -designDraftV12 "$variant" >"$log" 2>&1 &
  local pid=$!
  local waited=0
  while ! grep -q "designDraft.ready $variant" "$log" 2>/dev/null; do
    sleep 0.3
    waited=$((waited + 1))
    if [ "$waited" -ge 100 ]; then
      printf '== %s (%s) 未出现就绪标记，日志尾部：\n' "$variant" "$appearance" >>"$render_log"
      tail -20 "$log" >>"$render_log"
      kill "$pid" >/dev/null 2>&1 || true
      fail "变体 $variant 在 30s 内未打印 designDraft.ready"
    fi
  done
  # MapKit 瓦片与首帧稳定：就绪标记之后再等固定渲染窗（非 UI 测试，仅截图）。
  sleep "$settle_seconds"
  if [ -n "$out" ]; then
    xcrun simctl io "$udid" screenshot "$shots_dir/$out.png" >/dev/null 2>&1 \
      || fail "截图失败: $out.png"
    local width height
    width="$(sips -g pixelWidth "$shots_dir/$out.png" | awk '/pixelWidth/ { print $2 }')"
    height="$(sips -g pixelHeight "$shots_dir/$out.png" | awk '/pixelHeight/ { print $2 }')"
    [ "$width" = "1179" ] && [ "$height" = "2556" ] \
      || fail "$out.png 像素 ${width}x${height} 不是 393x852pt@3x（1179x2556）"
  fi
  xcrun simctl terminate "$udid" "$bundle_id" >/dev/null 2>&1 || true
  kill "$pid" >/dev/null 2>&1 || true
  {
    printf '== %s appearance=%s file=%s\n' "$variant" "$appearance" "${out:-<measure-only>}"
    grep -E 'designDraft\.(screen|height|ready)' "$log" || true
  } >>"$render_log"
  say "ok: ${out:-${variant}（仅量测）} [$appearance]"
}

for entry in "${shots[@]}"; do
  IFS='|' read -r variant appearance out <<<"$entry"
  selected "$variant" || continue
  capture "$variant" "$appearance" "$out"
done

say "生成 manifest.md / SHA256SUMS / heights.tsv"
python3 - "$shots_dir" "$render_log" "$udid" <<'PY'
import hashlib
import os
import re
import subprocess
import sys

shots_dir, render_log, udid = sys.argv[1], sys.argv[2], sys.argv[3]

heights = {}
screens = {}
current = None
order = []
for line in open(render_log, encoding="utf-8"):
    line = line.strip()
    if line.startswith("== "):
        current = line.split()[1]
        if current not in order:
            order.append(current)
        continue
    m = re.match(r"designDraft\.screen \S+ scale=([\d.]+) pt=([\d.]+)x([\d.]+) px=(\d+)x(\d+)", line)
    if m:
        screens[current] = m.groups()
        continue
    m = re.match(r"designDraft\.height \S+ (\S+) w=([\d.]+) h=([\d.]+)", line)
    if m and current:
        heights[(current, m.group(1))] = (m.group(2), m.group(3))

pngs = sorted(f for f in os.listdir(shots_dir) if f.endswith(".png"))
device = "iPhone 16"
model = subprocess.run(
    ["xcrun", "simctl", "list", "devices"], capture_output=True, text=True
).stdout
runtime = "iOS 18.6"
for line in model.splitlines():
    if udid in line:
        break

rows = []
for name in pngs:
    path = os.path.join(shots_dir, name)
    out = subprocess.run(
        ["sips", "-g", "pixelWidth", "-g", "pixelHeight", path],
        capture_output=True,
        text=True,
    ).stdout
    w = int(re.search(r"pixelWidth: (\d+)", out).group(1))
    h = int(re.search(r"pixelHeight: (\d+)", out).group(1))
    rows.append((name, w, h, w // 393, round(w / 393, 2)))

with open(os.path.join(shots_dir, "manifest.md"), "w", encoding="utf-8") as fh:
    fh.write("# V1.2 设计稿渲染清单（docs/design-draft-v12/）\n\n")
    fh.write(f"- 设备：{device}（{runtime} 模拟器，UDID `{udid}`）\n")
    fh.write("- 逻辑尺寸：393 × 852 pt（竖屏，iPhone 16）\n")
    fh.write("- 缩放倍率：@3x；像素尺寸：1179 × 2556\n")
    fh.write("- 生成入口：`bash scripts/capture-design-draft-v12.sh`（本轮运行日志 `render.log`）\n")
    fh.write("- 校验：`shasum -a 256 -c docs/design-draft-v12/SHA256SUMS`\n\n")
    fh.write("| # | 文件 | 逻辑尺寸 | 倍率 | 像素尺寸 |\n|---|---|---|---|---|\n")
    for index, (name, w, h, scale, ratio) in enumerate(rows, start=1):
        fh.write(f"| {index} | `{name}` | 393×852pt | @{scale}x | {w}×{h} |\n")
    fh.write(f"\n共 {len(rows)} 张 PNG。\n\n")

    fh.write("## 运行期实测高度（pt，取最后一次量测）\n\n")
    fh.write("| 变体 | 量测点 | 实测高 |\n|---|---|---|\n")
    for variant in order:
        for (v, label), (_w, h) in sorted(heights.items()):
            if v == variant:
                fh.write(f"| `{variant}` | `{label}` | {h} |\n")

with open(os.path.join(shots_dir, "heights.tsv"), "w", encoding="utf-8") as fh:
    fh.write("variant\tprobe\theight_pt\twidth_pt\n")
    for variant in order:
        for (v, label), (w, h) in sorted(heights.items()):
            if v == variant:
                fh.write(f"{variant}\t{label}\t{h}\t{w}\n")

with open(os.path.join(shots_dir, "SHA256SUMS"), "w", encoding="utf-8") as fh:
    fh.write(f"# V1.2 设计稿校验清单（{len(pngs)} 张 PNG，路径相对仓库根）\n")
    fh.write("# 校验（在仓库根执行）：shasum -a 256 -c docs/design-draft-v12/SHA256SUMS\n")
    fh.write("# 生成（在仓库根执行）：bash scripts/capture-design-draft-v12.sh\n")
    for name in pngs:
        digest = hashlib.sha256(open(os.path.join(shots_dir, name), "rb").read()).hexdigest()
        fh.write(f"{digest}  {shots_dir}/{name}\n")

print(f"png={len(pngs)}")
PY

say "完成：${shots_dir}（20 张 PNG + render.log + manifest.md + SHA256SUMS + heights.tsv）"
