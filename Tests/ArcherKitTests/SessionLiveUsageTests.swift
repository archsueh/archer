@testable import ArcherKit
import XCTest

final class SessionLiveUsageTests: XCTestCase {
    // MARK: - fold

    func testFoldEmptyReturnsNil() {
        XCTAssertNil(SessionLiveUsageAggregator.fold([], pricing: .empty))
    }

    func testFoldSingleRecordWithReportedCost() throws {
        let usage = TokenUsageCounts(
            inputTokens: 1000,
            outputTokens: 500,
            cacheCreationInputTokens: 0,
            cacheReadInputTokens: 0,
            reasoningOutputTokens: 0,
            totalTokens: 1500
        )
        let record = UsageRecord(
            date: "2026-07-09",
            tool: "Claude Code",
            model: "claude-sonnet-5",
            usage: usage,
            costUSD: 0.0123,
            sessionID: "sess-1"
        )
        let live = try XCTUnwrap(SessionLiveUsageAggregator.fold([record], pricing: .empty))
        XCTAssertEqual(live.tokens, 1500)
        XCTAssertEqual(live.costUSD, 0.0123, accuracy: 1e-9)
        XCTAssertEqual(live.estimated, false)
        XCTAssertEqual(live.model, "claude-sonnet-5")
        XCTAssertEqual(live.inputTokens, 1000)
        XCTAssertEqual(live.outputTokens, 500)
    }

    func testFoldEstimatesViaPricingProviderWhenCostMissing() throws {
        let usage = TokenUsageCounts(
            inputTokens: 1_000_000,
            outputTokens: 0,
            cacheCreationInputTokens: 0,
            cacheReadInputTokens: 0,
            reasoningOutputTokens: 0,
            totalTokens: 1_000_000
        )
        let record = UsageRecord(
            date: "2026-07-09",
            tool: "Claude Code",
            model: "claude-sonnet-5",
            usage: usage,
            costUSD: nil,
            sessionID: "sess-2"
        )
        // Sonnet snapshot: $3 / 1M input → $3.00 for 1M input tokens.
        let live = try XCTUnwrap(SessionLiveUsageAggregator.fold([record], pricing: .empty))
        XCTAssertEqual(live.tokens, 1_000_000)
        XCTAssertEqual(live.costUSD, 3.0, accuracy: 1e-6)
        XCTAssertEqual(live.estimated, true)
    }

    func testFoldSumsMultipleRecords() throws {
        let u1 = TokenUsageCounts(inputTokens: 100, outputTokens: 50, totalTokens: 150)
        let u2 = TokenUsageCounts(inputTokens: 200, outputTokens: 50, totalTokens: 250)
        let records = [
            UsageRecord(date: "2026-07-09", tool: "Claude Code", model: "claude-sonnet-5",
                        usage: u1, costUSD: 0.01, sessionID: "s"),
            UsageRecord(date: "2026-07-09", tool: "Claude Code", model: "claude-opus-4-1",
                        usage: u2, costUSD: 0.02, sessionID: "s"),
        ]
        let live = try XCTUnwrap(SessionLiveUsageAggregator.fold(records, pricing: .empty))
        XCTAssertEqual(live.tokens, 400)
        XCTAssertEqual(live.costUSD, 0.03, accuracy: 1e-9)
        XCTAssertEqual(live.estimated, false)
        XCTAssertEqual(live.model, "claude-opus-4-1")
    }

    func testFoldZeroTokensAndZeroCostReturnsNil() {
        let usage = TokenUsageCounts()
        let record = UsageRecord(
            date: "2026-07-09",
            tool: "Claude Code",
            model: "claude-sonnet-5",
            usage: usage,
            costUSD: 0,
            sessionID: "empty"
        )
        XCTAssertNil(SessionLiveUsageAggregator.fold([record], pricing: .empty))
    }

    // MARK: - formatters

    func testCostTextFormats() {
        XCTAssertEqual(SessionLiveUsageAggregator.costText(0), "$0.00")
        XCTAssertEqual(SessionLiveUsageAggregator.costText(0.0042), "$0.0042")
        XCTAssertEqual(SessionLiveUsageAggregator.costText(0.42), "$0.42")
        XCTAssertEqual(SessionLiveUsageAggregator.costText(12.34), "$12.3")
        XCTAssertEqual(SessionLiveUsageAggregator.costText(150), "$150")
    }

    func testTokensTextFormats() {
        XCTAssertEqual(SessionLiveUsageAggregator.tokensText(842), "842")
        XCTAssertEqual(SessionLiveUsageAggregator.tokensText(1500), "1.5k")
        XCTAssertEqual(SessionLiveUsageAggregator.tokensText(128_400), "128k")
        XCTAssertEqual(SessionLiveUsageAggregator.tokensText(1_200_000), "1.2M")
    }

    // MARK: - estimateCost parity with PricingProvider

