@testable import ArcherKit
import XCTest

@MainActor
final class FanboxClassifierTests: XCTestCase {
    func testClassifierSuggestions() {
        let baseDir = URL(fileURLWithPath: "/tmp/test-base")

        let swiftURL = URL(fileURLWithPath: "/tmp/file.swift")
        let swiftResult = Classifier.suggestMove(for: swiftURL, baseDir: baseDir)
        XCTAssertNotNil(swiftResult)
        XCTAssertEqual(swiftResult?.destination.path, baseDir.appendingPathComponent("Sources/file.swift").path)
        XCTAssertEqual(swiftResult?.rule?.folder, "Sources")

        let pngURL = URL(fileURLWithPath: "/tmp/image.png")
        let pngResult = Classifier.suggestMove(for: pngURL, baseDir: baseDir)
        XCTAssertNotNil(pngResult)
        XCTAssertEqual(pngResult?.destination.path, baseDir.appendingPathComponent("Assets/image.png").path)
        XCTAssertEqual(pngResult?.rule?.folder, "Assets")

        let mdURL = URL(fileURLWithPath: "/tmp/doc.md")
        let mdResult = Classifier.suggestMove(for: mdURL, baseDir: baseDir)
        XCTAssertNotNil(mdResult)
        XCTAssertEqual(mdResult?.destination.path, baseDir.appendingPathComponent("Docs/doc.md").path)
        XCTAssertEqual(mdResult?.rule?.folder, "Docs")

        let jsonURL = URL(fileURLWithPath: "/tmp/config.json")
        let jsonResult = Classifier.suggestMove(for: jsonURL, baseDir: baseDir)
        XCTAssertNotNil(jsonResult)
        XCTAssertEqual(jsonResult?.destination.path, baseDir.appendingPathComponent("Config/config.json").path)
        XCTAssertEqual(jsonResult?.rule?.folder, "Config")

        // Non-matching extension
        let unknownURL = URL(fileURLWithPath: "/tmp/file.xyz")
        let unknownResult = Classifier.suggestMove(for: unknownURL, baseDir: baseDir)
        XCTAssertNil(unknownResult)
    }

    func testDownloaderFallbackBehavior() async throws {
        let fileManager = FileManager.default
        let testDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("archer-downloader-test-\(UUID().uuidString)")

        defer {
            try? fileManager.removeItem(at: testDir)
        }

        // Try downloading an invalid/non-existent post. It should trigger the fallback path,
        // write a placeholder file, run it through the Classifier (ext: .txt -> no rule, stays in placeholder folder or gets classified if a rule matches)
        // Wait, does .txt match any classifier rule?
        // Let's check: Classifier built-in rules do not contain .txt, so it should stay in the fanbox/<postId>/ folder.
        let results = try await Downloader.download(postIds: ["999999999"], to: testDir)

        XCTAssertEqual(results.count, 1)
        let post = results[0]
        XCTAssertEqual(post.id, "999999999")
        XCTAssertEqual(post.files.count, 1)

        let expectedFile = testDir.appendingPathComponent("fanbox/999999999/999999999.txt")
        XCTAssertEqual(post.files.first?.path, expectedFile.path)
        XCTAssertTrue(fileManager.fileExists(atPath: expectedFile.path))

        let content = try String(contentsOf: expectedFile, encoding: .utf8)
        XCTAssertTrue(content.contains("placeholder: 999999999"))
    }

    /// [archer] begin: ClassificationReviewManager tests
    func testClassificationReviewManagerQueuing() {
        let reviewManager = ClassificationReviewManager.shared
        reviewManager.declineAll() // Clean state

        let sourceURL = URL(fileURLWithPath: "/tmp/test-review-queue.swift")
        let destURL = URL(fileURLWithPath: "/tmp/dest-review-queue.swift")
        let rule = ClassifyRule(extension: "swift", folder: "Sources", priority: 1)

        reviewManager.addPendingMove(source: sourceURL, destination: destURL, rule: rule)
        XCTAssertEqual(reviewManager.pendingMoves.count, 1)
        XCTAssertEqual(reviewManager.pendingMoves.first?.source, sourceURL)
        XCTAssertEqual(reviewManager.pendingMoves.first?.destination, destURL)

        // Test duplicate prevention
        reviewManager.addPendingMove(source: sourceURL, destination: destURL, rule: rule)
        XCTAssertEqual(reviewManager.pendingMoves.count, 1)

        reviewManager.declineAll()
        XCTAssertEqual(reviewManager.pendingMoves.count, 0)
    }

