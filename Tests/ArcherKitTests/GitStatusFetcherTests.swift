@testable import ArcherKit
import XCTest

final class GitStatusFetcherTests: XCTestCase {
    func testParseShortstatAllThree() {
        let (files, ins, del) = GitStatusFetcher.parseShortstat(
            " 3 files changed, 47 insertions(+), 12 deletions(-)"
        )
        XCTAssertEqual(files, 3)
        XCTAssertEqual(ins, 47)
        XCTAssertEqual(del, 12)
    }

    func testParseShortstatInsertionsOnly() {
        let (files, ins, del) = GitStatusFetcher.parseShortstat(
            " 1 file changed, 5 insertions(+)"
        )
        XCTAssertEqual(files, 1)
        XCTAssertEqual(ins, 5)
        XCTAssertEqual(del, 0)
    }

    func testParseShortstatDeletionsOnly() {
        let (files, ins, del) = GitStatusFetcher.parseShortstat(
            " 1 file changed, 3 deletions(-)"
        )
        XCTAssertEqual(files, 1)
        XCTAssertEqual(ins, 0)
        XCTAssertEqual(del, 3)
    }

    func testParseShortstatSingularNouns() {
        // git uses "1 file"/"1 insertion"/"1 deletion" (singular) when
        // count == 1 — prefix-match handles both forms.
        let (files, ins, del) = GitStatusFetcher.parseShortstat(
            " 1 file changed, 1 insertion(+), 1 deletion(-)"
        )
        XCTAssertEqual(files, 1)
        XCTAssertEqual(ins, 1)
        XCTAssertEqual(del, 1)
    }

    func testParseShortstatEmptyReturnsZeros() {
        let (files, ins, del) = GitStatusFetcher.parseShortstat("")
        XCTAssertEqual(files, 0)
        XCTAssertEqual(ins, 0)
        XCTAssertEqual(del, 0)
    }

    func testParseShortstatGarbageReturnsZeros() {
        let (files, ins, del) = GitStatusFetcher.parseShortstat("not a real shortstat output")
        XCTAssertEqual(files, 0)
        XCTAssertEqual(ins, 0)
        XCTAssertEqual(del, 0)
    }

    func testParseBranchesDropsBlanksAndDuplicates() {
        XCTAssertEqual(
            GitBranchInventory.parseBranches("main\n\nfeature/login\nmain\n"),
            ["main", "feature/login"]
        )
    }

    func testShellSwitchCommandQuotesBranchName() {
        XCTAssertEqual(
            GitBranchInventory.shellSwitchCommand(branch: "feature/needs review"),
            "git switch 'feature/needs review'\r"
        )
    }

    func testShellSwitchCommandEscapesSingleQuote() {
        XCTAssertEqual(
            GitBranchInventory.shellSwitchCommand(branch: "fix/corey's-branch"),
            "git switch 'fix/corey'\\''s-branch'\r"
        )
    }

    // MARK: - GitRemoteWebInfo (kooky v0.37.0 port)

    func testPreferredRemoteURLPrefersOrigin() {
        let listing = """
        upstream\tgit@example.com:other/repo.git (fetch)
        upstream\tgit@example.com:other/repo.git (push)
        origin\tgit@github.com:archsueh/archer.git (fetch)
        origin\tgit@github.com:archsueh/archer.git (push)
        """
        XCTAssertEqual(
            GitRemoteWebInfo.preferredRemoteURL(inRemoteListing: listing),
            "git@github.com:archsueh/archer.git"
        )
    }

    func testParseSCPRemoteURL() {
        let info = GitRemoteWebInfo.parse(remoteURL: "git@github.com:archsueh/archer.git")
        XCTAssertEqual(info?.webURL.absoluteString, "https://github.com/archsueh/archer")
        XCTAssertEqual(info?.forgeName, "GitHub")
    }

    func testParseHTTPSRemoteURL() {
        let info = GitRemoteWebInfo.parse(remoteURL: "https://gitlab.com/group/proj.git")
        XCTAssertEqual(info?.webURL.absoluteString, "https://gitlab.com/group/proj")
        XCTAssertEqual(info?.forgeName, "GitLab")
    }

    func testParseRejectsLocalPathRemote() {
        XCTAssertNil(GitRemoteWebInfo.parse(remoteURL: "/local/path/to/repo"))
        XCTAssertNil(GitRemoteWebInfo.parse(remoteURL: "file:///tmp/repo"))
    }
}
