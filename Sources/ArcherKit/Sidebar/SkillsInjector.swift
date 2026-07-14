// [archer] SkillsInjector.swift
//
// Bulk **symlink relay** of skills Archer already discovered into each agent
// harness's skills folder — the same mechanism as SkillsView.toggleAgent /
// one-click relay, not a second copy pipeline.
//
// Pure local FileManager. Never overwrites an existing owned install (real
// directory or unrelated symlink). Only fills missing agent endpoints.

import Foundation

/// Relays skill directories into harness skill folders via symlink (补缺).
struct SkillsInjector {
    /// One discovered skill: directory name + absolute path of the SKILL.md parent.
    struct SourceSkill: Equatable {
        let dirName: String
        let canonicalDir: URL
    }

    let sources: [SourceSkill]

    /// Convenience from raw directory URLs (last path component = skill name).
    init(sourceSkillDirs: [URL]) {
        sources = sourceSkillDirs.map {
            SourceSkill(dirName: $0.lastPathComponent, canonicalDir: $0)
        }
    }

    init(sources: [SourceSkill]) {
        self.sources = sources
    }

    // [archer] Test seam — when set, `candidateTargets` returns this instead of
    // the real home harness paths so unit tests never write under ~/.
    // nonisolated(unsafe): test-only mutable override, never used from concurrent
    // production paths.
    nonisolated(unsafe) static var candidateTargetsOverride: [(key: String, skillsDir: URL)]?

    /// [archer] Keep in sync with `SkillsView.agentDefs` subdirs. Duplicated here
    /// so this type stays nonisolated (SkillsView is a SwiftUI View / MainActor).
    private static let harnessSubdirs: [(key: String, subdir: String)] = [
        ("claude", ".claude/skills"),
        ("agents", ".agents/skills"),
        ("codex", ".codex/skills"),
        ("gemini", ".gemini/skills"),
        ("hermes", ".hermes/skills"),
    ]

    /// [archer] Target harness skill roots. Derived from NSHomeDirectory();
    /// username is never hardcoded.
    static var candidateTargets: [(key: String, skillsDir: URL)] {
        if let candidateTargetsOverride { return candidateTargetsOverride }
        let home = NSHomeDirectory() as NSString
        return harnessSubdirs.map { key, subdir in
            (key: key, skillsDir: URL(fileURLWithPath: home.appendingPathComponent(subdir)))
        }
    }

    /// Targets whose parent config root already exists (informational preview).
    var availableTargets: [URL] {
        let fm = FileManager.default
        return Self.candidateTargets.compactMap { _, skillsDir in
            let parent = skillsDir.deletingLastPathComponent()
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: parent.path, isDirectory: &isDir), isDir.boolValue else {
                return nil
            }
            return skillsDir
        }
    }

    struct RelayResult: Equatable {
        var linked: Int = 0
        var skippedExisting: Int = 0
        var skippedSelf: Int = 0
    }

    /// Symlink each source skill into every harness skills dir **when missing**.
    /// Existing real installs and foreign symlinks are left alone.
    @discardableResult
    func installToAllHarnesses(fileManager fm: FileManager = .default) throws -> RelayResult {
        guard !sources.isEmpty else { throw InjectorError.noSkills }

        var result = RelayResult()

        for (_, skillsDir) in Self.candidateTargets {
            try fm.createDirectory(at: skillsDir, withIntermediateDirectories: true, attributes: nil)

            let skillsDirResolved = skillsDir.resolvingSymlinksInPath()

            for source in sources {
                let resolvedSource = resolveIfSymlink(source.canonicalDir, fm: fm)
                    .resolvingSymlinksInPath()
                let dest = skillsDir.appendingPathComponent(source.dirName)

                // Source already lives inside this harness skills dir — skip.
                if resolvedSource.deletingLastPathComponent().path == skillsDirResolved.path {
                    result.skippedSelf += 1
                    continue
                }

                if fm.fileExists(atPath: dest.path) {
                    // Already present (owned copy or prior symlink) — do not clobber.
                    result.skippedExisting += 1
                    continue
                }

                try fm.createSymbolicLink(at: dest, withDestinationURL: resolvedSource)
                result.linked += 1
            }
        }
        return result
    }

    private func resolveIfSymlink(_ url: URL, fm: FileManager) -> URL {
        guard let linkDest = try? fm.destinationOfSymbolicLink(atPath: url.path) else {
            return url
        }
        if (linkDest as NSString).isAbsolutePath {
            return URL(fileURLWithPath: linkDest)
        }
        return url.deletingLastPathComponent().appendingPathComponent(linkDest)
    }

    enum InjectorError: LocalizedError, Equatable {
        case noSkills
        var errorDescription: String? {
            switch self {
            case .noSkills:
                return "没有可中继的已安装技能。"
            }
        }
    }
}
