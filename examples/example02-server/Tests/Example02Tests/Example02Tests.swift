//
//  Example02Tests.swift
//  Example02Tests
//
//  End-to-end over a real MIOServerKit NIOServer.
//

import Foundation
import Testing
import MIOExecutionKit
import MIOExecutionClient
import MIOExecutionServer
import MIOServerKit
import POSKit

/// One in-process MIOServerKit server shared by the whole suite.
private final class TestServer: @unchecked Sendable {
    static let shared = try! TestServer()

    let serverStore: POSStore
    let baseURL: URL
    private let server: NIOServer

    init() throws {
        var registry = OperationRegistry()
        registry.register(__Op_chargeToAccount.self)
        let operations = registry

        let store = try POSStore(storeURL: nil)   // in-memory
        let serverContext = ExecutionContext(
            profile: .server,
            configuration: EmptyConfiguration(),
            router: ServerRouter(),
            store: store
        )

        let router = Router()
        router.endpoint("/op/:operationID").post { (ctx: RouterContext) async throws -> (any Sendable)? in
            let raw: String = try ctx.urlParam("operationID")
            let operationID = raw.removingPercentEncoding ?? raw
            return try await operations.handle(operationID: operationID,
                                               body: ctx.bodyAsData() ?? Data(),
                                               context: serverContext)
        }

        let port = Int.random(in: 9100..<9900)
        let server = NIOServer(routes: router)
        Thread.detachNewThread {
            server.run(port: port)
        }
        _ = server.waitForServerRunning()

        self.server = server
        self.serverStore = store
        self.baseURL = URL(string: "http://127.0.0.1:\(port)")!
    }
}

private func makePOSContext(store: POSStore, accountsRemote: Bool) -> ExecutionContext {
    ExecutionContext(
        profile: .pos,
        configuration: POSConfiguration(installationID: "pos-test",
                                        cashDeskID: "TEST",
                                        clientAccountSyncRemotely: accountsRemote),
        router: ClientRouter(profile: .pos, hosts: [.default: TestServer.shared.baseURL]),
        store: store
    )
}

@Suite struct Example02Tests {

    @Test func documentNumberStaysLocal() async throws {
        let posStore = try POSStore(storeURL: nil)
        let context = makePOSContext(store: posStore, accountsRemote: true)

        let document = try await DocumentService(context: context).nextDocumentNumber(series: "T")

        #expect(document.prefix == "TEST")
        #expect(try await posStore.sequences().count == 1)
    }

    @Test func chargeExecutesOnTheServer() async throws {
        let posStore = try POSStore(storeURL: nil)
        let context = makePOSContext(store: posStore, accountsRemote: true)

        let balance = try await AccountService(context: context)
            .chargeToAccount(AccountCharge(accountID: "REMOTE-1", amount: 25, series: "T"))

        #expect(balance.balance == 25)
        #expect(balance.lastDocument.prefix == "SRV")   // numbered by the server
        #expect(try await TestServer.shared.serverStore.balances()["REMOTE-1"] == 25)
        #expect(try await posStore.balances().isEmpty)  // nothing written locally
    }

    @Test func singlePOSChargeStaysLocal() async throws {
        let posStore = try POSStore(storeURL: nil)
        let context = makePOSContext(store: posStore, accountsRemote: false)

        let balance = try await AccountService(context: context)
            .chargeToAccount(AccountCharge(accountID: "LOCAL-1", amount: 10, series: "T"))

        #expect(balance.balance == 10)
        #expect(balance.lastDocument.prefix == "TEST")  // numbered by the local cash desk
        #expect(try await posStore.balances()["LOCAL-1"] == 10)
        #expect(try await TestServer.shared.serverStore.balances()["LOCAL-1"] == nil)
    }
}
