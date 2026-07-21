@testable import ArcherKit
import XCTest

/// Bridge `handoff` / `open` / `agents` wire commands (pure handler, no socket).
@MainActor
final class BridgeHandoffTests: XCTestCase {
    private let project = URL(fileURLWithPath: "/tmp/archer-bridge-handoff")

    override func setUp() {
        super.setUp()
        try? FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
    }

    private func makeStore() -> WorkspaceStore {
        WorkspaceStore(
            persistence: InMemoryPersistence(),
            engineFactory: { TestEngine() },
            optionsProvider: { _ in nil },
            resumeProvider: { true }
        )
    }

    private func server(store: WorkspaceStore) -> BridgeServer {
        let s = BridgeServer()
        s.storeProvider = { store }
        return s
    }

    private func handle(_ server: BridgeServer, _ obj: [String: Any]) -> [String: Any] {
        let data = try! JSONSerialization.data(withJSONObject: obj)
        let reply = server.handle(data)
        return (try? JSONSerialization.jsonObject(with: reply) as? [String: Any]) ?? [:]
    }

    func testHandoffOpensTabWithPrompt() {
        let store = makeStore()
        _ = store.addWorkspace(workingDirectory: project)
        let srv = server(store: store)
        let dict = handle(srv, [
            "cmd": "handoff",
            "agent": "claude-code",
            "prompt": "do the thing",
        ])
        XCTAssertEqual(dict["ok"] as? Bool, true)
        XCTAssertEqual(dict["agent"] as? String, "claude-code")
        let label = dict["label"] as? String
        XCTAssertEqual(label, "claude-code")
        XCTAssertNotNil(dict["sessionId"] as? String)
    }

    func testHandoffAcceptsAtPrefixAndSetsDrivenBy() {
        let store = makeStore()
        let ws = store.addWorkspace(workingDirectory: project)
        // Source agent tab so handoff can capture drivenBy
        _ = store.addTab(in: ws, template: .grok)
        PaneRegistry.shared.sync(workspace: ws)
        let srv = server(store: store)
        let dict = handle(srv, [
            "cmd": "handoff",
            "agent": "@claude-code",
            "prompt": "from @route",
        ])
        XCTAssertEqual(dict["ok"] as? Bool, true)
        XCTAssertEqual(dict["from"] as? String, "grok")
        let sid = dict["sessionId"] as? String
        let session = ws.root.allPanes.flatMap(\.tabs).first { $0.id.uuidString == sid }
        XCTAssertEqual(session?.drivenByLabel, "grok")
    }

    func testTypeAcceptsAtLabel() {
        let store = makeStore()
        let ws = store.addWorkspace(workingDirectory: project)
        _ = store.addTab(in: ws, template: .claudeCode)
        let srv = server(store: store)
        let dict = handle(srv, [
            "cmd": "type",
            "label": "@claude-code",
            "text": "hello\n",
        ])
        XCTAssertEqual(dict["ok"] as? Bool, true)
    }

    func testOpenWithoutPrompt() {
        let store = makeStore()
        _ = store.addWorkspace(workingDirectory: project)
        let srv = server(store: store)
        let dict = handle(srv, ["cmd": "open", "agent": "grok"])
        XCTAssertEqual(dict["ok"] as? Bool, true)
        XCTAssertEqual(dict["agent"] as? String, "grok")
    }

    func testHandoffUnknownAgent() {
        let store = makeStore()
        _ = store.addWorkspace(workingDirectory: project)
        let srv = server(store: store)
        let dict = handle(srv, ["cmd": "handoff", "agent": "definitely-not-an-agent"])
        XCTAssertEqual(dict["ok"] as? Bool, false)
        let err = dict["error"] as? String ?? ""
        XCTAssertTrue(err.contains("unknown agent"), err)
    }

    func testAgentsListsNonShell() {
        let store = makeStore()
        let srv = server(store: store)
        let dict = handle(srv, ["cmd": "agents"])
        XCTAssertEqual(dict["ok"] as? Bool, true)
        let agents = dict["agents"] as? [[String: Any]] ?? []
        XCTAssertFalse(agents.isEmpty)
        XCTAssertTrue(agents.allSatisfy { ($0["id"] as? String) != "terminal" })
    }
}