    func testEstimateCostMatchesPricingProviderForSonnet() throws {
        let usage = TokenUsageCounts(
            inputTokens: 100_000,
            outputTokens: 10000,
            cacheCreationInputTokens: 0,
            cacheReadInputTokens: 0,
            reasoningOutputTokens: 0,
            totalTokens: 110_000
        )
        let price = try XCTUnwrap(PricingProvider.familyPrice(tool: "Claude Code", model: "claude-sonnet-5"))
        let viaProvider = PricingProvider.cost(usage: usage, price: price)
        let viaAgg = SessionLiveUsageAggregator.estimateCost(
            usage: usage,
            tool: "Claude Code",
            model: "claude-sonnet-5",
            pricing: .empty
        )
        XCTAssertEqual(viaAgg, viaProvider, accuracy: 1e-12)
    }

    // MARK: - P1b agent → tool mapping

    func testToolLabelMapsSupportedAgents() {
        XCTAssertEqual(SessionLiveUsageSource.toolLabel(for: .claudeCode), "Claude Code")
        XCTAssertEqual(SessionLiveUsageSource.toolLabel(for: .grok), "Grok")
        XCTAssertEqual(SessionLiveUsageSource.toolLabel(for: .codex), "Codex")
        XCTAssertEqual(SessionLiveUsageSource.toolLabel(for: .gemini), "Gemini")
        XCTAssertNil(SessionLiveUsageSource.toolLabel(for: .terminal))
        XCTAssertNil(SessionLiveUsageSource.toolLabel(for: .pi))
    }

    func testResolveSessionKeyPrefersConversationId() {
        let key = SessionCostPill.resolveSessionKey(
            tool: "Grok",
            conversationId: "  grok-sess-1  ",
            cwd: URL(fileURLWithPath: "/tmp")
        )
        XCTAssertEqual(key, "grok-sess-1")
    }

    func testResolveSessionKeyNilWithoutIdForNonCodex() {
        XCTAssertNil(
            SessionCostPill.resolveSessionKey(
                tool: "Claude Code",
                conversationId: nil,
                cwd: URL(fileURLWithPath: "/tmp")
            )
        )
    }

    func testCodexSessionMetaIdReadsPayloadId() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("archer-codex-meta-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("rollout-test.jsonl")
        let line = #"{"type":"session_meta","payload":{"id":"sess-codex-42","cwd":"/Users/me/p"}}"# + "\n"
        try line.write(to: file, atomically: true, encoding: .utf8)
        XCTAssertEqual(CodexUsageMonitor.sessionMetaId(atPath: file.path), "sess-codex-42")
        XCTAssertEqual(CodexUsageMonitor.sessionMetaCwd(atPath: file.path), "/Users/me/p")
    }

    // MARK: - P1c path resolution

    func testResolveClaudePathByFilename() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("archer-live-paths-\(UUID().uuidString)", isDirectory: true)
        let project = home.appendingPathComponent(".claude/projects/-Users-me", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let sessionID = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
        let file = project.appendingPathComponent("\(sessionID).jsonl")
        try " {}\n".write(to: file, atomically: true, encoding: .utf8)

        let resolved = SessionLiveUsagePaths.resolveClaude(sessionID: sessionID, homeURL: home)
        XCTAssertEqual(
            resolved?.resolvingSymlinksInPath().path,
            file.resolvingSymlinksInPath().path
        )
        XCTAssertNil(SessionLiveUsagePaths.resolveClaude(sessionID: "missing-id", homeURL: home))
    }

    func testResolveGrokUnifiedLog() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("archer-grok-paths-\(UUID().uuidString)", isDirectory: true)
        let logs = home.appendingPathComponent(".grok/logs", isDirectory: true)
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let file = logs.appendingPathComponent("unified.jsonl")
        try "{}\n".write(to: file, atomically: true, encoding: .utf8)

        XCTAssertEqual(
            SessionLiveUsagePaths.resolveGrok(homeURL: home)?.resolvingSymlinksInPath().path,
            file.resolvingSymlinksInPath().path
        )
    }

    func testResolveGeminiBySessionIdField() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("archer-gemini-paths-\(UUID().uuidString)", isDirectory: true)
        let chats = home
            .appendingPathComponent(".gemini/tmp/abc123/chats", isDirectory: true)
        try FileManager.default.createDirectory(at: chats, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let sessionID = "gemini-sess-99"
        let file = chats.appendingPathComponent("session-other.json")
        let json = #"{"sessionId":"\#(sessionID)","messages":[]}"#
        try json.write(to: file, atomically: true, encoding: .utf8)

        let resolved = SessionLiveUsagePaths.resolveGemini(sessionID: sessionID, homeURL: home)
        XCTAssertEqual(
            resolved?.resolvingSymlinksInPath().path,
            file.resolvingSymlinksInPath().path
        )
    }
}
