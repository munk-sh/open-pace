import Foundation

/// 与平台无关的轴对齐矩形（纯值类型）。
/// `ios/Core` 只允许 `import Foundation`，故本文件不引用平台图形类型；
/// UI 用例与单测在边界处把真实 frame 换算成本类型，判定口径仍是一份实现。
public struct RunLayoutFrame: Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var minY: Double { y }
    public var maxY: Double { y + height }
    public var midX: Double { x + width / 2 }
    public var midY: Double { y + height / 2 }
    public var isEmpty: Bool { width <= 0 || height <= 0 }

    /// 四边各内缩 `amount`（用于胶囊判据的边界容差）。
    public func insetBy(_ amount: Double) -> RunLayoutFrame {
        RunLayoutFrame(
            x: x + amount,
            y: y + amount,
            width: width - 2 * amount,
            height: height - 2 * amount
        )
    }

    /// 点是否落在本矩形内（含边界）。
    public func contains(x pointX: Double, y pointY: Double) -> Bool {
        pointX >= x && pointX <= x + width && pointY >= y && pointY <= y + height
    }
}

/// 一轮「运行指标区」采样：导航栏下沿、主操作顶边与可见内容帧集合。
/// UI 用例按同一口径逐轮采集，L1 单测喂合成序列，两处共用本文件的比较口径。
public struct RunLayoutSample: Equatable, Sendable {
    /// 内容区上界（导航栏下沿）。
    public let navigationBarBottom: Double
    /// 内容区下界（主操作顶边）。
    public let primaryActionTop: Double
    /// 采集到的可见内容块（含 inline 胶囊与地图卡）frame。
    public let contentFrames: [RunLayoutFrame]

    public init(
        navigationBarBottom: Double,
        primaryActionTop: Double,
        contentFrames: [RunLayoutFrame]
    ) {
        self.navigationBarBottom = navigationBarBottom
        self.primaryActionTop = primaryActionTop
        self.contentFrames = contentFrames
    }
}

/// 采样确定性判定（纯函数，无外部 IO）：
/// （a）帧集合连续 3 轮逐位一致才算「布局稳定」；（b）胶囊内层文本帧按帧中心点去重。
/// 预算在测量前写死、不因判红回调：连续一致 3 轮、轮数上限 12、单态等待上限 6s。
public enum RunLayoutSamplingPolicy {
    /// 连续一致轮数：低于 3 轮时一次瞬时重排就可能把抖动样本当成终值。
    public static let requiredStableRounds = 3
    /// 单态采样轮数上限（有界，不无限重采）。
    public static let maximumRounds = 12
    /// 单态等待上限（秒）：只作有界退出上界，不作「等够了就算稳定」的判据。
    public static let settleTimeout: TimeInterval = 6
    /// 胶囊矩形判据的边界内缩容差：中心点须落在内缩后的矩形内才算内层帧。
    public static let hintInsetTolerance: Double = 0.5

    /// 两轮采样是否描述同一布局：导航栏下沿、主操作顶边与内容帧逐位一致（零容差）。
    /// 帧顺序由可及树遍历决定、与几何无关，比较前按几何键排序消除纯顺序抖动；
    /// 排序只消解顺序，不对任何坐标做取整或容差。
    public static func isSameLayout(_ lhs: RunLayoutSample, _ rhs: RunLayoutSample) -> Bool {
        lhs.navigationBarBottom == rhs.navigationBarBottom
            && lhs.primaryActionTop == rhs.primaryActionTop
            && canonicalFrames(lhs.contentFrames) == canonicalFrames(rhs.contentFrames)
    }

    /// 首轮之后再出现 `requiredStableRounds - 1` 次逐位一致即判稳定。
    public struct SettleTracker {
        /// 已记录的轮数。
        public private(set) var rounds = 0
        /// 当前连续一致轮数（首轮计 1）。
        public private(set) var consecutiveMatches = 0
        private var latest: RunLayoutSample?

        public init() {}

        /// 最近一轮样本（未稳定时即为抖动样本，UI 诊断直接用）。
        public var lastSample: RunLayoutSample? { latest }

        /// 是否已达「连续 `requiredStableRounds` 轮逐位一致」。
        public var isStable: Bool {
            consecutiveMatches >= RunLayoutSamplingPolicy.requiredStableRounds
        }

        /// 稳定后的终值样本；未稳定返回 nil（调用方不得把它当稳定结果判定）。
        public var stableSample: RunLayoutSample? { isStable ? latest : nil }

        /// 是否还允许继续采样：未稳定且未用完轮数上限。
        public var canRecordMore: Bool {
            !isStable && rounds < RunLayoutSamplingPolicy.maximumRounds
        }

        /// 记录一轮采样；返回该轮之后是否已稳定。
        @discardableResult
        public mutating func record(_ sample: RunLayoutSample) -> Bool {
            rounds += 1
            if let latest, RunLayoutSamplingPolicy.isSameLayout(latest, sample) {
                consecutiveMatches += 1
            } else {
                consecutiveMatches = 1
            }
            latest = sample
            return isStable
        }
    }

    /// 把一串轮次样本喂给同一判定，返回首个稳定样本；持续漂移时返回 nil。
    public static func settledSample(from samples: [RunLayoutSample]) -> RunLayoutSample? {
        var tracker = SettleTracker()
        for sample in samples {
            tracker.record(sample)
            if let stable = tracker.stableSample { return stable }
        }
        return nil
    }

    /// 内层文本帧判据：帧中心点落入胶囊矩形（四边各内缩 `hintInsetTolerance`）即判为内层帧。
    ///
    /// 推导：稳定布局下内层文本 frame 比胶囊高 1.42pt（图标与文案合并后的行高差），
    /// 上下各外扩 0.71pt 后严格包含判据为假，于是同一可见内容块被当成「胶囊 + 文本」
    /// 双计并影响最大空洞；但该帧与胶囊同心，中心点仍落在胶囊内，故中心点判据能覆盖
    /// 1.42pt 情形。中心点落在胶囊外的相邻内容块（如紧贴胶囊下沿的说明文案）不受影响。
    public static func isFrameInsideHint(_ frame: RunLayoutFrame, hint: RunLayoutFrame) -> Bool {
        guard !frame.isEmpty, !hint.isEmpty else { return false }
        let target = hint.insetBy(hintInsetTolerance)
        guard target.width > 0, target.height > 0 else { return false }
        return target.contains(x: frame.midX, y: frame.midY)
    }

    /// 去掉胶囊内层文本帧；胶囊自身的 frame（与 hint 逐位相等）保留，保证内容块不被清空。
    public static func dedupeFramesInsideHint(
        _ frames: [RunLayoutFrame],
        hint: RunLayoutFrame?
    ) -> [RunLayoutFrame] {
        guard let hint, !hint.isEmpty else { return frames }
        return frames.filter { frame in
            frame == hint || !isFrameInsideHint(frame, hint: hint)
        }
    }

    /// 逐位比较用的规范化帧序列（几何键排序）。
    private static func canonicalFrames(_ frames: [RunLayoutFrame]) -> [RunLayoutFrame] {
        frames.sorted { lhs, rhs in
            if lhs.minY != rhs.minY { return lhs.minY < rhs.minY }
            if lhs.x != rhs.x { return lhs.x < rhs.x }
            if lhs.height != rhs.height { return lhs.height < rhs.height }
            return lhs.width < rhs.width
        }
    }
}
