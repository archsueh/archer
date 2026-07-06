import Foundation

/// Collects Gemini CLI usage from `~/.gemini/tmp/<project-hash>/chats/
/// session-*.json`. Each session file is one JSON object whose `messages`
/// carry per-turn `tokens {input, output, cached, thoughts}` on entries of
/// `type == "gemini"`.
///
/// Note this is the *stock* google-gemini/gemini-cli layout — distinct from
/// Antigravity CLI, whose protobuf conversation DB under
/// `~/.gemini/antigravity-cli/` genuinely has no plain-text token source
/// (that one stays unparsed; agy usage flows in via HermesParser).
///
/// `thoughts` folds into output: Gemini bills thinking tokens at the output
/// rate. `cached` maps to cache reads. // [archer]
enum GeminiParser: UsageParser {
    static let sourceLabel = "Gemini"

    static func collect(
        cache: inout CollectorCache,
        livePaths: inout Set<String>,
        modifiedSince cutoffDate: Date?
    ) -> CollectorResult {
        collect(
            cache: &cache,
            livePaths: &livePaths,
            homeURL: FileManager.default.homeDirectoryForCurrentUser,
            modifiedSince: cutoffDate
        )
    }

    /// Testable entry point that accepts a custom home URL.
    static func collect(
        cache: inout CollectorCache,
        livePaths: inout Set<String>,
        homeURL: URL,
        modifiedSince cutoffDate: Date?
    ) -> CollectorResult {
        let tmpRoot = homeURL.appendingPathComponent(".gemini/tmp", isDirectory: true)
        let paths = sessionFiles(under: tmpRoot, modifiedSince: cutoffDate)
        guard !paths.isEmpty else {
            return CollectorResult(
                records: [],
                source: SourceInfo(status: "missing", files: 0, records: 0)
            )
        }

        var records: [UsageRecord] = []
        for path in paths.sorted(by: { $0.path < $1.path }) {
            livePaths.insert(path.path)
            if let cached = UsageCollector.cachedRecords(for: path, tool: sourceLabel, cache: cache) {
                records.append(contentsOf: cached)
                continue
            }
            guard FileManager.default.isReadableFile(atPath: path.path),
                  let data = try? Data(contentsOf: path)
            else { continue }
            let fileRecords = parseSession(data, sourcePath: path.path)
            records.append(contentsOf: fileRecords)
            UsageCollector.updateCache(path: path, tool: sourceLabel, records: fileRecords, cache: &cache)
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

    /// Parses one session file into records. Static + pure for fixture tests.
    static func parseSession(_ data: Data, sourcePath: String? = nil) -> [UsageRecord] {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let messages = obj["messages"] as? [[String: Any]]
        else { return [] }
        let sessionID = obj["sessionId"] as? String

        var records: [UsageRecord] = []
        var lineNumber = 0
        for message in messages {
            lineNumber += 1
            guard message["type"] as? String == "gemini",
                  let tokens = message["tokens"] as? [String: Any]
            else { continue }

            let input = UsageCollector.integerValue(tokens["input"] as Any)
            let output = UsageCollector.integerValue(tokens["output"] as Any)
            let cached = UsageCollector.integerValue(tokens["cached"] as Any)
            let thoughts = UsageCollector.integerValue(tokens["thoughts"] as Any)

            var usage = TokenUsageCounts()
            usage.inputTokens = input
            usage.outputTokens = output + thoughts
            usage.cacheReadInputTokens = cached
            usage.reasoningOutputTokens = thoughts
            usage.totalTokens = input + output + thoughts + cached
            guard usage.totalTokens > 0,
                  let timestamp = message["timestamp"] as? String,
                  let day = UsageCollector.dayString(fromISO: timestamp)
            else { continue }

            records.append(
                UsageRecord(
                    date: day,
                    timestamp: timestamp,
                    tool: sourceLabel,
                    model: UsageCollector.modelKey(message["model"] as? String),
                    usage: usage,
                    source: .nativeGemini,
                    requestID: message["id"] as? String,
                    sessionID: sessionID,
                    sourcePath: sourcePath,
                    lineNumber: lineNumber
                )
            )
        }
        return records
    }

    /// `<tmp>/<project-hash>/chats/session-*.json` — one glob level deep,
    /// mirroring how the CLI shards sessions per project hash.
    private static func sessionFiles(under tmpRoot: URL, modifiedSince cutoffDate: Date?) -> [URL] {
        let fm = FileManager.default
        guard let hashDirs = try? fm.contentsOfDirectory(
            at: tmpRoot, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return [] }

        var result: [URL] = []
        for hashDir in hashDirs {
            let chats = hashDir.appendingPathComponent("chats", isDirectory: true)
            guard let files = try? fm.contentsOfDirectory(
                at: chats, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]
            ) else { continue }
            for file in files {
                let name = file.lastPathComponent
                guard name.hasPrefix("session-"), name.hasSuffix(".json") else { continue }
                if let cutoffDate,
                   let values = try? file.resourceValues(forKeys: [.contentModificationDateKey]),
                   let modified = values.contentModificationDate,
                   modified < cutoffDate
                {
                    continue
                }
                result.append(file)
            }
        }
        return result
    }
}
