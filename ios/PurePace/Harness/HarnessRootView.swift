import SwiftUI

/// 无业务 UI 的 Harness 根视图：只负责按 launch arg 启动对应采样源，不铺任何控件。
struct HarnessRootView: View {
    let activation: HarnessActivation

    @State private var locationController: HarnessLocationController?

    var body: some View {
        Color.clear
            .ignoresSafeArea()
            .onAppear(perform: launch)
            .onDisappear { locationController?.stop() }
    }

    private func launch() {
        switch activation {
        case .inactive:
            return
        case .invalid:
            HarnessBootstrap.writeArgumentFailure(activation)
        case let .active(configuration):
            switch configuration.mode {
            case .direct, .resume:
                Task.detached(priority: .userInitiated) {
                    HarnessRunner(configuration: configuration).run()
                }
            case .corelocation:
                let controller = HarnessLocationController(configuration: configuration)
                locationController = controller
                controller.start()
            }
        }
    }
}
