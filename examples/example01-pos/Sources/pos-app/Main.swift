//
//  Main.swift
//  pos-app
//

import Foundation
import POSKit

@main
struct POSApp {
    static func main() async throws {
        print("example01 — POS, standalone\n")

        // SQLite file next to where you run the app: run it twice and the
        // sequences continue where they left off.
        let storeURL = URL(fileURLWithPath: "pos.sqlite")
        let store = try POSStore(storeURL: storeURL)
        let context = AppContext(
            store: store,
            configuration: POSConfiguration(installationID: "pos-main", cashDeskID: "MAIN")
        )

        let documents = DocumentService(context: context)
        let accounts = AccountService(context: context)

        let ticket = try await documents.nextDocumentNumber(series: "T")
        print("new ticket           → \(ticket)")

        let balance1 = try await accounts.chargeToAccount(
            AccountCharge(accountID: "ACME", amount: 25, series: "T"))
        print("charge 25 to ACME    → \(balance1)")

        let balance2 = try await accounts.chargeToAccount(
            AccountCharge(accountID: "ACME", amount: 10, series: "T"))
        print("charge 10 to ACME    → \(balance2)")

        print("\nstate (persisted in \(storeURL.path)):")
        print("  sequences: \(try await store.sequences())")
        print("  balances:  \(try await store.balances())")
        print("\nrun again — the numbers continue.")
    }
}
