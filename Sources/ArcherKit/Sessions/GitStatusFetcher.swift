import Foundation

/// Snapshot of a working tree's git state for the pane footer.
/// `branch == nil` means "not in a repo" (or git unavailable / errored).
struct GitStatus: Equatable {
    var branch: String?
    /// Absolute worktree root (`rev-parse --show-toplevel`). Drives the
    /// status bar's repo pill. Nil inside a bare repo / `.git` dir.
    /// [archer] ported from iAmCorey/kooky (v0.37.0).
    var repoRoot: String?
    var filesChanged: Int
    var insertions: Int
    var deletions: Int

    static let empty = GitStatus(branch: nil, repoRoot: nil, filesChanged: 0, insertions: 0, deletions: 0)
}

/// Spawns `git` on a background queue to populate `Session.gitStatus`.
/// Refreshes are kicked from `WorkspaceStore` on (a) tab spawn, (b) cwd
/// change via OSC 7, and (c) command finished via OSC 133;D. No polling.
///
/// A monotonic per-session generation token drops stale results: if the user
/// `cd`s rapidly, several fetches may be in flight, but only the latest one's
/// result lands on the session.
@MainActor
final class GitStatusFetcher {
    private var generation: [UUID: Int] = [:]

    /// Schedules a fetch for `cwd`. `completion` fires on main with the
    /// freshest result; older in-flight results are silently dropped.
    func fetch(sessionId: UUID, cwd: URL, completion: @MainActor @escaping (GitStatus) -> Void) {
        let token = (generation[sessionId] ?? 0) + 1
        generation[sessionId] = token
        let path = cwd.path
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let result = Self.run(cwd: path)
            DispatchQueue.main.async {
                guard let self else { return }
                guard self.generation[sessionId] == token else { return }
                completion(result)
            }
        }
    }

    private nonisolated static func run(cwd: String) -> GitStatus {
        // One spawn answers both branch and repo root. Outside a healthy
        // worktree the combined form fails — fall back to branch-only.
        // [archer] ported from iAmCorey/kooky (v0.37.0).
        let head: String
        let repoRoot: String?
        if let combined = runGit([
            "-C", cwd, "--no-optional-locks", "rev-parse", "--abbrev-ref", "HEAD", "--show-toplevel",
        ]), let newline = combined.firstIndex(of: "\n") {
            head = String(combined[..<newline])
            repoRoot = String(combined[combined.index(after: newline)...])
        } else if let solo = runGit(["-C", cwd, "--no-optional-locks", "rev-parse", "--abbrev-ref", "HEAD"]) {
            head = solo
            repoRoot = nil
        } else {
            return .empty
        }
        let branch: String
        if head == "HEAD" {
            branch = runGit(["-C", cwd, "--no-optional-locks", "rev-parse", "--short", "HEAD"]) ?? "HEAD"
        } else {
            branch = head
        }
        let stat = runGit(["-C", cwd, "--no-optional-locks", "diff", "--shortstat", "HEAD"]) ?? ""
        let (files, ins, del) = parseShortstat(stat)
        return GitStatus(branch: branch, repoRoot: repoRoot, filesChanged: files, insertions: ins, deletions: del)
    }

    /// Runs `git <args>` with a 1-second timeout; returns trimmed stdout on
    /// exit 0, nil otherwise. Uses `/usr/bin/env` so the spawned subprocess
    /// resolves git via PATH (covers Apple's /usr/bin/git stub + Homebrew).
    nonisolated static func runGit(_ args: [String], timeout: TimeInterval = 1.0) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        task.arguments = ["git"] + args
        task.environment = ["PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"]
        let stdout = Pipe()
        task.standardOutput = stdout
        task.standardError = Pipe()

        let semaphore = DispatchSemaphore(value: 0)
        task.terminationHandler = { _ in semaphore.signal() }

        do {
            try task.run()
        } catch {
            return nil
        }

        if semaphore.wait(timeout: .now() + timeout) == .timedOut {
            task.terminate()
            _ = semaphore.wait(timeout: .now() + 0.1)
            return nil
        }
        guard task.terminationStatus == 0 else { return nil }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        // Trim only newlines — porcelain `-z` entries start with a space status
        // code (` M path`); stripping leading whitespace eats the first path char.
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .newlines)
    }

    /// Parses `git diff --shortstat` lines like
    /// ` 3 files changed, 47 insertions(+), 12 deletions(-)`.
    /// Returns `(0, 0, 0)` for empty / unparseable input — all fields drop.
    nonisolated static func parseShortstat(_ s: String) -> (files: Int, insertions: Int, deletions: Int) {
        var files = 0
        var ins = 0
        var del = 0
        for token in s.split(separator: ",") {
            let trimmed = token.trimmingCharacters(in: .whitespaces)
            let parts = trimmed.split(separator: " ", maxSplits: 1)
            guard parts.count == 2, let n = Int(parts[0]) else { continue }
            let label = parts[1]
            if label.hasPrefix("file") {
                files = n
            } else if label.hasPrefix("insertion") {
                ins = n
            } else if label.hasPrefix("deletion") {
                del = n
            }
        }
        return (files, ins, del)
    }
}

