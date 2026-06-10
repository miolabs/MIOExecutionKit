//
//  DocumentService.swift
//  VenueKit
//
//  Phase 1: the routing shim, __local_ body and envelope are written by hand,
//  exactly the way `@ExecutionProfile(.manager(.remote))` will expand them in
//  phase 2 (spec §5.3). Once the macro exists this file shrinks to the
//  annotated function alone.
//

import MIOExecutionKit

public struct DocumentService: ProfiledService {
    public let context: ExecutionContext

    public init(context: ExecutionContext) {
        self.context = context
    }

    /// Each POS owns its CashDesk: own prefix, own counter → local. The
    /// manager owns no cash desk → remote. On the server: no rule matches
    /// → local against the server store.
    ///
    ///     @ExecutionProfile(.manager(.remote))
    public func nextDocumentNumber(series: String) async throws -> DocumentNumber {
        let plan = context.router.resolve(
            operationID: __Op_nextDocumentNumber.operationID,
            host: __Op_nextDocumentNumber.host,
            rules: [.manager(.remote)],
            configuration: context.configuration
        )
        switch plan.method {
        case .local:
            return try await __local_nextDocumentNumber(series: series)
        case .remote:
            return try await context.router.executeRemote(
                plan,
                request: __Op_nextDocumentNumber(series: series),
                as: DocumentNumber.self
            )
        }
    }

    // The original body — what the developer actually writes.
    func __local_nextDocumentNumber(series: String) async throws -> DocumentNumber {
        guard let store = context.store as? any VenueStore else { throw VenueError.storeMismatch }
        let prefix = (context.configuration as? PosConfiguration)?.cashDeskID ?? "SRV"
        let number = await store.incrementSequence(named: "doc.\(prefix).\(series)")
        return DocumentNumber(prefix: prefix, series: series, number: number)
    }
}

/// Codable envelope: wire format + server-side executor in one type.
public struct __Op_nextDocumentNumber: ProfiledOperation {
    public static let operationID = "DocumentService.nextDocumentNumber(series:)"
    public let series: String

    public init(series: String) {
        self.series = series
    }

    public func execute(in context: ExecutionContext) async throws -> DocumentNumber {
        try await DocumentService(context: context).__local_nextDocumentNumber(series: series)
    }
}
