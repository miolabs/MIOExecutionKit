//
//  Store.swift
//  VenueKit
//

import Foundation
import MIOExecutionKit

/// The example's store surface. In a real app this is MIOPersistentStore
/// (client) / PostgreSQL (server); the in-memory actor below stands in for
/// both so the demo shows *where* state ends up.
public protocol VenueStore: PersistentStoreAdapter {
    func incrementSequence(named name: String) async -> Int
    func applyCharge(accountID: String, amount: Decimal, document: DocumentNumber) async -> AccountBalance
    func sequencesSnapshot() async -> [String: Int]
    func balancesSnapshot() async -> [String: Decimal]
}

public actor InMemoryVenueStore: VenueStore {
    private var sequences: [String: Int] = [:]
    private var balances: [String: Decimal] = [:]

    public init() {}

    public func incrementSequence(named name: String) -> Int {
        let next = (sequences[name] ?? 0) + 1
        sequences[name] = next
        return next
    }

    public func applyCharge(accountID: String, amount: Decimal, document: DocumentNumber) -> AccountBalance {
        let balance = (balances[accountID] ?? 0) + amount
        balances[accountID] = balance
        return AccountBalance(accountID: accountID, balance: balance, lastDocument: document)
    }

    public func sequencesSnapshot() -> [String: Int] { sequences }
    public func balancesSnapshot() -> [String: Decimal] { balances }
}
