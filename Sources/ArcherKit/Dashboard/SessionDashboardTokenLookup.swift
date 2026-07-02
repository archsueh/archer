import Foundation

/// The only `Dashboard/` file allowed to know `Usage/` exists — keeps the
/// row-building code (`SessionDashboardRow.swift`) decoupled from how
/// token totals are actually sourced. `AppDelegate` is the sole caller,
/// same place that already wires both areas together.
enum SessionDashboardTokenLookup {
    /// Builds a `(conversationId) -> tokenTotal?` closure backed by
    /// `UsageCollector.claudeSessionTokenTotals`, cached for 15s so the
    /// Sessions window's 1s refresh loop doesn't re-walk
    /// `~/.claude/projects/**/*.jsonl` on every tick — only every 15th.
    @MainActor static func makeClosure() -> (String) -> Int? {
        var cached: [String: Int] = [:]
        var lastBuilt: Date = .distantPast
        return { sessionID in
            if Date().timeIntervalSince(lastBuilt) > 15 {
                cached = UsageCollector.claudeSessionTokenTotals()
                lastBuilt = Date()
            }
            return cached[sessionID]
        }
    }
}
