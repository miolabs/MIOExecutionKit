//
//  OperationRegistry.swift
//  MIOExecutionServer
//

import Foundation
import MIOExecutionKit

/// Server-side dispatch table: operationID → decode envelope, execute, encode
/// output. Hand-registered in phase 1; phase 3's generated Routes.swift does
/// exactly this registration. Framework-agnostic: an HTTP layer (MIOServerKit,
/// or the example's mini server) just forwards the request body to `handle`.
public struct OperationRegistry: Sendable {
    public typealias Handler = @Sendable (Data, ExecutionContext) async throws -> Data

    private var handlers: [String: Handler] = [:]

    public init() {}

    public mutating func register<Op: ProfiledOperation>(_ type: Op.Type) {
        handlers[Op.operationID] = { body, context in
            let op = try JSONDecoder().decode(Op.self, from: body)
            let output = try await op.execute(in: context)
            return try JSONEncoder().encode(output)
        }
    }

    public func handle(operationID: String, body: Data, context: ExecutionContext) async throws -> Data {
        guard let handler = handlers[operationID] else {
            throw ProfiledOperationError.unknownOperation(operationID)
        }
        return try await handler(body, context)
    }

    public var operationIDs: [String] { Array(handlers.keys) }
}
