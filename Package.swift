// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "MIOExecutionKit",
    platforms: [
        .macOS(.v13), .iOS(.v16), .tvOS(.v16)
    ],
    products: [
        .library(name: "MIOExecutionKit", targets: ["MIOExecutionKit"]),
        .library(name: "MIOExecutionClient", targets: ["MIOExecutionClient"]),
        .library(name: "MIOExecutionServer", targets: ["MIOExecutionServer"]),
    ],
    targets: [
        // Core: ExecutionProfile, SyncMethod, ProfileRule, router protocols, resolution.
        .target(name: "MIOExecutionKit"),

        // Client runtime: ClientRouter (HTTP/WebSocket transport, delta sync engine).
        .target(name: "MIOExecutionClient", dependencies: ["MIOExecutionKit"]),

        // Server runtime: ServerRouter (everything resolves .local; MIOServerKit binding).
        .target(name: "MIOExecutionServer", dependencies: ["MIOExecutionKit"]),

        // Phase 2 will add: MIOExecutionMacros (SwiftSyntax) + macro declarations in core.
        // Phase 3 will add: MIOExecutionGen build-tool plugin.

        .testTarget(
            name: "MIOExecutionKitTests",
            dependencies: ["MIOExecutionKit", "MIOExecutionClient", "MIOExecutionServer"]
        ),
    ]
)
