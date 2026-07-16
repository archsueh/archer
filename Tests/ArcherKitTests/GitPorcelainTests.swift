@testable import ArcherKit
import XCTest

final class GitPorcelainTests: XCTestCase {
    func testParseModifiedAddedDeleted() {
        let cwd = "/tmp/repo"
        // XY + space + path, null-separated (porcelain -z)
        let raw = " M Sources/A.swift\0A  Sources/New.swift\0 D Sources/Gone.swift\0"
        let files = GitPorcelain.parse(raw, cwd: cwd)
        // Sorted by full path: A → Gone → New
        XCTAssertEqual(files.map { $0.url.lastPathComponent }, ["A.swift", "Gone.swift", "New.swift"])
        XCTAssertEqual(files.map(\.status), [.modified, .deleted, .added])
    }

    /// Regression: leading space in ` M path` must not be trimmed before parse
    /// (that used to eat the first letter of the filename).
    func testParseUnstagedModifyPreservesPath() {
        let files = GitPorcelain.parse(" M tracked.txt\0", cwd: "/repo")
        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(files[0].status, .modified)
        XCTAssertEqual(files[0].url.lastPathComponent, "tracked.txt")
    }

    func testParseUntrackedAsAdded() {
        let files = GitPorcelain.parse("?? untracked.txt\0", cwd: "/repo")
        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(files[0].status, .added)
        XCTAssertEqual(files[0].url.lastPathComponent, "untracked.txt")
    }

    /// `-z` rename: `R  <new>\0<old>\0` — old path must not become a phantom entry.
    func testParseRenameConsumesOldPathToken() {
        let raw = "R  app/New.swift\0app/Old.swift\0"
        let files = GitPorcelain.parse(raw, cwd: "/repo")
        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(files[0].status, .modified)
        XCTAssertEqual(files[0].url.lastPathComponent, "New.swift")
        // Without skip, bare `app/Old.swift` became `p/Old.swift` (dropFirst 3).
        XCTAssertFalse(files.contains { $0.url.path.hasSuffix("/p/Old.swift") })
        XCTAssertFalse(files.contains { $0.url.lastPathComponent == "Old.swift" })
    }

    func testParseCopyConsumesOldPathToken() {
        let raw = "C  app/Copy.swift\0app/Orig.swift\0 M other.txt\0"
        let files = GitPorcelain.parse(raw, cwd: "/repo")
        let names = Set(files.map { $0.url.lastPathComponent })
        XCTAssertEqual(names, ["Copy.swift", "other.txt"])
        XCTAssertEqual(files.map(\.status), [.modified, .modified])
        XCTAssertFalse(names.contains("Orig.swift"))
    }

    func testParseEmptyAndGarbage() {
        XCTAssertTrue(GitPorcelain.parse("", cwd: "/repo").isEmpty)
        XCTAssertTrue(GitPorcelain.parse("\0\0", cwd: "/repo").isEmpty)
        // Too short (no path after XY)
        XCTAssertTrue(GitPorcelain.parse("M \0", cwd: "/repo").isEmpty)
    }

    func testStatusByURLExactHit() {
        let map: [URL: GitFileStatus] = [
            URL(fileURLWithPath: "/repo/a.swift"): .modified,
            URL(fileURLWithPath: "/repo/b.swift"): .added,
        ]
        XCTAssertEqual(
            GitPorcelain.status(for: URL(fileURLWithPath: "/repo/a.swift"), in: map),
            .modified
        )
        XCTAssertNil(
            GitPorcelain.status(for: URL(fileURLWithPath: "/repo/clean.swift"), in: map)
        )
    }

    func testDirectoryRollupPrefersModified() {
        let map: [URL: GitFileStatus] = [
            URL(fileURLWithPath: "/repo/src/a.swift"): .added,
            URL(fileURLWithPath: "/repo/src/b.swift"): .deleted,
        ]
        // Mixed A+D under src → modified
        XCTAssertEqual(
            GitPorcelain.status(for: URL(fileURLWithPath: "/repo/src"), in: map),
            .modified
        )
        // Only added under nested
        let onlyA: [URL: GitFileStatus] = [
            URL(fileURLWithPath: "/repo/src/new.swift"): .added,
        ]
        XCTAssertEqual(
            GitPorcelain.status(for: URL(fileURLWithPath: "/repo/src"), in: onlyA),
            .added
        )
    }

    func testDirectoryRollupIgnoresSiblingPaths() {
        let map: [URL: GitFileStatus] = [
            URL(fileURLWithPath: "/repo/src2/x.swift"): .modified,
        ]
        // /repo/src must not match /repo/src2 via naive prefix
        XCTAssertNil(
            GitPorcelain.status(for: URL(fileURLWithPath: "/repo/src"), in: map)
        )
    }

    /// Live git smoke: init repo, dirty a file, map hits.
    func testLivePorcelainStatusByURL() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("archer-porcelain-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        guard GitStatusFetcher.runGit(["-C", root.path, "init", "--initial-branch=main"], timeout: 5) != nil else {
            throw XCTSkip("git init unavailable")
        }
        _ = GitStatusFetcher.runGit(["-C", root.path, "config", "user.email", "t@t"], timeout: 5)
        _ = GitStatusFetcher.runGit(["-C", root.path, "config", "user.name", "t"], timeout: 5)

        let tracked = root.appendingPathComponent("tracked.txt")
        try Data("v1\n".utf8).write(to: tracked)
        guard GitStatusFetcher.runGit(["-C", root.path, "add", "tracked.txt"], timeout: 5) != nil,
              GitStatusFetcher.runGit(["-C", root.path, "commit", "-m", "init"], timeout: 5) != nil
        else {
            throw XCTSkip("git commit failed")
        }

        try Data("v2\n".utf8).write(to: tracked)
        let untracked = root.appendingPathComponent("new.txt")
        try Data("n\n".utf8).write(to: untracked)

        let map = GitPorcelain.statusByURL(cwd: root.path)
        // Compare by basename — temp dirs may be `/var` vs `/private/var`.
        let byName = Dictionary(uniqueKeysWithValues: map.map {
            ($0.key.lastPathComponent, $0.value)
        })
        XCTAssertEqual(byName["tracked.txt"], .modified, "map=\(map)")
        XCTAssertEqual(byName["new.txt"], .added, "map=\(map)")
    }
}
