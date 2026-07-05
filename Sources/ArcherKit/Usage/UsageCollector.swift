import Foundation

enum AppPaths {
    static let appSupportRoot: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent("Archer", isDirectory: true)
    }()

    static let collectorCacheJSON = appSupportRoot.appendingPathComponent("cache/collector-cache.json")
}

/// Orchestrates usage collection across all native agent parsers plus the
/// ccSwitch proxy source. Individual parsers live under `Usage/Parsers/`;
/// this file keeps orchestration, shared I/O utilities, cache management,
/// deduplication, and aggregation. // [archer]
enum UsageCollector {
    private static let timezone = TimeZone(identifier: "Asia/Shanghai") ?? .current
    private static let maxRelevantLineBytes = 1_048_576
    private static let ccSwitchSourceName = "CC Switch Proxy"

    // ---- Parser registry ------------------------------------------------

    /// All native parsers in collection order (Codex → Claude → Grok → Hermes).
    /// ccSwitch is intentionally excluded — its signature and semantics differ. // [archer]
    private nonisolated(unsafe) static let parsers: [any UsageParser.Type] = [
        CodexParser.self,
        ClaudeCodeParser.self,
        GrokParser.self,
        HermesParser.self,
    ]

    // ---- Main entry point -----------------------------------------------

    static func collect(
        historyDays: Int = 180,
        includeCCSwitchProxyUsage: Bool = false,
        ccSwitchDatabaseURL: URL? = nil
    ) -> UsageSnapshot {
        // Refresh the models.dev pricing cache in the background; this pass
        // uses whatever is already on disk (or the built-in snapshot). // [archer]
        PricingProvider.refreshInBackgroundIfStale()

        var cache = loadCache()
        var livePaths = Set<String>()
        let sourceCutoff = sourceFileCutoffDate(historyDays: historyDays)

        // Loop over registered parsers — no per-agent hardcoding. // [archer]
        var allResults: [(label: String, result: CollectorResult)] = []
        var allRecords: [UsageRecord] = []

        for parser in parsers {
            let result = parser.collect(
                cache: &cache,
                livePaths: &livePaths,
                modifiedSince: sourceCutoff
            )
            allResults.append((parser.sourceLabel, result))
            allRecords.append(contentsOf: result.records)
        }

        var ccSwitch = includeCCSwitchProxyUsage
            ? collectCCSwitchProxyUsage(databaseURL: ccSwitchDatabaseURL)
            : CollectorResult(records: [], source: SourceInfo(status: "disabled", files: nil, records: 0))

        cache.files = cache.files.filter { livePaths.contains($0.key) }
        saveCache(cache)

        let deduped = deduplicateCrossSource(
            nativeRecords: allRecords,
            proxyRecords: ccSwitch.records
        )
        if includeCCSwitchProxyUsage {
            ccSwitch.source = sourceInfo(ccSwitch.source, annotatedWith: deduped)
        }

        var sources: [String: SourceInfo] = [:]
        for (label, result) in allResults {
            sources[label] = result.source
        }
        sources[ccSwitchSourceName] = ccSwitch.source

        return aggregate(records: deduped.records, sources: sources)
    }

    // ---- Forwarding shims (public API, backward-compat) -----------------

    /// Per-Claude-Code-session token totals for the Sessions dashboard's
    /// token column. Reuses `ClaudeCodeParser`'s JSONL parse path and
    /// re-folds by session instead of by day. // [archer]
    static func claudeSessionTokenTotals(
        historyDays: Int = 30,
        rootURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects", isDirectory: true)
    ) -> [String: Int] {
        var cache = CollectorCache()
        var livePaths = Set<String>()
        let result = ClaudeCodeParser.collectAsRecords(
            cache: &cache,
            livePaths: &livePaths,
            rootURL: rootURL,
            modifiedSince: sourceFileCutoffDate(historyDays: historyDays)
        )
        var totals: [String: Int] = [:]
        for record in result.records {
            guard let sessionID = record.sessionID else { continue }
            totals[sessionID, default: 0] += record.usage.totalTokens
        }
        return totals
    }

    /// Grok records for `UsageView` today-stats queries.
    static func grokRecords(
        homeURL: URL = FileManager.default.homeDirectoryForCurrentUser,
        modifiedSince cutoffDate: Date? = nil
    ) -> [UsageRecord] {
        var cache = CollectorCache()
        var livePaths = Set<String>()
        return GrokParser.collect(
            cache: &cache,
            livePaths: &livePaths,
            homeURL: homeURL,
            modifiedSince: cutoffDate
        ).records
    }

