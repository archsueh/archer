import Foundation

/// Snapshot of a working tree's git state for the pane footer.
/// `branch == nil` means "not in a repo" (or git unavailable / errored).
struct GitStatus: Equatable {
    var branch: String?
    var filesChanged: Int
    var insertions: Int
    var deletions: Int

    static let empty = GitStatus(branch: nil, filesChanged: 0, insertions: 0, deletions: 0)
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
        // `--abbrev-ref HEAD` returns the branch name, or "HEAD" when detached.
        // Failure here usually means cwd isn't inside a repo — fall through to
        // empty so the footer hides cleanly.
        guard let head = runGit(["-C", cwd, "--no-optional-locks", "rev-parse", "--abbrev-ref", "HEAD"]) else {
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
        return GitStatus(branch: branch, filesChanged: files, insertions: ins, deletions: del)
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
    /// Each entry is `XY path` (path may include spaces). Rename/copy old paths
    /// appear as a separate null-terminated token without the `XY ` prefix and
    /// are skipped (same as DiffModel historically).
    nonisolated static func parse(_ output: String, cwd: String) -> [ModifiedFile] {
        var files: [ModifiedFile] = []
        let root = URL(fileURLWithPath: cwd)
        for part in output.components(separatedBy: "\0") {
            // Do NOT trim leading whitespace — X/Y status codes are often spaces
            // (` M path` = unstaged modify). Trimming would shift the path and
            // turn `tracked.txt` into `racked.txt`.
            let line = part
            guard line.count > 3 else { continue }

            let xCode = line[line.startIndex]
            let yCode = line[line.index(after: line.startIndex)]

            // Path starts at offset 3 (`XY `).
            let relativePath = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            guard !relativePath.isEmpty else { continue }

            // Rename entries can look like `R  new -> old` in non-z form; with
            // -z the second path is a separate token. Still strip ` -> ` if present.
            let pathOnly: String
            if let arrow = relativePath.range(of: " -> ") {
                pathOnly = String(relativePath[..<arrow.lowerBound])
            } else {
                pathOnly = relativePath
            }

            let url = URL(fileURLWithPath: pathOnly, relativeTo: root).standardizedFileURL
            let status: GitFileStatus
            if xCode == "A" || xCode == "?" || yCode == "?" || yCode == "A" {
                status = .added
            } else if xCode == "D" || yCode == "D" {
                status = .deleted
            } else {
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
