//
//  Services.swift
//  POSKit
//
//  The domain logic, written as a plain local app. No networking, no
//  framework — the way every app in this architecture starts.
//

import Foundation

public struct POSConfiguration {
    public var installationID: String
    /// Each POS owns its cash desk: its own document prefix, its own
    /// counters starting from 1.
    public var cashDeskID: String

    public init(installationID: String, cashDeskID: String) {
        self.installationID = installationID
        self.cashDeskID = cashDeskID
    }
}

/// Everything a service needs to run. In tutorial 02 this struct is replaced
/// by MIOExecutionKit's ExecutionContext — same shape, plus a router.
public struct AppContext {
    public let store: POSStore
    public let configuration: POSConfiguration

    public init(store: POSStore, configuration: POSConfiguration) {
        self.store = store
        self.configuration = configuration
    }
}

public struct DocumentService {
    public let context: AppContext

    public init(context: AppContext) {
        self.context = context
    }

    public func nextDocumentNumber(series: String) async throws -> DocumentNumber {
        let prefix = context.configuration.cashDeskID
        let number = try await context.store.incrementSequence(named: "doc.\(prefix).\(series)")
        return DocumentNumber(prefix: prefix, series: series, number: number)
    }
}

public struct AccountService {
    public let context: AppContext

    public init(context: AppContext) {
        self.context = context
    }

    public func chargeToAccount(_ charge: AccountCharge) async throws -> AccountBalance {
        let number = try await DocumentService(context: context).nextDocumentNumber(series: charge.series)
        return try await context.store.applyCharge(accountID: charge.accountID,
                                                   amount: charge.amount,
                                                   document: number)
    }
}
