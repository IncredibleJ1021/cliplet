// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "cliplet",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "cliplet", targets: ["Cliplet"]),
        .library(name: "ClipletCore", targets: ["ClipletCore"])
    ],
    targets: [
        .target(name: "ClipletCore"),
        .executableTarget(
            name: "Cliplet",
            dependencies: ["ClipletCore"]
        ),
        .testTarget(
            name: "ClipletCoreTests",
            dependencies: ["ClipletCore"]
        ),
        .testTarget(
            name: "ClipletTests",
            dependencies: ["Cliplet", "ClipletCore"]
        )
    ]
)