    /// Test-only entry point for Grok parser with custom home URL.
    static func collectGrokForTesting(
        homeURL: URL,
        modifiedSince cutoffDate: Date?
    ) -> (records: [UsageRecord], source: SourceInfo) {
        var cache = CollectorCache()
        var livePaths = Set<String>()
        let result = GrokParser.collect(
            cache: &cache,
            livePaths: &livePaths,
            homeURL: homeURL,
            modifiedSince: cutoffDate
        )
        return (result.records, result.source)
    }

    // ---- ccSwitch (not protocol — different signature/semantics) --------

    private static func collectCCSwitchProxyUsage(databaseURL: URL? = nil) -> CollectorResult {
        let database = databaseURL ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cc-switch/cc-switch.db")

        guard FileManager.default.fileExists(atPath: database.path),
              FileManager.default.isReadableFile(atPath: database.path)
        else {
            return CollectorResult(
                records: [],
                source: SourceInfo(status: "missing_db", files: 0, records: 0)
            )
        }

        guard let columns = sqliteJSONRows(database: database, query: "pragma table_info(proxy_request_logs)") else {
            return CollectorResult(
                records: [],
                source: SourceInfo(status: "schema_unreadable", files: 1, records: 0)
            )
        }

        guard !columns.isEmpty else {
            return CollectorResult(
                records: [],
                source: SourceInfo(status: "missing_table", files: 1, records: 0)
            )
        }

        let availableColumns = Set(columns.compactMap { $0["name"] as? String })
        let requiredColumns: Set = [
            "request_id", "app_type", "provider_id", "model", "request_model",
            "pricing_model", "input_tokens", "output_tokens", "cache_read_tokens",
            "cache_creation_tokens", "total_cost_usd", "status_code", "created_at",
        ]
        guard requiredColumns.isSubset(of: availableColumns),
              availableColumns.contains("data_source")
        else {
            return CollectorResult(
                records: [],
                source: SourceInfo(status: "schema_mismatch", files: 1, records: 0)
            )
        }

        let sessionColumn = availableColumns.contains("session_id") ? "session_id" : "null"
        let query = """
        select
            request_id,
            \(sessionColumn) as session_id,
            data_source,
            created_at,
            app_type,
            coalesce(nullif(pricing_model, ''), nullif(model, ''), nullif(request_model, ''), 'unknown') as display_model,
            coalesce(input_tokens, 0) as input_tokens,
            coalesce(output_tokens, 0) as output_tokens,
            coalesce(cache_read_tokens, 0) as cache_read_tokens,
            coalesce(cache_creation_tokens, 0) as cache_creation_tokens,
            cast(coalesce(nullif(total_cost_usd, ''), '0') as real) as total_cost_usd
        from proxy_request_logs
        where status_code >= 200
            and status_code < 300
            and lower(data_source) = 'proxy'
            and (
                coalesce(input_tokens, 0)
                + coalesce(output_tokens, 0)
                + coalesce(cache_read_tokens, 0)
                + coalesce(cache_creation_tokens, 0)
            ) > 0
        order by created_at, request_id
        """

        guard let rows = sqliteJSONRows(database: database, query: query) else {
            return CollectorResult(
                records: [],
                source: SourceInfo(status: "query_failed", files: 1, records: 0)
            )
        }

        let records = rows.compactMap { row -> UsageRecord? in
            guard let day = dayString(fromEpoch: row["created_at"] as Any) else {
                return nil
            }

            var usage = TokenUsageCounts()
            usage.inputTokens = integerValue(row["input_tokens"] as Any)
            usage.outputTokens = integerValue(row["output_tokens"] as Any)
            usage.cacheReadInputTokens = integerValue(row["cache_read_tokens"] as Any)
            usage.cacheCreationInputTokens = integerValue(row["cache_creation_tokens"] as Any)
            usage.totalTokens = usage.inputTokens
                + usage.outputTokens
                + usage.cacheReadInputTokens
                + usage.cacheCreationInputTokens
            guard usage.totalTokens > 0 else { return nil }

            return UsageRecord(
                date: day,
                timestamp: isoString(fromEpoch: row["created_at"] as Any),
                tool: ccSwitchToolName(appType: row["app_type"] as? String),
                model: modelKey(row["display_model"] as? String),
                usage: usage,
                costUSD: doubleValue(row["total_cost_usd"] as Any),
                source: .ccSwitchProxy,
                requestID: nonEmptyString(row["request_id"] as? String),
                sessionID: nonEmptyString(row["session_id"] as? String),
                dataSource: nonEmptyString(row["data_source"] as? String)
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

    // ---- Deduplication --------------------------------------------------

    private static func deduplicateCrossSource(
        nativeRecords: [UsageRecord],
        proxyRecords: [UsageRecord]
    ) -> CrossSourceDedupeResult {
        var enrichedNativeRecords = nativeRecords
        var keptProxyRecords: [UsageRecord] = []
        var dedupedProxyRecords = 0

        for proxyRecord in proxyRecords {
            guard isDeduplicableProxyRecord(proxyRecord) else {
                keptProxyRecords.append(proxyRecord)
                continue
            }

            if let nativeIndex = nativeRecords.firstIndex(where: { isDuplicate(proxyRecord: proxyRecord, nativeRecord: $0) }) {
                enrichedNativeRecords[nativeIndex] = enrichedRecord(
                    enrichedNativeRecords[nativeIndex],
                    withProxyCostFrom: proxyRecord
                )
                dedupedProxyRecords += 1
            } else {
                keptProxyRecords.append(proxyRecord)
            }
        }

        return CrossSourceDedupeResult(
            records: enrichedNativeRecords + keptProxyRecords,
            rawProxyRecords: proxyRecords.count,
            keptProxyRecords: keptProxyRecords.count,
            dedupedProxyRecords: dedupedProxyRecords,
            skippedProxyRecords: 0
        )
    }

    private static func sourceInfo(
        _ source: SourceInfo,
        annotatedWith result: CrossSourceDedupeResult
    ) -> SourceInfo {
        var annotated = source
        annotated.rawRecords = result.rawProxyRecords
        annotated.dedupedRecords = result.dedupedProxyRecords
        annotated.skippedRecords = result.skippedProxyRecords
        annotated.strategy = "request_level_dedupe"
        annotated.records = result.keptProxyRecords
        if source.status == "ok",
           result.rawProxyRecords > 0,
           result.keptProxyRecords == 0,
           result.dedupedProxyRecords > 0
        {
            annotated.status = "all_deduped"
        }
        return annotated
    }

    private static func isDeduplicableProxyRecord(_ record: UsageRecord) -> Bool {
        guard record.source == .ccSwitchProxy else { return false }
        guard let family = toolFamily(for: record.tool) else { return false }
        return family == "claude" || family == "codex"
    }

    private static func isDuplicate(proxyRecord: UsageRecord, nativeRecord: UsageRecord) -> Bool {
        guard proxyRecord.date == nativeRecord.date,
              let proxyFamily = toolFamily(for: proxyRecord.tool),
              let nativeFamily = toolFamily(for: nativeRecord.tool),
              proxyFamily == nativeFamily,
              nativeRecord.source != .ccSwitchProxy
        else {
            return false
        }

        if hasExactIdentityMatch(proxyRecord: proxyRecord, nativeRecord: nativeRecord) {
            return true
        }

        return hasStrongUsageMatch(proxyRecord: proxyRecord, nativeRecord: nativeRecord)
    }

    private static func hasExactIdentityMatch(proxyRecord: UsageRecord, nativeRecord: UsageRecord) -> Bool {
        let proxyIDs = Set([proxyRecord.requestID, proxyRecord.responseID].compactMap(nonEmptyString))
        let nativeIDs = Set([nativeRecord.requestID, nativeRecord.responseID].compactMap(nonEmptyString))
        if !proxyIDs.isDisjoint(with: nativeIDs) {
            return true
        }

        guard let proxySessionID = nonEmptyString(proxyRecord.sessionID),
              let nativeSessionID = nonEmptyString(nativeRecord.sessionID),
              proxySessionID == nativeSessionID,
              areTimestampsClose(proxyRecord.timestamp, nativeRecord.timestamp, seconds: 10),
              modelsCompatible(proxyRecord.model, nativeRecord.model),
              usageVectorsClose(proxyRecord.usage, nativeRecord.usage)
        else {
            return false
        }
        return true
    }

    private static func hasStrongUsageMatch(proxyRecord: UsageRecord, nativeRecord: UsageRecord) -> Bool {
        areTimestampsClose(proxyRecord.timestamp, nativeRecord.timestamp, seconds: 30)
            && modelsCompatible(proxyRecord.model, nativeRecord.model)
            && usageVectorsClose(proxyRecord.usage, nativeRecord.usage)
    }

    private static func enrichedRecord(
        _ nativeRecord: UsageRecord,
        withProxyCostFrom proxyRecord: UsageRecord
    ) -> UsageRecord {
        var record = nativeRecord
        if record.costUSD == nil,
           let proxyCost = proxyRecord.costUSD,
           proxyCost > 0
        {
            record.costUSD = proxyCost
        }
        return record
    }

    private static func toolFamily(for tool: String) -> String? {
        let value = tool.lowercased()
        if value.contains("claude") { return "claude" }
        if value.contains("codex") { return "codex" }
        if value.contains("gemini") { return "gemini" }
        if value.contains("hermes") { return "hermes" }
        return nil
    }

    private static func areTimestampsClose(_ lhs: String?, _ rhs: String?, seconds: TimeInterval) -> Bool {
        guard let lhs,
              let rhs,
              let lhsDate = parseISO(lhs),
              let rhsDate = parseISO(rhs)
        else {
            return false
        }
        return abs(lhsDate.timeIntervalSince(rhsDate)) <= seconds
    }

    private static func modelsCompatible(_ lhs: String, _ rhs: String) -> Bool {
        let left = canonicalModel(lhs)
        let right = canonicalModel(rhs)
        if left == right { return true }
        guard left != "unknown",
              right != "unknown",
              min(left.count, right.count) >= 8
        else {
            return false
        }
        return left.contains(right) || right.contains(left)
    }

    private static func canonicalModel(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
    }

    private static func usageVectorsClose(_ lhs: TokenUsageCounts, _ rhs: TokenUsageCounts) -> Bool {
        guard tokenValuesClose(lhs.totalTokens, rhs.totalTokens) else { return false }
        let pairs = [
            (lhs.inputTokens, rhs.inputTokens),
            (lhs.outputTokens, rhs.outputTokens),
            (lhs.cacheCreationInputTokens, rhs.cacheCreationInputTokens),
            (lhs.cacheReadInputTokens, rhs.cacheReadInputTokens),
            (lhs.reasoningOutputTokens, rhs.reasoningOutputTokens),
        ]
        return pairs.allSatisfy { pair in
            let left = pair.0
            let right = pair.1
            return left == 0 && right == 0 || tokenValuesClose(left, right)
        }
    }

    private static func tokenValuesClose(_ lhs: Int, _ rhs: Int) -> Bool {
        if lhs == rhs { return true }
        let baseline = max(lhs, rhs)
        guard baseline > 0 else { return true }
        let tolerance = max(4, Int((Double(baseline) * 0.01).rounded(.up)))
        return abs(lhs - rhs) <= tolerance
    }

    // ---- Aggregation ----------------------------------------------------

    private static func aggregate(records: [UsageRecord], sources: [String: SourceInfo]) -> UsageSnapshot {
        var daily = [String: DailyAccumulator]()
        var tools = [String: UsageAccumulator]()
        var models = [ModelKey: UsageAccumulator]()

        // Load the models.dev pricing table once per pass (synchronous read of
        // the slim cache, or the built-in snapshot when absent). // [archer]
        let pricing = PricingProvider.table()
        for record in records {
            let cost = record.costUSD ?? estimateCost(usage: record.usage, tool: record.tool, model: record.model, pricing: pricing)
            daily[record.date, default: DailyAccumulator(date: record.date)].add(record: record, cost: cost)
            tools[record.tool, default: UsageAccumulator()].add(record.usage, cost: cost)
            models[ModelKey(tool: record.tool, model: record.model), default: UsageAccumulator()].add(record.usage, cost: cost)
        }

        let totalTokens = tools.values.map(\.usage.totalTokens).reduce(0, +)
        let totalCost = tools.values.map(\.cost).reduce(0, +)

        let dailyRows = daily.values
            .sorted { $0.date < $1.date }
            .map { item in
                DailyUsage(
                    date: item.date,
                    tools: item.tools,
                    models: item.models,
                    totalTokens: item.totalTokens,
                    cost: rounded(item.cost, digits: 4)
                )
            }

        let toolRows = tools
            .sorted { $0.value.usage.totalTokens > $1.value.usage.totalTokens }
            .map { tool, item in
                ToolUsage(
                    tool: tool,
                    tokens: item.usage.totalTokens,
                    percent: percent(item.usage.totalTokens, of: totalTokens)
                )
            }

        let modelRows = models
            .sorted { $0.value.usage.totalTokens > $1.value.usage.totalTokens }
            .map { key, item in
                ModelUsage(
                    model: key.model,
                    tool: key.tool,
                    tokens: item.usage.totalTokens,
                    percent: percent(item.usage.totalTokens, of: totalTokens)
                )
            }

        return UsageSnapshot(
            generatedAt: isoFormatter.string(from: Date()),
            timezone: "Asia/Shanghai",
            totals: UsageTotals(
                tokens: totalTokens,
                cost: rounded(totalCost, digits: 2),
                activeDays: dailyRows.filter { $0.totalTokens > 0 }.count
            ),
            daily: dailyRows,
            tools: toolRows,
            models: modelRows,
            sources: sources
        )
    }

    // ---- File I/O utilities (internal — used by parsers) ----------------

    static func jsonlFiles(under root: URL, modifiedSince cutoffDate: Date? = nil) -> [URL] {
        guard FileManager.default.fileExists(atPath: root.path),
              let enumerator = FileManager.default.enumerator(
                  at: root,
                  includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
                  options: [.skipsHiddenFiles]
              )
        else {
            return []
        }

        return enumerator.compactMap { item in
            guard let url = item as? URL,
                  url.pathExtension == "jsonl",
                  let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey]),
                  values.isRegularFile == true
            else {
                return nil
            }
            if let cutoffDate,
               let modificationDate = values.contentModificationDate,
               modificationDate < cutoffDate
            {
                return nil
            }
            return url
        }
    }

    // ---- Cache utilities (internal — used by parsers) -------------------

    static func cachedRecords(for url: URL, tool: String, cache: CollectorCache) -> [UsageRecord]? {
        guard let metadata = fileMetadata(for: url),
              let cached = cache.files[url.path],
              cached.tool == tool,
              cached.size == metadata.size,
              abs(cached.modificationTime - metadata.modificationTime) < 0.001
        else {
            return nil
        }
        return cached.records
    }

    static func updateCache(path: URL, tool: String, records: [UsageRecord], cache: inout CollectorCache) {
        guard let metadata = fileMetadata(for: path) else { return }
        cache.files[path.path] = CachedUsageFile(
            tool: tool,
            size: metadata.size,
            modificationTime: metadata.modificationTime,
            records: records
        )
    }

    private static func fileMetadata(for url: URL) -> (size: UInt64, modificationTime: TimeInterval)? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
              let size = values.fileSize,
              let modificationDate = values.contentModificationDate
        else {
            return nil
        }
        return (UInt64(max(0, size)), modificationDate.timeIntervalSince1970)
    }

