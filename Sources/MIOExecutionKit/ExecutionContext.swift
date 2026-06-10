//
//  ExecutionContext.swift
//  MIOExecutionKit
//

public protocol ExecutionRouter: Sendable {
    func resolve(operationID: String,
                 rules: [ProfileRule],
                 configuration: any ProfileConfiguration) -> ExecutionPlan

    func executeRemote<Op: ProfiledOperation>(
        _ plan: ExecutionPlan, request: Op, as output: Op.Output.Type
    ) async throws -> Op.Output

    func executeDeferred<T: Sendable>(
        _ plan: ExecutionPlan, _ body: @Sendable () async throws -> T
    ) async throws -> T
}

/// Adapter over the local (MIOPersistentStore/SQLite) or server (PostgreSQL)
/// store. Deliberately minimal in v1 — see spec §6.1. Surface to be defined
/// in phase 1 alongside the hand-written envelope flow.
public protocol PersistentStoreAdapter: Sendable {}

public struct ExecutionContext: Sendable {
    public let profile: ExecutionProfile
    public let configuration: any ProfileConfiguration
    public let router: any ExecutionRouter
    public let store: any PersistentStoreAdapter

    public init(profile: ExecutionProfile,
                configuration: any ProfileConfiguration,
                router: any ExecutionRouter,
                store: any PersistentStoreAdapter) {
        self.profile = profile
        self.configuration = configuration
        self.router = router
        self.store = store
    }
}

/// A type whose @ExecutionProfile-annotated functions route themselves.
/// The init(context:) requirement is what lets generated envelopes
/// re-instantiate the service server-side.
public protocol ProfiledService: Sendable {
    var context: ExecutionContext { get }
    init(context: ExecutionContext)
}

/// Codable envelope generated (phase 2: by the macro) per .sync-capable
/// operation — simultaneously the wire format and the server-side executor.
public protocol ProfiledOperation: Codable, Sendable {
    associatedtype Output: Codable & Sendable
    static var operationID: String { get }
    func execute(in context: ExecutionContext) async throws -> Output
}

public enum ProfiledOperationError: Error, Sendable {
    /// A .sync operation could not reach the server. Never silently
    /// downgraded to .local — degrading is a `when:` condition the
    /// developer writes deliberately (spec §6.5).
    case serverUnreachable(operationID: String)
    case notImplemented(String)
}
