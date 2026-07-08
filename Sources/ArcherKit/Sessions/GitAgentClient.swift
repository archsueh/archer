import Foundation

/// Thin Swift wrapper around the external `git-agent` CLI
/// (https://github.com/GitAgentHQ/git-agent-cli). git-agent analyzes staged /
/// unstaged changes, splits them into atomic commits, and generates
/// conventional commit messages via an LLM. It also mines git history for
/// co-change relations (`related`) — which files habitually change together.
///
/// Archer shells out the same way `GitStatusFetcher` shells out to `git`:
/// `/usr/bin/env <binary>` on a background queue, structured JSON parsed back.
/// Two call shapes are supported:
///   • `commit`  with `-o json` → atomic commit plan + SHAs
///   • `related` with `-o json` → co-change graph of coupled files
///
/// Binary resolution order (first hit wins):
///   1. `Archer_ArcherKit.bundle/Contents/Resources/Tools/git-agent` — when
///      bundled into Archer.app (see build-app.sh resource copy step)
///   2. `git-agent` on PATH
///   3. Homebrew prefix `/opt/homebrew/bin/git-agent` (Apple Silicon default)
@MainActor
final class GitAgentClient {
    static let shared = GitAgentClient()

    enum GitAgentError: LocalizedError {
        case notFound
        case nonZeroExit(Int, String)
        case invalidJSON(String)

        var errorDescription: String? {
            switch self {
            case .notFound:
                return "git-agent binary not found. Install via `brew install GitAgentHQ/brew/git-agent` or bundle it into Archer."
            case let .nonZeroExit(code, stderr):
                return "git-agent exited \(code): \(stderr.trimmingCharacters(in: .whitespacesAndNewlines))"
            case let .invalidJSON(msg):
                return "Failed to parse git-agent output: \(msg)"
            }
        }
    }

    /// Resolved binary path, or nil if git-agent is unavailable. Cached after
    /// first resolution so repeated calls don't re-walk the filesystem.
    private var cachedBinary: String?

    func binaryPath() -> String? {
        if let cached = cachedBinary { return cached }
        let candidate: String? = Self.locateBinary()
        cachedBinary = candidate
        return candidate
    }

    /// Locates the git-agent executable. Resolution order:
    ///   1. Bundled resource inside `Archer_ArcherKit.bundle/Contents/Resources/Tools/`
    ///      (populated when Archer bundles git-agent via SPM `.process("Resources")`)
    ///   2. `git-agent` on PATH
    ///   3. Homebrew prefix `/opt/homebrew/bin/git-agent` (Apple Silicon default)
    /// Pure (`nonisolated`) so it can run from any context; uses only
    /// `Foundation.Bundle` lookups that don't touch the main-actor resource helper.
    nonisolated static func locateBinary() -> String? {
        // 1. Bundled resource — mirror how SPM lays out `Resources/Tools/` into
        //    the compiled `<ModuleName>.bundle` (Archer_ArcherKit.bundle).
        if let bundleURL = Bundle.main.url(
            forResource: "Archer_ArcherKit",
            withExtension: "bundle"
        ), let bundle = Bundle(url: bundleURL),
        let bundled = bundle.url(forResource: "git-agent", withExtension: nil, subdirectory: "Tools")?.path,
        FileManager.default.isExecutableFile(atPath: bundled) {
            return bundled
        }
        // 2. PATH lookup via /usr/bin/env.
        if let envPath = try? Process.runCaptured(["/usr/bin/env", "which", "git-agent"]),
           !envPath.isEmpty, FileManager.default.isExecutableFile(atPath: envPath)
        {
            return envPath
        }
        // 3. Explicit Homebrew prefix on Apple Silicon.
        let brewPath = "/opt/homebrew/bin/git-agent"
        if FileManager.default.isExecutableFile(atPath: brewPath) {
            return brewPath
        }
        return nil
    }

    /// Runs `git-agent commit -o json`. Returns the structured commit plan.
    /// Pass `dryRun: true` to preview without touching the repo.
    func commit(cwd: URL, dryRun: Bool, intent: String? = nil) async throws -> GitAgentCommitResult {
        var args = ["commit", "-o", "json"]
        if dryRun { args.append("--dry-run") }
        if let intent, !intent.isEmpty { args += ["--intent", intent] }
        let data = try await run(args: args, cwd: cwd)
        return try decode(GitAgentCommitResult.self, from: data)
    }

