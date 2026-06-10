//
//  AccountService.swift
//  VenueKit
//
//  Phase 1 hand-written expansion of:
//
//      @ExecutionProfile(
//          host: .accounts,
//          .manager(.remote),
//          .pos(.remote, when: \PosConfiguration.clientAccountSyncRemotely)
//      )
//
//  Customer accounts are shared across all POSes → remote, owned by the
//  accounts service. Single-POS venues flip the flag off: no rule matches,
//  the call runs locally, the persistence layer's delta sync does the rest.
//

import MIOExecutionKit

public struct AccountService: ProfiledService {
    public let context: ExecutionContext

    public init(context: ExecutionContext) {
        self.context = context
    }

    public func chargeToAccount(_ charge: AccountCharge) async throws -> AccountBalance {
        let plan = context.router.resolve(
            operationID: __Op_chargeToAccount.operationID,
            host: __Op_chargeToAccount.host,
            rules: [
                .manager(.remote),
                .pos(.remote, when: \PosConfiguration.clientAccountSyncRemotely),
            ],
            configuration: context.configuration
        )
        switch plan.method {
        case .local:
            return try await __local_chargeToAccount(charge)
        case .remote:
            return try await context.router.executeRemote(
                plan,
                request: __Op_chargeToAccount(charge: charge),
                as: AccountBalance.self
            )
        }
    }

    // The original body. Note the composition: the inner call goes through
    // the *routed* nextDocumentNumber, which resolves independently — on the
    // server it lands .local against the server store.
    func __local_chargeToAccount(_ charge: AccountCharge) async throws -> AccountBalance {
        guard let store = context.store as? any VenueStore else { throw VenueError.storeMismatch }
        let number = try await DocumentService(context: context).nextDocumentNumber(series: charge.series)
        return await store.applyCharge(accountID: charge.accountID, amount: charge.amount, document: number)
    }
}

public struct __Op_chargeToAccount: ProfiledOperation {
    public static let operationID = "AccountService.chargeToAccount(_:)"
    public static let host = RemoteHost.accounts
    public let charge: AccountCharge

    public init(charge: AccountCharge) {
        self.charge = charge
    }

    public func execute(in context: ExecutionContext) async throws -> AccountBalance {
        try await AccountService(context: context).__local_chargeToAccount(charge)
    }
}
