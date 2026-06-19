import Foundation
import Network

/// Detects a local proxy (Clash / Clash Verge etc.) on common ports so the
/// usage request can route through it. Lifted from TokenChecker.
enum ProxyDetector {
    private actor State {
        var resolved = false
        func resolve() -> Bool {
            if resolved { return false }
            resolved = true
            return true
        }
    }

    /// First open common proxy port (7890 / 7897), or nil.
    static func detectProxyPort() async -> Int? {
        for port in [7890, 7897] where await isPortOpen(port: port) {
            return port
        }
        return nil
    }

    private static func isPortOpen(port: Int) async -> Bool {
        let connection = NWConnection(
            host: NWEndpoint.Host("127.0.0.1"),
            port: NWEndpoint.Port(rawValue: UInt16(port))!,
            using: .tcp
        )
        let state = State()
        return await withCheckedContinuation { continuation in
            connection.stateUpdateHandler = { connState in
                switch connState {
                case .ready:
                    Task { if await state.resolve() { connection.cancel(); continuation.resume(returning: true) } }
                case .failed, .cancelled:
                    Task { if await state.resolve() { continuation.resume(returning: false) } }
                default:
                    break
                }
            }
            connection.start(queue: .global())
            Task {
                try? await Task.sleep(nanoseconds: 200_000_000)
                if await state.resolve() { connection.cancel(); continuation.resume(returning: false) }
            }
        }
    }
}
