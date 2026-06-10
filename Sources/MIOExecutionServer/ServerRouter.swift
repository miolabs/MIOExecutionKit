//
//  ServerRouter.swift
//  MIOExecutionServer
//

import Foundation
import MIOExecutionKit

/// Router linked into a server target. A server is the authority **for the
/// hosts it serves**: operations belonging to its own hosts resolve .local
/// regardless of rules. In micro-server designs, operations owned by a
/// *different* host resolve .remote — a server-to-server RPC routed through
/// the same hosts map a client would use. The default single-server setup
/// (localHosts = [.default], everything local) falls out unchanged.
public struct ServerRouter: ExecutionRouter {
    public let localHosts: Set<RemoteHost>
    /// Base URLs of the *other* services, for cross-host calls. Empty in
    /// single-server deployments.
    public let hosts: [RemoteHost: URL]

    public init(localHosts: Set<RemoteHost> = [.default], hosts: [RemoteHost: URL] = [:]) {
        self.localHosts = localHosts
        self.hosts = hosts
    }

    public func resolve(operationID: String,
                        host: RemoteHost,
                        rules: [ProfileRule],
                        configuration: any ProfileConfiguration) -> ExecutionPlan {
        let method: ExecutionMethod = localHosts.contains(host) ? .local : .remote
        return ExecutionPlan(method: method, operationID: operationID, host: host)
    }

    public func executeRemote<Op: ProfiledOperation>(
        _ plan: ExecutionPlan, request: Op, as output: Op.Output.Type
    ) async throws -> Op.Output {
        guard let baseURL = hosts[plan.host] else {
            throw ProfiledOperationError.unknownHost(plan.host, operationID: plan.operationID)
        }
        // TODO(phase 1): server-to-server transport — same wire protocol as the
        // client, plus service identity headers (spec §7.1).
        _ = baseURL
        throw ProfiledOperationError.notImplemented("ServerRouter.executeRemote — cross-host transport")
    }
}
