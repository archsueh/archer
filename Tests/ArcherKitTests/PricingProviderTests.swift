@testable import ArcherKit
import XCTest

final class PricingProviderTests: XCTestCase {
    /// Sample usage exercising every token bucket.
    private let usage = TokenUsageCounts(
        inputTokens: 1_000_000,
        outputTokens: 500_000,
        cacheCreationInputTokens: 200_000,
        cacheReadInputTokens: 300_000,
        reasoningOutputTokens: 100_000,
        totalTokens: 2_100_000
    )

    // MARK: - Regression: offline snapshot reproduces the old inline numbers

    func testOpusSnapshotMatchesLegacyAnthropicFormula() throws {
        // Old estimateCost: costByParts(input:15, output:75, cacheCreation:18.75, cacheRead:1.5)
        let price = try XCTUnwrap(PricingProvider.familyPrice(tool: "Claude Code", model: "claude-opus-4-1"))
        let creation = 200_000.0, read = 300_000.0
        let rest = 1_000_000.0 - creation - read
        let expected = rest / 1e6 * 15 + creation / 1e6 * 18.75 + read / 1e6 * 1.5
            + (500_000.0 + 100_000.0) / 1e6 * 75
        XCTAssertEqual(PricingProvider.cost(usage: usage, price: price), expected, accuracy: 1e-9)
        XCTAssertEqual(price.style, .anthropic)
    }

    func testSonnetSnapshotRates() throws {
        let price = try XCTUnwrap(PricingProvider.familyPrice(tool: "Claude Code", model: "claude-sonnet-5"))
        XCTAssertEqual(price.input, 3)
        XCTAssertEqual(price.output, 15)
        XCTAssertEqual(price.cacheWrite, 3.75)
        XCTAssertEqual(price.cacheRead, 0.3)
    }

    func testGpt55SnapshotMatchesLegacyOpenAIFormula() throws {
        // Old estimateCost: openAICostByParts(input:5, cachedInput:0.5, output:30)
        let price = try XCTUnwrap(PricingProvider.familyPrice(tool: "Codex", model: "gpt-5.5"))
        let cached = 300_000.0
        let uncached = 1_000_000.0 - cached
        let expected = (uncached + 200_000.0) / 1e6 * 5 + cached / 1e6 * 0.5
            + (500_000.0 + 100_000.0) / 1e6 * 30
        XCTAssertEqual(PricingProvider.cost(usage: usage, price: price), expected, accuracy: 1e-9)
        XCTAssertEqual(price.style, .openai)
    }

    func testUnknownFamilyIsNilSoCallerFallsBackToFlatRate() {
        XCTAssertNil(PricingProvider.familyPrice(tool: "Grok", model: "grok-4"))
        XCTAssertNil(PricingProvider.resolve(tool: "Grok", model: "grok-4", in: .empty))
    }

    // MARK: - models.dev override precedence

    func testExactModelsDevMatchWinsOverSnapshot() {
        let live = ModelPrice(input: 99, output: 199, cacheWrite: 9, cacheRead: 1, style: .anthropic)
        let table = PricingTable(models: ["claude-opus-4-5": live], generatedAt: Date())
        // Exact id → live price, not the snapshot's opus 15/75.
        XCTAssertEqual(PricingProvider.resolve(tool: "Claude Code", model: "claude-opus-4-5", in: table), live)
    }

    func testSubstringMatchToleratesVersionSuffix() {
        let live = ModelPrice(input: 1.25, output: 2.5, cacheWrite: 1.25, cacheRead: 0.2, style: .anthropic)
        let table = PricingTable(models: ["grok-4.3": live], generatedAt: Date())
        XCTAssertEqual(PricingProvider.resolve(tool: "Grok", model: "grok-4.3-0309-reasoning", in: table), live)
    }

    func testSnapshotUsedWhenModelsDevMisses() {
        let table = PricingTable(models: ["some-other-model": ModelPrice(input: 1, output: 1, cacheWrite: 1, cacheRead: 1, style: .anthropic)], generatedAt: Date())
        let price = PricingProvider.resolve(tool: "Claude Code", model: "claude-opus-4-1", in: table)
        XCTAssertEqual(price?.input, 15)
    }

    // MARK: - models.dev parsing

    func testParseModelsDevMapsCostAndInfersStyleAndDefaults() throws {
        let json = """
        {
          "anthropic": { "models": {
            "claude-sonnet-5": { "cost": { "input": 3, "output": 15, "cache_read": 0.3, "cache_write": 3.75 } }
          }},
          "openai": { "models": {
            "o3": { "cost": { "input": 2, "output": 8, "cache_read": 0.5 } }
          }}
        }
        """.data(using: .utf8)!
        let map = try PricingProvider.parseModelsDev(json)

        let sonnet = try XCTUnwrap(map["claude-sonnet-5"])
        XCTAssertEqual(sonnet.style, .anthropic)
        XCTAssertEqual(sonnet.cacheWrite, 3.75)

        let o3 = try XCTUnwrap(map["o3"])
        XCTAssertEqual(o3.style, .openai)
        XCTAssertEqual(o3.cacheRead, 0.5)
        // Missing cache_write defaults to the input rate.
        XCTAssertEqual(o3.cacheWrite, 2)
    }
}
