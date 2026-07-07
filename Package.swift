// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "mission-wheel",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "mission-wheel",
            targets: ["MissionWheel"]
        )
    ],
    targets: [
        .target(name: "MissionWheelCore"),
        .executableTarget(
            name: "MissionWheel",
            dependencies: ["MissionWheelCore"],
            linkerSettings: [
                .linkedFramework("ApplicationServices"),
                .linkedFramework("AppKit"),
                .linkedFramework("CoreGraphics")
            ]
        ),
        .testTarget(
            name: "MissionWheelCoreTests",
            dependencies: ["MissionWheelCore"]
        )
    ]
)
