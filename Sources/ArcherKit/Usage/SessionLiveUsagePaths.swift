import Foundation

// [archer] Resolve the on-disk log path that feeds session live cost for a
// given tool + session key. Pure helpers — used by SessionLiveUsageMonitor
// and tests. Prefer exact filename matches over content scans.

/// Locates the file to watch for live session cost updates. // [archer]
enum SessionLiveUsagePaths {
    /// Primary path to watch for this tool/session. Nil when the log does not
    /// exist yet (caller should retry). // [archer]
    static func resolve(
        tool: String,
        sessionID: String,
        cwd: URL,
        homeURL: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL? {
        let trimmed = sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        switch tool {
        case "Claude Code":
            return resolveClaude(sessionID: trimmed, homeURL: homeURL)
        case "Grok":
            return resolveGrok(homeURL: homeURL)
        case "Codex":
            return resolveCodex(sessionID: trimmed, cwd: cwd, homeURL: homeURL)
        case "Gemini":
            return resolveGemini(sessionID: trimmed, homeURL: homeURL)
        default:
            return nil
        }
    }

    // MARK: - Claude: `~/.claude/projects/**/<sessionId>.jsonl`

    /// Claude Code names the transcript file after the session UUID. // [archer]
    static func resolveClaude(
        sessionID: String,
        homeURL: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL? {
        let root = homeURL.appendingPathComponent(".claude/projects", isDirectory: true)
        let targetName = "\(sessionID).jsonl"
        guard FileManager.default.fileExists(atPath: root.path),
              let enumerator = FileManager.default.enumerator(
                  at: root,
                  includingPropertiesForKeys: [.isRegularFileKey],
                  options: [.skipsHiddenFiles]
              )
        else { return nil }

        for case let url as URL in enumerator {
            if url.lastPathComponent == targetName {
                return url
            }
        }
        return nil
    }

    // MARK: - Grok: single unified log

    static func resolveGrok(
        homeURL: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL? {
        let path = homeURL.appendingPathComponent(".grok/logs/unified.jsonl")
        guard FileManager.default.isReadableFile(atPath: path.path) else { return nil }
        return path
    }

    // MARK: - Codex: active rollout for cwd (same identity as session key)

    /// Watch the cwd-matched rollout. The pill's `sessionID` for Codex is
    /// almost always derived from this same file, so a cwd match is enough;
    /// when meta id is present and disagrees, skip (another run). // [archer]
    static func resolveCodex(
        sessionID: String,
        cwd: URL,
        homeURL: URL = FileManager.default.homeDirectoryForCurrentUser,
        sessionsRoot: URL? = nil
    ) -> URL? {
        let root = sessionsRoot ?? homeURL
            .appendingPathComponent(".codex/sessions", isDirectory: true)
        guard let url = CodexUsageMonitor.resolveRollout(forCwd: cwd, sessionsRoot: root)
        else { return nil }
        if let metaId = CodexUsageMonitor.sessionMetaId(atPath: url.path),
           metaId != sessionID,
           !sessionID.hasPrefix("rollout-")
        {
            // Meta has a real UUID that doesn't match — not our session.
            // Basename-style session keys (rollout-…) still accept the match.
            return nil
        }
        return url
    }

    // MARK: - Gemini: `~/.gemini/tmp/**/chats/session-*.json`

    static func resolveGemini(
        sessionID: String,
        homeURL: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL? {
        let tmpRoot = homeURL.appendingPathComponent(".gemini/tmp", isDirectory: true)
        let fm = FileManager.default
        guard let hashDirs = try? fm.contentsOfDirectory(
            at: tmpRoot, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return nil }

        for hashDir in hashDirs {
            let chats = hashDir.appendingPathComponent("chats", isDirectory: true)
            guard let files = try? fm.contentsOfDirectory(
                at: chats, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
            ) else { continue }
            for file in files where file.pathExtension == "json" {
                // Filename often embeds the id; otherwise peek sessionId field.
                if file.lastPathComponent.contains(sessionID) {
                    return file
                }
                if let data = try? Data(contentsOf: file),
                   let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let sid = obj["sessionId"] as? String,
                   sid == sessionID
                {
                    return file
                }
            }
        }
        return nil
    }
}
