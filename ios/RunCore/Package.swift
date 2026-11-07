// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PurePaceRunCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "PurePaceRunCore", targets: ["PurePaceRunCore"])
    ],
    targets: [
        .target(name: "PurePaceRunCore"),
        .testTarget(name: "PurePaceRunCoreTests", dependencies: ["PurePaceRunCore"])
    ]
)
