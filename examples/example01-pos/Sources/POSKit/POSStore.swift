//
//  POSStore.swift
//  POSKit
//
//  Core Data stack with a programmatic model (no .xcdatamodeld needed in an
//  SPM package). Two entities: CDSequence (document numbering) and CDAccount
//  (customer account balances).
//

import CoreData
import Foundation

public final class POSStore: @unchecked Sendable {
    private let container: NSPersistentContainer
    private let context: NSManagedObjectContext

    /// Pass a file URL for a persistent SQLite store, or nil for in-memory
    /// (tests).
    public init(storeURL: URL?) throws {
        container = NSPersistentContainer(name: "POS", managedObjectModel: Self.makeModel())

        let description: NSPersistentStoreDescription
        if let storeURL {
            description = NSPersistentStoreDescription(url: storeURL)
            description.type = NSSQLiteStoreType
        } else {
            description = NSPersistentStoreDescription()
            description.type = NSInMemoryStoreType
        }
        description.shouldAddStoreAsynchronously = false
        container.persistentStoreDescriptions = [description]

        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError { throw loadError }

        context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    // MARK: Operations

    public func incrementSequence(named name: String) async throws -> Int {
        try await context.perform {
            let request = NSFetchRequest<NSManagedObject>(entityName: "CDSequence")
            request.predicate = NSPredicate(format: "name == %@", name)
            let sequence = try self.context.fetch(request).first ?? {
                let new = NSEntityDescription.insertNewObject(forEntityName: "CDSequence", into: self.context)
                new.setValue(name, forKey: "name")
                new.setValue(Int64(0), forKey: "value")
                return new
            }()
            let next = (sequence.value(forKey: "value") as! Int64) + 1
            sequence.setValue(next, forKey: "value")
            try self.context.save()
            return Int(next)
        }
    }

    public func applyCharge(accountID: String, amount: Decimal, document: DocumentNumber) async throws -> AccountBalance {
        try await context.perform {
            let request = NSFetchRequest<NSManagedObject>(entityName: "CDAccount")
            request.predicate = NSPredicate(format: "accountID == %@", accountID)
            let account = try self.context.fetch(request).first ?? {
                let new = NSEntityDescription.insertNewObject(forEntityName: "CDAccount", into: self.context)
                new.setValue(accountID, forKey: "accountID")
                new.setValue(NSDecimalNumber.zero, forKey: "balance")
                return new
            }()
            let balance = (account.value(forKey: "balance") as! NSDecimalNumber)
                .adding(NSDecimalNumber(decimal: amount))
            account.setValue(balance, forKey: "balance")
            try self.context.save()
            return AccountBalance(accountID: accountID, balance: balance.decimalValue, lastDocument: document)
        }
    }

    // MARK: Snapshots (for printing and tests)

    public func sequences() async throws -> [String: Int] {
        try await context.perform {
            let request = NSFetchRequest<NSManagedObject>(entityName: "CDSequence")
            return try self.context.fetch(request).reduce(into: [:]) {
                $0[$1.value(forKey: "name") as! String] = Int($1.value(forKey: "value") as! Int64)
            }
        }
    }

    public func balances() async throws -> [String: Decimal] {
        try await context.perform {
            let request = NSFetchRequest<NSManagedObject>(entityName: "CDAccount")
            return try self.context.fetch(request).reduce(into: [:]) {
                $0[$1.value(forKey: "accountID") as! String] = ($1.value(forKey: "balance") as! NSDecimalNumber).decimalValue
            }
        }
    }

    // MARK: Model

    private static func makeModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()

        let sequence = NSEntityDescription()
        sequence.name = "CDSequence"
        let sequenceName = NSAttributeDescription()
        sequenceName.name = "name"
        sequenceName.attributeType = .stringAttributeType
        sequenceName.isOptional = false
        let sequenceValue = NSAttributeDescription()
        sequenceValue.name = "value"
        sequenceValue.attributeType = .integer64AttributeType
        sequenceValue.isOptional = false
        sequenceValue.defaultValue = 0
        sequence.properties = [sequenceName, sequenceValue]

        let account = NSEntityDescription()
        account.name = "CDAccount"
        let accountID = NSAttributeDescription()
        accountID.name = "accountID"
        accountID.attributeType = .stringAttributeType
        accountID.isOptional = false
        let balance = NSAttributeDescription()
        balance.name = "balance"
        balance.attributeType = .decimalAttributeType
        balance.isOptional = false
        balance.defaultValue = NSDecimalNumber.zero
        account.properties = [accountID, balance]

        model.entities = [sequence, account]
        return model
    }
}