    private static func loadCache() -> CollectorCache {
        guard let data = try? Data(contentsOf: AppPaths.collectorCacheJSON),
              let cache = try? JSONDecoder().decode(CollectorCache.self, from: data),
              cache.version == CollectorCache.currentVersion
        else {
            return CollectorCache()
        }
        return cache
    }

    private static func saveCache(_ cache: CollectorCache) {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(cache)
            try FileManager.default.createDirectory(
                at: AppPaths.collectorCacheJSON.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: AppPaths.collectorCacheJSON, options: .atomic)
        } catch {
            // Cache misses should never prevent the app from showing fresh usage.
        }
    }

    private static func sourceFileCutoffDate(historyDays: Int) -> Date? {
        Calendar.current.date(byAdding: .day, value: -max(7, historyDays + 1), to: Date())
    }

    // ---- Line streaming (internal — used by parsers) --------------------

    static func forEachLine(in url: URL, matchingAny markers: [String] = [], _ body: (String) -> Void) throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        let newline = Data([0x0A])
        let markerData = markers.map { Data($0.utf8) }
        var buffer = Data()
        buffer.reserveCapacity(128 * 1024)
        var discardingOversizedLine = false

        func processLine(_ lineData: Data) {
            guard lineMatches(lineData, markers: markerData),
                  let line = String(data: lineData, encoding: .utf8),
                  !line.isEmpty
            else {
                return
            }
            body(line)
        }

        while true {
            guard let chunk = try handle.read(upToCount: 64 * 1024), !chunk.isEmpty else {
                break
            }
            buffer.append(chunk)

            var consumedEnd = buffer.startIndex
            var lineStart = buffer.startIndex
            var searchRange = buffer.startIndex ..< buffer.endIndex
            while let range = buffer.range(of: newline, options: [], in: searchRange) {
                let lineEnd = range.lowerBound
                if discardingOversizedLine {
                    discardingOversizedLine = false
                } else if lineEnd > lineStart {
                    let lineData = buffer.subdata(in: lineStart ..< lineEnd)
                    processLine(lineData)
                }
                consumedEnd = range.upperBound
                lineStart = range.upperBound
                searchRange = lineStart ..< buffer.endIndex
            }

            if consumedEnd > buffer.startIndex {
                buffer.removeSubrange(buffer.startIndex ..< consumedEnd)
            }

            if buffer.count > maxRelevantLineBytes {
                discardingOversizedLine = true
                buffer.removeAll(keepingCapacity: true)
            }
        }

        if !discardingOversizedLine,
           !buffer.isEmpty,
           buffer.count <= maxRelevantLineBytes
        {
            processLine(buffer)
        }
    }

    private static func lineMatches(_ data: Data, markers: [Data]) -> Bool {
        markers.isEmpty || markers.contains { data.range(of: $0) != nil }
    }

    // ---- JSON helpers (internal — used by parsers) ----------------------

    static func jsonObject(_ line: String) -> [String: Any]? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any]
        else {
            return nil
        }
        return dictionary
    }

    static func normalizeUsage(_ raw: [String: Any]?) -> TokenUsageCounts {
        guard let raw else { return TokenUsageCounts() }
        var usage = TokenUsageCounts()
        let aliases = [
            "input": "inputTokens", "output": "outputTokens", "cached": "cacheReadInputTokens",
            "thoughts": "reasoningOutputTokens", "total": "totalTokens", "input_tokens": "inputTokens",
            "output_tokens": "outputTokens", "cache_creation_input_tokens": "cacheCreationInputTokens",
            "cache_read_input_tokens": "cacheReadInputTokens", "cached_input_tokens": "cacheReadInputTokens",
            "reasoning_output_tokens": "reasoningOutputTokens", "total_tokens": "totalTokens",
        ]

        for (key, value) in raw {
            guard let mapped = aliases[key] else { continue }
            let intValue = integerValue(value)
            switch mapped {
            case "inputTokens": usage.inputTokens += intValue
            case "outputTokens": usage.outputTokens += intValue
            case "cacheCreationInputTokens": usage.cacheCreationInputTokens += intValue
            case "cacheReadInputTokens": usage.cacheReadInputTokens += intValue
            case "reasoningOutputTokens": usage.reasoningOutputTokens += intValue
            case "totalTokens": usage.totalTokens += intValue
            default: break
            }
        }

        if usage.totalTokens <= 0 {
            usage.totalTokens = usage.inputTokens
                + usage.outputTokens
                + usage.cacheCreationInputTokens
                + usage.cacheReadInputTokens
                + usage.reasoningOutputTokens
        }
        return usage
    }

    // ---- Value coercion (internal — used by parsers) --------------------

    static func integerValue(_ value: Any) -> Int {
        if let int = value as? Int { return int }
        if let double = value as? Double { return Int(double) }
        if let string = value as? String { return Int(string) ?? 0 }
        return 0
    }

    static func doubleValue(_ value: Any) -> Double {
        if let double = value as? Double { return double }
        if let int = value as? Int { return Double(int) }
        if let string = value as? String { return Double(string) ?? 0 }
        return 0
    }

    static func nonEmptyString(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // ---- Date helpers (internal — used by parsers) ----------------------

    static func dayString(fromISO value: String) -> String? {
        guard let date = parseISO(value) else { return nil }
        return dayFormatter.string(from: date)
    }

    static func dayString(fromEpoch value: Any?) -> String? {
        guard let seconds = epochSeconds(value) else { return nil }
        return dayFormatter.string(from: Date(timeIntervalSince1970: seconds))
    }

    static func isoString(fromEpoch value: Any?) -> String? {
        guard let seconds = epochSeconds(value) else { return nil }
        return isoFormatter.string(from: Date(timeIntervalSince1970: seconds))
    }

    private static func epochSeconds(_ value: Any?) -> Double? {
        var seconds: Double
        if let int = value as? Int {
            seconds = Double(int)
        } else if let double = value as? Double {
            seconds = double
        } else if let string = value as? String, let parsed = Double(string) {
            seconds = parsed
        } else {
            return nil
        }
        if seconds > 10_000_000_000 {
            seconds /= 1000
        }
        return seconds
    }

    static func parseISO(_ value: String) -> Date? {
        if let date = isoFormatterWithFractional.date(from: value) {
            return date
        }
        return isoFormatter.date(from: value)
    }

    // ---- Model key (internal — used by parsers) -------------------------

    static func modelKey(_ model: String?) -> String {
        let value = (model ?? "unknown").trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "unknown" : value
    }

    // ---- ccSwitch helpers -----------------------------------------------

    private static func ccSwitchToolName(appType: String?) -> String {
        let value = (appType ?? "unknown").trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = value.lowercased()
        switch normalized {
        case "claude":
            return "Claude Code via CC Switch"
        case "codex":
            return "Codex via CC Switch"
        case "gemini":
            return "Gemini via CC Switch"
        default:
            return "\(value.isEmpty ? "unknown" : value) via CC Switch (experimental)"
        }
    }

    // ---- SQLite helper (internal — used by parsers) ---------------------

    static func sqliteJSONRows(database: URL, query: String) -> [[String: Any]]? {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tokenstep-sqlite-\(UUID().uuidString).json")
        _ = FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        guard let outputHandle = try? FileHandle(forWritingTo: outputURL) else {
            return nil
        }
        defer {
            try? outputHandle.close()
            try? FileManager.default.removeItem(at: outputURL)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = ["-readonly", "-json", database.path, query]
        process.standardOutput = outputHandle
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }

        let data = (try? Data(contentsOf: outputURL)) ?? Data()
        guard !data.isEmpty else { return [] }
        return try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
    }

    // ---- Cost estimation ------------------------------------------------

    /// Cost for one record when the source didn't report one. Pricing numbers
    /// come from `PricingProvider` (models.dev cache → built-in family
    /// snapshot); only the flat total-token heuristic for unknown families
    /// stays here. // [archer]
    private static func estimateCost(usage: TokenUsageCounts, tool: String, model: String, pricing: PricingTable) -> Double {
        if let price = PricingProvider.resolve(tool: tool, model: model, in: pricing) {
            return PricingProvider.cost(usage: usage, price: price)
        }
        if tool == "Claude Code" {
            return Double(usage.totalTokens) / 1_000_000 * 3
        }
        return Double(usage.totalTokens) / 1_000_000
    }

    private static func percent(_ subset: Int, of total: Int) -> Double {
        guard total > 0 else { return 0 }
        return Double(subset) / Double(total)
    }

    private static func rounded(_ value: Double, digits: Int) -> Double {
        let mult = pow(10.0, Double(digits))
        return (value * mult).rounded() / mult
    }

    // ---- Formatters -----------------------------------------------------

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private nonisolated(unsafe) static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private nonisolated(unsafe) static let isoFormatterWithFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

// MARK: - Private types

private struct CrossSourceDedupeResult {
    var records: [UsageRecord]
    var rawProxyRecords: Int
    var keptProxyRecords: Int
    var dedupedProxyRecords: Int
    var skippedProxyRecords: Int
}

private struct UsageAccumulator {
    var usage = TokenUsageCounts()
    var cost = 0.0

    mutating func add(_ counts: TokenUsageCounts, cost: Double) {
        usage.inputTokens += counts.inputTokens
        usage.outputTokens += counts.outputTokens
        usage.cacheCreationInputTokens += counts.cacheCreationInputTokens
        usage.cacheReadInputTokens += counts.cacheReadInputTokens
        usage.reasoningOutputTokens += counts.reasoningOutputTokens
        usage.totalTokens += counts.totalTokens
        self.cost += cost
    }
}

private struct DailyAccumulator {
    var date: String
    var tools: [String: Int] = [:]
    var models: [String: Int] = [:]
    var totalTokens = 0
    var cost = 0.0

    mutating func add(record: UsageRecord, cost: Double) {
        tools[record.tool, default: 0] += record.usage.totalTokens
        models[record.model, default: 0] += record.usage.totalTokens
        totalTokens += record.usage.totalTokens
        self.cost += cost
    }
}

private struct ModelKey: Hashable {
    var tool: String
    var model: String
}

/// Returned by each parser's `collect()` — lightweight value type. // [archer]
struct CollectorResult {
    var records: [UsageRecord]
    var source: SourceInfo
}
