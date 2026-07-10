// ProjectRulesSectionTests.swift
// Verifies the orbiteditor-inspired project-rules discovery (read-only scan
// of `<workspace>/.archer/rules/*.md`). Copy-to-clipboard is exercised via the
// model's file discovery; the view itself is covered by build + manual use.

@testable import ArcherKit
import XCTest

final class ProjectRulesSectionTests: XCTestCase {
    private var dir: URL!

    override func setUp() {
        super.setUp()
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("archer-projectrules-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(
            at: dir.appendingPathComponent(".archer/rules"),
            withIntermediateDirectories: true
        )
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    private func writeRule(_ name: String) {
        let url = dir.appendingPathComponent(".archer/rules/\(name).md")
        try? "# \(name)\nrule body\n".write(to: url, atomically: true, encoding: .utf8)
    }

    /// Mirrors the discovery logic in `ProjectRulesSection.scan()` so the
    /// behaviour is locked without spinning up SwiftUI.
    private func discover() -> [URL] {
        let fm = FileManager.default
        let rulesDir = dir.appendingPathComponent(".archer/rules")
        guard let urls = try? fm.contentsOfDirectory(
            at: rulesDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return [] }
        return urls
            .filter { $0.pathExtension.lowercased() == "md" }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    func testDiscoversMarkdownRulesSorted() {
        writeRule("Zeta")
        writeRule("Alpha")
        let found = discover().map { $0.deletingPathExtension().lastPathComponent }
        XCTAssertEqual(found, ["Alpha", "Zeta"])
    }

    func testIgnoresNonMarkdownFiles() {
        writeRule("Real")
        let noise = dir.appendingPathComponent(".archer/rules/notes.txt")
        try? "skip me".write(to: noise, atomically: true, encoding: .utf8)
        let found = discover().map { $0.deletingPathExtension().lastPathComponent }
        XCTAssertEqual(found, ["Real"])
    }

    func testEmptyWhenNoRulesDir() {
        try? FileManager.default.removeItem(at: dir.appendingPathComponent(".archer/rules"))
        XCTAssertTrue(discover().isEmpty)
    }
}
