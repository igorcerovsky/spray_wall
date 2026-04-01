// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "SprayWall",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .executable(name: "SprayWall", targets: ["SprayWall"])
    ],
    targets: [
        .executableTarget(
            name: "SprayWall"
        ),
        .testTarget(
            name: "SprayWallTests",
            dependencies: ["SprayWall"]
        )
    ]
)
