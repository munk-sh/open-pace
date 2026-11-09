import Foundation
import XCTest

/// ac-built-plist-readback-both：直接读取**已构建 App 的 Info.plist 文件本体**（Data + PropertyListSerialization），
/// 断言 `UIBackgroundModes` 实际数组同时包含 `location` 与 `audio`，并用同一读取路径做负向自检。
final class BackgroundModesPlistTests: XCTestCase {
    private static let requiredModes = ["location", "audio"]

    private enum PlistInspectionError: Error, CustomStringConvertible {
        case appBundleNotFound(start: URL)
        case notADictionary
        case missingBackgroundModes([String])

        var description: String {
            switch self {
            case let .appBundleNotFound(start):
                return "无法从 \(start.path) 向上定位已构建的 PurePace.app"
            case .notADictionary:
                return "Info.plist 根节点不是字典"
            case let .missingBackgroundModes(modes):
                return "Info.plist 缺少 UIBackgroundModes 数组（或非字符串数组），实际：\(modes)"
            }
        }
    }

    // MARK: - 构建产物本体读回

    func testBuiltAppInfoPlistDeclaresLocationAndAudioBackgroundModes() throws {
        let plistURL = try Self.builtAppInfoPlistURL()
        let modes = try Self.backgroundModes(fromPlistAt: plistURL)

        XCTAssertTrue(
            modes.contains("location"),
            "构建产物 \(plistURL.path) 的 UIBackgroundModes 未含 location，实际：\(modes)"
        )
        XCTAssertTrue(
            modes.contains("audio"),
            "构建产物 \(plistURL.path) 的 UIBackgroundModes 未含 audio，实际：\(modes)"
        )
        XCTAssertEqual(
            Self.missingRequiredModes(in: modes),
            [],
            "构建产物 \(plistURL.path) 的 UIBackgroundModes 未同时覆盖 \(Self.requiredModes)，实际：\(modes)"
        )
    }

    // MARK: - 负向自检：同一读取路径在缺值时必须判红

    func testMissingRequiredModesDetectorRejectsEachMissingMode() throws {
        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("BackgroundModesPlistTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let both = try Self.writeFixturePlist(named: "both.plist", modes: ["location", "audio"], in: tmpDir)
        let onlyLocation = try Self.writeFixturePlist(named: "only-location.plist", modes: ["location"], in: tmpDir)
        let onlyAudio = try Self.writeFixturePlist(named: "only-audio.plist", modes: ["audio"], in: tmpDir)
        let empty = try Self.writeFixturePlist(named: "empty.plist", modes: [], in: tmpDir)

        XCTAssertEqual(Self.missingRequiredModes(in: try Self.backgroundModes(fromPlistAt: both)), [])
        XCTAssertEqual(
            Self.missingRequiredModes(in: try Self.backgroundModes(fromPlistAt: onlyLocation)),
            ["audio"],
            "缺少 audio 的夹具必须被同一读回路径判为缺 audio"
        )
        XCTAssertEqual(
            Self.missingRequiredModes(in: try Self.backgroundModes(fromPlistAt: onlyAudio)),
            ["location"],
            "缺少 location 的夹具必须被同一读回路径判为缺 location"
        )
        XCTAssertEqual(
            Self.missingRequiredModes(in: try Self.backgroundModes(fromPlistAt: empty)),
            ["location", "audio"],
            "空数组夹具必须被判为同时缺 location 与 audio"
        )
    }

    // MARK: - Helpers

    /// 从测试 bundle（`PurePace.app/PlugIns/PurePaceTests.xctest`）向上定位宿主 App 包，返回其 Info.plist 文件 URL。
    private static func builtAppInfoPlistURL() throws -> URL {
        let start = Bundle(for: BackgroundModesPlistTests.self).bundleURL
        var candidate = start
        for _ in 0..<6 {
            if candidate.pathExtension == "app" {
                let plist = candidate.appendingPathComponent("Info.plist", isDirectory: false)
                if FileManager.default.fileExists(atPath: plist.path) {
                    return plist
                }
            }
            let parent = candidate.deletingLastPathComponent()
            if parent.path == candidate.path { break }
            candidate = parent
        }
        throw PlistInspectionError.appBundleNotFound(start: start)
    }

    /// 读取 plist 文件本体（不做 Bundle 缓存解析），取出 `UIBackgroundModes` 字符串数组。
    private static func backgroundModes(fromPlistAt url: URL) throws -> [String] {
        let data = try Data(contentsOf: url)
        let object = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        guard let dict = object as? [String: Any] else {
            throw PlistInspectionError.notADictionary
        }
        guard let modes = dict["UIBackgroundModes"] as? [String] else {
            throw PlistInspectionError.missingBackgroundModes([])
        }
        return modes
    }

    private static func missingRequiredModes(in modes: [String]) -> [String] {
        requiredModes.filter { !modes.contains($0) }
    }

    private static func writeFixturePlist(named name: String, modes: [String], in dir: URL) throws -> URL {
        let url = dir.appendingPathComponent(name, isDirectory: false)
        let data = try PropertyListSerialization.data(
            fromPropertyList: ["UIBackgroundModes": modes],
            format: .xml,
            options: 0
        )
        try data.write(to: url, options: .atomic)
        return url
    }
}
