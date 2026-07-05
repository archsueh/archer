@testable import ArcherKit
import XCTest

@MainActor
final class OpenTabInNewWorktreeTests: XCTestCase {
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
            .appendingPathComponent("archer-wt-tab-\(UUID().uuidString)")
        tempRoots.append(url)
        return url
    }

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

    private func makeStore() -> WorkspaceStore {
        WorkspaceStore(
            persistence: InMemoryPersistence(),
            engineFactory: { TestEngine() },
            optionsProvider: { _ in nil },
            resumeProvider: { true }
        )
    }

    func testCreatesWorktreeChildWorkspaceWithAgentTemplate() async {
        let repo = tempDir()
        XCTAssertTrue(makeRepo(at: repo))
        let store = makeStore()
        let source = store.addWorkspace(workingDirectory: repo)
        let countBefore = store.workspaces.count

        guard let template = AgentTemplate.all.first(where: { $0.id != AgentTemplate.terminal.id }) else {
            return XCTFail("no agent template available")
        }
        let error = await store.openTabInNewWorktree(source: source, template: template)

        XCTAssertNil(error)
        XCTAssertEqual(store.workspaces.count, countBefore + 1)
        guard let child = store.workspaces.first(where: { $0.worktreeParentId == source.id }) else {
            return XCTFail("expected a child workspace grouped under the source")
        }
        tempRoots.append(child.workingDirectory)
        XCTAssertNotNil(child.worktreePath)
        XCTAssertEqual(child.worktreeBranch?.hasPrefix("archer/\(template.id)-"), true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: child.workingDirectory.path))
        // The worktree is real, not just a directory: git registered its
        // branch. Branch identity sidesteps /var vs /private/var symlink
        // normalization differences between git output and temp-dir URLs.
        guard case let .success(worktrees) = WorktreeManager.list(repoPath: repo) else {
            return XCTFail("git worktree list failed")
        }
        XCTAssertTrue(worktrees.contains { $0.branch == child.worktreeBranch })
    }

    func testNonGitDirectoryReturnsErrorAndAddsNothing() async {
        let dir = tempDir()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = makeStore()
        let source = store.addWorkspace(workingDirectory: dir)
        let countBefore = store.workspaces.count

        guard let template = AgentTemplate.all.first(where: { $0.id != AgentTemplate.terminal.id }) else {
            return XCTFail("no agent template available")
        }
        let error = await store.openTabInNewWorktree(source: source, template: template)

        XCTAssertEqual(error, "not inside a git repository")
        XCTAssertEqual(store.workspaces.count, countBefore)
    }

    func testRepeatedClicksForSameAgentDoNotCollide() async {
        let repo = tempDir()
        XCTAssertTrue(makeRepo(at: repo))
        let store = makeStore()
        let source = store.addWorkspace(workingDirectory: repo)

        guard let template = AgentTemplate.all.first(where: { $0.id != AgentTemplate.terminal.id }) else {
            return XCTFail("no agent template available")
        }
        let first = await store.openTabInNewWorktree(source: source, template: template)
        let second = await store.openTabInNewWorktree(source: source, template: template)

        XCTAssertNil(first)
        XCTAssertNil(second)
        let children = store.workspaces.filter { $0.worktreeParentId == source.id }
        for child in children {
            tempRoots.append(child.workingDirectory)
        }
        XCTAssertEqual(children.count, 2)
        XCTAssertEqual(Set(children.compactMap(\.worktreeBranch)).count, 2)
        XCTAssertEqual(Set(children.map(\.workingDirectory.path)).count, 2)
    }
}
