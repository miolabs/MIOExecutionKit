//
//  Services.swift
//  POSKit
//
//  Diff vs example01:
//   - AppContext is replaced by MIOExecutionKit's ExecutionContext.
//   - nextDocumentNumber is UNCHANGED in behavior: no rule → always local,
//     on the POS and on the server. No shim, no envelope, no endpoint.
//   - chargeToAccount gained ONE rule: remote on the POS while the venue
//     runs multiple POSes. The shim + envelope below are what the
//     @ExecutionProfile macro will generate in phase 2; today they are
//     written by hand (spec §5.3).
//

import Foundation
import MIOExecutionKit

public enum POSError: Error {
    case storeMismatch
}

public struct DocumentService: ProfiledService {
    public let context: ExecutionContext

    public init(context: ExecutionContext) {
        self.context = context
    }

    /// Unannotated → always .local. Same code, same behavior as example01.
    public func nextDocumentNumber(series: String) async throws -> DocumentNumber {
        guard let store = context.store as? POSStore else { throw POSError.storeMismatch }
        let prefix = (context.configuration as? POSConfiguration)?.cashDeskID ?? "SRV"
        let number = try await store.incrementSequence(named: "doc.\(prefix).\(series)")
        return DocumentNumber(prefix: prefix, series: series, number: number)
    }
}

public struct AccountService: ProfiledService {
    public let context: ExecutionContext

    public init(context: ExecutionContext) {
        self.context = context
    }

    /// Hand-written expansion of:
    ///
    ///     @ExecutionProfile(
    ///         .pos(.remote, when: \POSConfiguration.clientAccountSyncRemotely)
    ///     )
    public func chargeToAccount(_ charge: AccountCharge) async throws -> AccountBalance {
        let plan = context.router.resolve(
            operationID: __Op_chargeToAccount.operationID,
            host: __Op_chargeToAccount.host,
            rules: [
                .pos(.remote, when: \POSConfiguration.clientAccountSyncRemotely)
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

    // The original body — identical to example01's chargeToAccount.
    func __local_chargeToAccount(_ charge: AccountCharge) async throws -> AccountBalance {
        guard let store = context.store as? POSStore else { throw POSError.storeMismatch }
        let number = try await DocumentService(context: context).nextDocumentNumber(series: charge.series)
        return try await store.applyCharge(accountID: charge.accountID,
                                           amount: charge.amount,
                                           document: number)
    }
}

/// Codable envelope: wire format + server-side executor in one type.
public struct __Op_chargeToAccount: ProfiledOperation {
    public static let operationID = "AccountService.chargeToAccount(_:)"
    public let charge: AccountCharge

    public init(charge: AccountCharge) {
        self.charge = charge
    }

    public func execute(in context: ExecutionContext) async throws -> AccountBalance {
        try await AccountService(context: context).__local_chargeToAccount(charge)
    }
}
