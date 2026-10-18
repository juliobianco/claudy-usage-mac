// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ClaudyUsage",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "ClaudyCore"),
        .executableTarget(name: "ClaudyUsage", dependencies: ["ClaudyCore"], resources: [.copy("skins")]),
        .testTarget(name: "ClaudyCoreTests", dependencies: ["ClaudyCore"]),
    ]
)
