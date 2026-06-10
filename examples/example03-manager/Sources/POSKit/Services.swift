//
//  Services.swift
//  POSKit
//
//  Diff vs example02: the manager app exists, and it owns no cash desk —
//  so nextDocumentNumber gained ONE rule, .manager(.remote), and with it
//  a shim + envelope. chargeToAccount gained .manager(.remote) too.
//  The POS behavior is completely unchanged.
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

    /// Hand-written expansion of:
    ///
    ///     @ExecutionProfile(.manager(.remote))
    ///
    /// POS: no rule matches → local, same as example01/02.
    /// Manager: remote — the server numbers the document.
    /// Server: no rule matches → local against the server store.
    public func nextDocumentNumber(series: String) async throws -> DocumentNumber {
        let plan = context.router.resolve(
            operationID: __Op_nextDocumentNumber.operationID,
            host: __Op_nextDocumentNumber.host,
            rules: [
                .manager(.remote)
            ],
            configuration: context.configuration
        )
        switch plan.method {
        case .local:
            return try await __local_nextDocumentNumber(series: series)
        case .remote:
            return try await context.router.executeRemote(
                plan,
                request: __Op_nextDocumentNumber(series: series),
                as: DocumentNumber.self
            )
        }
    }

    // The original body — identical to example02's nextDocumentNumber.
    func __local_nextDocumentNumber(series: String) async throws -> DocumentNumber {
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
    ///         .manager(.remote),
    ///         .pos(.remote, when: \POSConfiguration.clientAccountSyncRemotely)
    ///     )
    public func chargeToAccount(_ charge: AccountCharge) async throws -> AccountBalance {
        let plan = context.router.resolve(
            operationID: __Op_chargeToAccount.operationID,
            host: __Op_chargeToAccount.host,
            rules: [
                .manager(.remote),
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

    func __local_chargeToAccount(_ charge: AccountCharge) async throws -> AccountBalance {
        guard let store = context.store as? POSStore else { throw POSError.storeMismatch }
        let number = try await DocumentService(context: context).nextDocumentNumber(series: charge.series)
        return try await store.applyCharge(accountID: charge.accountID,
                                           amount: charge.amount,
                                           document: number)
    }
}

// MARK: - Envelopes

public struct __Op_nextDocumentNumber: ProfiledOperation {
    public static let operationID = "DocumentService.nextDocumentNumber(series:)"
    public let series: String

    public init(series: String) {
        self.series = series
    }

    public func execute(in context: ExecutionContext) async throws -> DocumentNumber {
        try await DocumentService(context: context).__local_nextDocumentNumber(series: series)
    }
}

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