    func testClassificationReviewManagerApproveDecline() throws {
        let reviewManager = ClassificationReviewManager.shared
        reviewManager.declineAll()

        let fm = FileManager.default
        let testDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("review-manager-test-\(UUID().uuidString)")
        try fm.createDirectory(at: testDir, withIntermediateDirectories: true)

        defer {
            try? fm.removeItem(at: testDir)
        }

        let sourceFile = testDir.appendingPathComponent("file.swift")
        try "print(\"hello\")".write(to: sourceFile, atomically: true, encoding: .utf8)

        let destFile = testDir.appendingPathComponent("Sources/file.swift")
        let rule = ClassifyRule(extension: "swift", folder: "Sources", priority: 1)

        reviewManager.addPendingMove(source: sourceFile, destination: destFile, rule: rule)
        XCTAssertEqual(reviewManager.pendingMoves.count, 1)

        let move = try XCTUnwrap(reviewManager.pendingMoves.first)

        // Test decline
        reviewManager.decline(move)
        XCTAssertEqual(reviewManager.pendingMoves.count, 0)
        XCTAssertTrue(fm.fileExists(atPath: sourceFile.path))
        XCTAssertFalse(fm.fileExists(atPath: destFile.path))

        // Re-add and test approve
        reviewManager.addPendingMove(source: sourceFile, destination: destFile, rule: rule)
        XCTAssertEqual(reviewManager.pendingMoves.count, 1)

        let moveForApprove = try XCTUnwrap(reviewManager.pendingMoves.first)
        var callbackCalled = false

        reviewManager.approve(moveForApprove) {
            callbackCalled = true
        }

        XCTAssertTrue(callbackCalled)
        XCTAssertEqual(reviewManager.pendingMoves.count, 0)
        XCTAssertFalse(fm.fileExists(atPath: sourceFile.path))
        XCTAssertTrue(fm.fileExists(atPath: destFile.path))
    }

    func testClassificationReviewManagerBulkActions() throws {
        let reviewManager = ClassificationReviewManager.shared
        reviewManager.declineAll()

        let fm = FileManager.default
        let testDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("review-manager-bulk-test-\(UUID().uuidString)")
        try fm.createDirectory(at: testDir, withIntermediateDirectories: true)

        defer {
            try? fm.removeItem(at: testDir)
        }

        let source1 = testDir.appendingPathComponent("file1.swift")
        try "1".write(to: source1, atomically: true, encoding: .utf8)
        let dest1 = testDir.appendingPathComponent("Sources/file1.swift")

        let source2 = testDir.appendingPathComponent("file2.png")
        try "2".write(to: source2, atomically: true, encoding: .utf8)
        let dest2 = testDir.appendingPathComponent("Assets/file2.png")

        let rule1 = ClassifyRule(extension: "swift", folder: "Sources", priority: 1)
        let rule2 = ClassifyRule(extension: "png", folder: "Assets", priority: 1)

        reviewManager.addPendingMove(source: source1, destination: dest1, rule: rule1)
        reviewManager.addPendingMove(source: source2, destination: dest2, rule: rule2)
        XCTAssertEqual(reviewManager.pendingMoves.count, 2)

        var callbackCalled = false
        reviewManager.approveAll {
            callbackCalled = true
        }

        XCTAssertTrue(callbackCalled)
        XCTAssertEqual(reviewManager.pendingMoves.count, 0)
        XCTAssertTrue(fm.fileExists(atPath: dest1.path))
        XCTAssertTrue(fm.fileExists(atPath: dest2.path))
    }
    // [archer] end: ClassificationReviewManager tests
}
