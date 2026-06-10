//
//  POSKitTests.swift
//  POSKitTests
//

import Foundation
import Testing
import POSKit

private func makeContext() throws -> AppContext {
    AppContext(store: try POSStore(storeURL: nil),   // in-memory
               configuration: POSConfiguration(installationID: "pos-test", cashDeskID: "TEST"))
}

@Suite struct POSKitTests {

    @Test func documentNumbersIncrementPerSeries() async throws {
        let context = try makeContext()
        let documents = DocumentService(context: context)

        let first = try await documents.nextDocumentNumber(series: "T")
        let second = try await documents.nextDocumentNumber(series: "T")
        let other = try await documents.nextDocumentNumber(series: "R")

        #expect(first.number == 1)
        #expect(second.number == 2)
        #expect(other.number == 1)            // independent series
        #expect(first.prefix == "TEST")       // cash desk prefix
    }

    @Test func chargesAccumulate() async throws {
        let context = try makeContext()
        let accounts = AccountService(context: context)

        _ = try await accounts.chargeToAccount(AccountCharge(accountID: "ACME", amount: 25, series: "T"))
        let balance = try await accounts.chargeToAccount(AccountCharge(accountID: "ACME", amount: 10, series: "T"))

        #expect(balance.balance == 35)
        #expect(balance.lastDocument.number == 2)   // each charge numbered a document
    }
}
