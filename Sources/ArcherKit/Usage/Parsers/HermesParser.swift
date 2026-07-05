import Foundation

/// Collects Hermes usage from `~/.hermes/state.db` (SQLite).
///
/// Hermes is DB-native — it has no JSONL logs to cache, so `cache` and
/// `livePaths` are accepted for protocol conformance but unused. // [archer]
enum HermesParser: UsageParser {
    static let sourceLabel = "Hermes"

    static func collect(
        cache _: inout CollectorCache,
        livePaths _: inout Set<String>,
        modifiedSince cutoffDate: Date?
    ) -> CollectorResult {
        let database = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".hermes/state.db")

        guard FileManager.default.fileExists(atPath: database.path),
              FileManager.default.isReadableFile(atPath: database.path)
        else {
            return CollectorResult(
                records: [],
                source: SourceInfo(status: "missing_db", files: 0, records: 0)
            )
        }

        var query = """
        select id, started_at, model, input_tokens, output_tokens, \
        cache_read_tokens, estimated_cost_usd from sessions
        """
        if let cutoffDate {
            let cutoffTime = cutoffDate.timeIntervalSince1970
            query += " where started_at >= \(cutoffTime)"
        }

        guard let rows = UsageCollector.sqliteJSONRows(
            database: database, query: query
        ) else {
            return CollectorResult(
                records: [],
                source: SourceInfo(status: "query_failed", files: 1, records: 0)
            )
        }

        let records = rows.compactMap { row -> UsageRecord? in
            let input = UsageCollector.integerValue(row["input_tokens"] as Any)
            let output = UsageCollector.integerValue(row["output_tokens"] as Any)
            let cacheRead = UsageCollector.integerValue(row["cache_read_tokens"] as Any)
            let total = input + output + cacheRead
            guard total > 0,
                  let day = UsageCollector.dayString(fromEpoch: row["started_at"] as Any)
            else {
                return nil
            }
            var usage = TokenUsageCounts()
            usage.inputTokens = input
            usage.outputTokens = output
            usage.cacheReadInputTokens = cacheRead
            usage.totalTokens = total

            let costVal = UsageCollector.doubleValue(row["estimated_cost_usd"] as Any)

            return UsageRecord(
                date: day,
                timestamp: UsageCollector.isoString(fromEpoch: row["started_at"] as Any),
                tool: "Hermes",
                model: UsageCollector.modelKey(row["model"] as? String),
                usage: usage,
                costUSD: costVal > 0 ? costVal : nil,
                source: .nativeHermes,
                requestID: UsageCollector.nonEmptyString(row["id"] as? String),
                sessionID: UsageCollector.nonEmptyString(row["id"] as? String),
                dataSource: "hermes"
            )
        }

        return CollectorResult(
            records: records,
            source: SourceInfo(
                status: records.isEmpty ? "missing_valid_rows" : "ok",
                files: 1,
                records: records.count
            )
        )
    }
}
