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
    static func pos(_ m: SyncMethod) -> ProfileRule { .init(profile: .pos, method: m) }
    static func pos(_ m: SyncMethod, when kp: KeyPath<PosConfiguration, Bool> & Sendable) -> ProfileRule {
        .init(profile: .pos, method: m, when: kp)
    }
    static func manager(_ m: SyncMethod) -> ProfileRule { .init(profile: .manager, method: m) }
}

// The venue example from the spec (§5.2).
let chargeToAccountRules: [ProfileRule] = [
    .manager(.sync),
    .pos(.sync, when: \PosConfiguration.clientAccountSyncRemotely),
    .pos(.async),
]

@Suite struct ResolutionTests {

    @Test func noMatchResolvesLocal() {
        let plan = ProfileResolution.resolve(operationID: "Doc.next(series:)",
                                             rules: chargeToAccountRules,
                                             profile: .server,
                                             configuration: EmptyConfiguration())
        #expect(plan.method == .local)
        #expect(plan.isServerAuthoritative == false)
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
        #expect(plan.method == .sync)
        #expect(plan.isServerAuthoritative)
    }

    @Test func conditionTrueTakesConditionalRule() {
        let plan = ProfileResolution.resolve(operationID: "Account.charge(_:)",
                                             rules: chargeToAccountRules,
                                             profile: .pos,
                                             configuration: PosConfiguration(clientAccountSyncRemotely: true))
        #expect(plan.method == .sync)
    }

    @Test func conditionFalseFallsThroughToNextRule() {
        // The single-POS venue: flag off → same call runs locally + async.
        let plan = ProfileResolution.resolve(operationID: "Account.charge(_:)",
                                             rules: chargeToAccountRules,
                                             profile: .pos,
                                             configuration: PosConfiguration(clientAccountSyncRemotely: false))
        #expect(plan.method == .async)
    }

    @Test func firstMatchWins() {
        let rules: [ProfileRule] = [.pos(.async), .pos(.sync)]
        let plan = ProfileResolution.resolve(operationID: "Op",
                                             rules: rules,
                                             profile: .pos,
                                             configuration: EmptyConfiguration())
        #expect(plan.method == .async)
    }

    @Test func wrongConfigurationTypeFailsConditionSafely() {
        // A typed condition evaluated against a foreign configuration type
        // must not match (and must not crash).
        let plan = ProfileResolution.resolve(operationID: "Account.charge(_:)",
                                             rules: chargeToAccountRules,
                                             profile: .pos,
                                             configuration: EmptyConfiguration())
        #expect(plan.method == .async)
    }

    @Test func clientRouterDelegatesToResolution() {
        let router = ClientRouter(profile: .pos)
        let plan = router.resolve(operationID: "Account.charge(_:)",
                                  rules: chargeToAccountRules,
                                  configuration: PosConfiguration())
        #expect(plan.method == .sync)
    }

    @Test func serverRouterAlwaysResolvesLocal() {
        let router = ServerRouter()
        let plan = router.resolve(operationID: "Account.charge(_:)",
                                  rules: chargeToAccountRules,
                                  configuration: EmptyConfiguration())
        #expect(plan.method == .local)
    }
}
