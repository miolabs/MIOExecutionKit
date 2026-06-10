//
//  Profiles.swift
//  VenueKit
//
//  Application-side declarations: profiles, hosts, installation
//  configuration, and the per-profile rule sugar (spec §3.2–3.4, §3.7).
//

import MIOExecutionKit

public extension ExecutionProfile {
    static let pos     = ExecutionProfile(rawValue: "pos")
    static let manager = ExecutionProfile(rawValue: "manager")
    static let server  = ExecutionProfile(rawValue: "server")
}

public extension RemoteHost {
    /// The service that owns customer accounts. In this example it maps to
    /// the same URL as `.default`; in a micro-server deployment it would be
    /// a different server.
    static let accounts = RemoteHost(rawValue: "accounts")
}

public struct PosConfiguration: ProfileConfiguration {
    public var installationID: String
    public var cashDeskID: String
    public var clientAccountSyncRemotely: Bool

    public init(installationID: String, cashDeskID: String, clientAccountSyncRemotely: Bool) {
        self.installationID = installationID
        self.cashDeskID = cashDeskID
        self.clientAccountSyncRemotely = clientAccountSyncRemotely
    }
}

public extension ProfileRule {
    static func pos(_ m: ExecutionMethod) -> ProfileRule { .init(profile: .pos, method: m) }
    static func pos(_ m: ExecutionMethod, when kp: KeyPath<PosConfiguration, Bool> & Sendable) -> ProfileRule {
        .init(profile: .pos, method: m, when: kp)
    }
    static func manager(_ m: ExecutionMethod) -> ProfileRule { .init(profile: .manager, method: m) }
}
