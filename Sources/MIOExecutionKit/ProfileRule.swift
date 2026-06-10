//
//  ProfileRule.swift
//  MIOExecutionKit
//

/// One (profile, method, condition?) triple. The @ExecutionProfile macro takes
/// a variadic list of these; rules are evaluated in declaration order, first
/// match wins, and no match resolves to .local.
///
/// Since .local is the global default, rules almost always declare .remote.
/// An explicit .local rule is still meaningful as a conditional exception
/// placed before a broader rule for the same profile.
public struct ProfileRule: Sendable {
    public let profile: ExecutionProfile
    public let method: ExecutionMethod
    /// Evaluated at call time against the installation configuration.
    /// Type-erased at construction from a typed KeyPath.
    public let condition: (@Sendable (any ProfileConfiguration) -> Bool)?

    public init(profile: ExecutionProfile,
                method: ExecutionMethod,
                condition: (@Sendable (any ProfileConfiguration) -> Bool)? = nil) {
        self.profile = profile
        self.method = method
        self.condition = condition
    }

    public init<C: ProfileConfiguration>(profile: ExecutionProfile,
                                         method: ExecutionMethod,
                                         when keyPath: KeyPath<C, Bool> & Sendable) {
        self.init(profile: profile, method: method) {
            ($0 as? C)?[keyPath: keyPath] ?? false
        }
    }
}

/// The resolved decision for one call. `resolve()` is total: it always returns
/// .local or .remote, falling back to .local when no rule matches.
public struct ExecutionPlan: Sendable {
    public let method: ExecutionMethod
    public let operationID: String
    /// Which server executes the operation when method == .remote.
    public let host: RemoteHost

    public init(method: ExecutionMethod, operationID: String, host: RemoteHost = .default) {
        self.method = method
        self.operationID = operationID
        self.host = host
    }
}

public enum ProfileResolution {
    /// The entire resolution algorithm: first rule whose profile matches the
    /// active profile and whose condition (if any) evaluates true wins; no
    /// match resolves to .local. Runtime overrides (spec §3.6) sit above this
    /// in the routers, not here.
    public static func resolve(operationID: String,
                               host: RemoteHost = .default,
                               rules: [ProfileRule],
                               profile: ExecutionProfile,
                               configuration: any ProfileConfiguration) -> ExecutionPlan {
        for rule in rules where rule.profile == profile {
            if let condition = rule.condition, condition(configuration) == false { continue }
            return ExecutionPlan(method: rule.method, operationID: operationID, host: host)
        }
        return ExecutionPlan(method: .local, operationID: operationID, host: host)
    }
}
