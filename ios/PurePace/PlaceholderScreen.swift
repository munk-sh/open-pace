import SwiftUI

/// 每个空 Tab 共用的占位视图：仅展示标题与可选说明。
struct PlaceholderScreen: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(spacing: 12) {
            Text(title)
                .font(.largeTitle)
                .fontWeight(.semibold)
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
