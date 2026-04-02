// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RcloneKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "RcloneKit", targets: ["RcloneKit"]),
    ],
    targets: [
        .target(name: "RcloneKit"),
        .testTarget(name: "RcloneKitTests", dependencies: ["RcloneKit"]),
    ]
)
