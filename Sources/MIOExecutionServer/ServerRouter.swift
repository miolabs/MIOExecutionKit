//
//  ServerRouter.swift
//  MIOExecutionServer
//

import MIOExecutionKit

/// Router linked into the server target. Everything resolves .local — no rule
/// matches the server profile by construction, and even an explicit .sync
/// reaching the server executes locally, because the server *is* the authority.
public struct ServerRouter: ExecutionRouter {
    public init() {}

    public func resolve(operationID: String,
                        rules: [ProfileRule],
                        configuration: any ProfileConfiguration) -> ExecutionPlan {
        ExecutionPlan(method: .local, operationID: operationID)
    }

    public func executeRemote<Op: ProfiledOperation>(
        _ plan: ExecutionPlan, request: Op, as output: Op.Output.Type
    ) async throws -> Op.Output {
        // Unreachable in practice: resolve() never returns .sync on the server.
        try await request.execute(in: ExecutionContextProvider.current(plan))
    }

    public func executeDeferred<T: Sendable>(
        _ plan: ExecutionPlan, _ body: @Sendable () async throws -> T
    ) async throws -> T {
        try await body()
    }
}

/// Placeholder until the MIOServerKit binding lands (phase 3): the generated
/// registerProfiledOperations() will build a fresh ExecutionContext per request.
enum ExecutionContextProvider {
    static func current(_ plan: ExecutionPlan) throws -> ExecutionContext {
        throw ProfiledOperationError.notImplemented("ServerRouter context provider — phase 3")
    }
}
