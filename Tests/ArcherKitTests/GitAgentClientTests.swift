@testable import ArcherKit
import XCTest

/// Decoding only — `GitAgentClient` shells out to the external `git-agent`
/// binary, so these tests validate the JSON contract we mirror (commit `-o
/// json` and related `-o json`) without requiring the binary to be installed.
final class GitAgentClientTests: XCTestCase {
    private let decoder: JSONDecoder = .init()

    func testCommitResultDecodesAtomicGroups() throws {
        // Shape copied from `git-agent commit -o json` (dry-run) output.
        let json = """
        {
          "dry_run": true,
          "commits": [
            {
              "title": "feat(panel): add AI commit button",
              "message": "feat(panel): add AI commit button\\n\\nWire the wand button to git-agent dry-run.",
              "files": ["Sources/ArcherKit/Diff/DiffPanelView.swift"],
              "sha": "",
              "hook_outcome": "skipped"
            },
            {
              "title": "test(client): cover commit JSON",
              "message": "test(client): cover commit JSON",
              "files": ["Tests/ArcherKitTests/GitAgentClientTests.swift"],
              "sha": "",
              "hook_outcome": "skipped"
            }
          ],
          "committed_count": 0,
          "final_sha": ""
        }
        """.data(using: .utf8)!

        let result = try decoder.decode(GitAgentCommitResult.self, from: json)
        XCTAssertTrue(result.dryRun)
        XCTAssertEqual(result.commits.count, 2)
        XCTAssertEqual(result.commits[0].title, "feat(panel): add AI commit button")
        XCTAssertEqual(result.commits[0].files, ["Sources/ArcherKit/Diff/DiffPanelView.swift"])
        // git-agent emits "" (not omitted) on dry-run, so sha is empty string.
        XCTAssertEqual(result.commits[0].sha, "")
        XCTAssertEqual(result.committedCount, 0)
    }

    func testCommitResultDecodesRealSHAsWhenApplied() throws {
        // After a real commit, `sha` carries the hash and `final_sha` is set.
        let json = """
        {
          "dry_run": false,
          "commits": [
            {
              "title": "fix(core): patch watcher leak",
              "message": "fix(core): patch watcher leak",
              "files": ["Sources/ArcherKit/Sessions/GitWatcher.swift"],
              "sha": "a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0",
              "hook_outcome": "passed"
            }
          ],
          "committed_count": 1,
          "final_sha": "a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0"
        }
        """.data(using: .utf8)!

        let result = try decoder.decode(GitAgentCommitResult.self, from: json)
        XCTAssertFalse(result.dryRun)
        XCTAssertEqual(result.commits.count, 1)
        XCTAssertEqual(result.commits[0].sha, "a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0")
        XCTAssertEqual(result.commits[0].hookOutcome, "passed")
        XCTAssertEqual(result.committedCount, 1)
        XCTAssertEqual(result.finalSha, "a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0")
    }

    func testRelatedResultDecodesCoChangeGraph() throws {
        // Shape copied from `git-agent related -o json` output.
        let json = """
        {
          "targets": ["Sources/ArcherKit/Diff/DiffPanelView.swift"],
          "co_changed": [
            {
              "path": "Sources/ArcherKit/Sessions/GitAgentClient.swift",
              "coupling_count": 12,
              "coupling_strength": 0.83,
              "score": 0.83,
              "seed_matches": 1,
              "commits": [
                {"sha": "deadbeef", "subject": "feat: integrate git-agent", "ts": 1717000000}
              ]
            }
          ],
          "total_found": 1,
          "query_ms": 14
        }
        """.data(using: .utf8)!

        let result = try decoder.decode(GitAgentRelatedResult.self, from: json)
        XCTAssertEqual(result.targets.count, 1)
        XCTAssertEqual(result.coChanged.count, 1)
        let entry = result.coChanged[0]
        XCTAssertEqual(entry.path, "Sources/ArcherKit/Sessions/GitAgentClient.swift")
        XCTAssertEqual(entry.couplingCount, 12)
        XCTAssertEqual(entry.couplingStrength, 0.83, accuracy: 0.001)
        XCTAssertEqual(entry.commits?.count, 1)
        XCTAssertEqual(entry.commits?.first?.sha, "deadbeef")
        XCTAssertEqual(entry.commits?.first?.subject, "feat: integrate git-agent")
        XCTAssertEqual(result.totalFound, 1)
        XCTAssertEqual(result.queryMs, 14)
    }

    func testRelatedResultHandlesEmptyGraph() throws {
        let json = """
        {
          "targets": [],
          "co_changed": [],
          "total_found": 0,
          "query_ms": 3
        }
        """.data(using: .utf8)!

        let result = try decoder.decode(GitAgentRelatedResult.self, from: json)
        XCTAssertTrue(result.coChanged.isEmpty)
        XCTAssertEqual(result.totalFound, 0)
    }
}
