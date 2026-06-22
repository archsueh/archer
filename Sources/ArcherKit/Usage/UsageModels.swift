import Foundation
import SwiftUI

/// Local helper for localization fallback
private func L(_ key: String) -> String {
    return key
}

private func LFormat(_ format: String, _ arguments: CVarArg...) -> String {
    return String(format: format, arguments)
}

struct UsageSnapshot: Codable {
    var generatedAt: String?
    var timezone: String?
    var totals: UsageTotals
    var daily: [DailyUsage]
    var tools: [ToolUsage]
    var models: [ModelUsage]
    var sources: [String: SourceInfo]
    var records: [UsageRecord]?

    enum CodingKeys: String, CodingKey {
        case generatedAt = "generated_at"
        case timezone
        case totals
        case daily
        case tools
        case models
        case sources
        case records
    }

    static let empty = UsageSnapshot(
        generatedAt: nil,
        timezone: "Asia/Shanghai",
        totals: UsageTotals(tokens: 0, cost: 0, activeDays: 0),
        daily: [],
        tools: [],
        models: [],
        sources: [:],
        records: []
    )
}

struct UsageTotals: Codable {
    var tokens: Int
    var cost: Double
    var activeDays: Int

    enum CodingKeys: String, CodingKey {
        case tokens
        case cost
        case activeDays = "active_days"
    }
}

struct DailyUsage: Codable, Identifiable {
    var id: String {
        date
    }

    var date: String
    var tools: [String: Int]
    var models: [String: Int]
    var totalTokens: Int
    var cost: Double

    enum CodingKeys: String, CodingKey {
        case date
        case tools
        case models
        case totalTokens = "total_tokens"
        case cost
    }

    init(date: String, tools: [String: Int], models: [String: Int] = [:], totalTokens: Int, cost: Double) {
        self.date = date
        self.tools = tools
        self.models = models
        self.totalTokens = totalTokens
        self.cost = cost
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        date = try container.decode(String.self, forKey: .date)
        tools = try container.decodeIfPresent([String: Int].self, forKey: .tools) ?? [:]
        models = try container.decodeIfPresent([String: Int].self, forKey: .models) ?? [:]
        totalTokens = try container.decode(Int.self, forKey: .totalTokens)
        cost = try container.decode(Double.self, forKey: .cost)
    }
}

struct ToolUsage: Codable, Identifiable {
    var id: String {
        tool
    }

    var tool: String
    var tokens: Int
    var percent: Double?

    var percentValue: Double {
        percent ?? 0
    }
}

struct ModelUsage: Codable, Identifiable {
    var id: String {
        "\(model)-\(tool ?? "")"
    }

    var model: String
    var tool: String?
    var tokens: Int
    var percent: Double?

    var percentValue: Double {
        percent ?? 0
    }
}

struct SourceInfo: Codable {
    var status: String?
    var files: Int?
    var records: Int?
    var rawRecords: Int?
    var dedupedRecords: Int?
    var skippedRecords: Int?
    var strategy: String?

    enum CodingKeys: String, CodingKey {
        case status
        case files
        case records
        case rawRecords = "raw_records"
        case dedupedRecords = "deduped_records"
        case skippedRecords = "skipped_records"
        case strategy
    }
}

struct TokenStepLapProgress {
    var tokens: Int
    var goal: Int

    var safeGoal: Int {
        max(goal, 1)
    }

    var rawProgress: Double {
        Double(tokens) / Double(safeGoal)
    }

    var completedLaps: Int {
        tokens / safeGoal
    }

    var currentLap: Int {
        guard tokens > 0 else { return 1 }
        let remainder = tokens % safeGoal
        return max(1, completedLaps + (remainder > 0 ? 1 : 0))
    }

    var currentLapProgress: Double {
        guard tokens > 0 else { return 0 }
        let remainder = tokens % safeGoal
        if remainder == 0 { return 1 }
        return Double(remainder) / Double(safeGoal)
    }

    var currentLapPercent: Double {
        currentLapProgress * 100
    }

    var color: Color {
        Self.color(for: currentLap)
    }

    var lapTitle: String {
        return "第 \(currentLap) 圈"
    }

    var lapPercentText: String {
        return String(format: "%.0f%%", currentLapPercent)
    }

    var lapStatusText: String {
        return "第 \(currentLap) 圈 · \(lapPercentText)"
    }

    var completedLapsText: String {
        return "已完成 \(completedLaps) 圈"
    }

    var completedTokensText: String {
        return "已完成 \(formatTokensCompact(completedLaps * safeGoal))"
    }

    var perLapGoalText: String {
        return "每圈目标 \(formatTokensCompact(safeGoal))"
    }

    static func color(for lap: Int) -> Color {
        switch max(lap, 1) {
        case 1: return Color(red: 45 / 255, green: 164 / 255, blue: 78 / 255) // Green
        case 2: return Color(red: 14 / 255, green: 165 / 255, blue: 233 / 255) // Blue
        case 3: return Color(red: 139 / 255, green: 92 / 255, blue: 246 / 255) // Violet
        default: return Color(red: 245 / 255, green: 158 / 255, blue: 11 / 255) // Amber
        }
    }

    private func formatTokensCompact(_ count: Int) -> String {
        if count >= 1_000_000_000 {
            return String(format: "%.1fB", Double(count) / 1_000_000_000.0)
        } else if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000.0)
        } else if count >= 1000 {
            return String(format: "%.1fK", Double(count) / 1000.0)
        }
        return "\(count)"
    }
}

struct UsageRecord: Codable {
    var date: String
    var timestamp: String?
    var tool: String
    var model: String
    var usage: TokenUsageCounts
    var costUSD: Double? = nil
    var source: UsageRecordSource = .unknown
    var requestID: String? = nil
    var sessionID: String? = nil
    var responseID: String? = nil
    var sourcePath: String? = nil
    var lineNumber: Int? = nil
    var dataSource: String? = nil
}

enum UsageRecordSource: String, Codable {
    case nativeCodex
    case nativeCodexSQLite
    case nativeClaudeCode
    case nativeHermes
    case ccSwitchProxy
    case unknown
}

struct TokenUsageCounts: Codable {
    var inputTokens = 0
    var outputTokens = 0
    var cacheCreationInputTokens = 0
    var cacheReadInputTokens = 0
    var reasoningOutputTokens = 0
    var totalTokens = 0

    mutating func add(_ other: TokenUsageCounts) {
        inputTokens += other.inputTokens
        outputTokens += other.outputTokens
        cacheCreationInputTokens += other.cacheCreationInputTokens
        cacheReadInputTokens += other.cacheReadInputTokens
        reasoningOutputTokens += other.reasoningOutputTokens
        totalTokens += other.totalTokens
    }
}

struct CollectorCache: Codable {
    static let currentVersion = 1
    var version = currentVersion
    var files: [String: CachedUsageFile] = [:]
}

struct CachedUsageFile: Codable {
    var tool: String
    var size: UInt64
    var modificationTime: TimeInterval
    var records: [UsageRecord]
}
