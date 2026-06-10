//
//  Main.swift
//  manager-app
//
//  The new app type. It calls the SAME POSKit services with the same lines
//  of code as pos-app — only the profile in the ExecutionContext differs,
//  and that flips both operations to remote: the manager owns no cash desk
//  and no accounts; the server is its authority for everything.
//
//  Run `swift run pos-server` in another terminal first.
//

import Foundation
import MIOExecutionKit
import MIOExecutionClient
import POSKit

@main
struct ManagerApp {
    static func main() async throws {
        let environment = ProcessInfo.processInfo.environment
        let serverURL = URL(string: environment["SERVER_URL"] ?? "http://127.0.0.1:8080")!

        print("example03 — manager\n")

        // The manager keeps no domain data of its own: in-memory store,
        // empty configuration. Reporting apps read; they don't own.
        let store = try POSStore(storeURL: nil)
        let context = ExecutionContext(
            profile: .manager,
            configuration: EmptyConfiguration(),
            router: ClientRouter(profile: .manager, hosts: [.default: serverURL]),
            store: store
        )

        let documents = DocumentService(context: context)
        let accounts = AccountService(context: context)

        do {
            // Identical call to pos-app's — but .manager(.remote) matches,
            // so the SERVER numbers it (prefix SRV, server sequence).
            let document = try await documents.nextDocumentNumber(series: "R")
            print("nextDocumentNumber   → \(document)   [remote — numbered by the server]")

            let balance = try await accounts.chargeToAccount(
                AccountCharge(accountID: "ACME", amount: 5, series: "R"))
            print("charge 5 to ACME     → \(balance)   [remote — server is the authority]")
        } catch ProfiledOperationError.serverUnreachable {
            print("server unreachable — start it with `swift run pos-server`")
            return
        }

        print("\nlocal state (nothing — the manager wrote nowhere):")
        print("  sequences: \(try await store.sequences())")
        print("  balances:  \(try await store.balances())")
    }
}
