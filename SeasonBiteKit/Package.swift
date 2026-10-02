// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "SeasonBiteKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "SeasonBiteKit", targets: ["SeasonBiteKit"]),
    ],
    targets: [
        .target(name: "SeasonBiteKit"),
        .testTarget(name: "SeasonBiteKitTests", dependencies: ["SeasonBiteKit"]),
    ]
)
