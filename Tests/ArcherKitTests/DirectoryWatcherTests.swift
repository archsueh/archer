@testable import ArcherKit
import XCTest

@MainActor
final class DirectoryWatcherTests: XCTestCase {
    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("archer-watch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // US-2: an external file creation in a watched dir fires onChange for it.
    func testFiresOnExternalFileCreation() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let exp = expectation(description: "watcher fires on external change")
        let watcher = DirectoryWatcher { changed in
            if changed.standardizedFileURL == dir.standardizedFileURL { exp.fulfill() }
        }
        watcher.add(dir)
        defer { watcher.cancel() }

        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) {
            try? Data("x".utf8).write(to: dir.appendingPathComponent("new.txt"))
        }
        wait(for: [exp], timeout: 3.0)
    }

    /// After remove(), changes no longer fire.
    func testRemoveStopsFiring() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let exp = expectation(description: "no fire after remove")
        exp.isInverted = true
        let watcher = DirectoryWatcher { _ in exp.fulfill() }
        watcher.add(dir)
        watcher.remove(dir)
        defer { watcher.cancel() }

        try Data("x".utf8).write(to: dir.appendingPathComponent("new.txt"))
        wait(for: [exp], timeout: 1.0)
    }
}
