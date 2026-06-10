//
//  ClientRouter.swift
//  MIOExecutionClient
//

import Foundation
import MIOExecutionKit

/// Router linked into app targets (POS, manager, …).
/// .remote → HTTP/WebSocket RPC to the host's server (POST {baseURL}/op/{operationID})
/// .local  → run the local body; the persistence layer's delta sync picks
///           up the saves on its own — that is not this router's business.
public struct ClientRouter: ExecutionRouter {
    public let profile: ExecutionProfile
    /// Deployment config: logical host → base URL (may include a path prefix,
    /// e.g. https://api.example.com/billing). A single-server app passes
    /// [.default: serverURL] and never thinks about hosts again.
    public let hosts: [RemoteHost: URL]
    public let transport: any RemoteTransport

    public init(profile: ExecutionProfile,
                hosts: [RemoteHost: URL] = [:],
                transport: any RemoteTransport = URLSessionTransport()) {
        self.profile = profile
        self.hosts = hosts
        self.transport = transport
    }

    public func resolve(operationID: String,
                        host: RemoteHost,
                        rules: [ProfileRule],
                        configuration: any ProfileConfiguration) -> ExecutionPlan {
        // TODO(phase 5): consult runtime overrides config before the rules (spec §3.6).
        ProfileResolution.resolve(operationID: operationID,
                                  host: host,
                                  rules: rules,
                                  profile: profile,
                                  configuration: configuration)
    }

    public func executeRemote<Op: ProfiledOperation>(
        _ plan: ExecutionPlan, request: Op, as output: Op.Output.Type
    ) async throws -> Op.Output {
        guard let baseURL = hosts[plan.host] else {
            throw ProfiledOperationError.unknownHost(plan.host, operationID: plan.operationID)
        }
        let body = try JSONEncoder().encode(request)
        let data = try await transport.send(operationID: plan.operationID, to: baseURL, body: body)
        return try JSONDecoder().decode(Op.Output.self, from: data)
    }
}
