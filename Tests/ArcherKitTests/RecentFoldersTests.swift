@testable import ArcherKit
import Foundation
import XCTest

/// [archer] Ported assertion shape from iAmCorey/kooky RecentFoldersTests
/// (v0.35, issue #28). Verifies LRU ordering, dedup, cap, HOME exclusion,
/// and JSON persistence round-trip. Runs on the main actor because
/// `RecentFolders` is @MainActor-isolated.
@MainActor
final class RecentFoldersTests: XCTestCase {
    private var scratch: URL!

    override func setUp() {
        super.setUp()
        scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("archer-recent-\(UUID().uuidString).json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: scratch)
        super.tearDown()
    }

    private func note(_ folders: RecentFolders, _ paths: [String]) {
        for p in paths {
            folders.note(URL(fileURLWithPath: p))
        }
    }

    func testLRUOrder() {
        let f = RecentFolders(fileURL: scratch)
        note(f, ["/a", "/b", "/c"])
        XCTAssertEqual(f.paths, ["/c", "/b", "/a"])
    }

    func testReNoteMovesToFront() {
        let f = RecentFolders(fileURL: scratch)
        note(f, ["/a", "/b", "/c"])
        f.note(URL(fileURLWithPath: "/a"))
        XCTAssertEqual(f.paths, ["/a", "/c", "/b"])
    }

    func testDedupKeepsSingle() {
        let f = RecentFolders(fileURL: scratch)
        note(f, ["/a", "/a", "/a"])
        XCTAssertEqual(f.paths, ["/a"])
    }

    func testCap() {
        let f = RecentFolders(fileURL: scratch)
        let many = (1 ... 40).map { "/p\($0)" }
        note(f, many)
        XCTAssertEqual(f.paths.count, RecentFolders.cap)
        // Most-recent-first: the last noted (/p40) sits at index 0.
        XCTAssertEqual(f.paths.first, "/p40")
        XCTAssertEqual(f.paths.last, "/p21")
    }

    func testHomeExcluded() {
        let f = RecentFolders(fileURL: scratch)
        f.note(URL(fileURLWithPath: NSHomeDirectory()))
        XCTAssertTrue(f.paths.isEmpty)
    }

    func testExistingFiltersMissing() {
        let f = RecentFolders(fileURL: scratch)
        // /tmp always exists; a bogus path does not.
        note(f, ["/tmp", "/nonexistent-archer-path-\(UUID().uuidString)"])
        let existing = f.existing
        XCTAssertEqual(existing.count, 1)
        XCTAssertEqual(existing.first?.path, "/tmp")
    }

    func testPersistenceRoundTrip() {
        let f = RecentFolders(fileURL: scratch)
        note(f, ["/a", "/b", "/c"])
        // A fresh instance reading the same file should see the same order.
        let g = RecentFolders(fileURL: scratch)
        XCTAssertEqual(g.paths, ["/c", "/b", "/a"])
    }

    func testClear() {
        let f = RecentFolders(fileURL: scratch)
        note(f, ["/a", "/b"])
        f.clear()
        XCTAssertTrue(f.paths.isEmpty)
        // Clear persists — a reload shows empty too.
        let g = RecentFolders(fileURL: scratch)
        XCTAssertTrue(g.paths.isEmpty)
    }
}
