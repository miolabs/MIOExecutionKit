//
//  Demo.swift
//  venue-demo
//
//  End-to-end demo of the venue flow (spec §1.2) over real HTTP:
//  one in-process "server", three client setups, four routed calls.
//

import Foundation
import MIOExecutionKit
import MIOExecutionClient
import MIOExecutionServer
import MiniHTTP
import VenueKit

@main
struct VenueDemo {
    static func main() async throws {
        print("MIOExecutionKit — venue demo\n")

        // ── Server (would be MyApp-Server in a real deployment) ──────────
        let serverStore = InMemoryVenueStore()
        var registry = OperationRegistry()
        registry.register(__Op_nextDocumentNumber.self)
        registry.register(__Op_chargeToAccount.self)
        let operations = registry

        let serverContext = ExecutionContext(
            profile: .server,
            configuration: EmptyConfiguration(),
            router: ServerRouter(localHosts: [.default, .accounts]),
            store: serverStore
        )

        let server = try MiniHTTPServer { operationID, body in
            do {
                let output = try await operations.handle(operationID: operationID, body: body, context: serverContext)
                return (200, output)
            } catch ProfiledOperationError.unknownOperation {
                return (404, Data("{\"error\":\"unknown operation\"}".utf8))
            } catch {
                return (500, Data("{\"error\":\"\(error)\"}".utf8))
            }
        }
        print("server listening on \(server.baseURL)")
        print("registered ops: \(operations.operationIDs.sorted())\n")

        // Deployment config: both logical hosts point at the same server here;
        // in a micro-server setup .accounts would be a different URL.
        let hosts: [RemoteHost: URL] = [.default: server.baseURL, .accounts: server.baseURL]

        // ── 1. POS in a multi-POS venue: documents are local ─────────────
        let posStore = InMemoryVenueStore()
        let pos = ExecutionContext(
            profile: .pos,
            configuration: PosConfiguration(installationID: "pos-terrace",
                                            cashDeskID: "TERRACE",
                                            clientAccountSyncRemotely: true),
            router: ClientRouter(profile: .pos, hosts: hosts),
            store: posStore
        )

        let doc = try await DocumentService(context: pos).nextDocumentNumber(series: "T")
        print("1. POS nextDocumentNumber           → .local  → \(doc)")

        // ── 2. Same POS: customer accounts are shared → remote ───────────
        let balance = try await AccountService(context: pos)
            .chargeToAccount(AccountCharge(accountID: "ACME", amount: 25, series: "T"))
        print("2. POS chargeToAccount              → .remote → \(balance)")

        // ── 3. Single-POS venue: flag off → same call runs locally ───────
        let soloStore = InMemoryVenueStore()
        let soloPos = ExecutionContext(
            profile: .pos,
            configuration: PosConfiguration(installationID: "pos-main",
                                            cashDeskID: "MAIN",
                                            clientAccountSyncRemotely: false),
            router: ClientRouter(profile: .pos, hosts: hosts),
            store: soloStore
        )
        let soloBalance = try await AccountService(context: soloPos)
            .chargeToAccount(AccountCharge(accountID: "ACME", amount: 10, series: "M"))
        print("3. single-POS chargeToAccount       → .local  → \(soloBalance)")

        // ── 4. Manager: owns no cash desk → document numbers are remote ──
        let managerStore = InMemoryVenueStore()
        let manager = ExecutionContext(
            profile: .manager,
            configuration: EmptyConfiguration(),
            router: ClientRouter(profile: .manager, hosts: hosts),
            store: managerStore
        )
        let managerDoc = try await DocumentService(context: manager).nextDocumentNumber(series: "R")
        print("4. manager nextDocumentNumber       → .remote → \(managerDoc)")

        // ── Where did the state actually land? ───────────────────────────
        print("\nstate by store:")
        print("  server  sequences: \(await serverStore.sequencesSnapshot())  balances: \(await serverStore.balancesSnapshot())")
        print("  pos     sequences: \(await posStore.sequencesSnapshot())  balances: \(await posStore.balancesSnapshot())")
        print("  solo    sequences: \(await soloStore.sequencesSnapshot())  balances: \(await soloStore.balancesSnapshot())")
        print("  manager sequences: \(await managerStore.sequencesSnapshot())  balances: \(await managerStore.balancesSnapshot())")

        server.stop()
        print("\n✔ all flows executed over HTTP")
    }
}
