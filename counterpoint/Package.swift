// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Counterpoint",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "CounterpointDomain", targets: ["Domain"]),
        .library(name: "CounterpointUseCases", targets: ["UseCases"]),
        .library(name: "CounterpointAdapters", targets: ["Adapters"]),
        .executable(name: "counterpoint-cli", targets: ["CounterpointCLI"])
    ],
    dependencies: [
        .package(url: "https://github.com/iShape-Swift/iOverlay.git", branch: "main")
    ],
    targets: [
        .target(
            name: "Domain",
            dependencies: []
        ),
        .target(
            name: "UseCases",
            dependencies: ["Domain"]
        ),
        .target(
            name: "Adapters",
            dependencies: ["Domain", "iOverlay"]
        ),
        .executableTarget(
            name: "CounterpointCLI",
            dependencies: ["UseCases", "Adapters", "Domain"]
        ),
        .testTarget(
            name: "DomainTests",
            dependencies: ["Domain"]
        ),
        .testTarget(
            name: "AdaptersTests",
            dependencies: ["Adapters", "Domain"]
        ),
        .testTarget(
            name: "CLITests",
            dependencies: ["CounterpointCLI", "Domain"]
        ),
        .testTarget(
            name: "UseCaseTests",
            dependencies: ["UseCases", "Adapters", "Domain"]
        )
    ]
)
