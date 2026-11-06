/// 严格的 `x.y.z` 版本号：只接受三段十进制数字，拒绝前缀、后缀、缺段、多段与前导零。
public struct SemanticVersion: Sendable, Hashable, Comparable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int

    /// 解析严格的三段版本号字符串；任何不符合 `x.y.z` 的输入返回 nil。
    public init?(parsing text: String) {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }

        var components: [Int] = []
        components.reserveCapacity(3)
        for part in parts {
            guard let value = Self.parseComponent(part) else { return nil }
            components.append(value)
        }

        self.major = components[0]
        self.minor = components[1]
        self.patch = components[2]
    }

    public var description: String {
        "\(major).\(minor).\(patch)"
    }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }

    /// 单段必须非空、全为 ASCII 数字，且除 `0` 外不得有前导零。
    private static func parseComponent(_ text: Substring) -> Int? {
        guard !text.isEmpty else { return nil }
        guard text.allSatisfy({ $0 >= "0" && $0 <= "9" }) else { return nil }
        if text.count > 1 && text.first == "0" { return nil }
        return Int(text)
    }
}
