// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "NimbusSigma",
    platforms: [.iOS(.v15), .macOS(.v12), .visionOS(.v1)],
    products: [
        .library(name: "NimbusSigma", targets: ["NimbusSigma"]),
    ],
    targets: [
        .target(name: "NimbusSigma"),
        .testTarget(name: "NimbusSigmaTests", dependencies: ["NimbusSigma"]),
    ]
)
