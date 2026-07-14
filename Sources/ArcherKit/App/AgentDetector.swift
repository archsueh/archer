// [archer]
// AgentDetector.swift
//
// Lightweight *active* agent sniffer — the proactive counterpart to Archer's
// hook-driven session identification. Instead of waiting for an agent to
// announce itself via a hook, this periodically inspects the command lines of
// every running process (`ps -ax -o comm,args`) and classifies which coding
// agent (if any) is currently alive on the machine.
//
// Pure Swift / Foundation, no new dependencies, no network. Inspired by muxy's
// AIAgentDetector / ForegroundProcessInspector.

import Foundation

/// [archer]
/// The kind of coding agent the sniffer believes is running right now.
enum DetectedAgent {
    case claude
    case codex
    case gemini
    case aider
    case cursor
    case unknown
}

/// [archer]
/// Proactive process sniffer. The class itself is *not* actor-isolated: the
/// `ps` scan runs on a background queue, and results are pushed back onto the
/// main actor via the `@MainActor` `onDetect` closure so they can be written
/// straight into observed SwiftUI state.
final class AgentDetector {
    /// Polling interval in seconds.
    static let interval: TimeInterval = 5

    /// Match rules — order matters, first substring hit wins. Extend here as
    /// new agents appear (e.g. `.windsurf, "windsurf"`).
    private let rules: [(DetectedAgent, String)] = [
        (.claude, "claude"),
        (.codex, "codex"),
        (.gemini, "gemini"),
        (.aider, "aider"),
        (.cursor, "cursor"),
    ]

    private var timer: Timer?
    /// Delivered on the main actor so callers can write observable state safely.
    private var onDetect: (@MainActor (DetectedAgent) -> Void)?

    /// [archer] Each owner gets its own detector so isolated (test) instances
    /// don't share polling state.
    init() {}

    deinit {
        timer?.invalidate()
    }

    /// [archer]
    /// Begin periodic sniffing. `onDetect` is always delivered on the main
    /// actor. Call this from the main actor (e.g. `AgentMonitor.init`).
    func start(onDetect: @escaping @MainActor (DetectedAgent) -> Void) {
        self.onDetect = onDetect
        timer?.invalidate()
        // First scan on a background queue, then repeat on a 5s timer.
        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.scan()
        }
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
        onDetect = nil
    }

    /// [archer]
    /// Collect, classify, and report in one shot. Safe to call from any thread.
    private func scan() {
        let detected = classify(snapshot())
        let report = onDetect
        Task { @MainActor in
            report?(detected)
        }
    }

    /// [archer]
    /// Grab the `comm` + `args` of every process. Returns raw lines; an empty
    /// array means the snapshot failed (no match will be made). Runs synchronously
    /// on whatever queue called `scan` (the background queue), so it never blocks UI.
    private func snapshot() -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-ax", "-o", "comm,args"]
        let pipe = Pipe()
        process.standardOutput = pipe
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { return [] }
            return output.split(separator: "\n").map(String.init)
        } catch {
            return []
        }
    }

    /// [archer]
    /// Match the joined, lowercased output against known agent keywords.
    private func classify(_ lines: [String]) -> DetectedAgent {
        let haystack = lines.joined(separator: "\n").lowercased()
        for (agent, keyword) in rules {
            if haystack.contains(keyword) {
                return agent
            }
        }
        return .unknown
    }
}
