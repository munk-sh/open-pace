import SwiftUI

@main
struct PurePaceApp: App {
    private let activation = HarnessArgumentParser.parse(arguments: CommandLine.arguments)

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            // V1.2 设计稿入口：只在显式 `-designDraftV12 <变体号>` 时接管根视图；
            // 无该参数时与 Release 完全同路径（Release 编译期不存在该分支）。
            if let draft = DesignDraftV12.requested() {
                DesignDraftRootView(variant: draft)
            } else {
                rootContent
            }
            #else
            rootContent
            #endif
        }
    }

    @ViewBuilder
    private var rootContent: some View {
        if case .inactive = activation {
            ContentView()
        } else {
            HarnessRootView(activation: activation)
        }
    }
}
