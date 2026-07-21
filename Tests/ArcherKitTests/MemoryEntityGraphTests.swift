// MemoryEntityGraphTests.swift
// Offline, no LLM. Uses temp-dir .md fixtures.
@testable import ArcherKit
import XCTest

final class MemoryEntityGraphTests: XCTestCase {
    private var dir: URL!

    override func setUp() {
        super.setUp()
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mementity-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    private func write(_ name: String, _ body: String, tags: [String] = [], links: [String] = []) {
        var text = body
        if !tags.isEmpty { text += "\n\n" + tags.map { "#\($0)" }.joined(separator: " ") }
        if !links.isEmpty { text += "\n\n" + links.map { "[[\($0)]]" }.joined(separator: " ") }
        try! text.write(to: dir.appendingPathComponent("\(name).md"), atomically: true, encoding: .utf8)
    }

    private func build(threshold: Double = 0.1) -> MemoryEntityGraph {
        MemoryEntityGraph(graph: MemoryGraph(directory: dir), similarThreshold: threshold)
    }

    func testEntitySetContainsMemoAndTagNodes() {
        write("Alpha", "Alpha body about apples and oranges.", tags: ["fruit"], links: ["Beta"])
        write("Beta", "Beta body about bananas.")
        let g = build()
        XCTAssertNotNil(g.entities["Alpha"])
        XCTAssertNotNil(g.entities["Beta"])
        XCTAssertEqual(g.entities["Alpha"]?.kind, .memo)
        XCTAssertNotNil(g.entities[MemoryEntityGraph.tagEntityID("fruit")])
        XCTAssertEqual(g.entities[MemoryEntityGraph.tagEntityID("fruit")]?.kind, .tag)
    }

    func testLinksToEdgeBuilt() {
        write("Alpha", "Alpha body.", tags: [], links: ["Beta"])
        write("Beta", "Beta body.")
        let g = build()
        let outgoing = g.neighbors(of: "Alpha")
        XCTAssertTrue(outgoing.contains { $0.kind == .linksTo && $0.to == "Beta" && $0.weight == 1.0 })
    }

    func testSharesTagEdgeAndTagDegree() {
        write("Alpha", "Alpha body.", tags: ["fruit"], links: [])
        write("Beta", "Beta body.", tags: ["fruit"], links: [])
        let g = build()
        let fruitID = MemoryEntityGraph.tagEntityID("fruit")
        // tag node has two incoming sharesTag edges (from Alpha and Beta).
        XCTAssertEqual(g.entities[fruitID]?.degree, 2)
        // Alpha -> fruit edge exists.
        XCTAssertTrue(g.neighbors(of: "Alpha").contains { $0.kind == .sharesTag && $0.to == fruitID })
    }

    func testSimilarEdgeGatedByThreshold() {
        // Two memos with strong body overlap (Jaccard ≈ 1.0).
        let body = "apple orange banana fruit tree garden plant grow green leaf"
        write("One", body)
        write("Two", body)
        let gLoose = build(threshold: 0.1)
        XCTAssertTrue(gLoose.neighbors(of: "One").contains { $0.kind == .similar })
        // Even a high threshold (0.5) is below 1.0 overlap, so the edge stays.
        let gStrict = build(threshold: 0.5)
        XCTAssertTrue(gStrict.neighbors(of: "One").contains { $0.kind == .similar })
        // A threshold above 1.0 can never be met, so no similar edge is added.
        let gImpossible = build(threshold: 1.5)
        XCTAssertFalse(gImpossible.neighbors(of: "One").contains { $0.kind == .similar })
    }

    func testRankedEntitiesAndRelations() {
        write("Alpha", "Alpha body.", tags: ["fruit", "tool"], links: ["Beta"])
        write("Beta", "Beta body.")
        let g = build()
        let ranked = g.rankedEntities()
        XCTAssertFalse(ranked.isEmpty)
        // Alpha has a linksTo + 2 sharesTag = degree 3; it should rank high.
        XCTAssertEqual(ranked.first?.id, "Alpha")
        let rels = g.relations(minWeight: 1.0)
        XCTAssertFalse(rels.isEmpty)
        XCTAssertTrue(rels.allSatisfy { $0.weight >= 1.0 })
    }

    func testUnknownEntityNeighborsSafe() {
        write("Alpha", "Alpha body.")
        let g = build()
        XCTAssertTrue(g.neighbors(of: "does-not-exist").isEmpty)
    }
}
