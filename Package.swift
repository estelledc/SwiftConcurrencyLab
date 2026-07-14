// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SwiftConcurrencyCore",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "SwiftConcurrencyCore", targets: ["SwiftConcurrencyCore"])],
    targets: [
        .target(name: "SwiftConcurrencyCore"),
        .testTarget(name: "SwiftConcurrencyCoreTests", dependencies: ["SwiftConcurrencyCore"])
    ]
)
