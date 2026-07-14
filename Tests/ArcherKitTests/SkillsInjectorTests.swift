@testable import ArcherKit
import XCTest

final class SkillsInjectorTests: XCTestCase {
    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("skills-injector-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        SkillsInjector.candidateTargetsOverride = nil
    }

    override func tearDownWithError() throws {
        SkillsInjector.candidateTargetsOverride = nil
        try? FileManager.default.removeItem(at: tempRoot)
    }

    func testRelayCreatesSymlinkAndSkipsExistingAndSelf() throws {
        let fm = FileManager.default
        let source = tempRoot.appendingPathComponent("owned/demo-skill", isDirectory: true)
        try fm.createDirectory(at: source, withIntermediateDirectories: true)
        try "# demo".write(to: source.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        let harnessA = tempRoot.appendingPathComponent("a/skills", isDirectory: true)
        let harnessB = tempRoot.appendingPathComponent("b/skills", isDirectory: true)
        SkillsInjector.candidateTargetsOverride = [
            (key: "a", skillsDir: harnessA),
            (key: "b", skillsDir: harnessB),
        ]

        let injector = SkillsInjector(sources: [
            .init(dirName: "demo-skill", canonicalDir: source),
        ])

        let first = try injector.installToAllHarnesses()
        XCTAssertEqual(first.linked, 2)
        XCTAssertEqual(first.skippedExisting, 0)
        XCTAssertEqual(first.skippedSelf, 0)

        let linkA = harnessA.appendingPathComponent("demo-skill")
        XCTAssertEqual(try fm.destinationOfSymbolicLink(atPath: linkA.path), source.path)

        // Second pass — both destinations exist → skip, never clobber.
        let second = try injector.installToAllHarnesses()
        XCTAssertEqual(second.linked, 0)
        XCTAssertEqual(second.skippedExisting, 2)

        // Skill that physically lives inside harness A → self-skip for A, link for B.
        let native = harnessA.appendingPathComponent("native-skill", isDirectory: true)
        try fm.createDirectory(at: native, withIntermediateDirectories: true)
        try "# native".write(to: native.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)

        let nativeInjector = SkillsInjector(sources: [
            .init(dirName: "native-skill", canonicalDir: native),
        ])
        let selfPass = try nativeInjector.installToAllHarnesses()
        XCTAssertEqual(selfPass.skippedSelf, 1) // harness A
        XCTAssertEqual(selfPass.linked, 1) // harness B
    }

    func testNoSkillsThrows() {
        let injector = SkillsInjector(sourceSkillDirs: [])
        XCTAssertThrowsError(try injector.installToAllHarnesses()) { error in
            XCTAssertEqual(error as? SkillsInjector.InjectorError, .noSkills)
        }
    }
}
