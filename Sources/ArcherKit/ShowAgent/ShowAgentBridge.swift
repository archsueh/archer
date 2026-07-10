// [archer] ShowAgent integration — bridges the `showagent` Go binary
// (aytzey/showagent) into Archer. showagent is a 100% local TUI that
// indexes every coding-agent session on disk (Codex, Claude Code, Gemini
// CLI, OpenCode, jcode) and can convert a session into another agent's
// native format atomically. This layer shells out to the vendored binary
// and parses its `--json` output — it never re-implements showagent's
// provider parsers, so upstream updates are a drop-in binary swap.
//
// Design notes:
// - The binary lives in ArcherKit's processed resources (Vendor/showagent).
// - All writes are delegated to showagent itself; we only READ and LAUNCH.
//   Convert/branch write brand-new session files via showagent's atomic
//   path — originals are never touched (mirrors showagent's own contract).
// - No network, no telemetry — same guarantee showagent makes.

import Foundation

// MARK: - Model

/// One coding-agent session discovered by showagent on local disk.
struct ShowAgentSession: Identifiable, Hashable {
    let id: String
    let provider: String
    let workspace: String
    let updated: String
    let firstMessage: String
    let lastMessage: String

    /// Human-facing provider label ("Codex", "Claude", ...).
    var providerLabel: String {
        switch provider.lowercased() {
        case "codex": return "Codex"
        case "claude": return "Claude"
        case "gemini": return "Gemini"
        case "opencode": return "OpenCode"
        case "jcode": return "jcode"
        default: return provider.capitalized
        }
    }

    /// SF Symbol used in palette rows — mirrors Archer's agent glyph style.
    var symbol: String {
        switch provider.lowercased() {
        case "codex": return "c.circle"
        case "claude": return "point.topleft.filled.down.to.point.bottomright.filled.curvepath"
        case "gemini": return "sparkle.magnifyingglass"
        case "opencode": return "curlybraces"
        case "jcode": return "barcode"
        default: return "terminal"
        }
    }
}

/// Result of a `convert` / `branch` action — enough to relaunch the new
/// session in its own CLI.
struct ShowAgentConversion: Identifiable {
    let id: String
    let provider: String
    let file: String
    let resumeCommand: String
    let cwd: String
    let note: String
}

// MARK: - Errors

enum ShowAgentError: LocalizedError {
    case binaryMissing
    case failed(exitCode: Int32, stderr: String)
    case invalidJSON(String)
    case unexpectedOutput(String)

    var errorDescription: String? {
        switch self {
        case .binaryMissing:
            return "showagent binary not found in app resources."
        case let .failed(code, stderr):
            return "showagent exited \(code): \(stderr.isEmpty ? "(no stderr)" : stderr)"
        case let .invalidJSON(detail):
            return "showagent returned unparseable output: \(detail)"
        case let .unexpectedOutput(text):
            return "showagent returned unexpected output: \(text)"
        }
    }
}

// MARK: - Bridge

@MainActor
enum ShowAgentBridge {
    /// Location of the vendored binary. Sits next to the app
    /// executable (Contents/MacOS/showagent) — copied there by
    /// scripts/build-app.sh from Vendor/showagent/. Resolving via
    /// the executable URL keeps it on the same rpath as Archer itself.
    static var binaryURL: URL? {
        Bundle.main.executableURL?
            .deletingLastPathComponent()
            .appendingPathComponent("showagent")
    }

    // MARK: list

    /// Discovers all local coding-agent sessions, newest first.
    static func list() throws -> [ShowAgentSession] {
        let out = try run(["list", "--json"])
        guard let data = out.data(using: .utf8) else { throw ShowAgentError.invalidJSON("empty") }
        let raw = try JSONDecoder().decode([ShowAgentRaw].self, from: data)
        return raw.map { $0.toSession() }
    }

