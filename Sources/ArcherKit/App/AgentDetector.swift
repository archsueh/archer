// [archer]
// AgentDetector.swift
//
// Lightweight *active* agent sniffer — the proactive counterpart to Archer's
// hook-driven session identification. Periodically inspects running processes
// (`ps -ax -o pid=,comm=,args=`) and classifies which coding agents (if any)
// are alive on the machine.
//
// Pure Swift / Foundation. Inspired by muxy's AIAgentDetector — matching is
// basename-based (not a whole-table substring), and the monitor only starts
// when the user enables Settings → process-agent-sniffer (default off).

import Foundation

/// [archer]
/// Coding agents the process sniffer can report. Multi-agent machines return a set.
enum DetectedAgent: String, Hashable, CaseIterable {
    case claude
    case codex
    case gemini
    case aider
    case cursor
    case grok
    case hermes

    var label: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        case .gemini: return "Gemini"
        case .aider: return "Aider"
        case .cursor: return "Cursor"
        case .grok: return "Grok"
        case .hermes: return "Hermes"
        }
    }
}

/// [archer]
/// Proactive process sniffer. Not actor-isolated: `ps` runs on a utility queue;
/// results are delivered on the main actor via `onDetect`.
final class AgentDetector: @unchecked Sendable {
    /// Polling interval in seconds.
    static let interval: TimeInterval = 5

    /// UserDefaults key — shared with Settings UI (`@AppStorage`).
    static let preferenceKey = "archer.agentProcessSniffer"

    private var timer: Timer?
    private var onDetect: (@MainActor (Set<DetectedAgent>) -> Void)?
    private let lock = NSLock()

    init() {}

    deinit {
        timer?.invalidate()
    }

    /// [archer]
    /// Begin periodic sniffing. `onDetect` is always delivered on the main actor.
    func start(onDetect: @escaping @MainActor (Set<DetectedAgent>) -> Void) {
        lock.lock()
        self.onDetect = onDetect
        lock.unlock()
        timer?.invalidate()
        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.scan()
        }
        // Timer must be scheduled on a run-loop thread; main is fine — the
        // expensive `ps` work still hops to a utility queue.
        timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { [weak self] _ in
            DispatchQueue.global(qos: .utility).async {
                self?.scan()
            }
        }
    }

    /// [archer]
    func stop() {
        timer?.invalidate()
        timer = nil
        lock.lock()
        onDetect = nil
        lock.unlock()
    }

    private func scan() {
        let detected = Self.classify(snapshot())
        lock.lock()
        let report = onDetect
        lock.unlock()
        Task { @MainActor in
            report?(detected)
        }
    }

    /// Grab `comm` + `args` per process. Empty array = snapshot failed.
    private func snapshot() -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        // pid= keeps a stable column; we only need comm + args for matching.
        process.arguments = ["-ax", "-o", "comm=,args="]
        let pipe = Pipe()
        process.standardOutput = pipe
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { return [] }
            return output.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        } catch {
            return []
        }
    }

    /// [archer]
    /// Pure classifier — unit-tested. Matches **executable basenames** only
    /// (comm path tail + first args token tail), never a whole-table substring.
    static func classify(_ lines: [String]) -> Set<DetectedAgent> {
        var found = Set<DetectedAgent>()
        for line in lines {
            for basename in basenames(in: line) {
                if let agent = match(basename: basename) {
                    found.insert(agent)
                }
            }
        }
        return found
    }

    /// Extract candidate executable basenames from one `ps` line.
    private static func basenames(in line: String) -> [String] {
        let parts = line.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !parts.isEmpty else { return [] }
        var names: [String] = []
        // comm (first field) may be a path or a short name.
        names.append((parts[0] as NSString).lastPathComponent.lowercased())
        // args[0] often repeats the real binary path when comm is truncated.
        if parts.count > 1 {
            names.append((parts[1] as NSString).lastPathComponent.lowercased())
        }
        return names
    }

    /// Exact / prefix rules on a single basename (already lowercased).
    private static func match(basename: String) -> DetectedAgent? {
        // Strip a trailing ".app" / process suffix noise.
        let name = basename.replacingOccurrences(of: ".app", with: "")
        switch name {
        case "claude", "claude-code":
            return .claude
        case "codex":
            return .codex
        case "gemini", "gemini-cli":
            return .gemini
        case "aider":
            return .aider
        case "cursor", "cursor-agent":
            return .cursor
        case "grok", "grok-cli":
            return .grok
        case "hermes", "hermes-agent":
            return .hermes
        default:
            // Wrapper binaries like `claude-code` / `codex-cli` — only when the
            // basename has no file extension (avoid matching `claude-essay.txt`).
            guard !name.contains(".") else { return nil }
            if name.hasPrefix("claude-") { return .claude }
            if name.hasPrefix("codex-") { return .codex }
            if name.hasPrefix("gemini-") { return .gemini }
            return nil
        }
    }
}
