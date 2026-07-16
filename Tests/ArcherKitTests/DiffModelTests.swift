@testable import ArcherKit
import XCTest

@MainActor
final class DiffModelTests: XCTestCase {
    private var tempRoots: [URL] = []

    override func tearDown() {
        for url in tempRoots {
            try? FileManager.default.removeItem(at: url)
        }
        tempRoots.removeAll()
        super.tearDown()
    }

    private func tempDir() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("archer-diff-\(UUID().uuidString)", isDirectory: true)
        tempRoots.append(url)
        return url
    }

    @discardableResult
    private func makeRepo(at url: URL) -> Bool {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        guard GitStatusFetcher.runGit(["-C", url.path, "init", "--initial-branch=main"], timeout: 5) != nil else {
            return false
        }
        return GitStatusFetcher.runGit([
            "-C", url.path,
            "-c", "user.email=test@example.com",
            "-c", "user.name=Test",
            "commit", "--allow-empty", "-m", "init", "--no-gpg-sign",
        ], timeout: 5) != nil
    }

    func testDiffParserWithStandardDiff() {
        let rawDiff = """
        diff --git a/Sources/main.swift b/Sources/main.swift
        index 8e5fd20..69bbf1a 100644
        --- a/Sources/main.swift
        +++ b/Sources/main.swift
        @@ -10,3 +10,4 @@
         unchanged context line
        -deleted line
        +added line
         other context line
        """
        let lines = DiffParser.parse(rawDiff)

        XCTAssertEqual(lines.count, 9)
        XCTAssertEqual(lines[0].type, .header)
        XCTAssertEqual(lines[0].content, "diff --git a/Sources/main.swift b/Sources/main.swift")

        XCTAssertEqual(lines[4].type, .header) // @@ -10,3 +10,4 @@

        // Context line
        XCTAssertEqual(lines[5].type, .context)
        XCTAssertEqual(lines[5].content, " unchanged context line")
        XCTAssertEqual(lines[5].oldLineNum, 10)
        XCTAssertEqual(lines[5].newLineNum, 10)

        // Deleted line
        XCTAssertEqual(lines[6].type, .deleted)
        XCTAssertEqual(lines[6].content, "-deleted line")
        XCTAssertEqual(lines[6].oldLineNum, 11)
        XCTAssertNil(lines[6].newLineNum)

        // Added line
        XCTAssertEqual(lines[7].type, .added)
        XCTAssertEqual(lines[7].content, "+added line")
        XCTAssertNil(lines[7].oldLineNum)
        XCTAssertEqual(lines[7].newLineNum, 11)
    }

    func testDiffParserWithEmptyInput() {
        let lines = DiffParser.parse("")
        XCTAssertTrue(lines.isEmpty)
    }

    func testSingleRootHidesFamilyOverview() async throws {
        let repo = tempDir()
        try XCTSkipUnless(makeRepo(at: repo), "git unavailable")
        let model = DiffModel(rootURL: repo)
        defer { model.teardown() }
        // Wait for first refresh.
        for _ in 0 ..< 40 where model.isLoading {
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        XCTAssertFalse(model.showsFamilyOverview)
        XCTAssertEqual(model.summaries.count, 1)
        XCTAssertEqual(model.focusedRootURL.standardizedFileURL, repo.standardizedFileURL)
    }

    func testFamilyOverviewSummarizesEachWorktree() async throws {
        let repo = tempDir()
        try XCTSkipUnless(makeRepo(at: repo), "git unavailable")
        let wt = repo.appendingPathExtension("feat")
        let add = WorktreeManager.add(
            repoPath: repo, path: wt, mode: .newBranch(name: "feat-diff", base: nil)
        )
        try XCTSkipUnless({
            if case .success = add { return true }
            return false
        }(), "worktree add failed")

        // Dirty the satellite worktree only.
        try "x".write(to: wt.appendingPathComponent("only-wt.txt"), atomically: true, encoding: .utf8)

        let family = [
            WorktreeDiffMember(rootURL: repo, title: "main-tree", branch: "main", isActive: true),
            WorktreeDiffMember(rootURL: wt, title: "feat-tree", branch: "feat-diff", isActive: false),
        ]
        let model = DiffModel(rootURL: repo, family: family)
        defer { model.teardown() }
        for _ in 0 ..< 80 where model.summaries.count < 2 || model.isLoading {
            try await Task.sleep(nanoseconds: 25_000_000)
        }

        XCTAssertTrue(model.showsFamilyOverview)
        XCTAssertEqual(model.summaries.count, 2)
        let mainSummary = model.summaries.first { $0.rootURL == repo.standardizedFileURL }
        let wtSummary = model.summaries.first { $0.rootURL == wt.standardizedFileURL }
        XCTAssertEqual(mainSummary?.fileCount, 0)
        XCTAssertGreaterThanOrEqual(wtSummary?.fileCount ?? 0, 1)

        model.focus(rootURL: wt)
        for _ in 0 ..< 40 where model.isLoading {
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        XCTAssertEqual(model.focusedRootURL, wt.standardizedFileURL)
        XCTAssertFalse(model.modifiedFiles.isEmpty)
    }

    func testWorktreeFamilyMembersFromStore() {
        let store = WorkspaceStore(
            persistence: InMemoryPersistence(),
            engineFactory: { TestEngine() },
            optionsProvider: { _ in nil },
            resumeProvider: { true }
        )
        let source = store.addWorkspace(workingDirectory: URL(fileURLWithPath: "/tmp/proj-main"))
        let wt = store.addWorkspace(
            workingDirectory: URL(fileURLWithPath: "/tmp/proj-feat"),
            worktreeParent: source,
            worktreeBranch: "feat-x"
        )
        let family = store.worktreeFamilyMembers(for: wt)
        XCTAssertEqual(family.count, 2)
        XCTAssertTrue(family.contains { $0.branch == "feat-x" && $0.isActive })
        XCTAssertTrue(family.contains { $0.rootURL.path == source.diskPath.path && !$0.isActive })
    }
}
