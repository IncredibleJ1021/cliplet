// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Clip",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Clip", targets: ["Clip"]),
        .library(name: "ClipCore", targets: ["ClipCore"])
    ],
    targets: [
        .target(name: "ClipCore"),
        .executableTarget(
            name: "Clip",
            dependencies: ["ClipCore"]
        ),
        .testTarget(
            name: "ClipCoreTests",
            dependencies: ["ClipCore"]
        )
    ]
)
