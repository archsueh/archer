import Foundation

// [archer] Per-agent-session cost/token totals for the pane status-bar pill.
// Folded from UsageRecord rows that share a sessionID — same pricing path as
// UsageCollector so the pill and Usage panel stay consistent.

/// Snapshot of one agent conversation's cumulative spend. // [archer]
struct SessionLiveUsage: Equatable {
    var tokens: Int
    var costUSD: Double
    /// True when any record lacked a source-reported `costUSD` and we priced
    /// via `PricingProvider` / flat fallback. // [archer]
    var estimated: Bool
    var model: String?
    var inputTokens: Int
    var outputTokens: Int
    var cacheReadTokens: Int
    var cacheWriteTokens: Int

    static let empty = SessionLiveUsage(
        tokens: 0, costUSD: 0, estimated: false, model: nil,
        inputTokens: 0, outputTokens: 0, cacheReadTokens: 0, cacheWriteTokens: 0
    )
}

/// Maps an agent template to the UsageCollector `tool` label that owns its
/// session-keyed records. Nil = no live session cost support yet
/// (Pi/omp capture conversationId but have no usage parser; most CLIs
/// never report a conversation id). // [archer]
enum SessionLiveUsageSource {
    /// Usage tool label for this agent, if session cost is supported.
    static func toolLabel(for agent: AgentTemplate) -> String? {
        toolLabel(agentKey: agent.baseAgentId ?? agent.id)
    }

    static func toolLabel(agentKey: String) -> String? {
        switch agentKey {
        case AgentTemplate.claudeCodeID: return "Claude Code"
        case "grok": return "Grok"
        case "codex": return "Codex"
        default: return nil
        }
    }

    /// Agent ids that expose a Settings → Status Bar session-cost toggle.
    static let settingsAgentIDs: Set<String> = [
        AgentTemplate.claudeCodeID,
        "grok",
        "codex",
    ]

    /// Prefer hook `conversationId`. Codex falls back to the cwd-matched
    /// rollout's `session_meta.id`. // [archer]
    static func resolveSessionKey(
        tool: String,
        conversationId: String?,
        cwd: URL
    ) -> String? {
        if let cid = conversationId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !cid.isEmpty
        {
            return cid
        }
        if tool == "Codex" {
            return CodexUsageMonitor.resolveSessionID(forCwd: cwd)
        }
        return nil
    }
}

/// Pure fold + display formatters for session live usage. // [archer]
enum SessionLiveUsageAggregator {
    /// Aggregates records that already belong to one session. Returns nil when
    /// there is nothing to show (no rows, or zero tokens and zero cost). // [archer]
    static func fold(_ records: [UsageRecord], pricing: PricingTable) -> SessionLiveUsage? {
        guard !records.isEmpty else { return nil }

        var tokens = 0
        var cost = 0.0
        var estimated = false
        var lastModel: String?
        var input = 0
        var output = 0
        var cacheRead = 0
        var cacheWrite = 0

        for record in records {
            tokens += record.usage.totalTokens
            input += record.usage.inputTokens
            output += record.usage.outputTokens + record.usage.reasoningOutputTokens
            cacheRead += record.usage.cacheReadInputTokens
            cacheWrite += record.usage.cacheCreationInputTokens

            if let reported = record.costUSD {
                cost += reported
            } else {
                cost += estimateCost(
                    usage: record.usage,
                    tool: record.tool,
                    model: record.model,
                    pricing: pricing
                )
                estimated = true
            }
            if !record.model.isEmpty {
                lastModel = record.model
            }
        }

        guard tokens > 0 || cost > 0 else { return nil }

        return SessionLiveUsage(
            tokens: tokens,
            costUSD: roundCost(cost),
            estimated: estimated,
            model: lastModel,
            inputTokens: input,
            outputTokens: output,
            cacheReadTokens: cacheRead,
            cacheWriteTokens: cacheWrite
        )
    }

    /// Same arithmetic as `UsageCollector.estimateCost` — keep in sync. // [archer]
    static func estimateCost(
        usage: TokenUsageCounts,
        tool: String,
        model: String,
        pricing: PricingTable
    ) -> Double {
        if let price = PricingProvider.resolve(tool: tool, model: model, in: pricing) {
            return PricingProvider.cost(usage: usage, price: price)
        }
        if tool == "Claude Code" {
            return Double(usage.totalTokens) / 1_000_000 * 3
        }
        return Double(usage.totalTokens) / 1_000_000
    }

    /// `$0.42` / `$1.23` / `$12.3` / `$0.0042` for tiny amounts. // [archer]
    static func costText(_ cost: Double) -> String {
        if cost < 0.01 && cost > 0 {
            return String(format: "$%.4f", cost)
        }
        if cost < 10 {
            return String(format: "$%.2f", cost)
        }
        if cost < 100 {
            return String(format: "$%.1f", cost)
        }
        return String(format: "$%.0f", cost)
    }

    /// Compact token count: `128.4k` / `1.2M` / `842`. // [archer]
    static func tokensText(_ tokens: Int) -> String {
        if tokens >= 1_000_000 {
            return String(format: "%.1fM", Double(tokens) / 1_000_000)
        }
        if tokens >= 10000 {
            return "\(tokens / 1000)k"
        }
        if tokens >= 1000 {
            return String(format: "%.1fk", Double(tokens) / 1000)
        }
        return "\(tokens)"
    }

    private static func roundCost(_ value: Double) -> Double {
        (value * 10000).rounded() / 10000
    }
}
