// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Snaps",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Snaps", path: "Sources/Snaps")
    ]
)
