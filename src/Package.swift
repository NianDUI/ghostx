// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GhostX",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "GhostX",
            path: "GhostX"
        ),
    ]
)
