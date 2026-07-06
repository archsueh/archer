@testable import ArcherKit
import XCTest

final class GeminiParserTests: XCTestCase {
    private var tempRoots: [URL] = []

    override func tearDown() {
        for url in tempRoots {
            try? FileManager.default.removeItem(at: url)
        }
        tempRoots.removeAll()
        super.tearDown()
    }

    /// Mirrors agentsview's testdata/gemini/standard_session.json — the
    /// authoritative shape for stock gemini-cli session files.
    private func standardSession() -> Data {
        let session: [String: Any] = [
            "sessionId": "sess-uuid-1",
            "projectHash": "abc123def456",
            "startTime": "2024-01-01T10:00:00Z",
            "lastUpdated": "2024-01-01T10:05:05Z",
            "messages": [
                ["id": "u1", "type": "user", "timestamp": "2024-01-01T10:00:00Z", "content": "Fix the login bug"],
                [
                    "id": "a1", "type": "gemini", "timestamp": "2024-01-01T10:00:05Z",
                    "model": "gemini-2.5-pro",
                    "content": "Looking at the auth module...",
                    "tokens": ["input": 1500, "output": 200, "cached": 100, "thoughts": 50, "tool": 0, "total": 1850],
                ],
                ["id": "u2", "type": "user", "timestamp": "2024-01-01T10:05:00Z", "content": "That looks right"],
                [
                    "id": "a2", "type": "gemini", "timestamp": "2024-01-01T10:05:05Z",
                    "content": "Applied the fix.",
                    "tokens": ["input": 2000, "output": 300, "cached": 50, "thoughts": 100, "tool": 0, "total": 2450],
                ],
            ],
        ]
        return try! JSONSerialization.data(withJSONObject: session)
    }

    func testParseSessionExtractsGeminiTurnsOnly() {
        let records = GeminiParser.parseSession(standardSession(), sourcePath: "/x/session-1.json")
        XCTAssertEqual(records.count, 2)

        let first = records[0]
        XCTAssertEqual(first.tool, "Gemini")
        XCTAssertEqual(first.source, .nativeGemini)
        XCTAssertEqual(first.sessionID, "sess-uuid-1")
        XCTAssertEqual(first.model, "gemini-2.5-pro")
        XCTAssertEqual(first.usage.inputTokens, 1500)
        // thoughts bill at the output rate → folded into output
        XCTAssertEqual(first.usage.outputTokens, 250)
        XCTAssertEqual(first.usage.cacheReadInputTokens, 100)
        XCTAssertEqual(first.usage.reasoningOutputTokens, 50)
        XCTAssertEqual(first.usage.totalTokens, 1850)
        XCTAssertEqual(first.date, "2024-01-01")

        // second gemini turn has no model field → normalized key
        XCTAssertEqual(records[1].usage.totalTokens, 2450)
    }

    func testParseSessionToleratesMalformedInput() throws {
        XCTAssertEqual(GeminiParser.parseSession(Data("not json".utf8)).count, 0)
        let noMessages = try JSONSerialization.data(withJSONObject: ["sessionId": "s"])
        XCTAssertEqual(GeminiParser.parseSession(noMessages).count, 0)
        let zeroTokens = try JSONSerialization.data(withJSONObject: [
            "sessionId": "s",
            "messages": [["type": "gemini", "timestamp": "2024-01-01T10:00:00Z",
                          "tokens": ["input": 0, "output": 0]]],
        ])
        XCTAssertEqual(GeminiParser.parseSession(zeroTokens).count, 0)
    }

    func testCollectWalksTmpHashChatsLayout() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("archer-gemini-\(UUID().uuidString)")
        tempRoots.append(home)
        let chats = home.appendingPathComponent(".gemini/tmp/abc123/chats")
        try FileManager.default.createDirectory(at: chats, withIntermediateDirectories: true)
        try standardSession().write(to: chats.appendingPathComponent("session-2024-01-01.json"))
        // Decoys that must not be picked up.
        try Data("{}".utf8).write(to: chats.appendingPathComponent("notes.json"))
        let antigravity = home.appendingPathComponent(".gemini/antigravity-cli")
        try FileManager.default.createDirectory(at: antigravity, withIntermediateDirectories: true)

        var cache = CollectorCache()
        var livePaths = Set<String>()
        let result = GeminiParser.collect(
            cache: &cache, livePaths: &livePaths, homeURL: home, modifiedSince: nil
        )

        XCTAssertEqual(result.source.status, "ok")
        XCTAssertEqual(result.records.count, 2)
        XCTAssertEqual(livePaths.count, 1)
    }

    func testCollectWithoutGeminiDirReportsMissing() {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("archer-gemini-\(UUID().uuidString)")
        tempRoots.append(home)
        var cache = CollectorCache()
        var livePaths = Set<String>()
        let result = GeminiParser.collect(
            cache: &cache, livePaths: &livePaths, homeURL: home, modifiedSince: nil
        )
        XCTAssertEqual(result.source.status, "missing")
        XCTAssertTrue(result.records.isEmpty)
    }
}
