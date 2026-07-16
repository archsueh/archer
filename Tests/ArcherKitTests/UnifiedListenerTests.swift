@testable import ArcherKit
import Darwin
import XCTest

/// Tests for `UnifiedListener` — the cmux-style local socket demux that
/// serves the bridge (archer-bridge CLI) and hook (ArcherHook CLI) protocols
/// on ONE unix socket, routing by first-frame JSON keys.
///
/// Covers both the pure classifier (`isBridgeFrame`) and a real round-trip
/// over the actual socket: a bridge frame gets a JSON reply, a hook frame is
/// dispatched to the hook handler. Runs on the main actor because
/// `UnifiedListener` is `@MainActor`.
@MainActor
final class UnifiedListenerTests: XCTestCase {
    private func data(_ json: String) -> Data {
        Data(json.utf8)
    }

    // MARK: - First-frame classifier (cmux-style Match)

    func testIsBridgeFrameTrueForCmdPayload() {
        let json = #"{"cmd":"list"}"#
        XCTAssertTrue(UnifiedListener.isBridgeFrame(data(json)))
    }

    func testIsBridgeFrameFalseForHookPayload() {
        let json = #"{"surface":"00000000-0000-0000-0000-000000000001","agent":"claude","event":"running"}"#
        XCTAssertFalse(UnifiedListener.isBridgeFrame(data(json)))
    }

    func testIsBridgeFrameFalseForMalformedJSON() {
        XCTAssertFalse(UnifiedListener.isBridgeFrame(data("not json")))
    }

    // MARK: - Socket round-trip (single listener, two protocols)

    func testRoundTripBridgesAndHooksOverOneSocket() {
        // Use SHORT socket paths: unix socket sun_path is capped (~104 chars
        // on macOS), and NSTemporaryDirectory() paths are far longer, so bind
        // would silently fail. /tmp stays under the limit.
        let tag = String(UUID().uuidString.prefix(8))
        let bridgePath = "/tmp/archer-ul-\(tag)-b.sock"
        let hookPath = "/tmp/archer-ul-\(tag)-h.sock"

        var receivedHook: HookMessage?
        let listener = TestUnifiedListener(
            bridgePath: bridgePath,
            hookPath: hookPath,
            hookHandler: { receivedHook = $0 },
            storeProvider: { nil }
        )
        listener.start()
        defer {
            listener.stop()
            try? FileManager.default.removeItem(atPath: bridgePath)
            try? FileManager.default.removeItem(atPath: hookPath)
        }

        // Client runs on a background queue; the test pumps the main run loop
        // so the server's @MainActor route() can execute.
        let group = DispatchGroup()
        group.enter()
        var bridgeReply = Data()
        DispatchQueue.global().async {
            bridgeReply = UnifiedListenerTests.sendFrame(to: bridgePath, json: #"{"cmd":"list"}"#)
            _ = UnifiedListenerTests.sendFrame(
                to: hookPath,
                json: #"{"surface":"00000000-0000-0000-0000-000000000001","agent":"claude","event":"running"}"#,
                expectReply: false
            )
            group.leave()
        }

        // Pump the main run loop until the client finishes AND the hook fires.
        let deadline = Date().addingTimeInterval(3)
        while receivedHook == nil || group.wait(timeout: .now()) != .success, Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }

        let bridgeDict = (try? JSONSerialization.jsonObject(with: bridgeReply) as? [String: Any]) ?? [:]
        XCTAssertEqual(bridgeDict["ok"] as? Bool, true)

        guard case let .agent(agent, event, _) = receivedHook else {
            return XCTFail("Expected .agent hook, got \(String(describing: receivedHook))")
        }
        XCTAssertEqual(agent.id, AgentTemplate.claudeCodeID)
        XCTAssertEqual(event, .running)

        // 3) Legacy hook symlink resolves to the bridge socket.
        var buf = [CChar](repeating: 0, count: 4096)
        let n = buf.withUnsafeMutableBufferPointer { readlink(hookPath, $0.baseAddress!, $0.count) }
        XCTAssertGreaterThan(n, 0, "hook path should be a symlink to the bridge socket")
        let target = String(decoding: buf.map { UInt8($0) }[0 ..< Int(n)], as: UTF8.self)
        XCTAssertEqual(target, bridgePath, "hook symlink should point at the bridge socket")
    }

    // MARK: - Helpers

    /// `sendFrame` is a nonisolated, static helper so the detached client task
    /// can call it without main-actor capture.
    private nonisolated static func sendFrame(to path: String, json: String, expectReply: Bool = true) -> Data {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return Data() }
        defer { close(fd) }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        _ = withUnsafeMutableBytes(of: &addr.sun_path) { dst in
            bytes.withUnsafeBufferPointer { src in
                dst.baseAddress?.copyMemory(from: src.baseAddress!, byteCount: min(src.count, dst.count))
            }
        }
        let len = socklen_t(MemoryLayout<sockaddr_un>.size)
        let connected = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, len)
            }
        }
        guard connected == 0 else { return Data() }

        let out = Array(json.utf8)
        _ = out.withUnsafeBufferPointer { write(fd, $0.baseAddress, out.count) }

        guard expectReply else {
            // Give the server a moment to read + dispatch, then close.
            usleep(100_000)
            return Data()
        }
        var buf = [UInt8](repeating: 0, count: 4096)
        let n = buf.withUnsafeMutableBufferPointer { read(fd, $0.baseAddress, $0.count) }
        guard n > 0 else { return Data() }
        return Data(bytes: buf, count: n)
    }
}

/// Test double pointing `UnifiedListener` at temp sockets so we don't touch
/// ~/.archer or the global hook socket.
@MainActor
private final class TestUnifiedListener: UnifiedListener {
    private let overrideBridge: String
    private let overrideHook: String

    init(bridgePath: String, hookPath: String, hookHandler: @escaping (HookMessage) -> Void, storeProvider: @escaping () -> WorkspaceStore?) {
        overrideBridge = bridgePath
        overrideHook = hookPath
        super.init(hookHandler: hookHandler, storeProvider: storeProvider)
    }

    override var bridgePath: String {
        overrideBridge
    }

    override var hookPath: String {
        overrideHook
    }
}
