// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "example02-server",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(path: "../.."),                    // MIOExecutionKit
        .package(path: "../../../MIOServerKit"),    // MIOServerKit
    ],
    targets: [
        // The shared domain module from example01, now compiled into BOTH
        // executables. Diff vs example01: AppContext → ExecutionContext,
        // and chargeToAccount gained a routing rule.
        .target(
            name: "POSKit",
            dependencies: [
                .product(name: "MIOExecutionKit", package: "MIOExecutionKit")
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),

        .executableTarget(
            name: "pos-app",
            dependencies: [
                "POSKit",
                .product(name: "MIOExecutionClient", package: "MIOExecutionKit"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),

        // The new layer: same POSKit, served over MIOServerKit.
        .executableTarget(
            name: "pos-server",
            dependencies: [
                "POSKit",
                .product(name: "MIOExecutionServer", package: "MIOExecutionKit"),
                .product(name: "MIOServerKit", package: "MIOServerKit"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),

        .testTarget(
            name: "Example02Tests",
            dependencies: [
                "POSKit",
                .product(name: "MIOExecutionClient", package: "MIOExecutionKit"),
                .product(name: "MIOExecutionServer", package: "MIOExecutionKit"),
                .product(name: "MIOServerKit", package: "MIOServerKit"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
