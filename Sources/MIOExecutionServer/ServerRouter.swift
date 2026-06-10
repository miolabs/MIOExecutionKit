//
//  ServerRouter.swift
//  MIOExecutionServer
//

import MIOExecutionKit

/// Router linked into the server target. Everything resolves .local — no rule
/// matches the server profile by construction, and even an explicit .remote
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
        // Unreachable in practice: resolve() never returns .remote on the server.
        throw ProfiledOperationError.notImplemented("ServerRouter.executeRemote — the server is the authority")
    }
}
