//
//  ClientRouter.swift
//  MIOExecutionClient
//

import MIOExecutionKit

/// Router linked into app targets (POS, manager, …).
/// .remote → HTTP/WebSocket RPC to the server (POST /op/{operationID})
/// .local  → run the local body; the persistence layer's delta sync picks
///           up the saves on its own — that is not this router's business.
public struct ClientRouter: ExecutionRouter {
    public let profile: ExecutionProfile

    public init(profile: ExecutionProfile) {
        self.profile = profile
    }

    public func resolve(operationID: String,
                        rules: [ProfileRule],
                        configuration: any ProfileConfiguration) -> ExecutionPlan {
        // TODO(phase 5): consult runtime overrides config before the rules (spec §3.6).
        ProfileResolution.resolve(operationID: operationID,
                                  rules: rules,
                                  profile: profile,
                                  configuration: configuration)
    }

    public func executeRemote<Op: ProfiledOperation>(
        _ plan: ExecutionPlan, request: Op, as output: Op.Output.Type
    ) async throws -> Op.Output {
        // TODO(phase 1): HTTP transport — POST /op/{operationID} with the envelope
        // JSON, idempotency key + tenancy headers (spec §7.1–7.2).
        throw ProfiledOperationError.notImplemented("ClientRouter.executeRemote — phase 1 transport")
    }
}
