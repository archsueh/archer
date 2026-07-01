@testable import ArcherKit
import XCTest

final class UsageCollectorTests: XCTestCase {
    func testCollectGrokParsesInferenceDoneFromUnifiedLog() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("archer-grok-usage-\(UUID().uuidString)", isDirectory: true)
        let logsDir = root.appendingPathComponent(".grok/logs", isDirectory: true)
        try FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)

        let unified = logsDir.appendingPathComponent("unified.jsonl")
        let line = """
        {"ts":"2026-07-01T09:14:47.830Z","src":"shell","sid":"sess-a","msg":"shell.turn.inference_done","ctx":{"loop_index":1,"prompt_tokens":1000,"cached_prompt_tokens":800,"completion_tokens":50,"reasoning_tokens":5}}
        """
        try line.write(to: unified, atomically: true, encoding: .utf8)

        let sessionsRoot = root.appendingPathComponent(".grok/sessions/proj/sess-a", isDirectory: true)
        try FileManager.default.createDirectory(at: sessionsRoot, withIntermediateDirectories: true)
        let summary = """
        {"info":{"id":"sess-a"},"current_model_id":"grok-composer-2.5-fast"}
        """
        try summary.write(
            to: sessionsRoot.appendingPathComponent("summary.json"),
            atomically: true,
            encoding: .utf8
        )

        let result = UsageCollector.collectGrokForTesting(
            homeURL: root,
            modifiedSince: nil
        )

        XCTAssertEqual(result.source.status, "ok")
        XCTAssertEqual(result.records.count, 1)
        let record = try XCTUnwrap(result.records.first)
        XCTAssertEqual(record.tool, "Grok")
        XCTAssertEqual(record.date, "2026-07-01")
        XCTAssertEqual(record.model, "grok-composer-2.5-fast")
        XCTAssertEqual(record.usage.inputTokens, 200)
        XCTAssertEqual(record.usage.cacheReadInputTokens, 800)
        XCTAssertEqual(record.usage.outputTokens, 50)
        XCTAssertEqual(record.usage.reasoningOutputTokens, 5)
        XCTAssertEqual(record.usage.totalTokens, 1055)
        XCTAssertEqual(record.sessionID, "sess-a")
        XCTAssertEqual(record.source, .nativeGrok)
    }

    func testCollectGrokSkipsDuplicateInferenceEvents() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("archer-grok-dedupe-\(UUID().uuidString)", isDirectory: true)
        let logsDir = root.appendingPathComponent(".grok/logs", isDirectory: true)
        try FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)

        let unified = logsDir.appendingPathComponent("unified.jsonl")
        let line = """
        {"ts":"2026-07-01T09:14:47.830Z","src":"shell","sid":"sess-b","msg":"shell.turn.inference_done","ctx":{"loop_index":2,"prompt_tokens":100,"cached_prompt_tokens":0,"completion_tokens":10,"reasoning_tokens":0}}
        {"ts":"2026-07-01T09:14:47.830Z","src":"shell","sid":"sess-b","msg":"shell.turn.inference_done","ctx":{"loop_index":2,"prompt_tokens":100,"cached_prompt_tokens":0,"completion_tokens":10,"reasoning_tokens":0}}
        """
        try line.write(to: unified, atomically: true, encoding: .utf8)

        let result = UsageCollector.collectGrokForTesting(
            homeURL: root,
            modifiedSince: nil
        )

        XCTAssertEqual(result.records.count, 1)
    }

    func testGrokRecordsPublicAPIReturnsParsedRows() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("archer-grok-api-\(UUID().uuidString)", isDirectory: true)
        let logsDir = root.appendingPathComponent(".grok/logs", isDirectory: true)
        try FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)

        let unified = logsDir.appendingPathComponent("unified.jsonl")
        let line = """
        {"ts":"2026-07-01T10:00:00.000Z","src":"shell","sid":"sess-c","msg":"shell.turn.inference_done","ctx":{"loop_index":1,"prompt_tokens":42,"cached_prompt_tokens":0,"completion_tokens":7,"reasoning_tokens":0}}
        """
        try line.write(to: unified, atomically: true, encoding: .utf8)

        let records = UsageCollector.grokRecords(homeURL: root, modifiedSince: nil)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.tool, "Grok")
    }
}
