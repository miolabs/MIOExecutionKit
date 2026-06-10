//
//  Main.swift
//  pos-app
//
//  Same app as example01 — the only changes are the ExecutionContext wiring
//  (router + server URL) and the configuration flag. The service calls are
//  IDENTICAL; where they execute is the framework's decision.
//
//  Run `swift run pos-server` in another terminal first (or SERVER_URL=...).
//

import Foundation
import MIOExecutionKit
import MIOExecutionClient
import POSKit

@main
struct POSApp {
    static func main() async throws {
        let environment = ProcessInfo.processInfo.environment
        let serverURL = URL(string: environment["SERVER_URL"] ?? "http://127.0.0.1:8080")!
        let multiPOS = environment["SINGLE_POS"] == nil   // SINGLE_POS=1 → everything local

        print("example02 — POS + server  (accounts \(multiPOS ? "remote" : "local"))\n")

        let store = try POSStore(storeURL: URL(fileURLWithPath: "pos.sqlite"))
        let context = ExecutionContext(
            profile: .pos,
            configuration: POSConfiguration(installationID: "pos-main",
                                            cashDeskID: "MAIN",
                                            clientAccountSyncRemotely: multiPOS),
            router: ClientRouter(profile: .pos, hosts: [.default: serverURL]),
            store: store
        )

        let documents = DocumentService(context: context)
        let accounts = AccountService(context: context)

        // Unannotated → local, exactly as in example01.
        let ticket = try await documents.nextDocumentNumber(series: "T")
        print("new ticket           → \(ticket)   [local]")

        // Annotated → remote while clientAccountSyncRemotely == true.
        do {
            let balance = try await accounts.chargeToAccount(
                AccountCharge(accountID: "ACME", amount: 25, series: "T"))
            let document = balance.lastDocument
            print("charge 25 to ACME    → \(balance)   [\(document.prefix == "SRV" ? "remote, executed on the server" : "local")]")
        } catch ProfiledOperationError.serverUnreachable {
            print("charge 25 to ACME    → server unreachable — start it with `swift run pos-server`")
        }

        print("\nlocal state:")
        print("  sequences: \(try await store.sequences())")
        print("  balances:  \(try await store.balances())")
    }
}
