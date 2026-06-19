@testable import ArcherKit
import XCTest

final class FileTreeModelTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("archer-filetree-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    @discardableResult
    private func makeFile(_ rel: String, _ contents: String = "x") throws -> URL {
        let url = root.appendingPathComponent(rel)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data(contents.utf8).write(to: url)
        return url
    }

    @discardableResult
    private func makeDir(_ rel: String) throws -> URL {
        let url = root.appendingPathComponent(rel)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // US-1: drag a file onto a folder → physically moved into it.
    func testMoveFileIntoFolder() throws {
        let model = FileTreeModel(rootURL: root)
        let x = try makeFile("A/x.txt")
        let b = try makeDir("B")
        let moved = try model.move(x, into: b)
        XCTAssertEqual(moved, b.appendingPathComponent("x.txt"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: moved.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: x.path))
    }

    // Acceptance: dest already has same name → rename "x 2.txt", don't overwrite.
    func testMoveCollisionRenames() throws {
        let model = FileTreeModel(rootURL: root)
        let x = try makeFile("A/x.txt", "from-A")
        try makeFile("B/x.txt", "existing-B")
        let b = root.appendingPathComponent("B")
        let moved = try model.move(x, into: b)
        XCTAssertEqual(moved.lastPathComponent, "x 2.txt")
        XCTAssertEqual(try String(contentsOf: moved, encoding: .utf8), "from-A")
        XCTAssertEqual(
            try String(contentsOf: b.appendingPathComponent("x.txt"), encoding: .utf8),
            "existing-B"
        )
    }

    /// Tree order: directories first, then files, each localized-standard sorted.
    func testChildrenSortsDirsFirstThenName() throws {
        try makeFile("root.txt")
        try makeFile("apple.txt")
        try makeDir("Zebra")
        try makeDir("alpha")
        let model = FileTreeModel(rootURL: root)
        let names = model.children(of: root).map { $0.url.lastPathComponent }
        XCTAssertEqual(names, ["alpha", "Zebra", "apple.txt", "root.txt"])
    }

    /// Dropping onto the folder it already lives in is a no-op (no rename).
    func testMoveIntoSameDirectoryIsNoop() throws {
        let model = FileTreeModel(rootURL: root)
        let x = try makeFile("A/x.txt")
        let a = root.appendingPathComponent("A")
        let moved = try model.move(x, into: a)
        XCTAssertEqual(moved, x)
        XCTAssertTrue(FileManager.default.fileExists(atPath: x.path))
    }

    /// Folders move as a unit, contents intact.
    func testMoveDirectoryIntoFolder() throws {
        let model = FileTreeModel(rootURL: root)
        try makeFile("A/sub/y.txt")
        let sub = root.appendingPathComponent("A/sub")
        let b = try makeDir("B")
        let moved = try model.move(sub, into: b)
        // Compare by .path — appendingPathComponent stats the now-existing dir
        // and appends a trailing slash, which the model's pre-move URL lacks.
        XCTAssertEqual(moved.path, b.appendingPathComponent("sub").path)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: moved.appendingPathComponent("y.txt").path)
        )
    }
}
