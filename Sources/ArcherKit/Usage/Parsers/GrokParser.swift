import Foundation

/// Collects Grok usage from `~/.grok/logs/unified.jsonl` (inference_done
/// events) with model ids resolved from `~/.grok/sessions/*/summary.json`.
///
/// Deduplicates by `(sessionID, timestamp, loop_index, totalTokens)`. // [archer]
enum GrokParser: UsageParser {
    static let sourceLabel = "Grok"

    static func collect(
        cache: inout CollectorCache,
        livePaths: inout Set<String>,
        modifiedSince cutoffDate: Date?
    ) -> CollectorResult {
        collectFromHome(
            cache: &cache,
            livePaths: &livePaths,
            homeURL: FileManager.default.homeDirectoryForCurrentUser,
            modifiedSince: cutoffDate
        )
    }

    /// Testable entry point that accepts a custom home URL (used by
    /// `collectGrokForTesting` forwarding shim). // [archer]
    static func collect(
        cache: inout CollectorCache,
        livePaths: inout Set<String>,
        homeURL: URL,
        modifiedSince cutoffDate: Date?
    ) -> CollectorResult {
        collectFromHome(
            cache: &cache,
            livePaths: &livePaths,
            homeURL: homeURL,
            modifiedSince: cutoffDate
        )
    }

    // MARK: - Implementation

    private static func collectFromHome(
        cache: inout CollectorCache,
        livePaths: inout Set<String>,
        homeURL: URL,
        modifiedSince cutoffDate: Date?
    ) -> CollectorResult {
        let path = homeURL.appendingPathComponent(".grok/logs/unified.jsonl")
        guard FileManager.default.fileExists(atPath: path.path) else {
            return CollectorResult(
                records: [],
                source: SourceInfo(status: "missing", files: 0, records: 0)
            )
        }
        if let cutoffDate,
           let values = try? path.resourceValues(forKeys: [.contentModificationDateKey]),
           let modificationDate = values.contentModificationDate,
           modificationDate < cutoffDate
        {
            return CollectorResult(
                records: [],
                source: SourceInfo(status: "missing", files: 0, records: 0)
            )
        }

        let modelBySession = grokSessionModels(homeURL: homeURL)
        livePaths.insert(path.path)
        if let cached = UsageCollector.cachedRecords(
            for: path, tool: "Grok", cache: cache
        ) {
            return CollectorResult(
                records: cached,
                source: SourceInfo(
                    status: cached.isEmpty ? "missing" : "ok",
                    files: 1,
                    records: cached.count
                )
            )
        }

        var records: [UsageRecord] = []
        var seen = Set<String>()
        var lineNumber = 0
        guard FileManager.default.isReadableFile(atPath: path.path) else {
            return CollectorResult(
                records: [],
                source: SourceInfo(status: "missing", files: 1, records: 0)
            )
        }

        try? UsageCollector.forEachLine(
            in: path,
            matchingAny: ["shell.turn.inference_done"]
        ) { line in
            autoreleasepool {
                lineNumber += 1
                guard let obj = UsageCollector.jsonObject(line),
                      obj["msg"] as? String == "shell.turn.inference_done",
                      let ctx = obj["ctx"] as? [String: Any]
                else {
                    return
                }

                let promptTokens = UsageCollector.integerValue(ctx["prompt_tokens"] as Any)
                let cachedPromptTokens = UsageCollector.integerValue(ctx["cached_prompt_tokens"] as Any)
                let completionTokens = UsageCollector.integerValue(ctx["completion_tokens"] as Any)
                let reasoningTokens = UsageCollector.integerValue(ctx["reasoning_tokens"] as Any)
                let totalTokens = promptTokens + completionTokens + reasoningTokens
                guard totalTokens > 0,
                      let timestamp = obj["ts"] as? String,
                      let day = UsageCollector.dayString(fromISO: timestamp)
                else {
                    return
                }

                let sessionID = UsageCollector.nonEmptyString(obj["sid"] as? String)
                let loopIndex = UsageCollector.integerValue(ctx["loop_index"] as Any)
                let dedupeKey = "\(sessionID ?? "unknown")|\(timestamp)|\(loopIndex)|\(totalTokens)"
                guard !seen.contains(dedupeKey) else { return }
                seen.insert(dedupeKey)

                var usage = TokenUsageCounts()
                usage.inputTokens = max(0, promptTokens - cachedPromptTokens)
                usage.cacheReadInputTokens = cachedPromptTokens
                usage.outputTokens = completionTokens
                usage.reasoningOutputTokens = reasoningTokens
                usage.totalTokens = totalTokens

                let model = UsageCollector.modelKey(
                    sessionID.flatMap { modelBySession[$0] }
                )
                records.append(
                    UsageRecord(
                        date: day,
                        timestamp: timestamp,
                        tool: "Grok",
                        model: model,
                        usage: usage,
                        source: .nativeGrok,
                        requestID: dedupeKey,
                        sessionID: sessionID,
                        sourcePath: path.path,
                        lineNumber: lineNumber
                    )
                )
            }
        }

        UsageCollector.updateCache(
            path: path, tool: "Grok", records: records, cache: &cache
        )
        return CollectorResult(
            records: records,
            source: SourceInfo(
                status: records.isEmpty ? "missing" : "ok",
                files: 1,
                records: records.count
            )
        )
    }

    // MARK: - Session model resolution

    private static func grokSessionModels(homeURL: URL) -> [String: String] {
        let root = homeURL.appendingPathComponent(".grok/sessions", isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return [:]
        }

        var models: [String: String] = [:]
        for case let url as URL in enumerator {
            guard url.lastPathComponent == "summary.json",
                  let data = try? Data(contentsOf: url),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                continue
            }
            let sessionID = [
                (obj["info"] as? [String: Any])?["id"] as? String,
                obj["session_id"] as? String,
            ].compactMap(UsageCollector.nonEmptyString).first
            guard let sessionID,
                  let model = UsageCollector.nonEmptyString(obj["current_model_id"] as? String)
            else {
                continue
            }
            models[sessionID] = model
        }
        return models
    }
}
