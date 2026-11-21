// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OpenWilo",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "OpenWilo", targets: ["OpenWilo"])],
    targets: [
        .target(name: "OpenWiloCore"),
        .executableTarget(name: "OpenWilo", dependencies: ["OpenWiloCore"]),
        .testTarget(name: "OpenWiloCoreTests", dependencies: ["OpenWiloCore"])
    ]
)
