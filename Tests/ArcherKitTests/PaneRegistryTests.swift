@testable import ArcherKit
import XCTest

@MainActor
final class PaneRegistryTests: XCTestCase {
    func testNormalizeLabelStripsAt() {
        XCTAssertEqual(PaneRegistry.normalizeLabel("@codex"), "codex")
        XCTAssertEqual(PaneRegistry.normalizeLabel("  @claude-code  "), "claude-code")
        XCTAssertEqual(PaneRegistry.normalizeLabel("hermes"), "hermes")
    }

    func testAtFormats() {
        XCTAssertEqual(PaneRegistry.at("codex"), "@codex")
        XCTAssertEqual(PaneRegistry.at("@codex"), "@codex")
        XCTAssertEqual(PaneRegistry.at("  "), "")
    }

    func testRegistersAllNonShellTabsNotOnlyActive() {
        let store = WorkspaceStore(
            persistence: InMemoryPersistence(),
            engineFactory: { TestEngine() },
            optionsProvider: { _ in nil },
            resumeProvider: { true }
        )
        let ws = store.addWorkspace(workingDirectory: URL(fileURLWithPath: "/tmp/pr-reg"))
        let claude = store.addTab(in: ws, template: .claudeCode)
        let grok = store.addTab(in: ws, template: .grok)
        // Active is last added (grok); claude is background.
        PaneRegistry.shared.sync(workspace: ws)
        XCTAssertNotNil(PaneRegistry.shared.label(for: claude))
        XCTAssertNotNil(PaneRegistry.shared.label(for: grok))
        XCTAssertEqual(PaneRegistry.shared.entries.count, 2)
    }
}
