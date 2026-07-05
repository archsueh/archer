import Foundation

/// Collects Codex usage from `~/.codex/sessions/*.jsonl` (primary) with
/// `~/.codex/state_*.sqlite` fallback. // [archer]
enum CodexParser: UsageParser {
    static let sourceLabel = "Codex"

    static func collect(
        cache: inout CollectorCache,
        livePaths: inout Set<String>,
        modifiedSince cutoffDate: Date?
    ) -> CollectorResult {
        let jsonlResult = collectFromJSONL(
            cache: &cache,
            livePaths: &livePaths,
            modifiedSince: cutoffDate
        )
        if jsonlResult.source.status == "ok" {
            return jsonlResult
        }
        return collectFromSQLite(modifiedSince: cutoffDate) ?? jsonlResult
    }

    // MARK: - SQLite fallback

    private static func collectFromSQLite(
        modifiedSince cutoffDate: Date?
    ) -> CollectorResult? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            home.appendingPathComponent(".codex/state_5.sqlite"),
            home.appendingPathComponent(".codex/sqlite/state_5.sqlite"),
        ]
        guard let database = candidates.first(where: {
            FileManager.default.fileExists(atPath: $0.path)
        }) else {
            return nil
        }

        var query = "select created_at, model, tokens_used from threads where tokens_used > 0"
        if let cutoffDate {
            let cutoffTime = cutoffDate.timeIntervalSince1970
            query += " and created_at >= \(cutoffTime)"
        }

        guard let rows = UsageCollector.sqliteJSONRows(database: database, query: query) else {
            return nil
        }

        let records = rows.compactMap { row -> UsageRecord? in
            let tokens = UsageCollector.integerValue(row["tokens_used"] as Any)
            guard tokens > 0,
                  let day = UsageCollector.dayString(fromEpoch: row["created_at"] as Any)
            else {
                return nil
            }
            var usage = TokenUsageCounts()
            usage.totalTokens = tokens
            return UsageRecord(
                date: day,
                timestamp: nil,
                tool: "Codex",
                model: UsageCollector.modelKey(row["model"] as? String),
                usage: usage,
                source: .nativeCodexSQLite
            )
        }

        guard !records.isEmpty else { return nil }
        return CollectorResult(
            records: records,
            source: SourceInfo(
                status: "ok_sqlite",
                files: 1,
                records: records.count
            )
        )
    }

    // MARK: - JSONL (primary)

    private static func collectFromJSONL(
        cache: inout CollectorCache,
        livePaths: inout Set<String>,
        modifiedSince cutoffDate: Date?,
        homeURL: URL = FileManager.default.homeDirectoryForCurrentUser,
        roots: [URL]? = nil
    ) -> CollectorResult {
        let roots = roots ?? [homeURL.appendingPathComponent(".codex/sessions", isDirectory: true)]
        let paths = roots.flatMap {
            UsageCollector.jsonlFiles(under: $0, modifiedSince: cutoffDate)
        }
        var records: [UsageRecord] = []
        var seen = Set<String>()

        for path in paths.sorted(by: { $0.path < $1.path }) {
            livePaths.insert(path.path)
            if let cached = UsageCollector.cachedRecords(for: path, tool: "Codex", cache: cache) {
                records.append(contentsOf: cached)
                continue
            }

            var fileRecords: [UsageRecord] = []
            var sessionID = path.deletingPathExtension().lastPathComponent
            var currentModel = "unknown"
            var eventIndex = 0
            var lineNumber = 0
            guard FileManager.default.isReadableFile(atPath: path.path) else { continue }

            try? UsageCollector.forEachLine(
                in: path,
                matchingAny: ["session_meta", "turn_context", "token_count"]
            ) { line in
                autoreleasepool {
                    lineNumber += 1
                    guard let obj = UsageCollector.jsonObject(line) else { return }
                    let type = obj["type"] as? String
                    let payload = obj["payload"] as? [String: Any]

                    if type == "session_meta",
                       let id = payload?["id"] as? String,
                       !id.isEmpty
                    {
                        sessionID = id
                    }
                    if type == "turn_context" {
                        currentModel = UsageCollector.modelKey(
                            payload?["model"] as? String ?? currentModel
                        )
                    }
                    guard type == "event_msg",
                          payload?["type"] as? String == "token_count",
                          let info = payload?["info"] as? [String: Any]
                    else {
                        return
                    }

                    let usage = UsageCollector.normalizeUsage(
                        info["last_token_usage"] as? [String: Any]
                    )
                    guard usage.totalTokens > 0,
                          let timestamp = obj["timestamp"] as? String,
                          let day = UsageCollector.dayString(fromISO: timestamp)
                    else {
                        return
                    }

                    eventIndex += 1
                    let key = "\(sessionID)|\(timestamp)|\(eventIndex)|\(usage.totalTokens)"
                    guard !seen.contains(key) else { return }
                    seen.insert(key)
                    fileRecords.append(
                        UsageRecord(
                            date: day,
                            timestamp: timestamp,
                            tool: "Codex",
                            model: currentModel,
                            usage: usage,
                            source: .nativeCodex,
                            requestID: key,
                            sessionID: sessionID,
                            sourcePath: path.path,
                            lineNumber: lineNumber
                        )
                    )
                }
            }
            records.append(contentsOf: fileRecords)
            UsageCollector.updateCache(
                path: path,
                tool: "Codex",
                records: fileRecords,
                cache: &cache
            )
        }

        return CollectorResult(
            records: records,
            source: SourceInfo(
                status: records.isEmpty ? "missing" : "ok",
                files: paths.count,
                records: records.count
            )
        )
    }
}