enum GitBranchInventory {
    static func localBranches(cwd: URL) -> [String] {
        let output = GitStatusFetcher.runGit([
            "-C", cwd.path,
            "--no-optional-locks",
            "for-each-ref",
            "--sort=-committerdate",
            "--format=%(refname:short)",
            "refs/heads",
        ]) ?? ""
        return parseBranches(output)
    }

    static func shellSwitchCommand(branch: String) -> String {
        "git switch \(ArcherShellIntegration.quote(branch))\r"
    }

    static func parseBranches(_ output: String) -> [String] {
        var seen = Set<String>()
        return output
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { seen.insert($0).inserted }
    }
}

// MARK: - Porcelain file status (shared by Diff panel + file-tree badges)

/// Parses `git status --porcelain -z` into absolute file URLs + M/A/D status.
/// Shared so DiffModel and FileTreeModel never drift on path/status rules.
enum GitPorcelain {
    /// Live fetch for a working tree root. Returns empty when not a repo.
    nonisolated static func modifiedFiles(cwd: String) -> [ModifiedFile] {
        guard let output = GitStatusFetcher.runGit([
            "-C", cwd,
            "--no-optional-locks",
            "status",
            "--porcelain",
            "-z",
        ]) else {
            return []
        }
        return parse(output, cwd: cwd)
    }

    /// URL → status map for O(1) row badge lookup.
    nonisolated static func statusByURL(cwd: String) -> [URL: GitFileStatus] {
        var map: [URL: GitFileStatus] = [:]
        for file in modifiedFiles(cwd: cwd) {
            map[file.url] = file.status
        }
        return map
    }

    /// Pure parse of porcelain `-z` output. Testable without spawning git.
    ///
    /// Each entry is `XY path` (path may include spaces). For rename/copy in
    /// `-z` mode git emits `R  <new>\0<old>\0` — the bare `<old>` token has no
    /// `XY ` prefix and must be **consumed**, not parsed (otherwise
    /// `dropFirst(3)` mangles it into a phantom path). Non-z form may still
    /// use `new -> old` on one line; we strip that arrow if present.
    nonisolated static func parse(_ output: String, cwd: String) -> [ModifiedFile] {
        var files: [ModifiedFile] = []
        let root = URL(fileURLWithPath: cwd)
        let tokens = output.components(separatedBy: "\0")
        var i = 0
        while i < tokens.count {
            // Do NOT trim leading whitespace — X/Y status codes are often spaces
            // (` M path` = unstaged modify). Trimming would shift the path and
            // turn `tracked.txt` into `racked.txt`.
            let line = tokens[i]
            i += 1
            guard line.count > 3 else { continue }

            let xCode = line[line.startIndex]
            let yCode = line[line.index(after: line.startIndex)]

            // Path starts at offset 3 (`XY `).
            var relativePath = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            guard !relativePath.isEmpty else { continue }

            // Rename/copy: next NUL token is the other path — skip it.
            let isRenameOrCopy =
                xCode == "R" || xCode == "C" || yCode == "R" || yCode == "C"
            if isRenameOrCopy, i < tokens.count {
                i += 1
            }

            // Non-z rename form: `R  new -> old` on one line.
            if let arrow = relativePath.range(of: " -> ") {
                relativePath = String(relativePath[..<arrow.lowerBound])
            }

            let url = URL(fileURLWithPath: relativePath, relativeTo: root).standardizedFileURL
            let status: GitFileStatus
            if xCode == "A" || xCode == "?" || yCode == "?" || yCode == "A" {
                status = .added
            } else if xCode == "D" || yCode == "D" {
                status = .deleted
            } else {
                // Includes M / R / C / space combinations → badge as modified.
                status = .modified
            }
            files.append(ModifiedFile(url: url, status: status))
        }
        return files.sorted { a, b in
            a.url.path.localizedStandardCompare(b.url.path) == .orderedAscending
        }
    }