    /// Runs `git-agent related -o json` for the given seed paths (files or
    /// directories). With `testsOnly: true` returns only coupled test files.
    /// Empty `seeds` means "what co-changes with my current working-tree edits".
    func related(cwd: URL, seeds: [String] = [], testsOnly: Bool = false) async throws -> GitAgentRelatedResult {
        var args = ["related", "-o", "json"]
        if testsOnly { args.append("--tests") }
        args += seeds
        let data = try await run(args: args, cwd: cwd)
        return try decode(GitAgentRelatedResult.self, from: data)
    }

    // MARK: - Execution

    /// Spawns `git-agent <args>` in cwd, captures stdout, throws on non-zero
    /// exit or missing binary. 60s timeout — `related` indexes git history on
    /// first run, which can take a while on large repos.
    private func run(args: [String], cwd: URL) async throws -> Data {
        guard let binary = binaryPath() else { throw GitAgentError.notFound }

        return try await withCheckedThrowingContinuation { continuation in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            task.arguments = [binary] + args
            task.currentDirectoryURL = cwd
            // Inherit Archer's PATH so git-agent resolves `git` consistently.
            task.environment = ["PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"]

            let stdout = Pipe()
            let stderr = Pipe()
            task.standardOutput = stdout
            task.standardError = stderr

            task.terminationHandler = { proc in
                let outData = stdout.fileHandleForReading.readDataToEndOfFile()
                let errData = stderr.fileHandleForReading.readDataToEndOfFile()
                let err = String(data: errData, encoding: .utf8) ?? ""
                if proc.terminationStatus != 0 {
                    continuation.resume(throwing: GitAgentError.nonZeroExit(Int(proc.terminationStatus), err))
                    return
                }
                continuation.resume(returning: outData)
            }

            do {
                try task.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func decode<T: Decodable>(_: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            let snippet = String(data: data.prefix(512), encoding: .utf8) ?? "<non-utf8>"
            throw GitAgentError.invalidJSON("\(error.localizedDescription) — output: \(snippet)")
        }
    }
}

// MARK: - JSON models (mirror git-agent's agent-facing contract)

/// `git-agent commit -o json` envelope.
struct GitAgentCommitResult: Decodable, Equatable {
    let dryRun: Bool
    let commits: [GitAgentCommit]
    let committedCount: Int?
    let finalSha: String?

    enum CodingKeys: String, CodingKey {
        case dryRun = "dry_run"
        case commits
        case committedCount = "committed_count"
        case finalSha = "final_sha"
    }
}

struct GitAgentCommit: Decodable, Equatable, Identifiable {
    let title: String
    let message: String
    let files: [String]
    let sha: String?
    let hookOutcome: String?

    var id: String {
        sha ?? title
    }

    enum CodingKeys: String, CodingKey {
        case title
        case message
        case files
        case sha
        case hookOutcome = "hook_outcome"
    }
}

/// `git-agent related -o json` envelope.
struct GitAgentRelatedResult: Decodable, Equatable {
    let targets: [String]
    let coChanged: [GitAgentRelatedEntry]
    let totalFound: Int
    let queryMs: Int64

    enum CodingKeys: String, CodingKey {
        case targets
        case coChanged = "co_changed"
        case totalFound = "total_found"
        case queryMs = "query_ms"
    }
}

struct GitAgentRelatedEntry: Decodable, Equatable, Identifiable {
    let path: String
    let couplingCount: Int
    let couplingStrength: Double
    let score: Double
    let seedMatches: Int
    let commits: [GitAgentCommitRef]?

    var id: String {
        path
    }

    enum CodingKeys: String, CodingKey {
        case path
        case couplingCount = "coupling_count"
        case couplingStrength = "coupling_strength"
        case score
        case seedMatches = "seed_matches"
        case commits
    }
}

struct GitAgentCommitRef: Decodable, Equatable, Identifiable {
    let sha: String
    let subject: String
    let ts: Int64

    var id: String {
        sha
    }
}

// MARK: - Process helper (non-isolated, reusable across the app)

extension Process {
    /// Runs a command and returns its trimmed stdout. Throws on launch failure
    /// or non-zero exit; stderr is discarded. Synchronous — for short probes
    /// like `which git-agent`.
    static func runCaptured(_ args: [String]) throws -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: args[0])
        task.arguments = Array(args.dropFirst())
        let stdout = Pipe()
        task.standardOutput = stdout
        task.standardError = Pipe()
        try task.run()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else { return "" }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
