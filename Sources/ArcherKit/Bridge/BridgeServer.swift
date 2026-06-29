import Darwin
import Foundation

/// Unix-socket server for the `archer-bridge` CLI.
///
/// Wire format — one JSON object per line, request/response:
///
///   → {"cmd":"list"}
///   ← {"ok":true,"labels":["claude","codex"]}
///
///   → {"cmd":"read","label":"claude","lines":20}
///   ← {"ok":true,"text":"…last 20 rows…"}
///
///   → {"cmd":"type","label":"claude","text":"ls -la\n"}
///   ← {"ok":true}
///
///   → {"cmd":"keys","label":"claude","keys":["Enter"]}
///   ← {"ok":true}
///
///   → {"cmd":"sync"}   (re-syncs PaneRegistry from active workspace)
///   ← {"ok":true,"count":2}
///
/// The server lives on the main queue and dispatches through PaneRegistry,
/// so all surface access is main-actor-safe.
@MainActor
final class BridgeServer {
    weak var store: WorkspaceStore?

    private var listenFd: Int32 = -1
    private var source: DispatchSourceRead?

    static let socketPath: String = {
        let dir = (NSHomeDirectory() as NSString).appendingPathComponent(".archer")
        try? FileManager.default.createDirectory(
            atPath: dir, withIntermediateDirectories: true
        )
        return (dir as NSString).appendingPathComponent("bridge.sock")
    }()

    func start() {
        let path = Self.socketPath
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
        guard bound == 0, listen(fd, 8) == 0 else { close(fd); return }

        listenFd = fd
        let src = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
        src.setEventHandler { [weak self] in self?.acceptOne() }
        src.resume()
        source = src
        ArcherLogger.bridge.info("BridgeServer listening at \(path)")
    }

    func stop() {
        source?.cancel(); source = nil
        if listenFd >= 0 { close(listenFd); listenFd = -1 }
        try? FileManager.default.removeItem(atPath: Self.socketPath)
    }

    // MARK: - Accept / dispatch

    private func acceptOne() {
        let clientFd = accept(listenFd, nil, nil)
        guard clientFd >= 0 else { return }
        defer { close(clientFd) }

        var buf = [UInt8](repeating: 0, count: 65536)
        let n = buf.withUnsafeMutableBufferPointer { read(clientFd, $0.baseAddress, $0.count) }
        guard n > 0 else { return }

        let data = Data(bytes: buf, count: n)
        let response = handle(data)
        response.withUnsafeBytes { ptr in
            _ = Darwin.write(clientFd, ptr.baseAddress!, ptr.count)
        }
    }

    private func handle(_ data: Data) -> Data {
        guard let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cmd = dict["cmd"] as? String
        else { return error("invalid JSON or missing cmd") }

        // Sync registry from active workspace before every command.
        PaneRegistry.shared.sync(workspace: store?.active)

        switch cmd {
        case "list":
            let labels = Array(PaneRegistry.shared.entries.keys).sorted()
            return ok(["labels": labels])

        case "sync":
            let count = PaneRegistry.shared.entries.count
            return ok(["count": count])

        case "read":
            guard let label = dict["label"] as? String else { return error("missing label") }
            let lines = (dict["lines"] as? Int) ?? 20
            guard let text = PaneRegistry.shared.read(label: label, lines: lines) else {
                return error("label not found or surface unavailable: \(label)")
            }
            return ok(["text": text])

        case "type":
            guard let label = dict["label"] as? String else { return error("missing label") }
            guard let text = dict["text"] as? String else { return error("missing text") }
            guard PaneRegistry.shared.entries[label] != nil else {
                return error("label not found: \(label)")
            }
            PaneRegistry.shared.type(label: label, text: text)
            return ok([:])

        case "keys":
            guard let label = dict["label"] as? String else { return error("missing label") }
            guard let keys = dict["keys"] as? [String] else { return error("missing keys array") }
            guard PaneRegistry.shared.entries[label] != nil else {
                return error("label not found: \(label)")
            }
            PaneRegistry.shared.keys(label: label, keys: keys)
            return ok([:])

        default:
            return error("unknown cmd: \(cmd)")
        }
    }

    private func ok(_ extra: [String: Any]) -> Data {
        var d: [String: Any] = ["ok": true]
        extra.forEach { d[$0] = $1 }
        return (try? JSONSerialization.data(withJSONObject: d)) ?? Data()
    }

    private func error(_ msg: String) -> Data {
        let d: [String: Any] = ["ok": false, "error": msg]
        return (try? JSONSerialization.data(withJSONObject: d)) ?? Data()
    }
}
