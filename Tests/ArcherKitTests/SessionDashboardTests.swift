@testable import ArcherKit
import XCTest

@MainActor
final class SessionDashboardTests: XCTestCase {
    // MARK: - SessionStatusDeriver

    func testStatusDeriverAttentionWinsOverError() {
        let status = SessionStatusDeriver.status(activityState: .attention, lastCommandExit: 1)
        XCTAssertEqual(status, .waiting)
    }

    func testStatusDeriverErrorWinsOverRunning() {
        let status = SessionStatusDeriver.status(activityState: .running, lastCommandExit: 1)
        XCTAssertEqual(status, .error)
    }

    func testStatusDeriverRunningWithCleanExit() {
        let status = SessionStatusDeriver.status(activityState: .running, lastCommandExit: 0)
        XCTAssertEqual(status, .running)
    }

    func testStatusDeriverNilExitIsNotError() {
        let status = SessionStatusDeriver.status(activityState: .idle, lastCommandExit: nil)
        XCTAssertEqual(status, .idle)
    }

    func testStatusDeriverIdleDefault() {
        let status = SessionStatusDeriver.status(activityState: .idle, lastCommandExit: 0)
        XCTAssertEqual(status, .idle)
    }

    // MARK: - SessionDashboardIndex.build

    private func makeStore() -> WorkspaceStore {
        WorkspaceStore(
            persistence: InMemoryPersistence(),
            engineFactory: { TestEngine() },
            optionsProvider: { _ in nil },
            resumeProvider: { true }
        )
    }

    func testBuildFlattensSingleStoreWithNoWindowLabel() {
        let store = makeStore()
        let ws = store.workspaces[0]
        _ = store.addTab(in: ws, template: .terminal)

        let rows = SessionDashboardIndex.build(stores: [store], tokenLookup: { _ in nil })

        XCTAssertEqual(rows.count, 2) // default tab + the one just added
        XCTAssertTrue(rows.allSatisfy { $0.windowLabel.isEmpty })
    }

    func testBuildLabelsRowsByWindowWhenMultipleStores() {
        let storeA = makeStore()
        let storeB = makeStore()

        let rows = SessionDashboardIndex.build(stores: [storeA, storeB], tokenLookup: { _ in nil })

        XCTAssertEqual(rows.filter { $0.windowLabel == " · window 1" }.count, 1)
        XCTAssertEqual(rows.filter { $0.windowLabel == " · window 2" }.count, 1)
    }

    func testBuildDerivesStatusFromLiveSessionState() throws {
        let store = makeStore()
        let session = try XCTUnwrap(store.workspaces[0].activeSession)
        session.activityState = .running

        let rows = SessionDashboardIndex.build(stores: [store], tokenLookup: { _ in nil })

        XCTAssertEqual(rows.first?.status, .running)
    }

    func testBuildTokenLookupOnlyCalledForSessionsWithConversationId() {
        let store = makeStore()
        let ws = store.workspaces[0]
        let withConversation = store.addTab(in: ws, template: .terminal, conversationId: "conv-1")
        _ = withConversation

        var lookedUp: [String] = []
        let rows = SessionDashboardIndex.build(stores: [store], tokenLookup: { id in
            lookedUp.append(id)
            return id == "conv-1" ? 42 : nil
        })

        // Only the tab with a conversationId should have triggered a lookup.
        XCTAssertEqual(lookedUp, ["conv-1"])
        XCTAssertEqual(rows.first { $0.id == withConversation.id }?.tokenTotal, 42)
        // The default tab (no conversationId) falls back to nil, not a lookup call.
        XCTAssertTrue(rows.contains { $0.id != withConversation.id && $0.tokenTotal == nil })
    }

    // MARK: - UsageCollector.claudeSessionTokenTotals

    func testClaudeSessionTokenTotalsSumsPerSession() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("archer-dashboard-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let file = root.appendingPathComponent("project.jsonl")
        let lines = [
            #"{"type":"assistant","sessionId":"sess-1","timestamp":"2026-01-01T00:00:00Z","message":{"id":"resp-1","model":"claude-3-5-sonnet","usage":{"input_tokens":100,"output_tokens":50},"stop_reason":"end_turn"}}"#,
            #"{"type":"assistant","sessionId":"sess-1","timestamp":"2026-01-01T00:05:00Z","message":{"id":"resp-2","model":"claude-3-5-sonnet","usage":{"input_tokens":20,"output_tokens":10},"stop_reason":"end_turn"}}"#,
            #"{"type":"assistant","sessionId":"sess-2","timestamp":"2026-01-01T00:00:00Z","message":{"id":"resp-3","model":"claude-3-5-sonnet","usage":{"input_tokens":5,"output_tokens":5},"stop_reason":"end_turn"}}"#,
        ]
        try lines.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)

        let totals = UsageCollector.claudeSessionTokenTotals(rootURL: root)

        XCTAssertEqual(totals["sess-1"], 180) // 100+50 + 20+10
        XCTAssertEqual(totals["sess-2"], 10)
    }
}
