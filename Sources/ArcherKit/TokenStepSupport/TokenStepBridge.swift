import AppKit
import Foundation
import SwiftUI

// MARK: - Minimal, read-only bridge into TokenStep.

public struct TokenStepToday {
    public let date: String
    public let totalTokens: Int
    public let inputTokens: Int
    public let outputTokens: Int
    public let cacheCreation: Int
    public let cacheRead: Int
    public let reasoning: Int
    public let goal: Int
    public let ratio: Double
    public let provider: String?

    public init(
        date: String = "",
        totalTokens: Int = 0,
        inputTokens: Int = 0,
        outputTokens: Int = 0,
        cacheCreation: Int = 0,
        cacheRead: Int = 0,
        reasoning: Int = 0,
        goal: Int = 100_000_000,
        provider: String? = nil
    ) {
        self.date = date
        self.totalTokens = totalTokens
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheCreation = cacheCreation
        self.cacheRead = cacheRead
        self.reasoning = reasoning
        self.goal = goal
        if goal > 0 {
            ratio = min(Double(totalTokens) / Double(goal), 1.0)
        } else {
            ratio = 0.0
        }
        self.provider = provider
    }
}

public enum TokenStepBridge {
    private static let supportDir: URL = {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/TokenStep")
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }()

    private static let todayString: String = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.timeZone = TimeZone(secondsFromGMT: 0)
        return df.string(from: Date())
    }()

    public static func isInstalled() -> Bool {
        FileManager.default.fileExists(atPath: supportDir.path)
    }

    @discardableResult
    public static func today(forceRefresh _: Bool = false) -> TokenStepToday {
        if !isInstalled() {
            return .init(date: todayString, goal: 100_000_000)
        }

        let usageURL = supportDir.appendingPathComponent("data/usage.json")
        guard let data = try? Data(contentsOf: usageURL) else {
            return .init(date: todayString, goal: 100_000_000)
        }

        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let days = (json["days"] as? [[String: Any]]) ?? []
        let today = days.first { ($0["date"] as? String) == todayString }

        if let today = today,
           let usage = today["usage"] as? [String: Any],
           let total = usage["total_tokens"] as? Int
        {
            return .init(
                date: todayString,
                totalTokens: total,
                inputTokens: (usage["input_tokens"] as? Int) ?? 0,
                outputTokens: (usage["output_tokens"] as? Int) ?? 0,
                cacheCreation: (usage["cache_creation_input_tokens"] as? Int) ?? 0,
                cacheRead: (usage["cache_read_input_tokens"] as? Int) ?? 0,
                reasoning: (usage["reasoning_output_tokens"] as? Int) ?? 0,
                goal: (json["goal_daily"] as? Int) ?? 100_000_000,
                provider: (json["provider"] as? String) ?? nil
            )
        }

        return .init(date: todayString, goal: (json["goal_daily"] as? Int) ?? 100_000_000)
    }

    public static func openApp() {
        let appURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications/TokenStep.app")
        if FileManager.default.fileExists(atPath: appURL.path) {
            NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration())
        }
    }
}
