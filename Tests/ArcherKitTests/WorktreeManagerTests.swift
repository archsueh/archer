@testable import ArcherKit
import XCTest

final class WorktreeManagerTests: XCTestCase {
    private var tempRoots: [URL] = []

    override func tearDown() {
        // Each test creates its repo + worktree under temporaryDirectory;
        // collect them here so a `git worktree remove` skip doesn't leave
        // half-built repos around between runs.
        for url in tempRoots {
            try? FileManager.default.removeItem(at: url)
        }
        tempRoots.removeAll()
        super.tearDown()
    }

    private func tempDir() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("archer-wt-\(UUID().uuidString)")
        tempRoots.append(url)
        return url
    }

    /// Spins up a git repo with one empty commit so worktrees can branch
    /// off `main`. `-c user.*` sidesteps machines without global git
    /// identity (CI / fresh dev boxes).
    @discardableResult
    private func makeRepo(at url: URL) -> Bool {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        guard GitStatusFetcher.runGit(["-C", url.path, "init", "--initial-branch=main"], timeout: 5) != nil else {
            return false
        }
        guard GitStatusFetcher.runGit([
            "-C", url.path,
            "-c", "user.email=test@example.com",
            "-c", "user.name=Test",
            "commit", "--allow-empty", "-m", "init", "--no-gpg-sign",
        ], timeout: 5) != nil else {
            return false
        }
        return true
    }

    // MARK: - parseList (pure)

    func testParseListEmpty() {
        XCTAssertEqual(WorktreeManager.parseList(""), [])
    }

    func testParseListMultipleRecords() {
        let output = """
        worktree /Users/test/repo
        HEAD abc123
        branch refs/heads/main

        worktree /Users/test/repo-feat
        HEAD def456
        branch refs/heads/feat-x

        """
        let infos = WorktreeManager.parseList(output)
        XCTAssertEqual(infos.count, 2)
        XCTAssertEqual(infos[0].path, URL(fileURLWithPath: "/Users/test/repo"))
        XCTAssertEqual(infos[0].branch, "main")
        XCTAssertEqual(infos[1].path, URL(fileURLWithPath: "/Users/test/repo-feat"))
        XCTAssertEqual(infos[1].branch, "feat-x")
    }

    func testParseListDetachedHEADHasNilBranch() {
        let output = """
        worktree /Users/test/repo
        HEAD abc123
        detached

        """
        let infos = WorktreeManager.parseList(output)
        XCTAssertEqual(infos.count, 1)
        XCTAssertNil(infos[0].branch)
    }

    func testCheckedOutBranchesDropsDetachedRecords() {
        let infos = [
            WorktreeManager.Info(path: URL(fileURLWithPath: "/tmp/repo"), branch: "main"),
            WorktreeManager.Info(path: URL(fileURLWithPath: "/tmp/repo-feat"), branch: "feature/foo"),
            WorktreeManager.Info(path: URL(fileURLWithPath: "/tmp/repo-detached"), branch: nil),
        ]

        XCTAssertEqual(WorktreeManager.checkedOutBranches(in: infos), ["main", "feature/foo"])
    }

    func testDefaultDirectoryNameSlugsBranchPathSeparators() {
        XCTAssertEqual(
            WorktreeManager.defaultDirectoryName(sourceName: "archer", branch: "feature/worktree ux"),
            "archer-feature-worktree-ux"
        )
        XCTAssertEqual(
            WorktreeManager.defaultDirectoryName(sourceName: "archer", branch: "bugfix\\pane:drag"),
            "archer-bugfix-pane-drag"
        )
    }

    func testDefaultDirectoryNameKeepsPlaceholderShapeWhenBranchEmpty() {
        XCTAssertEqual(
            WorktreeManager.defaultDirectoryName(sourceName: "archer", branch: ""),
            "archer-"
        )
    }

    func testRepoRootResolvesFromNestedDirectory() throws {
        let repo = tempDir()
        try XCTSkipUnless(makeRepo(at: repo), "git unavailable")
        let nested = repo.appendingPathComponent("sub/dir", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)

        let root = WorktreeManager.repoRoot(near: nested)

        XCTAssertEqual(root?.standardizedFileURL, repo.standardizedFileURL)
    }

    // MARK: - Integration (git on PATH)

    func testAddNewBranchListsAndRemoves() throws {
        let repo = tempDir()
        try XCTSkipUnless(makeRepo(at: repo), "git unavailable")

        let wt = repo.appendingPathExtension("feat-x")

        let addResult = WorktreeManager.add(
            repoPath: repo,
            path: wt,
            mode: .newBranch(name: "feat-x", base: nil)
        )
        if case let .failure(err) = addResult {
            XCTFail("add failed: \(err.description)")
            return
        }

        guard case let .success(infos) = WorktreeManager.list(repoPath: repo) else {
            XCTFail("list failed"); return
        }
        XCTAssertEqual(infos.count, 2)
        XCTAssertTrue(infos.contains { $0.branch == "feat-x" })

        let removeResult = WorktreeManager.remove(repoPath: repo, path: wt, force: false)
        if case let .failure(err) = removeResult {
            XCTFail("remove failed: \(err.description)")
            return
        }

        guard case let .success(afterRemove) = WorktreeManager.list(repoPath: repo) else {
            XCTFail("list after remove failed"); return
        }
        XCTAssertEqual(afterRemove.count, 1)
    }

    func testAddExistingBranchCheckoutWorks() throws {
        let repo = tempDir()
        try XCTSkipUnless(makeRepo(at: repo), "git unavailable")
        _ = GitStatusFetcher.runGit(["-C", repo.path, "branch", "side"], timeout: 5)

        let wt = repo.appendingPathExtension("side")
        let result = WorktreeManager.add(
            repoPath: repo, path: wt, mode: .existing(branch: "side")
        )
        if case let .failure(err) = result {
            XCTFail("add existing failed: \(err.description)")
            return
        }
        guard case let .success(infos) = WorktreeManager.list(repoPath: repo) else {
            XCTFail("list failed"); return
        }
        XCTAssertTrue(infos.contains { $0.branch == "side" })
    }

    func testAddFailsCarriesStderrFromGit() throws {
        // Picking a clearly bogus branch name keeps the failure stable
        // across git versions (some accept an empty dir as the worktree
        // path; none accept an unknown ref).
        let repo = tempDir()
        try XCTSkipUnless(makeRepo(at: repo), "git unavailable")

        let wt = repo.appendingPathExtension("ghost")
        let result = WorktreeManager.add(
            repoPath: repo,
            path: wt,
            mode: .existing(branch: "this-branch-does-not-exist-12345")
        )
        guard case let .failure(err) = result else {
            XCTFail("expected failure when branch is unknown")
            return
        }
        XCTAssertFalse(err.stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                       "stderr should carry git's message")
        XCTAssertNotEqual(err.exitCode, 0)
    }

    func testCurrentBranchReportsMainAfterInit() throws {
        let repo = tempDir()
        try XCTSkipUnless(makeRepo(at: repo), "git unavailable")
        XCTAssertEqual(WorktreeManager.currentBranch(repoPath: repo), "main")
    }

    func testMergeFeatureBranchIntoMainTree() throws {
        let repo = tempDir()
        try XCTSkipUnless(makeRepo(at: repo), "git unavailable")
        let wt = repo.appendingPathExtension("feat-merge")
        let addResult = WorktreeManager.add(
            repoPath: repo,
            path: wt,
            mode: .newBranch(name: "feat-merge", base: nil)
        )
        if case let .failure(err) = addResult {
            XCTFail("add failed: \(err.description)")
            return
        }
        // Commit on the worktree branch so merge has content.
        let file = wt.appendingPathComponent("feature.txt")
        try "hello".write(to: file, atomically: true, encoding: .utf8)
        guard GitStatusFetcher.runGit(["-C", wt.path, "add", "feature.txt"], timeout: 5) != nil,
              GitStatusFetcher.runGit([
                  "-C", wt.path,
                  "-c", "user.email=test@example.com",
                  "-c", "user.name=Test",
                  "commit", "-m", "feat", "--no-gpg-sign",
              ], timeout: 5) != nil
        else {
            XCTFail("commit on worktree failed")
            return
        }

        let merge = WorktreeManager.merge(repoPath: repo, branch: "feat-merge")
        if case let .failure(err) = merge {
            XCTFail("merge failed: \(err.description)")
            return
        }
        // File should now exist on main tree after merge.
        let mergedFile = repo.appendingPathComponent("feature.txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: mergedFile.path))
        XCTAssertEqual(try String(contentsOf: mergedFile, encoding: .utf8), "hello")
    }

    func testMergeUnknownBranchSurfacesStderr() throws {
        let repo = tempDir()
        try XCTSkipUnless(makeRepo(at: repo), "git unavailable")
        let result = WorktreeManager.merge(repoPath: repo, branch: "no-such-branch-zzzz")
        guard case let .failure(err) = result else {
            XCTFail("expected merge of unknown branch to fail")
            return
        }
        XCTAssertFalse(err.stderr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
}
