/// 产品展示名 + 语义化版本号的只读构建元数据；版本由调用方注入，包内不写死任何版本。
public struct BuildMetadata: Sendable, Hashable {
    public let displayName: String
    public let version: SemanticVersion

    /// 显示名必须含至少一个非空白字符；版本须由调用方提供合法值。
    public init?(displayName: String, version: SemanticVersion) {
        guard Self.isValidDisplayName(displayName) else { return nil }
        self.displayName = displayName
        self.version = version
    }

    /// 便捷入口：显示名合法且版本字符串可严格解析时才成功。
    public init?(displayName: String, versionString: String) {
        guard let version = SemanticVersion(parsing: versionString) else { return nil }
        self.init(displayName: displayName, version: version)
    }

    private static func isValidDisplayName(_ name: String) -> Bool {
        !name.isEmpty && !name.allSatisfy { $0.isWhitespace }
    }
}
