//
//  RoundTripTests.swift
//  MIOExecutionKitTests
//
//  End-to-end of the kit's own logic without sockets: envelope encode →
//  registry decode → server-side execute → output encode → client decode.
//

import Foundation
import Testing
import MIOExecutionKit
import MIOExecutionClient
import MIOExecutionServer

private struct NullStore: PersistentStoreAdapter {}

private struct DoubleOp: ProfiledOperation {
    static let operationID = "Math.double(_:)"
    let value: Int
    func execute(in context: ExecutionContext) async throws -> Int { value * 2 }
}

/// Calls the server-side registry directly instead of going over HTTP.
private struct LoopbackTransport: RemoteTransport {
    let registry: OperationRegistry
    let serverContext: ExecutionContext

    func send(operationID: String, to baseURL: URL, body: Data) async throws -> Data {
        try await registry.handle(operationID: operationID, body: body, context: serverContext)
    }
}

@Suite struct RoundTripTests {

    private func makeLoopbackRouter(registering: Bool = true) -> ClientRouter {
        var registry = OperationRegistry()
        if registering { registry.register(DoubleOp.self) }
        let serverContext = ExecutionContext(profile: .server,
                                             configuration: EmptyConfiguration(),
                                             router: ServerRouter(),
                                             store: NullStore())
        return ClientRouter(profile: .pos,
                            hosts: [.default: URL(string: "loopback://server")!],
                            transport: LoopbackTransport(registry: registry, serverContext: serverContext))
    }

    @Test func envelopeRoundTrip() async throws {
        let router = makeLoopbackRouter()
        let plan = ExecutionPlan(method: .remote, operationID: DoubleOp.operationID)
        let result = try await router.executeRemote(plan, request: DoubleOp(value: 21), as: Int.self)
        #expect(result == 42)
    }

    @Test func unregisteredOperationThrows() async {
        let router = makeLoopbackRouter(registering: false)
        let plan = ExecutionPlan(method: .remote, operationID: DoubleOp.operationID)
        await #expect(throws: ProfiledOperationError.self) {
            _ = try await router.executeRemote(plan, request: DoubleOp(value: 1), as: Int.self)
        }
    }
}
