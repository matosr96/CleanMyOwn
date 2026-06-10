// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CleanMyOwn",
    platforms: [.macOS(.v14)],
    targets: [
        // Código compartido entre la app y el helper privilegiado:
        // protocolo XPC, allowlist de borrado como root y ShellRunner.
        .target(
            name: "CleanMyOwnShared",
            path: "Shared"
        ),
        .executableTarget(
            name: "CleanMyOwn",
            dependencies: ["CleanMyOwnShared"],
            path: ".",
            exclude: ["README.md", "LICENSE", "CleanMyOwn.app", "run.sh", "Tests", "Shared", "Helper"],
            sources: ["App", "Core", "Modules", "UI"]
        ),
        // Daemon root registrado vía SMAppService.daemon (ver Helper/main.swift).
        .executableTarget(
            name: "CleanMyOwnHelper",
            dependencies: ["CleanMyOwnShared"],
            path: "Helper"
        ),
        .testTarget(
            name: "CleanMyOwnTests",
            dependencies: ["CleanMyOwn", "CleanMyOwnShared"],
            path: "Tests"
        )
    ]
)
