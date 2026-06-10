// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "example03-manager",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(path: "../.."),                    // MIOExecutionKit
        .package(path: "../../../MIOServerKit"),    // MIOServerKit
    ],
    targets: [
        // Diff vs example02: nextDocumentNumber gained a .manager(.remote)
        // rule (and with it a shim + envelope), because the manager owns no
        // cash desk. Nothing else in the domain code changed.
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

        // The new app type: SAME POSKit, different profile → different routing.
        .executableTarget(
            name: "manager-app",
            dependencies: [
                "POSKit",
                .product(name: "MIOExecutionClient", package: "MIOExecutionKit"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),

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
            name: "Example03Tests",
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
