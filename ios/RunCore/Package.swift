// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PurePaceRunCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "PurePaceRunCore", targets: ["PurePaceRunCore"]),
        .executable(name: "PurePaceGpxTool", targets: ["PurePaceGpxTool"])
    ],
    targets: [
        .target(name: "PurePaceRunCore"),
        .executableTarget(name: "PurePaceGpxTool", dependencies: ["PurePaceRunCore"]),
        .testTarget(name: "PurePaceRunCoreTests", dependencies: ["PurePaceRunCore"])
    ]
)
