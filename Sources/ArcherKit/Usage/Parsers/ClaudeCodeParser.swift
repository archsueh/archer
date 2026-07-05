import Foundation

/// Collects Claude Code usage from `~/.claude/projects/**/*.jsonl`.
///
/// Deduplicates assistant messages within each file by preferring the
/// best-quality candidate (has stop_reason → latest timestamp → highest
/// line number). // [archer]
enum ClaudeCodeParser: UsageParser {
    static let sourceLabel = "Claude Code"

    static func collect(
        cache: inout CollectorCache,
        livePaths: inout Set<String>,
        modifiedSince cutoffDate: Date?
    ) -> CollectorResult {
        collectFromProjects(
            cache: &cache,
            livePaths: &livePaths,
            modifiedSince: cutoffDate
        )
    }

    /// Per-session token totals entry point used by `UsageCollector`
    /// forwarding shim. Creates a throwaway cache and re-folds records
    /// by session ID. // [archer]
    static func collectAsRecords(
        cache: inout CollectorCache,
        livePaths: inout Set<String>,
        rootURL: URL,
        modifiedSince cutoffDate: Date?
    ) -> CollectorResult {
        collectFromProjects(
            cache: &cache,
            livePaths: &livePaths,
            rootURL: rootURL,
            modifiedSince: cutoffDate
        )
    }

    // MARK: - Implementation

    private static func collectFromProjects(
        cache: inout CollectorCache,
        livePaths: inout Set<String>,
        rootURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects", isDirectory: true),
        modifiedSince cutoffDate: Date?
    ) -> CollectorResult {
        let paths = UsageCollector.jsonlFiles(under: rootURL, modifiedSince: cutoffDate)
        var records: [UsageRecord] = []

        for path in paths.sorted(by: { $0.path < $1.path }) {
            livePaths.insert(path.path)
            if let cached = UsageCollector.cachedRecords(
                for: path, tool: "Claude Code", cache: cache
            ) {
                records.append(contentsOf: cached)
                continue
            }

            var fileRecords: [UsageRecord] = []
            var responses = [String: Candidate]()
            guard FileManager.default.isReadableFile(atPath: path.path) else { continue }

            var lineNumber = 0
            try? UsageCollector.forEachLine(in: path, matchingAny: ["usage"]) { line in
                autoreleasepool {
                    lineNumber += 1
                    guard let obj = UsageCollector.jsonObject(line),
                          obj["type"] as? String == "assistant",
                          let message = obj["message"] as? [String: Any]
                    else {
                        return
                    }

                    let usage = UsageCollector.normalizeUsage(
                        message["usage"] as? [String: Any]
                    )
                    guard usage.totalTokens > 0,
                          let timestamp = obj["timestamp"] as? String,
                          let day = UsageCollector.dayString(fromISO: timestamp)
                    else {
                        return
                    }

                    let identity = claudeIdentity(
                        obj: obj, message: message,
                        path: path, lineNumber: lineNumber
                    )
                    let candidate = Candidate(
                        date: day,
                        timestamp: timestamp,
                        model: UsageCollector.modelKey(message["model"] as? String),
                        usage: usage,
                        hasStopReason: hasStopReason(message["stop_reason"]),
                        lineNumber: lineNumber,
                        requestID: identity.requestID,
                        responseID: identity.responseID,
                        sessionID: identity.sessionID,
                        sourcePath: path.path
                    )
                    if let existing = responses[identity.deduplicationKey],
                       !candidate.isPreferred(over: existing)
                    {
                        return
                    }
                    responses[identity.deduplicationKey] = candidate
                }
            }
            fileRecords = responses.values.map(\.record)
            records.append(contentsOf: fileRecords)
            UsageCollector.updateCache(
                path: path,
                tool: "Claude Code",
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

    // MARK: - Identity helpers

    private static func claudeIdentity(
        obj: [String: Any],
        message: [String: Any],
        path: URL,
        lineNumber: Int
    ) -> Identity {
        let responseID = UsageCollector.nonEmptyString(message["id"] as? String)
        let requestID = [
            obj["requestId"] as? String,
            obj["request_id"] as? String,
            message["requestId"] as? String,
            message["request_id"] as? String,
        ].compactMap(UsageCollector.nonEmptyString).first
        let sessionID = [
            obj["sessionId"] as? String,
            obj["session_id"] as? String,
            obj["sessionID"] as? String,
        ].compactMap(UsageCollector.nonEmptyString).first
        let uuid = UsageCollector.nonEmptyString(obj["uuid"] as? String)

        let deduplicationKey: String
        if let responseID {
            deduplicationKey = "response:\(responseID)"
        } else if let requestID {
            deduplicationKey = "request:\(requestID)"
        } else if let uuid {
            deduplicationKey = "uuid:\(uuid)"
        } else {
            deduplicationKey = "line:\(path.path):\(lineNumber)"
        }
        return Identity(
            deduplicationKey: deduplicationKey,
            requestID: requestID,
            responseID: responseID,
            sessionID: sessionID
        )
    }

    private static func hasStopReason(_ value: Any?) -> Bool {
        guard let text = value as? String else { return false }
        return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// MARK: - Private types

extension ClaudeCodeParser {
    private struct Identity {
        var deduplicationKey: String
        var requestID: String?
        var responseID: String?
        var sessionID: String?
    }

    private struct Candidate {
        var date: String
        var timestamp: String
        var model: String
        var usage: TokenUsageCounts
        var hasStopReason: Bool
        var lineNumber: Int
        var requestID: String?
        var responseID: String?
        var sessionID: String?
        var sourcePath: String

        var record: UsageRecord {
            UsageRecord(
                date: date,
                timestamp: timestamp,
                tool: "Claude Code",
                model: model,
                usage: usage,
                source: .nativeClaudeCode,
                requestID: requestID,
                sessionID: sessionID,
                responseID: responseID,
                sourcePath: sourcePath,
                lineNumber: lineNumber
            )
        }

        func isPreferred(over other: Candidate) -> Bool {
            if hasStopReason != other.hasStopReason {
                return hasStopReason
            }
            if timestamp != other.timestamp {
                return timestamp > other.timestamp
            }
            return lineNumber > other.lineNumber
        }
    }
}
