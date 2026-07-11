import Foundation

/// How a model bills cache tokens. Anthropic charges cache-write and
/// cache-read at distinct rates; OpenAI bills cache-creation at the normal
/// input rate and only discounts cached reads. The two need different cost
/// arithmetic, so the style travels with the price. // [archer]
enum CostStyle: String, Codable {
    case anthropic
    case openai
}

/// Per-model pricing in USD per 1M tokens — the same unit models.dev uses,
/// so no conversion is needed. `cacheWrite` == cache-creation. // [archer]
struct ModelPrice: Codable, Equatable {
    var input: Double
    var output: Double
    var cacheWrite: Double
    var cacheRead: Double
    var style: CostStyle
}

/// A resolved pricing table. `models` is keyed by lowercased model id and is
/// populated from the models.dev cache when present; empty means "offline,
/// use the built-in family snapshot". // [archer]
struct PricingTable {
    var models: [String: ModelPrice]
    var generatedAt: Date?

    static let empty = PricingTable(models: [:], generatedAt: nil)
}

/// Single source of truth for token pricing.
///
/// Resolution chain (per `resolve`):
///   1. models.dev exact model-id match  (precise, current, from cache)
///   2. models.dev substring match        (version-suffix tolerance)
///   3. built-in family snapshot          (opus/sonnet/gpt-5.x — offline)
///   4. nil → caller applies a flat total-token heuristic
///
/// The snapshot reproduces the numbers that used to live inline in
/// `UsageCollector.estimateCost` / `SessionLiveUsageAggregator.estimateCost`, so offline
/// behaviour is byte-for-byte unchanged; a live models.dev cache only
/// *upgrades* precision. // [archer]
enum PricingProvider {
    // MARK: - Cache location

    static let cacheURL = AppPaths.appSupportRoot.appendingPathComponent("cache/pricing-cache.json")
    private static let endpoint = URL(string: "https://models.dev/api.json")!
    private static let ttl: TimeInterval = 24 * 3600

    // MARK: - Resolution

    /// models.dev override (if any) falling back to the built-in family
    /// snapshot. Returns nil only for models with no known family, letting the
    /// caller apply its flat-rate heuristic.
    static func resolve(tool: String, model: String, in table: PricingTable) -> ModelPrice? {
        let m = model.lowercased()
        if let exact = table.models[m] { return exact }
        var best: (key: String, price: ModelPrice)?
        for (key, price) in table.models where m.contains(key) || key.contains(m) {
            if best == nil || key.count > best!.key.count { best = (key, price) }
        }
        if let best { return best.price }
        return familyPrice(tool: tool, model: m)
    }

    /// Offline-only resolution against the built-in snapshot. Pure, no IO —
    /// safe to call from a SwiftUI `body`. `model` may already be lowercased.
    static func familyPrice(tool: String, model: String) -> ModelPrice? {
        let m = model.lowercased()
        if tool == "Codex", m.contains("gpt-5.5") {
            return ModelPrice(input: 5, output: 30, cacheWrite: 5, cacheRead: 0.5, style: .openai)
        }
        if tool == "Codex", m.contains("gpt-5.4") {
            return ModelPrice(input: 2.5, output: 15, cacheWrite: 2.5, cacheRead: 0.25, style: .openai)
        }
        if m.contains("opus") {
            return ModelPrice(input: 15, output: 75, cacheWrite: 18.75, cacheRead: 1.5, style: .anthropic)
        }
        if m.contains("sonnet") {
            return ModelPrice(input: 3, output: 15, cacheWrite: 3.75, cacheRead: 0.3, style: .anthropic)
        }
        return nil
    }

    // MARK: - Cost arithmetic (canonical — the only copy)

    static func cost(usage: TokenUsageCounts, price: ModelPrice) -> Double {
        switch price.style {
        case .anthropic:
            return anthropicCost(usage: usage, price: price)
        case .openai:
            return openAICost(usage: usage, price: price)
        }
    }

