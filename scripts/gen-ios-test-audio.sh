#!/usr/bin/env bash
# 生成 UITests target 自带的合成音源（真机 audio 阶段 runner 自播，无人操作）。
#
# 输出：ios/PurePaceUITests/Fixtures/runner-music-loop.wav
# 特点：python3 标准库合成（wave + struct + math）、确定性（同参数同 sha256）、幂等（默认已存在即跳过）、
#       零网络、无第三方依赖；超过 200 KB 直接非零退出。
set -euo pipefail

usage() {
  cat <<'EOF'
用法: scripts/gen-ios-test-audio.sh [--force] [--help]

生成 UITests target 自带的确定性合成音源：
  ios/PurePaceUITests/Fixtures/runner-music-loop.wav

参数:
  --force      覆盖已存在的 wav（默认仅在文件缺失时生成）
  -h, --help   显示本帮助并退出 0

输出:
  打印目标路径、字节数与 sha256；字节数 > 204800 时非零退出。

退出码:
  0  已生成或已存在且未超限
  2  参数非法
  1  生成失败或产物超限
EOF
}

force=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --force)
      force=1
      ;;
    *)
      echo "gen-ios-test-audio: 未知参数 '$1'（使用 --help 查看用法）" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
target_dir="${repo_root}/ios/PurePaceUITests/Fixtures"
target="${target_dir}/runner-music-loop.wav"
max_bytes=204800

mkdir -p "$target_dir"

if [ -f "$target" ] && [ "$force" -ne 1 ]; then
  echo "gen-ios-test-audio: 已存在，跳过生成（--force 可覆盖）: ${target#"$repo_root"/}"
else
  python3 - "$target" <<'PY'
import math
import struct
import sys
import wave

path = sys.argv[1]
sample_rate = 22050
seconds = 2.0
frame_count = int(sample_rate * seconds)
amplitude = 0.22
# 两音叠加（440 Hz + 660 Hz），留 5 ms 首尾淡入淡出，避免起播爆音；纯确定性计算。
fade_frames = int(sample_rate * 0.005)

frames = bytearray()
for index in range(frame_count):
    t = index / sample_rate
    sample = amplitude * (math.sin(2.0 * math.pi * 440.0 * t) + 0.5 * math.sin(2.0 * math.pi * 660.0 * t)) / 1.5
    if index < fade_frames:
        sample *= index / fade_frames
    remaining = frame_count - index - 1
    if remaining < fade_frames:
        sample *= remaining / fade_frames
    frames += struct.pack("<h", max(-32768, min(32767, int(round(sample * 32767)))))

with wave.open(path, "wb") as handle:
    handle.setnchannels(1)
    handle.setsampwidth(2)
    handle.setframerate(sample_rate)
    handle.writeframes(bytes(frames))
PY
fi

bytes_count="$(wc -c < "$target" | tr -d ' ')"
digest="$(shasum -a 256 "$target" | cut -d' ' -f1)"
printf 'gen-ios-test-audio: %s\n' "${target#"$repo_root"/}"
printf 'gen-ios-test-audio: bytes=%s sha256=%s\n' "$bytes_count" "$digest"

if [ "$bytes_count" -gt "$max_bytes" ]; then
  echo "gen-ios-test-audio: 产物 ${bytes_count} 字节超过上限 ${max_bytes}" >&2
  exit 1
fi