    /// Search sessions by free-text query over provider, workspace, and
    /// first/last user message. Kept as a uniform entry point so callers
    /// don't care that showagent's own `list` has no --query flag.
    static func search(_ query: String) throws -> [ShowAgentSession] {
        let all = try list()
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return all }
        return all.filter { session in
            [session.provider, session.providerLabel, session.workspace,
             session.firstMessage, session.lastMessage]
                .contains { $0.lowercased().contains(q) }
        }
    }

    // MARK: convert / branch / resume

    /// Convert `sessionId` (or "latest") into `target` agent's native
    /// format. Returns the newly written session's resume recipe. Original
    /// is never modified.
    static func convert(sessionId: String, to target: String) throws -> ShowAgentConversion {
        let out = try run(["convert", sessionId, "--to", target])
        return try parseConversion(out)
    }

    /// Fork `sessionId` (or "latest") into a new session of the same agent.
    static func branch(sessionId: String) throws -> ShowAgentConversion {
        let out = try run(["branch", sessionId])
        return try parseConversion(out)
    }

    /// Returns the exact shell command + cwd that reopens a session in its
    /// own agent CLI. showagent never executes it — we return it for the
    /// caller to launch (or present) on Archer's terms.
    static func resumeRecipe(sessionId: String) throws -> ShowAgentConversion {
        let out = try run(["info", sessionId])
        return try parseConversion(out)
    }

    // MARK: - process runner

    /// Runs the vendored binary with `args`, returning stdout. Throws on
    /// non-zero exit or missing binary.
    private static func run(_ args: [String]) throws -> String {
        guard let url = binaryURL, FileManager.default.isExecutableFile(atPath: url.path) else {
            throw ShowAgentError.binaryMissing
        }
        let process = Process()
        process.executableURL = url
        process.arguments = args

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
        if process.terminationStatus != 0 {
            throw ShowAgentError.failed(
                exitCode: process.terminationStatus,
                stderr: String(data: stderrData, encoding: .utf8) ?? ""
            )
        }
        return stdout
    }

    /// showagent's convert/branch/info print a "recipe" block of `key: value`
    /// lines, not JSON. Parse the fields we need defensively.
    private static func parseConversion(_ output: String) throws -> ShowAgentConversion {
        var dict: [String: String] = [:]
        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let colon = trimmed.firstIndex(of: ":") else { continue }
            let key = String(trimmed[..<colon]).trimmingCharacters(in: .whitespaces).lowercased()
            let value = String(trimmed[trimmed.index(after: colon)...])
                .trimmingCharacters(in: .whitespaces)
            dict[key] = value
        }

        // convert prints a header line "converted <src> <sid> -> <tgt> <newid>"
        // before the recipe; the recipe itself carries `session:` and `command:`.
        guard let command = dict["command"], !command.isEmpty else {
            throw ShowAgentError.unexpectedOutput(output)
        }
        // `session:` holds the new session id; fall back to `id:` if present.
        let id = dict["session"] ?? dict["id"] ?? ""
        // `storage:` is the file path; `cwd:` the launch directory.
        let file = dict["storage"] ?? ""
        let cwd = dict["cwd"] ?? ""
        let provider = dict["provider"] ?? ""
        let note = dict["note"] ?? ""
        return ShowAgentConversion(
            id: id, provider: provider, file: file,
            resumeCommand: command, cwd: cwd, note: note
        )
    }
}

// MARK: - JSON raw shape (showagent `list --json`)

private struct ShowAgentRaw: Codable {
    let id: String
    let provider: String
    let workspace: String
    let updated: String
    let firstMessage: String
    let lastMessage: String

    enum CodingKeys: String, CodingKey {
        case id, provider, workspace, updated
        case firstMessage = "first_message"
        case lastMessage = "last_message"
    }

    func toSession() -> ShowAgentSession {
        ShowAgentSession(
            id: id, provider: provider, workspace: workspace,
            updated: updated, firstMessage: firstMessage, lastMessage: lastMessage
        )
    }
}
