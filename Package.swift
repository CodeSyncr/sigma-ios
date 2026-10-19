// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "NimbusSigma",
    platforms: [.iOS(.v16), .macOS(.v13), .visionOS(.v1)],
    products: [
        .library(name: "NimbusSigma", targets: ["NimbusSigma"]),
    ],
    targets: [
        // Sigma's engine is not in the package: a session downloads it from
        // Sigma for a sheet opened through the API (see SigmaSession).
        .target(name: "NimbusSigma"),
        .testTarget(name: "NimbusSigmaTests", dependencies: ["NimbusSigma"]),
    ]
)
