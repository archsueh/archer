import Foundation

/// Protocol for native agent usage collectors. Each parser reads a specific
/// agent's local log files or databases and emits `UsageRecord` rows.
///
/// The ccSwitch proxy source is intentionally excluded — its signature and
/// semantics differ (SQLite proxy dedup, different cost attribution), and
/// forcing a common protocol would be a false abstraction. // [archer]
protocol UsageParser {
    /// Human-readable label for the source row (e.g. "Codex", "Grok").
    static var sourceLabel: String { get }

    /// Collect usage records from the local filesystem.
    ///
    /// - Parameters:
    ///   - cache: Shared collector cache (parsers that touch JSONL files
    ///     should read/write through `cachedRecords`/`updateCache`).
    ///   - livePaths: File paths touched during this pass (used to prune
    ///     stale cache entries after collection completes).
    ///   - modifiedSince: Optional cutoff date for file modification times.
    /// - Returns: A `CollectorResult` with parsed records and source metadata.
    static func collect(
        cache: inout CollectorCache,
        livePaths: inout Set<String>,
        modifiedSince cutoffDate: Date?
    ) -> CollectorResult
}
