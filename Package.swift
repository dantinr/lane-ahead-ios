// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LaneAheadCore",
    platforms: [.macOS(.v13), .iOS(.v17)],
    products: [.library(name: "LaneAheadCore", targets: ["LaneAheadCore"])],
    targets: [
        .target(name: "LaneAheadCore", path: "LaneAhead/Core"),
        .target(name: "LANavigationPayload", path: "LaneAhead/Bridge/RoutePayload", publicHeadersPath: "."),
        .testTarget(name: "LaneAheadCoreTests", dependencies: ["LaneAheadCore", "LANavigationPayload"], path: "Tests/Core")
    ]
)
