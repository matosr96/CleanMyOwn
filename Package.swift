// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CleanMyOwn",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "CleanMyOwn",
            path: ".",
            exclude: ["README.md", "CleanMyOwn.app", "run.sh", "Tests"],
            sources: ["App", "Core", "Modules", "UI"]
        ),
        .testTarget(
            name: "CleanMyOwnTests",
            dependencies: ["CleanMyOwn"],
            path: "Tests"
        )
    ]
)
