// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CleanMyOwn",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "CleanMyOwn",
            path: ".",
            exclude: ["README.md", "CleanMyOwn.app", "run.sh"],
            sources: ["App", "Core", "Modules", "UI"]
        )
    ]
)
