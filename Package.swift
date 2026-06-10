// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "pets",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "pets", path: "Sources/Pets")
    ]
)
