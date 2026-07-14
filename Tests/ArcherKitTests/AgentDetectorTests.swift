@testable import ArcherKit
import XCTest

final class AgentDetectorTests: XCTestCase {
    func testClassifyMatchesExecutableBasenames() {
        let lines = [
            "/opt/homebrew/bin/claude --resume",
            "codex    /usr/local/bin/codex exec",
            "Cursor   /Applications/Cursor.app/Contents/MacOS/Cursor",
        ]
        let found = AgentDetector.classify(lines)
        XCTAssertEqual(found, [.claude, .codex, .cursor])
    }

    func testClassifyDoesNotMatchKeywordInsideUnrelatedPath() {
        // Whole-table substring would false-positive on "cursor" in a path;
        // basename matching must not.
        let lines = [
            "vim    /Users/me/docs/cursor-notes/README.md",
            "cat    /tmp/claude-essay.txt",
            "bash   /Users/me/bin/my-gemini-helper-notes",
            "python3 /opt/tools/claude-legacy/run.py",
        ]
        let found = AgentDetector.classify(lines)
        XCTAssertTrue(found.isEmpty, "unexpected hits: \(found)")
    }

    func testClassifySupportsMultipleAgents() {
        let lines = [
            "claude  claude",
            "hermes  hermes-agent",
            "grok    grok",
        ]
        let found = AgentDetector.classify(lines)
        XCTAssertEqual(found, [.claude, .hermes, .grok])
    }

    func testClassifyEmptySnapshot() {
        XCTAssertTrue(AgentDetector.classify([]).isEmpty)
    }
}
