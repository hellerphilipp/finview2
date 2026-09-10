// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ImportKit",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "ImportKit", targets: ["ImportKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.1.0"),
    ],
    targets: [
        .target(
            name: "ImportKit",
            dependencies: ["Yams"],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "ImportKitTests",
            dependencies: ["ImportKit"]
        ),
    ]
)
