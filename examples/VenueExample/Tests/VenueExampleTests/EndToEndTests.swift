//
//  EndToEndTests.swift
//  VenueExampleTests
//
//  The venue flow (spec §1.2) over real HTTP, asserting not just the results
//  but *where* the state landed — which store each call actually mutated.
//

import Foundation
import Testing
import MIOExecutionKit
import MIOExecutionClient
import MIOExecutionServer
import MiniHTTP
import VenueKit

/// One in-process server + the client contexts of the venue.
private struct Venue {
    let server: MiniHTTPServer
    let serverStore: InMemoryVenueStore
    let hosts: [RemoteHost: URL]

    init() throws {
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
                return (200, try await operations.handle(operationID: operationID, body: body, context: serverContext))
            } catch ProfiledOperationError.unknownOperation {
                return (404, Data())
            } catch {
                return (500, Data())
            }
        }
        self.server = server
        self.serverStore = serverStore
        self.hosts = [.default: server.baseURL, .accounts: server.baseURL]
    }

    func posContext(cashDesk: String, accountsRemote: Bool, store: InMemoryVenueStore) -> ExecutionContext {
        ExecutionContext(
            profile: .pos,
            configuration: PosConfiguration(installationID: "pos-\(cashDesk)",
                                            cashDeskID: cashDesk,
                                            clientAccountSyncRemotely: accountsRemote),
            router: ClientRouter(profile: .pos, hosts: hosts),
            store: store
        )
    }

    func managerContext(store: InMemoryVenueStore) -> ExecutionContext {
        ExecutionContext(
            profile: .manager,
            configuration: EmptyConfiguration(),
            router: ClientRouter(profile: .manager, hosts: hosts),
            store: store
        )
    }
}

@Suite struct EndToEndTests {

    @Test func posDocumentNumberIsLocal() async throws {
        let venue = try Venue()
        defer { venue.server.stop() }
        let posStore = InMemoryVenueStore()
        let context = venue.posContext(cashDesk: "TERRACE", accountsRemote: true, store: posStore)

        let doc = try await DocumentService(context: context).nextDocumentNumber(series: "T")

        #expect(doc.prefix == "TERRACE")
        #expect(doc.number == 1)
        #expect(await posStore.sequencesSnapshot().count == 1)        // landed locally
        #expect(await venue.serverStore.sequencesSnapshot().isEmpty)  // server untouched
    }

    @Test func posChargeToAccountIsRemote() async throws {
        let venue = try Venue()
        defer { venue.server.stop() }
        let posStore = InMemoryVenueStore()
        let context = venue.posContext(cashDesk: "TERRACE", accountsRemote: true, store: posStore)

        let balance = try await AccountService(context: context)
            .chargeToAccount(AccountCharge(accountID: "ACME", amount: 25, series: "T"))

        #expect(balance.balance == 25)
        // Executed server-side: the inner nextDocumentNumber resolved .local
        // *on the server*, so the document carries the server prefix.
        #expect(balance.lastDocument.prefix == "SRV")
        #expect(await venue.serverStore.balancesSnapshot()["ACME"] == 25)
        #expect(await posStore.balancesSnapshot().isEmpty)
    }

    @Test func singlePosChargeToAccountIsLocal() async throws {
        let venue = try Venue()
        defer { venue.server.stop() }
        let soloStore = InMemoryVenueStore()
        let context = venue.posContext(cashDesk: "MAIN", accountsRemote: false, store: soloStore)

        let balance = try await AccountService(context: context)
            .chargeToAccount(AccountCharge(accountID: "ACME", amount: 10, series: "M"))

        #expect(balance.balance == 10)
        #expect(balance.lastDocument.prefix == "MAIN")               // numbered by the local cash desk
        #expect(await soloStore.balancesSnapshot()["ACME"] == 10)    // landed locally
        #expect(await venue.serverStore.balancesSnapshot().isEmpty)  // server untouched
    }

    @Test func managerDocumentNumberIsRemote() async throws {
        let venue = try Venue()
        defer { venue.server.stop() }
        let managerStore = InMemoryVenueStore()
        let context = venue.managerContext(store: managerStore)

        let doc = try await DocumentService(context: context).nextDocumentNumber(series: "R")

        #expect(doc.prefix == "SRV")
        #expect(await venue.serverStore.sequencesSnapshot().count == 1)
        #expect(await managerStore.sequencesSnapshot().isEmpty)
    }

    @Test func serverSequencesAreSharedAcrossRemoteCallers() async throws {
        let venue = try Venue()
        defer { venue.server.stop() }
        let m1 = venue.managerContext(store: InMemoryVenueStore())
        let m2 = venue.managerContext(store: InMemoryVenueStore())

        let first  = try await DocumentService(context: m1).nextDocumentNumber(series: "R")
        let second = try await DocumentService(context: m2).nextDocumentNumber(series: "R")

        #expect(first.number == 1)
        #expect(second.number == 2)   // same server sequence, two callers
    }
}
