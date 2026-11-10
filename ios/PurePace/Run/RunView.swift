import SwiftUI

/// 首屏跑步页：距离 / 时长 / 当前配速为强主信息，平均配速与分段为次信息；
/// 开始 / 暂停 / 继续 / 结束是唯一主操作区，三态可辨。样式全部取自 `DesignTokens`。
/// 所有数值来自 `RunSessionViewModel`（即 `RunSessionOrchestrator.metrics`），View 只做绑定与格式化。
struct RunView: View {
    @ObservedObject var viewModel: RunSessionViewModel

    var body: some View {
        NavigationStack {
            VStack(spacing: DesignTokens.Spacing.lg) {
                distanceHero

                HStack(alignment: .top, spacing: DesignTokens.Spacing.md) {
                    primaryMetric(title: "Time", value: viewModel.elapsedText, identifier: "run.elapsed")
                    primaryMetric(
                        title: "Current",
                        value: viewModel.currentPaceText,
                        identifier: "run.currentPace"
                    )
                }

                HStack(alignment: .top, spacing: DesignTokens.Spacing.md) {
                    secondaryMetric(
                        title: "Average",
                        value: viewModel.averagePaceText,
                        identifier: "run.averagePace"
                    )
                    secondaryMetric(title: "Splits", value: viewModel.splitCountText, identifier: "run.splits")
                }

                if let message = statusMessage {
                    Text(message)
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(DesignTokens.Colors.secondary)
                        .multilineTextAlignment(.center)
                }

                if let hint = viewModel.authorization.backgroundDegradationHint {
                    Text(hint)
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(DesignTokens.Colors.warning)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("run.backgroundDegraded")
                }

                if viewModel.didSave {
                    Text("已保存")
                        .font(DesignTokens.Typography.title)
                        .foregroundStyle(DesignTokens.Colors.success)
                        .accessibilityIdentifier("run.saved")
                }

#if DEBUG
                if let summary = viewModel.telemetrySummary {
                    Text(summary)
                        .font(DesignTokens.Typography.caption)
                        .foregroundStyle(DesignTokens.Colors.secondary)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("run.telemetry")
                }
#endif

                controls

                Spacer()
            }
            .padding(DesignTokens.Spacing.md)
            .navigationTitle("Run")
            .onAppear { viewModel.onAppear() }
        }
        .accessibilityIdentifier("tab.run")
    }

    // MARK: - 主信息

    private var distanceHero: some View {
        VStack(spacing: DesignTokens.Spacing.xs) {
            Text(viewModel.distanceText)
                .font(DesignTokens.Typography.display)
                .foregroundStyle(DesignTokens.Colors.primary)
                .monospacedDigit()
                .accessibilityIdentifier("run.distance")
            Text("Distance")
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(DesignTokens.Colors.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DesignTokens.Spacing.sm)
    }

    private func primaryMetric(title: String, value: String, identifier: String) -> some View {
        VStack(spacing: DesignTokens.Spacing.xxs) {
            Text(value)
                .font(DesignTokens.Typography.primaryValue)
                .foregroundStyle(DesignTokens.Colors.primary)
                .monospacedDigit()
                .accessibilityIdentifier(identifier)
            Text(title)
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(DesignTokens.Colors.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 次信息

    private func secondaryMetric(title: String, value: String, identifier: String) -> some View {
        VStack(spacing: DesignTokens.Spacing.xxs) {
            Text(value)
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(DesignTokens.Colors.secondary)
                .monospacedDigit()
                .accessibilityIdentifier(identifier)
            Text(title)
                .font(DesignTokens.Typography.caption)
                .foregroundStyle(DesignTokens.Colors.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 主操作

    private var statusMessage: String? {
        if let error = viewModel.errorMessage {
            return error
        }
        if viewModel.state == .ready {
            switch viewModel.authorization {
            case .denied, .restricted:
                return "定位不可用，请在系统设置中允许 PurePace 使用定位。"
            case .notDetermined:
                return "等待定位授权…"
            case .authorizedWhenInUse, .authorizedAlways:
                return nil
            }
        }
        return nil
    }

    @ViewBuilder
    private var controls: some View {
        switch viewModel.state {
        case .ready:
            primaryControl("开始", label: "开始记录跑次") {
                viewModel.start()
            }
            .accessibilityIdentifier("run.start")
        case .running:
            HStack(spacing: DesignTokens.Spacing.sm) {
                primaryControl("暂停", label: "暂停记录跑次") { viewModel.pause() }
                    .accessibilityIdentifier("run.pause")
                secondaryControl("结束", label: "结束并保存跑次") { viewModel.finish() }
                    .accessibilityIdentifier("run.finish")
            }
        case .paused:
            HStack(spacing: DesignTokens.Spacing.sm) {
                primaryControl("继续", label: "继续记录跑次") { viewModel.resume() }
                    .accessibilityIdentifier("run.resume")
                secondaryControl("结束", label: "结束并保存跑次") { viewModel.finish() }
                    .accessibilityIdentifier("run.finish")
            }
        case .finished:
            EmptyView()
        }
    }

    private func primaryControl(
        _ title: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(DesignTokens.Typography.control)
                .frame(maxWidth: .infinity)
                .frame(minHeight: DesignTokens.minTapTarget)
        }
        .buttonStyle(.borderedProminent)
        .tint(DesignTokens.Colors.accent)
        .accessibilityLabel(label)
    }

    private func secondaryControl(
        _ title: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(DesignTokens.Typography.control)
                .frame(maxWidth: .infinity)
                .frame(minHeight: DesignTokens.minTapTarget)
        }
        .buttonStyle(.bordered)
        .tint(DesignTokens.Colors.warning)
        .accessibilityLabel(label)
    }
}
