// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "VenueExample",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(path: "../..")   // MIOExecutionKit
    ],
    targets: [
        // Shared domain module: compiles unmodified into client and server.
        // Phase 1: the @ExecutionProfile expansion is hand-written (spec §9).
        .target(
            name: "VenueKit",
            dependencies: [
                .product(name: "MIOExecutionKit", package: "MIOExecutionKit")
            ]
        ),

        // Tiny blocking HTTP server, demo-grade only — real deployments bind
        // the OperationRegistry into MIOServerKit (spec §7).
        .target(name: "MiniHTTP"),

        .executableTarget(
            name: "venue-demo",
            dependencies: [
                "VenueKit",
                "MiniHTTP",
                .product(name: "MIOExecutionClient", package: "MIOExecutionKit"),
                .product(name: "MIOExecutionServer", package: "MIOExecutionKit"),
            ]
        ),

        .testTarget(
            name: "VenueExampleTests",
            dependencies: [
                "VenueKit",
                "MiniHTTP",
                .product(name: "MIOExecutionClient", package: "MIOExecutionKit"),
                .product(name: "MIOExecutionServer", package: "MIOExecutionKit"),
            ]
        ),
    ]
)
