//
//  Profiles.swift
//  POSKit
//
//  Diff vs example02: the manager profile exists, and rules can name it.
//

import MIOExecutionKit

public extension ExecutionProfile {
    static let pos     = ExecutionProfile(rawValue: "pos")
    static let manager = ExecutionProfile(rawValue: "manager")   // new in example03
    static let server  = ExecutionProfile(rawValue: "server")
}

public struct POSConfiguration: ProfileConfiguration {
    public var installationID: String
    /// Each POS owns its cash desk: its own document prefix, its own
    /// counters starting from 1.
    public var cashDeskID: String
    /// true in multi-POS venues (accounts shared → server call);
    /// false in single-POS venues (everything stays local).
    public var clientAccountSyncRemotely: Bool

    public init(installationID: String, cashDeskID: String, clientAccountSyncRemotely: Bool) {
        self.installationID = installationID
        self.cashDeskID = cashDeskID
        self.clientAccountSyncRemotely = clientAccountSyncRemotely
    }
}

public extension ProfileRule {
    static func pos(_ m: ExecutionMethod) -> ProfileRule { .init(profile: .pos, method: m) }
    static func pos(_ m: ExecutionMethod, when kp: KeyPath<POSConfiguration, Bool>) -> ProfileRule {
        .init(profile: .pos, method: m, when: kp)
    }
}

public extension ProfileRule {
    static func manager(_ m: ExecutionMethod) -> ProfileRule { .init(profile: .manager, method: m) }
}
