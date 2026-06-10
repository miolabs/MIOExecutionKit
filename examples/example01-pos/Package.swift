// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "example01-pos",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        // The whole app: domain logic over Core Data. No server, no
        // execution framework — this is the "build the app standalone"
        // starting point of the tutorial series.
        .target(name: "POSKit", swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(
            name: "pos-app",
            dependencies: ["POSKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "POSKitTests",
            dependencies: ["POSKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
