// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PurePaceCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "PurePaceCore", targets: ["PurePaceCore"])
    ],
    targets: [
        .target(name: "PurePaceCore"),
        .testTarget(name: "PurePaceCoreTests", dependencies: ["PurePaceCore"])
    ]
)
