//
//  RemoteTransport.swift
//  MIOExecutionClient
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

import MIOExecutionKit

/// Carries an encoded envelope to a server and returns the encoded output.
/// Pluggable so tests can short-circuit it (loopback) and future versions
/// can add a WebSocket implementation.
public protocol RemoteTransport: Sendable {
    func send(operationID: String, to baseURL: URL, body: Data) async throws -> Data
}

/// Default transport: POST {baseURL}/op/{operationID} with the envelope JSON.
public struct URLSessionTransport: RemoteTransport {
    public let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(operationID: String, to baseURL: URL, body: Data) async throws -> Data {
        let url = baseURL
            .appendingPathComponent("op")
            .appendingPathComponent(operationID)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // TODO(phase 4): reuse the key across retries of the same logical call,
        // dedup server-side (spec §7.2); tenancy/auth headers (spec §7.1).
        request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Idempotency-Key")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ProfiledOperationError.serverUnreachable(operationID: operationID)
        }
        guard let http = response as? HTTPURLResponse else {
            throw ProfiledOperationError.serverUnreachable(operationID: operationID)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw ProfiledOperationError.remoteFailure(operationID: operationID, statusCode: http.statusCode)
        }
        return data
    }
}
