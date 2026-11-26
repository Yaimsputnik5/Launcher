import Foundation
import Network

struct ServerStatus {
    var online: Bool
    var joining: Bool
    var onlinePlayers: Int32
}

enum ServerStatusClient {
    static func query(address: String, timeout: TimeInterval = 5) async -> ServerStatus? {
        guard let (host, port) = parse(address) else { return nil }
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else { return nil }

        return await withCheckedContinuation { continuation in
            let connection = NWConnection(
                host: NWEndpoint.Host(host),
                port: endpointPort,
                using: .udp
            )
            var resumed = false

            let finish: (ServerStatus?) -> Void = { status in
                guard !resumed else { return }
                resumed = true
                connection.stateUpdateHandler = nil
                connection.cancel()
                continuation.resume(returning: status)
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.send(content: Data([0x00, 0x20]), completion: .contentProcessed { error in
                        if error != nil {
                            finish(nil)
                            return
                        }
                        connection.receive(minimumIncompleteLength: 6, maximumLength: 64) { data, _, _, error in
                            guard error == nil, let data, data.count >= 6 else {
                                finish(nil)
                                return
                            }
                            finish(ServerStatus(
                                online: data[0] != 0,
                                joining: data[1] != 0,
                                onlinePlayers: readInt32(data, offset: 2)
                            ))
                        }
                    })
                case .failed, .cancelled:
                    finish(nil)
                default:
                    break
                }
            }

            connection.start(queue: .global(qos: .utility))
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) {
                finish(nil)
            }
        }
    }

    /// Handles plain `host`, `host:port`, and bracketed IPv6 `[::1]:port`.
    static func parse(_ value: String) -> (String, UInt16)? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.hasPrefix("["), let close = trimmed.firstIndex(of: "]") {
            let host = String(trimmed[trimmed.index(after: trimmed.startIndex)..<close])
            let after = trimmed[trimmed.index(after: close)...]
            let portString = after.hasPrefix(":") ? String(after.dropFirst()) : ""
            let port: UInt16
            if let parsed = UInt16(portString), parsed != 0 {
                port = parsed
            } else {
                port = AppConstants.statusPort
            }
            guard !host.isEmpty else { return nil }
            return (host, port)
        }

        let colonCount = trimmed.filter { $0 == ":" }.count
        if colonCount == 1, let colon = trimmed.firstIndex(of: ":") {
            let host = String(trimmed[..<colon])
            guard let port = UInt16(trimmed[trimmed.index(after: colon)...]), port > 0 else { return nil }
            return (host, port)
        }

        // IPv6 without an explicit port, or a plain hostname.
        return (trimmed, AppConstants.statusPort)
    }

    private static func readInt32(_ data: Data, offset: Int) -> Int32 {
        var bits: UInt32 = 0
        for index in 0..<4 {
            bits |= UInt32(data[offset + index]) << (8 * index)
        }
        return Int32(bitPattern: bits)
    }
}
