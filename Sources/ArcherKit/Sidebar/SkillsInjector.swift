// [archer] SkillsInjector.swift
//
// Reverse-injection: takes the skills Archer already discovered on this
// machine and copies them into the skill folders of *external* agent
// harnesses (Claude Code, Codex, ...) — the inverse of what SkillsView
// normally does (discover/install/manage).
//
// This is intentionally a **pure local file operation**: it only uses
// `FileManager` to copy directories on disk. There are no network calls
// and no new dependencies, so it can never reach out to a remote host.

import Foundation

/// Copies Archer-discovered skill directories into each agent harness's
/// `skills/` folder so other tools (Claude Code, Codex, ...) can use them.
struct SkillsInjector {
    /// [archer] Source skill directories on disk. Each entry is the *parent
    /// directory* of a `SKILL.md` (i.e. the skill's own folder), exactly as
    /// surfaced by `SkillsView.SkillItem.canonicalDirPath`.
    let sourceSkillDirs: [URL]

    /// [archer] Target harness skill directories we inject into. All paths are
    /// derived from `NSHomeDirectory()` — the username is never hardcoded.
    ///
    /// - Claude Code: ~/.claude/skills
    ///     Long-standing, well-established path for Claude Code skills.
    /// - Codex CLI:   ~/.codex/skills
    ///     OpenAI Codex CLI keeps its config under ~/.codex. This repo's own
    ///     `SkillsView.agentDefs` already scans ~/.codex/skills, so we align
    ///     with that convention (rather than ~/.config/codex/skills) to avoid
    ///     scattering duplicate copies across two different locations.
    /// - Gemini CLI:  intentionally OMITTED.
    ///     Gemini CLI's skills directory convention is not firmly established;
    ///     writing to a guessed path could land in the wrong place, so we skip
    ///     it for now. Add an entry here once the canonical path is confirmed.
    static var candidateTargets: [URL] {
        let home = NSHomeDirectory()
        return [
            URL(fileURLWithPath: (home as NSString).appendingPathComponent(".claude/skills")),
            URL(fileURLWithPath: (home as NSString).appendingPathComponent(".codex/skills")),
        ]
    }

    /// Target directories that already exist on this machine. Informational —
    /// the UI uses this to preview where skills will land before injecting.
    var availableTargets: [URL] {
        let fm = FileManager.default
        return Self.candidateTargets.filter { url in
            var isDir: ObjCBool = false
            return fm.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
        }
    }

    /// Copies every source skill directory into every candidate harness
    /// skills directory. The target directory is created if it does not
    /// exist yet, and any previously injected copy is overwritten so the
    /// harness always sees the latest version.
    ///
    /// Throws on the first unrecoverable file error (e.g. permission denied).
    func installToAllHarnesses() throws {
        let fm = FileManager.default

        guard !sourceSkillDirs.isEmpty else {
            throw InjectorError.noSkills
        }

        for target in Self.candidateTargets {
            // Create the harness skills dir (and any parents) if missing.
            try fm.createDirectory(at: target, withIntermediateDirectories: true, attributes: nil)

            for source in sourceSkillDirs {
                // Resolve a top-level symlink so we copy the *real* contents
                // rather than a dangling link node.
                let resolvedSource = resolveIfSymlink(source, fm: fm)
                let skillName = resolvedSource.lastPathComponent
                let dest = target.appendingPathComponent(skillName)

                // [archer] Never copy a skill onto itself. Archer *discovers*
                // skills from these same harness dirs, so a source skill's
                // path can equal its injection destination — removing it first
                // would delete the original.
                guard resolvedSource.resolvingSymlinksInPath().path != dest.resolvingSymlinksInPath().path else {
                    continue
                }

                // Overwrite: drop an earlier injected copy before re-copying.
                if fm.fileExists(atPath: dest.path) {
                    try fm.removeItem(at: dest)
                }
                try fm.copyItem(at: resolvedSource, to: dest)
            }
        }
    }

    /// If `url` is a symlink, return the (resolved) real directory it points
    /// to; otherwise return `url` unchanged.
    private func resolveIfSymlink(_ url: URL, fm: FileManager) -> URL {
        guard let linkDest = try? fm.destinationOfSymbolicLink(atPath: url.path) else {
            return url
        }
        let realPath: String
        if (linkDest as NSString).isAbsolutePath {
            realPath = linkDest
        } else {
            realPath = url.deletingLastPathComponent().appendingPathComponent(linkDest).path
        }
        return URL(fileURLWithPath: realPath)
    }

    enum InjectorError: LocalizedError {
        case noSkills
        var errorDescription: String? {
            switch self {
            case .noSkills:
                return "没有可导出的已安装技能。"
            }
        }
    }
}