    private static func anthropicCost(usage: TokenUsageCounts, price: ModelPrice) -> Double {
        let creation = max(0, usage.cacheCreationInputTokens)
        let read = max(0, usage.cacheReadInputTokens)
        let rest = max(0, usage.inputTokens - creation - read)
        return Double(rest) / 1_000_000 * price.input
            + Double(creation) / 1_000_000 * price.cacheWrite
            + Double(read) / 1_000_000 * price.cacheRead
            + Double(usage.outputTokens + usage.reasoningOutputTokens) / 1_000_000 * price.output
    }

    private static func openAICost(usage: TokenUsageCounts, price: ModelPrice) -> Double {
        let cached = max(0, usage.cacheReadInputTokens)
        let uncachedInput = max(0, usage.inputTokens - cached)
        return Double(uncachedInput + usage.cacheCreationInputTokens) / 1_000_000 * price.input
            + Double(cached) / 1_000_000 * price.cacheRead
            + Double(usage.outputTokens + usage.reasoningOutputTokens) / 1_000_000 * price.output
    }

    // MARK: - Disk cache (synchronous read, used per collection pass)

    private struct CacheFile: Codable {
        var generatedAt: Double
        var models: [String: ModelPrice]
    }

    /// Synchronously load the models.dev cache, or `.empty` if absent/stale to
    /// parse. Cheap: the slim cache holds only cost objects. Reads the file
    /// each call (no shared mutable state) so it is safe off the main thread.
    static func table() -> PricingTable {
        guard let data = try? Data(contentsOf: cacheURL),
              let file = try? JSONDecoder().decode(CacheFile.self, from: data)
        else {
            return .empty
        }
        return PricingTable(models: file.models, generatedAt: Date(timeIntervalSince1970: file.generatedAt))
    }

    // MARK: - Refresh (async, off the collection path)

    /// Fire-and-forget refresh; safe to call every collection pass. The
    /// current pass uses whatever is already cached — a refresh only benefits
    /// the next one.
    static func refreshInBackgroundIfStale() {
        Task.detached(priority: .utility) { await refreshIfStale() }
    }

    static func refreshIfStale() async {
        if let mtime = try? FileManager.default.attributesOfItem(atPath: cacheURL.path)[.modificationDate] as? Date,
           Date().timeIntervalSince(mtime) < ttl
        {
            return
        }
        do {
            let (data, response) = try await URLSession.shared.data(from: endpoint)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return }
            let models = try parseModelsDev(data)
            guard !models.isEmpty else { return }
            let file = CacheFile(generatedAt: Date().timeIntervalSince1970, models: models)
            let encoded = try JSONEncoder().encode(file)
            try FileManager.default.createDirectory(
                at: cacheURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try encoded.write(to: cacheURL, options: .atomic)
        } catch {
            // Silent: a failed refresh just leaves the previous cache (or the
            // built-in snapshot) in place. Pricing is never blocked on network.
        }
    }

    /// Flatten models.dev's `{provider: {models: {id: {cost: {...}}}}}` into a
    /// lowercased id → ModelPrice map. Missing cache fields degrade gracefully.
    static func parseModelsDev(_ data: Data) throws -> [String: ModelPrice] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        var out: [String: ModelPrice] = [:]
        for (providerKey, providerValue) in root {
            guard let provider = providerValue as? [String: Any],
                  let models = provider["models"] as? [String: Any] else { continue }
            let style: CostStyle = providerKey.lowercased().contains("openai") ? .openai : .anthropic
            for (modelId, modelValue) in models {
                guard let model = modelValue as? [String: Any],
                      let costObj = model["cost"] as? [String: Any],
                      let input = numeric(costObj["input"]),
                      let output = numeric(costObj["output"]) else { continue }
                let cacheRead = numeric(costObj["cache_read"]) ?? 0
                let cacheWrite = numeric(costObj["cache_write"]) ?? input
                out[modelId.lowercased()] = ModelPrice(
                    input: input, output: output,
                    cacheWrite: cacheWrite, cacheRead: cacheRead, style: style
                )
            }
        }
        return out
    }

    private static func numeric(_ any: Any?) -> Double? {
        if let d = any as? Double { return d }
        if let i = any as? Int { return Double(i) }
        if let n = any as? NSNumber { return n.doubleValue }
        return nil
    }
}
