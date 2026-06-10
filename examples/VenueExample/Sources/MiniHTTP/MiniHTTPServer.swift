//
//  MiniHTTPServer.swift
//  MiniHTTP
//
//  Minimal blocking HTTP/1.1 server, demo-grade only: one route shape,
//  POST /op/{operationID}. Real deployments bind the OperationRegistry
//  into MIOServerKit instead (spec §7).
//

import Foundation

public final class MiniHTTPServer: @unchecked Sendable {
    public typealias Handler = @Sendable (_ operationID: String, _ body: Data) async -> (status: Int, body: Data)

    public let port: UInt16
    private let listenFD: Int32
    private let handler: Handler
    private let queue = DispatchQueue(label: "MiniHTTPServer", attributes: .concurrent)

    public init(handler: @escaping Handler) throws {
        self.handler = handler

        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXError(.EMFILE) }

        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))

        // Bind to 127.0.0.1, port 0 → the kernel picks a free port.
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0, listen(fd, 16) == 0 else {
            close(fd)
            throw POSIXError(.EADDRINUSE)
        }

        var assigned = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        withUnsafeMutablePointer(to: &assigned) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                _ = getsockname(fd, $0, &len)
            }
        }

        listenFD = fd
        port = UInt16(bigEndian: assigned.sin_port)

        queue.async { [weak self] in self?.acceptLoop() }
    }

    public var baseURL: URL { URL(string: "http://127.0.0.1:\(port)")! }

    public func stop() {
        close(listenFD)
    }

    private func acceptLoop() {
        while true {
            let fd = accept(listenFD, nil, nil)
            guard fd >= 0 else { return }   // listenFD closed → stop
            queue.async { [weak self] in self?.handleConnection(fd) }
        }
    }

    private func handleConnection(_ fd: Int32) {
        defer { close(fd) }

        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        let headerTerminator = Data("\r\n\r\n".utf8)

        // Read until the end of the headers.
        var headerRange = buffer.range(of: headerTerminator)
        while headerRange == nil {
            let n = read(fd, &chunk, chunk.count)
            guard n > 0 else { return }
            buffer.append(contentsOf: chunk[0..<n])
            headerRange = buffer.range(of: headerTerminator)
        }
        guard let headerEnd = headerRange,
              let head = String(data: buffer[..<headerEnd.lowerBound], encoding: .utf8) else { return }

        let lines = head.components(separatedBy: "\r\n")
        let requestParts = lines[0].split(separator: " ")
        let contentLength = lines.dropFirst()
            .first { $0.lowercased().hasPrefix("content-length:") }
            .flatMap { Int($0.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)) } ?? 0

        // Read the remainder of the body.
        var body = Data(buffer[headerEnd.upperBound...])
        while body.count < contentLength {
            let n = read(fd, &chunk, chunk.count)
            guard n > 0 else { return }
            body.append(contentsOf: chunk[0..<n])
        }

        var status = 404
        var responseBody = Data("{\"error\":\"not found\"}".utf8)

        if requestParts.count >= 2, requestParts[0] == "POST", requestParts[1].hasPrefix("/op/"),
           let operationID = String(requestParts[1].dropFirst("/op/".count)).removingPercentEncoding {
            // Bridge the blocking connection thread to the async handler.
            final class ResultBox: @unchecked Sendable {
                var value: (status: Int, body: Data) = (500, Data())
            }
            let box = ResultBox()
            let semaphore = DispatchSemaphore(value: 0)
            let handler = self.handler
            let requestBody = body
            Task {
                box.value = await handler(operationID, requestBody)
                semaphore.signal()
            }
            semaphore.wait()
            (status, responseBody) = box.value
        }

        let responseHead = "HTTP/1.1 \(status) \(status == 200 ? "OK" : "Error")\r\n"
            + "Content-Type: application/json\r\n"
            + "Content-Length: \(responseBody.count)\r\n"
            + "Connection: close\r\n\r\n"
        var response = Data(responseHead.utf8)
        response.append(responseBody)

        response.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            var offset = 0
            while offset < raw.count {
                let written = write(fd, raw.baseAddress!.advanced(by: offset), raw.count - offset)
                guard written > 0 else { return }
                offset += written
            }
        }
    }
}
