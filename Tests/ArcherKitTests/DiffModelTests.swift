@testable import ArcherKit
import XCTest

final class DiffModelTests: XCTestCase {
    func testDiffParserWithStandardDiff() {
        let rawDiff = """
        diff --git a/Sources/main.swift b/Sources/main.swift
        index 8e5fd20..69bbf1a 100644
        --- a/Sources/main.swift
        +++ b/Sources/main.swift
        @@ -10,3 +10,4 @@
         unchanged context line
        -deleted line
        +added line
         other context line
        """
        let lines = DiffParser.parse(rawDiff)

        XCTAssertEqual(lines.count, 9)
        XCTAssertEqual(lines[0].type, .header)
        XCTAssertEqual(lines[0].content, "diff --git a/Sources/main.swift b/Sources/main.swift")

        XCTAssertEqual(lines[4].type, .header) // @@ -10,3 +10,4 @@

        // Context line
        XCTAssertEqual(lines[5].type, .context)
        XCTAssertEqual(lines[5].content, " unchanged context line")
        XCTAssertEqual(lines[5].oldLineNum, 10)
        XCTAssertEqual(lines[5].newLineNum, 10)

        // Deleted line
        XCTAssertEqual(lines[6].type, .deleted)
        XCTAssertEqual(lines[6].content, "-deleted line")
        XCTAssertEqual(lines[6].oldLineNum, 11)
        XCTAssertNil(lines[6].newLineNum)

        // Added line
        XCTAssertEqual(lines[7].type, .added)
        XCTAssertEqual(lines[7].content, "+added line")
        XCTAssertNil(lines[7].oldLineNum)
        XCTAssertEqual(lines[7].newLineNum, 11)
    }

    func testDiffParserWithEmptyInput() {
        let lines = DiffParser.parse("")
        XCTAssertTrue(lines.isEmpty)
    }
}
