// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Counterpoint2",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "CP2Geometry", targets: ["CP2Geometry"]),
        .library(name: "CP2Skeleton", targets: ["CP2Skeleton"]),
        .executable(name: "cp2-cli", targets: ["cp2-cli"])
    ],
    targets: [
        .target(
            name: "CP2Geometry",
            dependencies: []
        ),
        .target(
            name: "CP2Skeleton",
            dependencies: ["CP2Geometry"],
            exclude: [
                "Sampling/README.md"
            ]
        ),
        .executableTarget(
            name: "cp2-cli",
            dependencies: ["CP2Geometry", "CP2Skeleton"]
        ),
        .testTarget(
            name: "CP2GeometryTests",
            dependencies: ["CP2Geometry"]
        ),
        .testTarget(
            name: "CP2SkeletonTests",
            dependencies: ["CP2Skeleton"],
            exclude: [
                "RingIntersectionTests.swift.disabled"
            ]
        ),
        .testTarget(
            name: "CP2CLITests",
            dependencies: ["cp2-cli"],
            exclude: [
                "SweepPlanTests.swift.disabled",
                "KeyframedScalarTests.swift.disabled"
            ]
        )
    ]
)
