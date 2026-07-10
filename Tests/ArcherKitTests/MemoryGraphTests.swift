// MemoryGraphTests.swift
// Verifies the A-mem style local link graph (parse, backlink resolution,
// centrality ranking, tag clusters, orphans, link suggestions).

@testable import ArcherKit
import XCTest

final class MemoryGraphTests: XCTestCase {
    private var dir: URL!

    override func setUp() {
        super.setUp()
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("archer-memorygraph-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    private func write(_ name: String, _ body: String) {
        let url = dir.appendingPathComponent("\(name).md")
        try? body.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Parse

    func testParseExtractsTagsAndLinks() {
        let (tags, links) = MemoryGraph.parse("# A note\nbody with #swift and #agentic-memory linking [[Other Note]] and [[Yet/Another|alias]].")
        XCTAssertEqual(tags, ["swift", "agentic-memory"])
        XCTAssertEqual(links, ["Other Note", "Yet/Another"]) // alias stripped
    }

    func testParseIgnoresInlineCodeFences() {
        let (tags, links) = MemoryGraph.parse("use `#tag` and `[[NotALink]]` literally")
        XCTAssertTrue(tags.isEmpty)
        XCTAssertTrue(links.isEmpty)
    }

    // MARK: - Backlinks + centrality

    func testBacklinksAndRanking() throws {
        // hub is referenced by two notes -> highest degree.
        write("Hub", "# Hub\n#hub\nreferences [[Leaf One]] and [[Leaf Two]]")
        write("Leaf One", "# Leaf One\nlinks back to [[Hub]]")
        write("Leaf Two", "# Leaf Two\nlinks back to [[Hub]]")

        var g = MemoryGraph(directory: dir)
        XCTAssertEqual(g.nodes.count, 3)

        let hub = try XCTUnwrap(g.nodes["Hub"])
        XCTAssertEqual(hub.links, ["Leaf One", "Leaf Two"])
        // Leaves link back to Hub, so Hub has backlinks too.
        XCTAssertEqual(hub.backlinks, ["Leaf One", "Leaf Two"])
        XCTAssertEqual(hub.degree, 4) // out(2) + in(2)

        XCTAssertEqual(g.nodes["Leaf One"]?.backlinks, ["Hub"])
        XCTAssertEqual(g.nodes["Leaf Two"]?.backlinks, ["Hub"])

        // Hub has degree 4, leaves have degree 2 -> hub ranks first.
        XCTAssertEqual(g.ranked.first?.title, "Hub")
    }

    // MARK: - Tag clusters

    func testTagClusters() {
        write("Alpha", "# Alpha\n#shared #unique-a")
        write("Beta", "# Beta\n#shared #unique-b")
        var g = MemoryGraph(directory: dir)

        let clusters = g.tagClusters
        let shared = clusters.first { $0.tag == "shared" }
        XCTAssertEqual(shared?.nodes.map(\.title).sorted(), ["Alpha", "Beta"])
    }

    // MARK: - Orphans

    func testOrphans() {
        write("Connected", "# Connected\nsee [[Other]]")
        write("Other", "# Other\n#tag")
        write("Lone", "# Lone\nno connections here")
        var g = MemoryGraph(directory: dir)

        XCTAssertEqual(g.orphans.map(\.title), ["Lone"])
    }

    // MARK: - Link suggestions (token overlap)

    func testSuggestedLinks() {
        write("Swift Memory", "# Swift Memory\n#swift\ntopics about swift memory management and caching")
        write("Memory Cache", "# Memory Cache\n#cache\ndiscusses memory caching and swift performance")
        write("Unrelated", "# Unrelated\n#music\njazz guitar chords and improvisation techniques")
        var g = MemoryGraph(directory: dir)

        let suggestions = g.suggestedLinks(for: "Swift Memory")
        // "Memory Cache" should be suggested; "Unrelated" should not.
        XCTAssertTrue(suggestions.contains("Memory Cache"))
        XCTAssertFalse(suggestions.contains("Unrelated"))
    }

    func testRebuildAfterDiskChange() {
        write("A", "# A\n[[B]]")
        write("B", "# B\n")
        var g = MemoryGraph(directory: dir)
        // A has out(1)+in(0); B has out(0)+in(1) -> equal degree, tie broken by title "A" < "B".
        XCTAssertEqual(g.ranked.first?.title, "A")

        // Add a new note linking to A; rebuild should see the new edge.
        write("C", "# C\n[[A]]")
        g.build()
        XCTAssertEqual(g.nodes["A"]?.backlinks, ["C"])
    }
}
