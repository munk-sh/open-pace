#if DEBUG
import PurePaceRunCore
import SwiftUI

/// V1.2 设计稿（`docs/design-draft-v12/`）专用配色与运行期量测，**仅 DEBUG 编译**。
///
/// 本文件是设计稿里唯一允许出现颜色字面量的地方：它承载的是「候选值」，不是生产 token；
/// `ios/PurePace/Design/DesignTokens.swift` 保持零改动（结论写进 `token-diff.md`，不落地）。
///
/// 阈值先定后测（2026-11-12，与 `ContrastPolicy` 同一 WCAG 2.x 公式 `(L1+0.05)/(L2+0.05)`，
/// 相对亮度分段线性 `c/12.92`（c ≤ 0.04045）/ `((c+0.055)/1.055)^2.4`）：
/// - 非文本 UI 组件：实心主按钮底 vs 页面底（light `background` `#FAFAF9`）≥ 3:1；
/// - 按钮文字：`onAccent` vs `accent` ≥ 4.5:1；
/// - 浅色 accent 必须仍是橙：HSL 色相 H ∈ [20°, 35°]、S ≥ 60%，禁止压暗成砖红/棕。
/// 先定色相区间与「亮底深字 / 深底白字」两种意图，再用公式实测；实测值写 README（不得先测后凑）。
struct DesignDraftPalette {
    let accent: Color
    let onAccent: Color

    /// 除 accent / onAccent 外全部取生产 token，保证 A1↔A2 对照只差这两个颜色。
    static func hex(_ value: UInt32) -> Color {
        Color(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    /// A1「饱和橙底 + 深字」：accent `#E85D04`（H 23.4° / S 97% / L 46%），onAccent `#1F1200`。
    static let a1 = DesignDraftPalette(
        accent: hex(0xE85D04),
        onAccent: hex(0x1F1200)
    )

    /// A2「深橙底 + 白字」：accent `#BE4E05`（H 23.7° / S 95% / L 38%），onAccent `#FFFFFF`。
    static let a2 = DesignDraftPalette(
        accent: hex(0xBE4E05),
        onAccent: hex(0xFFFFFF)
    )

    /// B/C 组不比较颜色：直接沿用生产 token，只考察版式。
    static let production = DesignDraftPalette(
        accent: DesignTokens.Colors.accent,
        onAccent: DesignTokens.Colors.onAccent
    )
}

/// 设计稿统一真实数据（与 `docs/screenshots/run-finished*.png` 同源 fixture：1.20 km / 00:22）：
/// 坐标基准与推进方式照抄 `RunTestLocationSource`（37.3349 / -122.0090，纬度按米换算推进），
/// 时长 22 s 内按 1 Hz 采样，距离锁死 1 200 m。分段 = 1 km 完整段 + 0.20 km 尾段。
enum DesignDraftFixture {
    static let distanceMeters: Double = 1_200
    static let activeDuration: TimeInterval = 22
    static let distanceText = "1.20"
    static let durationText = "00:22"
    static let averagePaceText = "0:18"
    static let splitsSummaryText = "2"

    private static let baseLatitude = 37.334900
    private static let baseLongitude = -122.009000
    private static let metersPerDegreeLatitude = 111_194.93
    private static let sampleCount = 22

    /// 逐秒采样：22 个点沿纬度推进 1 200 m，供 `TrackMapView` 画真实折线（不手绘轨迹）。
    static let samples: [RunSample] = {
        let startedAt = Date(timeIntervalSince1970: 1_760_000_000)
        return (0..<sampleCount).compactMap { index in
            let ratio = Double(index) / Double(sampleCount - 1)
            return RunSample(
                latitude: baseLatitude + distanceMeters * ratio / metersPerDegreeLatitude,
                longitude: baseLongitude,
                altitude: 4,
                timestamp: startedAt.addingTimeInterval(Double(index)),
                heartRate: 152,
                cadence: 178
            )
        }
    }()

    struct Split: Identifiable {
        let id: Int
        let distance: String
        let pace: String
    }

    /// 分段明细：1.00 km（0:18 /km）+ 剩余 0.20 km（0:04 /km），合计 1.20 km / 00:22。
    static let splits: [Split] = [
        Split(id: 1, distance: "1.00 km", pace: "0:18 /km"),
        Split(id: 2, distance: "0.20 km", pace: "0:04 /km")
    ]
}

/// 运行期量测输出：`simctl launch --console-pty` 直接收 stdout，作为 README 高度表的实测来源。
/// 只打印，不落盘、不改状态；`#if DEBUG` 外不存在。
enum DesignDraftReporter {
    static func reportScreen(_ variant: String, scale: CGFloat, size: CGSize) {
        print(
            String(
                format: "designDraft.screen %@ scale=%.1f pt=%.1fx%.1f px=%.0fx%.0f",
                variant,
                scale,
                size.width,
                size.height,
                size.width * scale,
                size.height * scale
            )
        )
    }

    static func report(_ variant: String, label: String, size: CGSize) {
        guard size.height > 0 else { return }
        print(
            String(
                format: "designDraft.height %@ %@ w=%.1f h=%.1f",
                variant,
                label,
                size.width,
                size.height
            )
        )
    }

    /// 稳定就绪标记：截图脚本轮询该行，不靠固定 sleep 猜页面就绪。
    static func markReady(_ variant: String, after delay: TimeInterval = 1.6) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            print("designDraft.ready \(variant)")
        }
    }
}

/// 尺寸探针：把某个区块的实测高度（pt）打到日志，供高度表引用。
private struct DesignDraftProbe: ViewModifier {
    let variant: String
    let label: String

    func body(content: Content) -> some View {
        content.background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear {
                        DesignDraftReporter.report(variant, label: label, size: proxy.size)
                    }
                    .onChange(of: proxy.size) { _, size in
                        DesignDraftReporter.report(variant, label: label, size: size)
                    }
            }
        )
    }
}

extension View {
    func designDraftProbe(_ label: String, variant: String) -> some View {
        modifier(DesignDraftProbe(variant: variant, label: label))
    }
}
#endif
