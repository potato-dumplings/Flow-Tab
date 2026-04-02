// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "FlowTab",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "FlowTabCore", targets: ["FlowTabCore"])
    ],
    targets: [
        .target(
            name: "FlowTabCore"
        ),
        .testTarget(
            name: "FlowTabCoreTests",
            dependencies: ["FlowTabCore"]
        )
    ]
)
