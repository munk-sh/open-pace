import SwiftUI

/// 设置页：本阶段没有可配置项，明确声明而不放置任何假开关或示例数值。
struct SettingsView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Text("本阶段暂无可配置项")
                    .font(.headline)
                    .accessibilityIdentifier("settings.empty")
                Text("每公里播报开关与偏好持久化将在后续阶段提供。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Settings")
        }
    }
}
