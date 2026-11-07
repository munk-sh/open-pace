import SwiftUI

@main
struct PurePaceApp: App {
    private let activation = HarnessArgumentParser.parse(arguments: CommandLine.arguments)

    var body: some Scene {
        WindowGroup {
            if case .inactive = activation {
                ContentView()
            } else {
                HarnessRootView(activation: activation)
            }
        }
    }
}
