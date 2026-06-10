//
//  ResolutionTests.swift
//  MIOExecutionKitTests
//

import Testing
import MIOExecutionKit
import MIOExecutionClient
import MIOExecutionServer

extension ExecutionProfile {
    static let pos     = ExecutionProfile(rawValue: "pos")
    static let manager = ExecutionProfile(rawValue: "manager")
    static let server  = ExecutionProfile(rawValue: "server")
}

struct PosConfiguration: ProfileConfiguration {
    var clientAccountSyncRemotely = true
}

extension ProfileRule {
    static func pos(_ m: ExecutionMethod) -> ProfileRule { .init(profile: .pos, method: m) }
    static func pos(_ m: ExecutionMethod, when kp: KeyPath<PosConfiguration, Bool> & Sendable) -> ProfileRule {
        .init(profile: .pos, method: m, when: kp)
    }
    static func manager(_ m: ExecutionMethod) -> ProfileRule { .init(profile: .manager, method: m) }
}

// The venue example from the spec (§5.2): remote for the manager, remote on
// the POS only while the venue runs multiple POSes. No fallback rule needed —
// condition false → no match → local.
let chargeToAccountRules: [ProfileRule] = [
    .manager(.remote),
    .pos(.remote, when: \PosConfiguration.clientAccountSyncRemotely),
]

@Suite struct ResolutionTests {

    @Test func noMatchResolvesLocal() {
        let plan = ProfileResolution.resolve(operationID: "Doc.next(series:)",
                                             rules: chargeToAccountRules,
                                             profile: .server,
                                             configuration: EmptyConfiguration())
        #expect(plan.method == .local)
    }

    @Test func unannotatedEquivalentIsLocalEverywhere() {
        for profile in [ExecutionProfile.pos, .manager, .server] {
            let plan = ProfileResolution.resolve(operationID: "Doc.next(series:)",
                                                 rules: [],
                                                 profile: profile,
                                                 configuration: EmptyConfiguration())
            #expect(plan.method == .local)
        }
    }

    @Test func profileMatch() {
        let plan = ProfileResolution.resolve(operationID: "Account.charge(_:)",
                                             rules: chargeToAccountRules,
                                             profile: .manager,
                                             configuration: EmptyConfiguration())
        #expect(plan.method == .remote)
    }

    @Test func conditionTrueTakesConditionalRule() {
        let plan = ProfileResolution.resolve(operationID: "Account.charge(_:)",
                                             rules: chargeToAccountRules,
                                             profile: .pos,
                                             configuration: PosConfiguration(clientAccountSyncRemotely: true))
        #expect(plan.method == .remote)
    }

    @Test func conditionFalseResolvesLocal() {
        // The single-POS venue: flag off → no rule matches → local execution;
        // the persistence layer's delta sync handles the rest.
        let plan = ProfileResolution.resolve(operationID: "Account.charge(_:)",
                                             rules: chargeToAccountRules,
                                             profile: .pos,
                                             configuration: PosConfiguration(clientAccountSyncRemotely: false))
        #expect(plan.method == .local)
    }

    @Test func firstMatchWins() {
        // Conditional .local exception placed before a broader .remote rule.
        let rules: [ProfileRule] = [.pos(.local), .pos(.remote)]
        let plan = ProfileResolution.resolve(operationID: "Op",
                                             rules: rules,
                                             profile: .pos,
                                             configuration: EmptyConfiguration())
        #expect(plan.method == .local)
    }

    @Test func wrongConfigurationTypeFailsConditionSafely() {
        // A typed condition evaluated against a foreign configuration type
        // must not match (and must not crash).
        let plan = ProfileResolution.resolve(operationID: "Account.charge(_:)",
                                             rules: chargeToAccountRules,
                                             profile: .pos,
                                             configuration: EmptyConfiguration())
        #expect(plan.method == .local)
    }

    @Test func clientRouterDelegatesToResolution() {
        let router = ClientRouter(profile: .pos)
        let plan = router.resolve(operationID: "Account.charge(_:)",
                                  rules: chargeToAccountRules,
                                  configuration: PosConfiguration())
        #expect(plan.method == .remote)
    }

    @Test func serverRouterAlwaysResolvesLocal() {
        let router = ServerRouter()
        let plan = router.resolve(operationID: "Account.charge(_:)",
                                  rules: chargeToAccountRules,
                                  configuration: EmptyConfiguration())
        #expect(plan.method == .local)
    }
}
