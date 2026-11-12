#!/usr/bin/env bash
# 浅/深界面截图并排对照合成：左浅右深、等高、1:1 像素不缩放、无分隔线。
#
# 只产证据，不改原图：
#   - 输入 docs/screenshots/<screen>.png（浅）+ <screen>-dark.png（深）；
#   - 输出 docs/screenshots/side-by-side/<screen>-side-by-side.png（宽 = 2 × 原宽，高 = 原高）；
#   - 合成确定性：像素按字节复制、编码不带时间戳等易变元数据，同一输入两次运行字节相同；
#   - 零第三方依赖：仅系统 Swift + CoreGraphics / ImageIO。
set -euo pipefail

usage() {
  cat <<'EOF'
用法: scripts/compose-ios-screenshots-side-by-side.sh [--help]

把 docs/screenshots/ 的 7 组浅/深截图水平拼成并排对照图，输出到
docs/screenshots/side-by-side/<screen>-side-by-side.png，并重写该目录 SHA256SUMS。

约束:
  - 左半 = 浅色原图，右半 = 深色原图；1:1 像素、无缩放、无分隔线、等高；
  - 合成确定性：同一输入连续运行两次输出字节相同；
  - 零第三方依赖：仅用系统 Swift + CoreGraphics / ImageIO。

选项:
  -h, --help  显示本帮助并退出 0

退出码: 0 成功；1 合成/校验失败；2 参数非法
EOF
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "compose-ios-screenshots-side-by-side: 未知参数 '$1'（使用 --help 查看用法）" >&2
      exit 2
      ;;
  esac
done

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
cd "$repo_root"

shots_dir="docs/screenshots"
side_dir="$shots_dir/side-by-side"
head_sha="$(git rev-parse HEAD)"
tree_sha="$(git rev-parse HEAD^{tree})"

screenshot_bases=(
  run-not-started run-running run-finished discard-confirmation
  history-list history-detail settings
)

mkdir -p "$side_dir"

swift_script="$(mktemp "${TMPDIR:-/tmp}/purepace-side-by-side.XXXXXX.swift")"
trap 'rm -f "$swift_script"' EXIT

cat >"$swift_script" <<'SWIFT'
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count >= 4 else {
    FileHandle.standardError.write(Data("compose: 参数不足\n".utf8))
    exit(2)
}
let shotsDir = args[1]
let sideDir = args[2]
let bases = Array(args[3...])

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("compose: \(message)\n".utf8))
    exit(1)
}

func loadPNG(_ path: String) -> CGImage {
    let url = URL(fileURLWithPath: path) as CFURL
    guard let source = CGImageSourceCreateWithURL(url, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        fail("无法解码 PNG：\(path)")
    }
    return image
}

func rgbaContext(width: Int, height: Int) -> CGContext {
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
          ) else {
        fail("无法创建 \(width)x\(height) 位图上下文")
    }
    context.interpolationQuality = .none
    return context
}

func decodedPixels(_ image: CGImage) -> (bytes: [UInt8], width: Int, height: Int) {
    let context = rgbaContext(width: image.width, height: image.height)
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    guard let data = context.data else { fail("位图上下文无像素数据") }
    let buffer = data.bindMemory(to: UInt8.self, capacity: image.width * image.height * 4)
    return (Array(UnsafeBufferPointer(start: buffer, count: image.width * image.height * 4)),
            image.width, image.height)
}

func encodePNG(_ image: CGImage) -> Data {
    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(
        data as CFMutableData, UTType.png.identifier as CFString, 1, nil
    ) else {
        fail("无法创建 PNG 编码器")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fail("PNG 编码失败") }
    return data as Data
}

for base in bases {
    let lightPath = "\(shotsDir)/\(base).png"
    let darkPath = "\(shotsDir)/\(base)-dark.png"
    let light = loadPNG(lightPath)
    let dark = loadPNG(darkPath)
    guard light.width == dark.width, light.height == dark.height else {
        fail("\(base) 浅/深尺寸不一致：light=\(light.width)x\(light.height) dark=\(dark.width)x\(dark.height)")
    }
    let width = light.width
    let height = light.height
    let composite = rgbaContext(width: width * 2, height: height)
    composite.draw(light, in: CGRect(x: 0, y: 0, width: width, height: height))
    composite.draw(dark, in: CGRect(x: width, y: 0, width: width, height: height))
    guard let compositeImage = composite.makeImage() else { fail("\(base) 合成图生成失败") }

    // 逐像素确认：左半 == 浅色原图、右半 == 深色原图（同一解码口径、逐字节）。
    guard let compositeData = composite.data else { fail("\(base) 合成图无像素数据") }
    let stride = width * 4
    let compositeBytes = compositeData.bindMemory(to: UInt8.self, capacity: stride * height)
    let lightPixels = decodedPixels(light)
    let darkPixels = decodedPixels(dark)
    for row in 0..<height {
        let compositeRow = row * width * 8
        let lightRow = row * stride
        for column in 0..<stride {
            guard compositeBytes[compositeRow + column] == lightPixels.bytes[lightRow + column] else {
                fail("\(base) 左半像素与浅色原图不一致 row=\(row) column=\(column)")
            }
            guard compositeBytes[compositeRow + width * 4 + column] == darkPixels.bytes[lightRow + column] else {
                fail("\(base) 右半像素与深色原图不一致 row=\(row) column=\(column)")
            }
        }
    }

    let png = encodePNG(compositeImage)
    guard png == encodePNG(compositeImage) else { fail("\(base) PNG 编码不确定（两次字节不同）") }
    let outputPath = "\(sideDir)/\(base)-side-by-side.png"
    do {
        try png.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
    } catch {
        fail("写入 \(outputPath) 失败：\(error)")
    }
    print("compose: \(outputPath) light=\(width)x\(height) dark=\(width)x\(height) output=\(width * 2)x\(height)")
}
SWIFT

swift "$swift_script" "$shots_dir" "$side_dir" "${screenshot_bases[@]}"

{
  echo "# PurePace 浅/深并排对照校验清单（docs/screenshots/side-by-side/）"
  echo "#"
  echo "# 校验（在仓库根执行）：shasum -a 256 -c docs/screenshots/side-by-side/SHA256SUMS"
  echo "# 合成（在仓库根执行）：bash scripts/compose-ios-screenshots-side-by-side.sh"
  echo "#"
  echo "# 构建 head sha（原图产出所在 commit，实取 git rev-parse HEAD）：${head_sha}"
  echo "# 构建 tree sha（实取 git rev-parse HEAD^{tree}）：${tree_sha}"
  echo "# 左半 = 浅色原图、右半 = 深色原图；1:1 像素、无缩放、无分隔线。"
  echo "#"
  shasum -a 256 "$side_dir"/*.png
} >"$side_dir/SHA256SUMS"

echo "compose: 已重写 $side_dir/SHA256SUMS（7 行 SHA256）"
echo "compose: 构建绑定 head=${head_sha} tree=${tree_sha}"
