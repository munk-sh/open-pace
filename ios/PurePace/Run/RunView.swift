import SwiftUI

/// 首屏跑步页：实时距离/时长/配速/分段 + 开始/暂停/恢复/结束，结束后给出「已保存」。
/// 所有数值来自 `RunSessionViewModel`（即 `RunSessionOrchestrator.metrics`），View 只做绑定与格式化。
struct RunView: View {
    @ObservedObject var viewModel: RunSessionViewModel

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                metric(
                    title: "Distance",
                    value: viewModel.distanceText,
                    identifier: "run.distance",
                    font: .system(size: 56, weight: .bold, design: .rounded)
                )

                HStack(alignment: .top, spacing: 20) {
                    metric(title: "Time", value: viewModel.elapsedText, identifier: "run.elapsed")
                    metric(title: "Current", value: viewModel.currentPaceText, identifier: "run.currentPace")
                    metric(title: "Average", value: viewModel.averagePaceText, identifier: "run.averagePace")
                    metric(title: "Splits", value: viewModel.splitCountText, identifier: "run.splits")
                }

                if let message = statusMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                if let hint = viewModel.authorization.backgroundDegradationHint {
                    Text(hint)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("run.backgroundDegraded")
                }

                if viewModel.didSave {
                    Text("已保存")
                        .font(.headline)
                        .foregroundStyle(.green)
                        .accessibilityIdentifier("run.saved")
                }

                controls

                Spacer()
            }
            .padding()
            .navigationTitle("Run")
            .onAppear { viewModel.onAppear() }
        }
    }

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
            controlButton("开始", identifier: "run.start") {
                viewModel.start()
            }
        case .running:
            HStack(spacing: 16) {
                controlButton("暂停", identifier: "run.pause") { viewModel.pause() }
                controlButton("结束", identifier: "run.finish") { viewModel.finish() }
            }
        case .paused:
            HStack(spacing: 16) {
                controlButton("继续", identifier: "run.resume") { viewModel.resume() }
                controlButton("结束", identifier: "run.finish") { viewModel.finish() }
            }
        case .finished:
            EmptyView()
        }
    }

    private func controlButton(_ title: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .frame(minWidth: 120, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .accessibilityIdentifier(identifier)
    }

    private func metric(
        title: String,
        value: String,
        identifier: String,
        font: Font = .title3
    ) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(font)
                .monospacedDigit()
                .accessibilityIdentifier(identifier)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
