// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "RideKit",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "RideKit", targets: ["RideKit"]),
    ],
    targets: [
        .target(name: "RideKit"),
        .testTarget(name: "RideKitTests", dependencies: ["RideKit"]),
    ]
)
