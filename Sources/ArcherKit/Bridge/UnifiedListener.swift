// [archer] UnifiedListener — cmux-inspired single-socket demultiplexer.
//
// Collapses Archer's two legacy local listeners into ONE unix socket:
//   • BridgeServer  → ~/.archer/bridge.sock        (archer-bridge CLI)
//   • HookServer    → ~/Library/Application Support/Archer/socket  (ArcherHook CLI)
//
// cmux serves gRPC/SSH/HTTP on one listener by sniffing the first bytes; we
// serve bridge + hook on one listener by sniffing the first JSON object's
// top-level keys — the `Match(HTTP1Fast())` / `Match(Any())` classifier
// ported to our wire shapes:
//
//   • has "cmd"  → bridge request/response path (writes a reply)
//   • otherwise  → hook event path (one-shot, no reply)
//
// The legacy hook socket path is kept as a SYMLINK to the canonical bridge
// socket, so external clients (archer-bridge, ArcherHook) need zero changes —
// connect() resolves the symlink to the live listener. Wire contracts are
// untouched: bridge still gets JSON replies, hooks still fire-and-forget.
import Darwin
import Foundation

@MainActor
final class UnifiedListener {
    /// Canonical listener socket (was BridgeServer.socketPath).
    static let bridgeSocketPath: String = {
        let dir = (NSHomeDirectory() as NSString).appendingPathComponent(".archer")
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return (dir as NSString).appendingPathComponent("bridge.sock")
    }()

    /// Legacy hook socket path (was HookServer.socketPath). Maintained as a
    /// symlink → bridgeSocketPath so ArcherHook's hardcoded path still works.
    static let hookSocketPath: String = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("Archer", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("socket").path
    }()

    typealias HookHandler = (_ message: HookMessage) -> Void
    typealias StoreProvider = () -> WorkspaceStore?

    private let hookHandler: HookHandler
    private let bridgeHandler: BridgeServer

    private var listenFd: Int32 = -1
    private var source: DispatchSourceRead?

    /// Concurrent queue for blocking client I/O — keeps read()/write() off the main actor.
    private static let ioQueue = DispatchQueue(
        label: "ai.archer.unified.io",
        attributes: .concurrent
    )

    init(hookHandler: @escaping HookHandler, storeProvider: @escaping StoreProvider) {
        self.hookHandler = hookHandler
        bridgeHandler = BridgeServer()
        bridgeHandler.storeProvider = storeProvider
    }

    func start() {
        let path = Self.bridgeSocketPath
        try? FileManager.default.removeItem(atPath: path)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(path.utf8)
        guard pathBytes.count < MemoryLayout.size(ofValue: addr.sun_path) else {
            close(fd); return
        }
        withUnsafeMutableBytes(of: &addr.sun_path) { dst in
            pathBytes.withUnsafeBufferPointer { src in
                dst.baseAddress?.copyMemory(from: src.baseAddress!, byteCount: src.count)
            }
        }
        let len = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, len) }
        }
        guard bound == 0 else { close(fd); return }
        fchmod(fd, S_IRUSR | S_IWUSR) // 0600 — owner-only; blocks same-UID injection via type/keys cmds
        guard listen(fd, 8) == 0 else { close(fd); return }

        listenFd = fd

        // Maintain the legacy hook socket as a symlink to the live listener.
        installHookSymlink()

        let src = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
        src.setEventHandler { [weak self] in self?.acceptOne() }
        src.resume()
        source = src
        ArcherLogger.bridge.info("UnifiedListener listening at \(path) (bridge + hook demuxed)")
    }

    private func installHookSymlink() {
        let hookPath = Self.hookSocketPath
        try? FileManager.default.removeItem(atPath: hookPath)
        // Symlink target is the absolute bridge socket path; connect() follows it.
        guard symlink(Self.bridgeSocketPath, hookPath) == 0 else {
            ArcherLogger.bridge.warning("UnifiedListener: hook symlink failed errno=\(errno)")
            return
        }
    }

    func stop() {
        source?.cancel(); source = nil
        if listenFd >= 0 { close(listenFd); listenFd = -1 }
        try? FileManager.default.removeItem(atPath: Self.bridgeSocketPath)
        // Drop the legacy hook symlink so stale links don't accumulate across restarts.
        try? FileManager.default.removeItem(atPath: Self.hookSocketPath)
    }

    // MARK: - Accept / demux

    private func acceptOne() {
        let clientFd = accept(listenFd, nil, nil)
        guard clientFd >= 0 else { return }

        // Blocking read/write moves off the main actor; route() hops back via Task.
        Self.ioQueue.async { [weak self] in
            // 5-second receive timeout: a hung client can't stall a queue thread indefinitely.
            var tv = timeval(tv_sec: 5, tv_usec: 0)
            setsockopt(clientFd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

            var buf = [UInt8](repeating: 0, count: 65536)
            let n = buf.withUnsafeMutableBufferPointer { read(clientFd, $0.baseAddress!, $0.count) }
            guard n > 0 else { close(clientFd); return }

            let data = Data(bytes: buf, count: n)
            Task { @MainActor [weak self] in
                guard let self else { close(clientFd); return }
                self.route(data, clientFd: clientFd)
            }
        }
    }

    /// cmux-style first-frame classifier. Peek the top-level JSON keys —
    /// `has("cmd")` is the bridge protocol (needs a reply); anything else is
    /// a hook event (fire-and-forget).
    private func route(_ data: Data, clientFd: Int32) {
        let isBridge = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["cmd"] != nil

        if isBridge {
            let response = bridgeHandler.handle(data)
            Self.ioQueue.async {
                response.withUnsafeBytes { ptr in
                    _ = Darwin.write(clientFd, ptr.baseAddress!, ptr.count)
                }
                close(clientFd)
            }
        } else {
            if let message = HookServer.parseMessage(data) {
                hookHandler(message)
            }
            close(clientFd)
        }
    }
}
