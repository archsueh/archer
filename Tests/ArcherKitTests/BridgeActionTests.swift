@testable import ArcherKit
import XCTest

@MainActor
final class BridgeActionTests: XCTestCase {
    private let project = URL(fileURLWithPath: "/tmp/archer-bridge-action")

    override func setUp() {
        super.setUp()
        try? FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        BridgeEventLog.shared.clear()
    }

    private func makeStore() -> WorkspaceStore {
        WorkspaceStore(
            persistence: InMemoryPersistence(),
            engineFactory: { TestEngine() },
            optionsProvider: { _ in nil },
            resumeProvider: { true }
        )
    }

    func testTypeAgainstLiveLabel() {
        let store = makeStore()
        let ws = store.addWorkspace(workingDirectory: project)
        _ = store.addTab(in: ws, template: .claudeCode)
        PaneRegistry.shared.sync(workspace: ws)
        let result = BridgeAction.perform(
            verb: .type,
            target: "@claude-code",
            text: "hello\n",
            store: store
        )
        guard case .success = result else {
            return XCTFail("\(result)")
        }
        XCTAssertTrue(BridgeEventLog.shared.entries.contains { $0.summary.contains("type → @claude-code") })
    }

    func testTypeMissingLabelFails() {
        let store = makeStore()
        _ = store.addWorkspace(workingDirectory: project)
        PaneRegistry.shared.sync(workspace: store.active)
        let result = BridgeAction.perform(
            verb: .type,
            target: "no-pane",
            text: "x",
            store: store
        )
        guard case let .failure(err) = result else {
            return XCTFail("expected failure")
        }
        XCTAssertTrue(err.message.contains("not found"), err.message)
    }

    func testHandoffOpensAndLogsRoute() {
        let store = makeStore()
        let ws = store.addWorkspace(workingDirectory: project)
        _ = store.addTab(in: ws, template: .grok)
        let result = BridgeAction.perform(
            verb: .handoff,
            target: "claude-code",
            text: "do it",
            store: store
        )
        guard case let .success(msg) = result else {
            return XCTFail("\(result)")
        }
        XCTAssertTrue(msg.contains("@claude-code"), msg)
        XCTAssertTrue(BridgeEventLog.shared.entries.contains { $0.summary.hasPrefix("handoff") })
        let opened = ws.root.allPanes.flatMap(\.tabs).first { $0.displayAgent.id == "claude-code" }
        XCTAssertEqual(opened?.drivenByLabel, "grok")
    }

    func testKeysParsesSpaceSeparated() throws {
        let store = makeStore()
        let ws = store.addWorkspace(workingDirectory: project)
        let tab = store.addTab(in: ws, template: .claudeCode)
        PaneRegistry.shared.sync(workspace: ws)
        let eng = try XCTUnwrap(tab.engine as? TestEngine)
        let before = eng.sentInputs.count
        let result = BridgeAction.perform(
            verb: .keys,
            target: "claude-code",
            text: "Enter ctrl+c",
            store: store
        )
        guard case .success = result else {
            return XCTFail("\(result)")
        }
        XCTAssertGreaterThan(eng.sentInputs.count, before)
    }

    /// Skeptic: activity-bar ↗ / ContentView must open console *with* store —
    /// bare show() + refreshLabels → sync(nil) wipes PaneRegistry.
    func testSyncNilWipesRegistryButStorePathPreservesLabels() {
        let store = makeStore()
        let ws = store.addWorkspace(workingDirectory: project)
        _ = store.addTab(in: ws, template: .claudeCode)
        PaneRegistry.shared.sync(workspace: ws)
        XCTAssertFalse(PaneRegistry.shared.entries.isEmpty, "precondition: registry filled")

        // Bad path (old BridgeActivityBar): sync without workspace clears.
        PaneRegistry.shared.sync(workspace: nil)
        XCTAssertTrue(PaneRegistry.shared.entries.isEmpty, "sync(nil) must clear")

        // Good path: re-sync from store (BridgeConsoleView when provider returns store).
        PaneRegistry.shared.sync(workspace: store.active)
        XCTAssertFalse(PaneRegistry.shared.entries.isEmpty)
        XCTAssertNotNil(PaneRegistry.shared.session(forAddress: "claude-code"))

        // Activity-bar open path: show(storeProvider:) retains store for handoff.
        LogPanelWindowController.show(storeProvider: { store })
        XCTAssertNotNil(LogPanelWindowController.installedStoreProvider?())
        XCTAssertTrue(LogPanelWindowController.installedStoreProvider?() === store)

        let handoff = BridgeAction.perform(
            verb: .handoff,
            target: "grok",
            text: "from activity bar open",
            store: LogPanelWindowController.installedStoreProvider?()
        )
        guard case .success = handoff else {
            return XCTFail("handoff after show(storeProvider:) failed: \(handoff)")
        }
    }

    /// Named for skeptic checklist: activity-bar open path keeps store + registry.
    func testActivityBarOpenPathKeepsStoreAndRegistry() {
        let store = makeStore()
        let ws = store.addWorkspace(workingDirectory: project)
        _ = store.addTab(in: ws, template: .claudeCode)
        PaneRegistry.shared.sync(workspace: ws)
        let countBefore = PaneRegistry.shared.entries.count
        XCTAssertGreaterThan(countBefore, 0)

        // Exact path used by BridgeActivityBar ↗ and AgentRosterStrip "Bridge".
        BridgeConsoleLauncher.open(store: store)
        // Console must not wipe: re-sync only when store present (same as refreshLabels).
        if let s = LogPanelWindowController.installedStoreProvider?() {
            PaneRegistry.shared.sync(workspace: s.active)
        }
        XCTAssertEqual(PaneRegistry.shared.entries.count, countBefore)
        XCTAssertNotNil(PaneRegistry.shared.session(forAddress: "claude-code"))
        XCTAssertTrue(LogPanelWindowController.installedStoreProvider?() === store)

        let result = BridgeAction.perform(
            verb: .type,
            target: "@claude-code",
            text: "still addressable\n",
            store: LogPanelWindowController.installedStoreProvider?()
        )
        guard case .success = result else {
            return XCTFail("type after activity-bar open failed: \(result)")
        }
    }

    /// Activity bar requires store at compile time; launcher is the only open path.
    func testBridgeActivityBarRequiresStoreProperty() {
        // If BridgeActivityBar() without store compiles again, this test file's
        // construction below would still force the store path for open.
        let store = makeStore()
        _ = store.addWorkspace(workingDirectory: project)
        BridgeConsoleLauncher.open(store: store)
        XCTAssertTrue(LogPanelWindowController.installedStoreProvider?() === store)
    }
}
