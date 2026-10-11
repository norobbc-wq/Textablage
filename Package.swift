// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TextablageCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "TextablageCore", targets: ["TextablageCore"])],
    targets: [
        .target(name: "TextablageCore", path: "Shared"),
        .testTarget(name: "TextablageCoreTests", dependencies: ["TextablageCore"], path: "Tests")
    ],
    swiftLanguageVersions: [.v5]
)
