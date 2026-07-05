@testable import ArcherKit
import XCTest

@MainActor
final class SkillSourceTests: XCTestCase {
    // MARK: - Path conventions per source

    func testSkillsShResultDefaultsToMonorepoConvention() {
        let result = SkillsView.SkillsShResult(
            id: "react-best-practices", name: "vercel-react-best-practices",
            source: "vercel-labs/agent-skills", installs: 1
        )
        XCTAssertEqual(result.resolvedRepoPath, "skills/react-best-practices")
        XCTAssertEqual(result.installDirName, "react-best-practices")
    }

    func testExplicitRepoPathOverridesConventionAndDrivesDirName() {
        let result = SkillsView.SkillsShResult(
            id: "marketing-pro-workflow/seo-optimizer", name: "seo-optimizer",
            source: "nicepkg/ai-workflow", installs: 0,
            repoPath: "workflows/marketing-pro-workflow/.claude/skills/seo-optimizer",
            groupLabel: "marketing-pro"
        )
        XCTAssertEqual(result.resolvedRepoPath, "workflows/marketing-pro-workflow/.claude/skills/seo-optimizer")
        XCTAssertEqual(result.installDirName, "seo-optimizer")
    }

    func testDetailURLPerSource() {
        let shResult = SkillsView.SkillsShResult(
            id: "find-skills", name: "find-skills", source: "vercel-labs/skills", installs: 1
        )
        XCTAssertEqual(
            SkillsView.SkillSourceId.skillsSh.detailURL(for: shResult)?.absoluteString,
            "https://www.skills.sh/vercel-labs/skills/find-skills"
        )
        let awResult = SkillsView.SkillsShResult(
            id: "content-creator-workflow/canvas-design", name: "canvas-design",
            source: "nicepkg/ai-workflow", installs: 0,
            repoPath: "workflows/content-creator-workflow/.claude/skills/canvas-design",
            groupLabel: "content-creator"
        )
        XCTAssertEqual(
            SkillsView.SkillSourceId.aiWorkflow.detailURL(for: awResult)?.absoluteString,
            "https://github.com/nicepkg/ai-workflow/tree/main/workflows/content-creator-workflow/.claude/skills/canvas-design"
        )
    }

    // MARK: - Trees API parsing

    private func treesFixture(paths: [String]) -> Data {
        let tree = paths.map { ["path": $0, "type": "blob"] }
        return try! JSONSerialization.data(withJSONObject: ["sha": "abc", "tree": tree, "truncated": false])
    }

    func testParseExtractsOnlyExactDepthSkills() {
        let data = treesFixture(paths: [
            // included: exact depth
            "workflows/marketing-pro-workflow/.claude/skills/seo-optimizer/SKILL.md",
            "workflows/stock-trader-workflow/.claude/skills/backtest-expert/SKILL.md",
            // excluded: repo's own meta skills at top level
            ".claude/skills/skill-creator/SKILL.md",
            // excluded: sub-skill nested inside a skill's assets
            "workflows/stock-trader-workflow/.claude/skills/weekly-trade-strategy/.claude/skills/inner/SKILL.md",
            "workflows/marketing-pro-workflow/.claude/skills/legacy/assets/helper/SKILL.md",
            // excluded: non-SKILL.md files at matching depth
            "workflows/marketing-pro-workflow/.claude/skills/seo-optimizer/README.md",
        ])
        let results = SkillsView.parseAIWorkflowTree(data)
        XCTAssertEqual(results.map(\.name), ["seo-optimizer", "backtest-expert"])
        XCTAssertEqual(results[0].groupLabel, "marketing-pro")
        XCTAssertEqual(results[0].repoPath, "workflows/marketing-pro-workflow/.claude/skills/seo-optimizer")
        XCTAssertEqual(results[0].source, "nicepkg/ai-workflow")
        XCTAssertEqual(results[0].installs, 0)
    }

    func testParseSortsByGroupThenName() {
        let data = treesFixture(paths: [
            "workflows/video-creator-workflow/.claude/skills/zzz/SKILL.md",
            "workflows/content-creator-workflow/.claude/skills/beta/SKILL.md",
            "workflows/content-creator-workflow/.claude/skills/alpha/SKILL.md",
        ])
        let results = SkillsView.parseAIWorkflowTree(data)
        XCTAssertEqual(results.map(\.name), ["alpha", "beta", "zzz"])
    }

    func testParseIdsAreUniqueAcrossWorkflowsForDuplicateNames() {
        let data = treesFixture(paths: [
            "workflows/marketing-pro-workflow/.claude/skills/canvas-design/SKILL.md",
            "workflows/content-creator-workflow/.claude/skills/canvas-design/SKILL.md",
        ])
        let results = SkillsView.parseAIWorkflowTree(data)
        XCTAssertEqual(Set(results.map(\.id)).count, 2)
        XCTAssertEqual(Set(results.map(\.installDirName)), ["canvas-design"])
    }

    func testParseToleratesMalformedPayload() throws {
        XCTAssertEqual(SkillsView.parseAIWorkflowTree(Data("not json".utf8)), [])
        let noTree = try JSONSerialization.data(withJSONObject: ["sha": "abc"])
        XCTAssertEqual(SkillsView.parseAIWorkflowTree(noTree), [])
    }
}

extension SkillsView.SkillsShResult: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id && lhs.repoPath == rhs.repoPath
    }
}
