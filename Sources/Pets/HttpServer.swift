import Foundation
import Network

let serverPort: UInt16 = ProcessInfo.processInfo.environment["PETS_PORT"].flatMap { UInt16($0) } ?? 7387

final class HttpServer {
    private let listener: NWListener
    private let handler: (Data) -> Void
    var stateProvider: (() -> String)?

    init(port: UInt16, handler: @escaping (Data) -> Void, onFailure: @escaping (Error) -> Void) throws {
        self.handler = handler
        let params = NWParameters.tcp
        // Loopback-only: never exposed on the network, no firewall prompt.
        params.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback),
                                                           port: NWEndpoint.Port(rawValue: port)!)
        params.allowLocalEndpointReuse = true
        listener = try NWListener(using: params)
        listener.stateUpdateHandler = { state in
            if case .failed(let error) = state { onFailure(error) }
        }
        listener.newConnectionHandler = { [weak self] conn in
            conn.start(queue: .main)
            self?.receive(conn, buffer: Data())
        }
    }

    func start() {
        listener.start(queue: .main)
    }

    private func receive(_ conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { conn.cancel(); return }
            var buf = buffer
            if let data { buf.append(data) }

            if let headerEnd = buf.range(of: Data("\r\n\r\n".utf8)) {
                let header = String(decoding: buf[..<headerEnd.lowerBound], as: UTF8.self)
                let contentLength = header.components(separatedBy: "\r\n")
                    .compactMap { line -> Int? in
                        let parts = line.split(separator: ":", maxSplits: 1)
                        guard parts.count == 2,
                              parts[0].trimmingCharacters(in: .whitespaces).lowercased() == "content-length"
                        else { return nil }
                        return Int(parts[1].trimmingCharacters(in: .whitespaces))
                    }
                    .first ?? 0
                if header.hasPrefix("GET /state") {
                    let json = self.stateProvider?() ?? "{}\n"
                    let response = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(json.utf8.count)\r\nConnection: close\r\n\r\n\(json)"
                    conn.send(content: Data(response.utf8), completion: .contentProcessed { _ in conn.cancel() })
                    return
                }
                let body = buf[headerEnd.upperBound...]
                if body.count >= contentLength {
                    // Always 200, even on garbage — never make Claude Code wait.
                    let response = Data("HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8)
                    conn.send(content: response, completion: .contentProcessed { _ in conn.cancel() })
                    self.handler(Data(body.prefix(contentLength)))
                    return
                }
            }

            if error != nil || isComplete || buf.count > 1_000_000 {
                conn.cancel()
                return
            }
            self.receive(conn, buffer: buf)
        }
    }
}
