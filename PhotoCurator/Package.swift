// swift-tools-version: 5.7
import PackageDescription

let package = Package(
    name: "PhotoCurator",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "PhotoCurator",
            targets: ["PhotoCurator"]),
    ],
    dependencies: [
    ],
    targets: [
        .target(
            name: "PhotoCurator",
            dependencies: [],
            resources: [
                .process("PhotoCurator.xcdatamodeld")
            ]
        ),
        .testTarget(
            name: "PhotoCuratorTests",
            dependencies: ["PhotoCurator"]),
    ]
)