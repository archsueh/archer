import XCTest
@testable import ArcherKit

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
}
