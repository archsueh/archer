import Foundation

// [archer] TTL-cached session → live usage lookup. Collect walks Claude
// jsonl (and later other tools); the status-bar pill polls this instead of
// re-walking the tree every frame.

/// Thread-safe lookup of per-session cost/token totals. // [archer]
enum SessionLiveUsageLookup {
    private static let lock = NSLock()
    /// Guarded by `lock`; `nonisolated(unsafe)` matches other Archer shared
    /// mutable caches protected by external synchronization. // [archer]
    private nonisolated(unsafe) static var cache: [String: Entry] = [:]
    /// Default TTL when the agent is idle — running sessions use a shorter
    /// interval at the call site by passing `ttl`. // [archer]
    static let defaultTTL: TimeInterval = 15

    private struct Entry {
        let at: Date
        let value: SessionLiveUsage?
    }

    /// Returns folded live usage for `sessionID`, reading from cache when still
    /// fresh. `preferredSourcePath` scopes parse to the watched file (P1c).
    /// Safe off the main thread. // [archer]
    static func usage(
        sessionID: String,
        tool: String = "Claude Code",
        historyDays: Int = 30,
        preferredSourcePath: String? = nil,
        ttl: TimeInterval = defaultTTL,
        force: Bool = false
    ) -> SessionLiveUsage? {
        let key = cacheKey(tool: tool, sessionID: sessionID)

        if !force {
            lock.lock()
            if let hit = cache[key], Date().timeIntervalSince(hit.at) < ttl {
                let value = hit.value
                lock.unlock()
                return value
            }
            lock.unlock()
        }

        let value = UsageCollector.sessionLiveUsage(
            sessionID: sessionID,
            tool: tool,
            historyDays: historyDays,
            preferredSourcePath: preferredSourcePath
        )

        lock.lock()
        cache[key] = Entry(at: Date(), value: value)
        lock.unlock()
        return value
    }

    static func invalidate(sessionID: String? = nil, tool: String = "Claude Code") {
        lock.lock()
        defer { lock.unlock() }
        if let sessionID {
            cache.removeValue(forKey: cacheKey(tool: tool, sessionID: sessionID))
        } else {
            cache.removeAll()
        }
    }

    private static func cacheKey(tool: String, sessionID: String) -> String {
        "\(tool)|\(sessionID)"
    }
}
