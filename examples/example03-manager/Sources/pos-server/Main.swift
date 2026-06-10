//
//  Main.swift
//  pos-server
//
//  The entire server layer. The same POSKit that runs in the app executes
//  here against the server's own store — registry + one MIOServerKit route.
//

import Foundation
import MIOExecutionKit
import MIOExecutionServer
import MIOServerKit
import POSKit

@main
struct POSServer {
    static func main() throws {
        // 1. Which operations may arrive over the wire (phase 3 generates this).
        var registry = OperationRegistry()
        registry.register(__Op_chargeToAccount.self)
        registry.register(__Op_nextDocumentNumber.self)
        let operations = registry

        // 2. The server's execution context: same shared code, own store.
        let store = try POSStore(storeURL: URL(fileURLWithPath: "server.sqlite"))
        let serverContext = ExecutionContext(
            profile: .server,
            configuration: EmptyConfiguration(),
            router: ServerRouter(),
            store: store
        )

        // 3. One MIOServerKit route dispatches every operation.
        let router = Router()
        router.endpoint("/op/:operationID").post { (ctx: RouterContext) async throws -> (any Sendable)? in
            let raw: String = try ctx.urlParam("operationID")
            let operationID = raw.removingPercentEncoding ?? raw
            return try await operations.handle(operationID: operationID,
                                               body: ctx.bodyAsData() ?? Data(),
                                               context: serverContext)
        }

        let port = Int(ProcessInfo.processInfo.environment["PORT"] ?? "") ?? 8080
        print("pos-server: \(operations.operationIDs.count) operation(s) registered, listening on port \(port)")
        NIOServer(routes: router).run(port: port)   // blocks until terminated
    }
}
