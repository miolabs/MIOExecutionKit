//
//  ExecutionProfile.swift
//  MIOExecutionKit
//

/// Names an application type — what kind of binary this is (e.g. pos, manager, server).
/// The framework ships none hard-coded; apps declare their own as static members.
/// A RawRepresentable struct instead of an enum so it is open for extension
/// without recompiling the framework, yet still pattern-matchable.
public struct ExecutionProfile: RawRepresentable, Hashable, Codable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

/// How a function executes relative to the server.
public enum SyncMethod: String, Codable, Sendable {
    /// Execute locally against the local store. Never talks to the server.
    case local

    /// Execute locally, persist locally, enqueue delta; background service
    /// pushes/pulls via the changelog sync engine.
    case async

    /// Always execute on the server. The client call is an RPC; the local
    /// store may be updated from the response (read-through).
    case sync
}

/// Installation-level settings — what differs between two installations of the
/// same profile (e.g. the main-area POS and the terrace POS). The app owns the
/// concrete type and its storage; rule conditions read it at call time.
public protocol ProfileConfiguration: Sendable {}

/// A configuration for apps that need none (typically the server).
public struct EmptyConfiguration: ProfileConfiguration {
    public init() {}
}
