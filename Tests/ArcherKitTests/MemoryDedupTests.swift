// MemoryDedupTests.swift
@testable import ArcherKit
import XCTest

final class MemoryDedupTests: XCTestCase {
    private var dir: URL!

    override func setUp() {
        super.setUp()
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("memdedup-\(UUID().uuidString)")
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

    private func build() -> MemoryGraph {
        MemoryGraph(directory: dir)
    }

    /// 1. Exact title match -> discard.
    func testTitleConflictDiscards() {
        write("Meeting Notes", "Discussed roadmap and milestones for the quarter.")
        let d = MemoryDedup(graph: build())
        let matches = d.check(MemoCandidate(title: "meeting notes",
                                            tags: [], links: [], body: "Completely different content here about something else entirely."))
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches[0].verdict, .discard)
        XCTAssertEqual(matches[0].score, 1.0)
    }

    /// 2. Identical tag + link signature -> merge.
    func testTagLinkSignatureMerges() {
        write("Alpha", "Alpha body text about project planning.", tags: ["project", "q3"], links: ["Beta"])
        let d = MemoryDedup(graph: build())
        let matches = d.check(MemoCandidate(
            title: "Alpha Copy",
            tags: ["project", "q3"],
            links: ["Beta"],
            body: "Totally different body wording that shares no vocabulary with alpha at all."
        ))
        XCTAssertTrue(matches.contains { $0.verdict == .merge && $0.reason == "标签与链接完全一致" })
    }

    /// 3. High body similarity -> merge.
    func testHighBodySimilarityMerges() throws {
        let body = "The quarterly roadmap meeting discussed milestones deliverables and the overall plan for the team this quarter."
        write("Roadmap", body)
        let d = MemoryDedup(graph: build())
        let matches = d.check(MemoCandidate(
            title: "Roadmap Draft", tags: [], links: [],
            body: "The quarterly roadmap meeting discussed milestones deliverables and the overall plan for the team this quarter."
        ))
        XCTAssertTrue(matches.contains { $0.verdict == .merge && $0.reason == "正文高度相似" })
        let hit = try XCTUnwrap(matches.first { $0.reason == "正文高度相似" })
        XCTAssertGreaterThanOrEqual(hit.score, 0.85)
    }

    /// 4. Partial body similarity -> keep + warning (no discard).
    func testPartialBodySimilarityKeepsWithWarning() {
        write("Plan", "The quarterly roadmap meeting discussed milestones deliverables and the overall plan for the team this quarter.")
        let d = MemoryDedup(graph: build())
        let matches = d.check(MemoCandidate(
            title: "Plan Fragment", tags: [], links: [],
            body: "The quarterly roadmap meeting discussed milestones deliverables and the overall plan for the banana fruit salad recipe ingredients list."
        ))
        XCTAssertFalse(matches.contains { $0.verdict == .discard })
    }

    /// 5. Completely different -> empty.
    func testUnrelatedCandidateNoMatches() {
        write("Coffee", "A note about brewing espresso and coffee beans roasting process.")
        let d = MemoryDedup(graph: build())
        let matches = d.check(MemoCandidate(
            title: "Spaceship", tags: ["orbit"], links: ["Mars"],
            body: "Rocket propulsion and interplanetary travel to the red planet mars colony."
        ))
        XCTAssertTrue(matches.isEmpty)
    }
}