    /// Badge for a path: exact file hit, or for a directory the roll-up of any
    /// dirty descendant (mixed → `.modified`).
    nonisolated static func status(
        for url: URL,
        in map: [URL: GitFileStatus]
    ) -> GitFileStatus? {
        let key = url.standardizedFileURL
        if let exact = map[key] { return exact }

        let prefix = key.path.hasSuffix("/") ? key.path : key.path + "/"
        var hasM = false
        var hasA = false
        var hasD = false
        for (pathURL, status) in map {
            let p = pathURL.path
            guard p.hasPrefix(prefix) else { continue }
            switch status {
            case .modified: hasM = true
            case .added: hasA = true
            case .deleted: hasD = true
            }
        }
        if hasM { return .modified }
        if hasA, hasD { return .modified }
        if hasA { return .added }
        if hasD { return .deleted }
        return nil
    }
}

/// Browsable https page of a git remote, for the status bar's repo popover.
/// [archer] ported from iAmCorey/kooky (v0.37.0).
struct GitRemoteWebInfo: Equatable {
    var webURL: URL

    var host: String {
        webURL.host ?? ""
    }

    var forgeName: String {
        let h = host.lowercased()
        if h.contains("github") { return "GitHub" }
        if h.contains("gitlab") { return "GitLab" }
        if h.contains("bitbucket") { return "Bitbucket" }
        return host
    }

    static func resolve(repoRoot: String) -> GitRemoteWebInfo? {
        let listing = GitStatusFetcher.runGit(["-C", repoRoot, "--no-optional-locks", "remote", "-v"]) ?? ""
        return preferredRemoteURL(inRemoteListing: listing).flatMap(parse(remoteURL:))
    }

    static func preferredRemoteURL(inRemoteListing output: String) -> String? {
        var first: String?
        for line in output.split(whereSeparator: \.isNewline) {
            guard line.hasSuffix(" (fetch)"), let tab = line.firstIndex(of: "\t") else { continue }
            let url = line[line.index(after: tab)...]
                .dropLast(" (fetch)".count)
                .trimmingCharacters(in: .whitespaces)
            if line[..<tab] == "origin" { return url }
            if first == nil { first = url }
        }
        return first
    }

    static func parse(remoteURL raw: String) -> GitRemoteWebInfo? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let webOrigin: String
        var path: String
        if trimmed.contains("://") {
            guard let url = URL(string: trimmed),
                  let scheme = url.scheme?.lowercased(),
                  ["https", "http", "ssh", "git"].contains(scheme),
                  let host = url.host, !host.isEmpty
            else { return nil }
            if scheme == "http" || scheme == "https" {
                webOrigin = "\(scheme)://\(host)" + (url.port.map { ":\($0)" } ?? "")
            } else {
                webOrigin = "https://\(host)"
            }
            path = url.path
        } else if let colon = trimmed.firstIndex(of: ":") {
            let head = String(trimmed[..<colon])
            let host = head.split(separator: "@").last.map(String.init) ?? head
            guard !host.isEmpty, !host.contains("/") else { return nil }
            webOrigin = "https://\(host)"
            path = String(trimmed[trimmed.index(after: colon)...])
        } else {
            return nil
        }
        path = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if path.lowercased().hasSuffix(".git") { path.removeLast(4) }
        guard !path.isEmpty, let web = URL(string: "\(webOrigin)/\(path)") else { return nil }
        return GitRemoteWebInfo(webURL: web)
    }
}
