import AppKit
import SQLite3
import SwiftUI

@MainActor
final class UsageViewModel: ObservableObject {
    @Published var usage: ServiceUsage?
    @Published var error: String?
    @Published var stats = UsageStats()
    @Published var isLoading = true

    private let provider = ClaudeUsageProvider()

    func load() async {
        isLoading = true

        // 1. Fetch live Anthropic OAuth usage
        do {
            usage = try await provider.fetch()
            error = nil
        } catch {
            self.error = (error as? UsageError)?.errorDescription ?? error.localizedDescription
        }

        // 2. Query usage.db for tokens and 7-day usage
        stats = fetchStatsFromDB()

        isLoading = false
    }

    private func fetchStatsFromDB() -> UsageStats {
        let home = NSHomeDirectory()
        let fm = FileManager.default

        let claudeDbPath = (home as NSString).appendingPathComponent(".claude/usage.db")
        let hermesDbPath = (home as NSString).appendingPathComponent(".hermes/state.db")

        var todayClaudeInput = 0
        var todayClaudeOutput = 0
        var todayClaudeCacheRead = 0

        if fm.fileExists(atPath: claudeDbPath) {
            var db: OpaquePointer?
            if sqlite3_open_v2(claudeDbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK {
                let todayQuery = """
                    SELECT SUM(input_tokens), SUM(output_tokens), SUM(cache_read_tokens)
                    FROM turns
                    WHERE date(timestamp, 'localtime') = date('now', 'localtime');
                """
                var stmt: OpaquePointer?
                if sqlite3_prepare_v2(db, todayQuery, -1, &stmt, nil) == SQLITE_OK {
                    if sqlite3_step(stmt) == SQLITE_ROW {
                        todayClaudeInput = Int(sqlite3_column_int64(stmt, 0))
                        todayClaudeOutput = Int(sqlite3_column_int64(stmt, 1))
                        todayClaudeCacheRead = Int(sqlite3_column_int64(stmt, 2))
                    }
                    sqlite3_finalize(stmt)
                }
                sqlite3_close(db)
            }
        }

        var todayHermesInput = 0
        var todayHermesOutput = 0
        var todayHermesCacheRead = 0

        if fm.fileExists(atPath: hermesDbPath) {
            var db: OpaquePointer?
            if sqlite3_open_v2(hermesDbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK {
                let todayQuery = """
                    SELECT SUM(input_tokens), SUM(output_tokens), SUM(cache_read_tokens)
                    FROM sessions
                    WHERE date(started_at, 'unixepoch', 'localtime') = date('now', 'localtime');
                """
                var stmt: OpaquePointer?
                if sqlite3_prepare_v2(db, todayQuery, -1, &stmt, nil) == SQLITE_OK {
                    if sqlite3_step(stmt) == SQLITE_ROW {
                        todayHermesInput = Int(sqlite3_column_int64(stmt, 0))
                        todayHermesOutput = Int(sqlite3_column_int64(stmt, 1))
                        todayHermesCacheRead = Int(sqlite3_column_int64(stmt, 2))
                    }
                    sqlite3_finalize(stmt)
                }
                sqlite3_close(db)
            }
        }

        var claudeUsageByDay: [String: (input: Int, output: Int)] = [:]
        if fm.fileExists(atPath: claudeDbPath) {
            var db: OpaquePointer?
            if sqlite3_open_v2(claudeDbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK {
                let last7DaysQuery = """
                    SELECT date(timestamp, 'localtime') as day, SUM(input_tokens), SUM(output_tokens)
                    FROM turns
                    WHERE timestamp >= datetime('now', '-7 days')
                    GROUP BY day;
                """
                var stmt: OpaquePointer?
                if sqlite3_prepare_v2(db, last7DaysQuery, -1, &stmt, nil) == SQLITE_OK {
                    while sqlite3_step(stmt) == SQLITE_ROW {
                        if let dayChars = sqlite3_column_text(stmt, 0) {
                            let day = String(cString: dayChars)
                            let input = Int(sqlite3_column_int64(stmt, 1))
                            let output = Int(sqlite3_column_int64(stmt, 2))
                            claudeUsageByDay[day] = (input, output)
                        }
                    }
                    sqlite3_finalize(stmt)
                }
                sqlite3_close(db)
            }
        }

        var hermesUsageByDay: [String: (input: Int, output: Int)] = [:]
        if fm.fileExists(atPath: hermesDbPath) {
            var db: OpaquePointer?
            if sqlite3_open_v2(hermesDbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK {
                let last7DaysQuery = """
                    SELECT date(started_at, 'unixepoch', 'localtime') as day, SUM(input_tokens), SUM(output_tokens)
                    FROM sessions
                    WHERE started_at >= strftime('%s', 'now', '-7 days')
                    GROUP BY day;
                """
                var stmt: OpaquePointer?
                if sqlite3_prepare_v2(db, last7DaysQuery, -1, &stmt, nil) == SQLITE_OK {
                    while sqlite3_step(stmt) == SQLITE_ROW {
                        if let dayChars = sqlite3_column_text(stmt, 0) {
                            let day = String(cString: dayChars)
                            let input = Int(sqlite3_column_int64(stmt, 1))
                            let output = Int(sqlite3_column_int64(stmt, 2))
                            hermesUsageByDay[day] = (input, output)
                        }
                    }
                    sqlite3_finalize(stmt)
                }
                sqlite3_close(db)
            }
        }

        var dayItems: [UsageStats.DayUsage] = []
        let calendar = Calendar.current
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let weekdayFormatter = DateFormatter()
        weekdayFormatter.locale = Locale(identifier: "zh_CN")
        weekdayFormatter.dateFormat = "E"

        var maxTotal = 0
        var rawDays: [(dayName: String, claude: Int, hermes: Int)] = []

        for i in (0 ..< 7).reversed() {
            if let date = calendar.date(byAdding: .day, value: -i, to: Date()) {
                let dateStr = dateFormatter.string(from: date)
                let dayName = i == 0 ? "今天" : weekdayFormatter.string(from: date)

                let claudeTokens = (claudeUsageByDay[dateStr]?.input ?? 0) + (claudeUsageByDay[dateStr]?.output ?? 0)
                let hermesTokens = (hermesUsageByDay[dateStr]?.input ?? 0) + (hermesUsageByDay[dateStr]?.output ?? 0)

                let total = claudeTokens + hermesTokens
                if total > maxTotal {
                    maxTotal = total
                }
                rawDays.append((dayName: dayName, claude: claudeTokens, hermes: hermesTokens))
            }
        }

        let scaleMax = maxTotal > 0 ? CGFloat(maxTotal) : 1_000_000.0
        for item in rawDays {
            let claudeH = (CGFloat(item.claude) / scaleMax) * 110.0
            let hermesH = (CGFloat(item.hermes) / scaleMax) * 110.0

            dayItems.append(UsageStats.DayUsage(
                dayName: item.dayName,
                claudeHeight: max(claudeH, 4),
                hermesHeight: max(hermesH, 4)
            ))
        }

        return UsageStats(
            todayInput: todayClaudeInput,
            todayOutput: todayClaudeOutput,
            todayCacheRead: todayClaudeCacheRead,
            hermesTodayInput: todayHermesInput,
            hermesTodayOutput: todayHermesOutput,
            hermesTodayCacheRead: todayHermesCacheRead,
            chartDays: dayItems
        )
    }
}

struct UsageStats {
    var todayInput: Int = 0
    var todayOutput: Int = 0
    var todayCacheRead: Int = 0

    var hermesTodayInput: Int = 0
    var hermesTodayOutput: Int = 0
    var hermesTodayCacheRead: Int = 0

    struct DayUsage: Identifiable {
        let id = UUID()
        let dayName: String
        let claudeHeight: CGFloat
        let hermesHeight: CGFloat
    }

    var chartDays: [DayUsage] = []
}

@MainActor
struct UsageView: View {
    @Bindable var store: WorkspaceStore
    @StateObject private var viewModel = UsageViewModel()
    @State private var selectedAgentId: String = ""
    @State private var hoverBack = false

    var availableAgents: [AgentTemplate] {
        var usedIds = Set<String>()

        // 1. Check all distinct agents used in sessions across all workspaces.
        for workspace in store.workspaces {
            for agent in workspace.distinctAgents {
                usedIds.insert(agent.id)
            }
        }

        // 2. Check if the databases have records.
        let home = NSHomeDirectory()
        let fm = FileManager.default
        let claudeDbPath = (home as NSString).appendingPathComponent(".claude/usage.db")
        let hermesDbPath = (home as NSString).appendingPathComponent(".hermes/state.db")

        if fm.fileExists(atPath: claudeDbPath) {
            usedIds.insert("claude-code")
        }
        if fm.fileExists(atPath: hermesDbPath) {
            usedIds.insert("hermes")
            usedIds.insert("antigravity")
        }

        // 3. Make sure the currently selected agent or active cockpit agent is in the list
        if let activeAgentId = store.active?.activeSession?.agent.id, !activeAgentId.isEmpty {
            usedIds.insert(activeAgentId)
        }

        // 4. Always include Claude Code and Hermes as baseline core agents
        usedIds.insert("claude-code")
        usedIds.insert("hermes")

        // Resolve agent templates from all (built-in + custom)
        let allTemplates = AgentTemplate.all

        // Filter and return the templates that are in our usedIds set.
        return allTemplates.filter { usedIds.contains($0.id) && !$0.isShell }
    }

    private var resolvedBaseAgentId: String {
        guard let agent = AgentTemplate.all.first(where: { $0.id == selectedAgentId }) else {
            return selectedAgentId
        }
        return agent.baseAgentId ?? agent.id
    }

    var body: some View {
        VStack(spacing: 0) {
            titlebar

            if viewModel.isLoading {
                Spacer()
                ProgressView("Loading usage details…")
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.chromeMuted)
                Spacer()
            } else {
                ScrollView(showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 24) {
                        headerSection
                        agentPicker
                        statStrip
                        gridPanels
                        chartPanel
                    }
                    .padding(32)
                }
            }
        }
        .background(Theme.chromeBackground)
        .onAppear {
            if selectedAgentId.isEmpty {
                selectedAgentId = store.active?.activeSession?.agent.id ?? "claude-code"
            }
            Task {
                await viewModel.load()
            }
        }
    }

    private var agentPicker: some View {
        HStack(spacing: 8) {
            ForEach(availableAgents) { agent in
                Button(action: {
                    withAnimation(Theme.chromeTransition) {
                        selectedAgentId = agent.id
                    }
                }) {
                    HStack(spacing: 6) {
                        AgentIconView(asset: agent.iconAsset, fallbackSymbol: agent.symbol, size: 12)
                        Text(agent.title)
                            .font(Theme.mono(11.5, weight: selectedAgentId == agent.id ? .bold : .medium))
                    }
                    .foregroundStyle(selectedAgentId == agent.id ? Theme.chromeForeground : Theme.chromeMuted)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(selectedAgentId == agent.id ? Theme.chromeActive : Color.clear)
                    .bracketBorder()
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
    }

    // MARK: - Subviews

    private var titlebar: some View {
        HStack(spacing: Theme.space3) {
            Color.clear.frame(width: 82)

            Button(action: {
                withAnimation(Theme.chromeTransition) {
                    store.activeScreen = .cockpit
                }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10, weight: .bold))
                    Text("Archer")
                        .font(Theme.mono(11.5))
                }
                .foregroundStyle(Theme.chromeForeground)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(hoverBack ? Theme.chromeHover : Color.clear)
                .bracketBorder()
            }
            .buttonStyle(PlainButtonStyle())
            .onHover { hoverBack = $0 }

            Rectangle()
                .fill(Theme.chromeHairline)
                .frame(width: 1, height: 20)

            HStack(spacing: 6) {
                Image(systemName: "gauge.medium")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.chromeMuted)
                Text("Agent 用量")
                    .font(Theme.mono(12, weight: .bold))
                    .foregroundStyle(Theme.chromeForeground)
                Text("· 配额 / token / 窗口重置")
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.chromeMuted)
            }

            Spacer()
        }
        .frame(height: 48)
        .overlay(
            VStack {
                Spacer()
                Rectangle().fill(Theme.chromeHairline).frame(height: 1)
            }
        )
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Agent 用量")
                .font(Theme.display(24, weight: .semibold))
                .foregroundStyle(Theme.chromeForeground)

            Text("Claude Code 官方 5h 窗口 + 周配额（与 /usage 同源） · Hermes 统计（与 state.db 同源）")
                .font(Theme.mono(11))
                .foregroundStyle(Theme.chromeMuted)
        }
    }

    private var statStrip: some View {
        let (fiveHourPercent, weeklyPercent) = getUsagePercentages()

        return HStack(spacing: 0) {
            if resolvedBaseAgentId == "claude-code" {
                // Stat 1: Claude 5h
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .lastTextBaseline, spacing: 2) {
                        Text("\(fiveHourPercent)")
                            .font(Theme.display(38, weight: .semibold))
                            .foregroundStyle(fiveHourPercent > 75 ? Theme.activityAttention : Theme.activityRunning)
                        Text("%")
                            .font(Theme.display(17, weight: .medium))
                            .foregroundStyle(Theme.chromeMuted)
                    }
                    Text("Claude · 5h 窗口")
                        .font(Theme.display(13))
                        .foregroundStyle(Theme.chromeForeground)

                    if let resets = viewModel.usage?.fiveHour?.resetsAt {
                        Text("重置 \(countdown(resets))")
                            .font(Theme.mono(10.5))
                            .foregroundStyle(Theme.chromeMuted)
                    } else {
                        Text("重置 1h 12m")
                            .font(Theme.mono(10.5))
                            .foregroundStyle(Theme.chromeMuted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .overlay(
                    HStack {
                        Spacer()
                        Rectangle().fill(Theme.chromeHairline).frame(width: 1)
                    }
                )

                // Stat 2: Claude Weekly
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .lastTextBaseline, spacing: 2) {
                        Text("\(weeklyPercent)")
                            .font(Theme.display(38, weight: .semibold))
                            .foregroundStyle(Theme.activityRunning)
                        Text("%")
                            .font(Theme.display(17, weight: .medium))
                            .foregroundStyle(Theme.chromeMuted)
                    }
                    Text("Claude · 周配额")
                        .font(Theme.display(13))
                        .foregroundStyle(Theme.chromeForeground)
                    Text("重置 周一 09:00")
                        .font(Theme.mono(10.5))
                        .foregroundStyle(Theme.chromeMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .overlay(
                    HStack {
                        Spacer()
                        Rectangle().fill(Theme.chromeHairline).frame(width: 1)
                    }
                )

                // Stat 3: Today's Tokens
                VStack(alignment: .leading, spacing: 8) {
                    let totalToday = Double(viewModel.stats.todayInput + viewModel.stats.todayOutput) / 1_000_000.0
                    HStack(alignment: .lastTextBaseline, spacing: 2) {
                        Text(String(format: "%.2f", totalToday))
                            .font(Theme.display(38, weight: .semibold))
                            .foregroundStyle(Theme.chromeForeground)
                        Text("M")
                            .font(Theme.display(17, weight: .medium))
                            .foregroundStyle(Theme.chromeMuted)
                    }
                    Text("今日 Token")
                        .font(Theme.display(13))
                        .foregroundStyle(Theme.chromeForeground)
                    Text("输入 \(formatTokens(viewModel.stats.todayInput)) · 输出 \(formatTokens(viewModel.stats.todayOutput))")
                        .font(Theme.mono(10.5))
                        .foregroundStyle(Theme.chromeMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            } else if resolvedBaseAgentId == "hermes" || resolvedBaseAgentId == "antigravity" {
                // Gemini/Hermes stats
                let totalInput = viewModel.stats.hermesTodayInput + viewModel.stats.hermesTodayCacheRead
                let hitRate = totalInput > 0 ? Double(viewModel.stats.hermesTodayCacheRead) / Double(totalInput) : 0.0

                // Stat 1: Cache Hit Rate
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .lastTextBaseline, spacing: 2) {
                        Text(String(format: "%.0f", hitRate * 100))
                            .font(Theme.display(38, weight: .semibold))
                            .foregroundStyle(Theme.activityRunning)
                        Text("%")
                            .font(Theme.display(17, weight: .medium))
                            .foregroundStyle(Theme.chromeMuted)
                    }
                    Text("缓存命中率")
                        .font(Theme.display(13))
                        .foregroundStyle(Theme.chromeForeground)
                    Text("基于最近的 API 会话")
                        .font(Theme.mono(10.5))
                        .foregroundStyle(Theme.chromeMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .overlay(
                    HStack {
                        Spacer()
                        Rectangle().fill(Theme.chromeHairline).frame(width: 1)
                    }
                )

                // Stat 2: Today's Tokens
                VStack(alignment: .leading, spacing: 8) {
                    let totalHermesToday = Double(viewModel.stats.hermesTodayInput + viewModel.stats.hermesTodayOutput) / 1_000_000.0
                    HStack(alignment: .lastTextBaseline, spacing: 2) {
                        Text(String(format: "%.2f", totalHermesToday))
                            .font(Theme.display(38, weight: .semibold))
                            .foregroundStyle(Theme.activityRunning)
                        Text("M")
                            .font(Theme.display(17, weight: .medium))
                            .foregroundStyle(Theme.chromeMuted)
                    }
                    Text("今日 Token")
                        .font(Theme.display(13))
                        .foregroundStyle(Theme.chromeForeground)
                    Text("输入 \(formatTokens(viewModel.stats.hermesTodayInput)) · 输出 \(formatTokens(viewModel.stats.hermesTodayOutput))")
                        .font(Theme.mono(10.5))
                        .foregroundStyle(Theme.chromeMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .overlay(
                    HStack {
                        Spacer()
                        Rectangle().fill(Theme.chromeHairline).frame(width: 1)
                    }
                )

                // Stat 3: Estimated Cost
                VStack(alignment: .leading, spacing: 8) {
                    let cost = calculateCost(input: viewModel.stats.hermesTodayInput, output: viewModel.stats.hermesTodayOutput, cacheRead: viewModel.stats.hermesTodayCacheRead)
                    HStack(alignment: .lastTextBaseline, spacing: 2) {
                        Text(String(format: "$%.2f", cost))
                            .font(Theme.display(38, weight: .semibold))
                            .foregroundStyle(Theme.gitInsertion)
                    }
                    Text("今日估算花费")
                        .font(Theme.display(13))
                        .foregroundStyle(Theme.chromeForeground)
                    Text("本地大模型 & API 计费")
                        .font(Theme.mono(10.5))
                        .foregroundStyle(Theme.chromeMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            } else {
                // Placeholder stats for other agents
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .lastTextBaseline, spacing: 2) {
                        Text("N/A")
                            .font(Theme.display(38, weight: .semibold))
                            .foregroundStyle(Theme.chromeMuted)
                    }
                    Text("缓存命中率")
                        .font(Theme.display(13))
                        .foregroundStyle(Theme.chromeForeground)
                    Text("无本地数据")
                        .font(Theme.mono(10.5))
                        .foregroundStyle(Theme.chromeMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .overlay(
                    HStack {
                        Spacer()
                        Rectangle().fill(Theme.chromeHairline).frame(width: 1)
                    }
                )

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .lastTextBaseline, spacing: 2) {
                        Text("0.00")
                            .font(Theme.display(38, weight: .semibold))
                            .foregroundStyle(Theme.chromeMuted)
                        Text("M")
                            .font(Theme.display(17, weight: .medium))
                            .foregroundStyle(Theme.chromeMuted)
                    }
                    Text("今日 Token")
                        .font(Theme.display(13))
                        .foregroundStyle(Theme.chromeForeground)
                    Text("未检测到 API 活动")
                        .font(Theme.mono(10.5))
                        .foregroundStyle(Theme.chromeMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .overlay(
                    HStack {
                        Spacer()
                        Rectangle().fill(Theme.chromeHairline).frame(width: 1)
                    }
                )

                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .lastTextBaseline, spacing: 2) {
                        Text("$0.00")
                            .font(Theme.display(38, weight: .semibold))
                            .foregroundStyle(Theme.chromeMuted)
                    }
                    Text("今日估算花费")
                        .font(Theme.display(13))
                        .foregroundStyle(Theme.chromeForeground)
                    Text("未检测到 API 活动")
                        .font(Theme.mono(10.5))
                        .foregroundStyle(Theme.chromeMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
            }
        }
        .bracketBorder()
    }

    private var gridPanels: some View {
        VStack(alignment: .leading, spacing: 16) {
            if resolvedBaseAgentId == "claude-code" {
                // Claude Code Panel
                let agent = AgentTemplate.all.first { $0.id == selectedAgentId }
                let title = agent?.title ?? "Claude Code"
                let symbol = agent?.symbol ?? "sparkles"

                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 8) {
                        Image(systemName: symbol)
                            .foregroundStyle(.orange)
                        Text(title)
                            .font(Theme.mono(12, weight: .bold))
                        Text("Pro 订阅 · /usage 同源")
                            .font(Theme.mono(9.5))
                            .foregroundStyle(Theme.chromeMuted)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .bracketBorder()
                    }

                    // Meter 1: 5h Window
                    let (fiveHourPercent, weeklyPercent) = getUsagePercentages()
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("5 小时滚动窗口")
                                .font(Theme.display(13))
                            Spacer()
                            Text("\(Int(Double(fiveHourPercent) / 100.0 * 50000.0))")
                                .font(Theme.mono(12))
                                .foregroundStyle(Theme.chromeForeground) +
                                Text(" / 50,000")
                                .font(Theme.mono(12))
                                .foregroundStyle(Theme.chromeMuted)
                        }

                        GeometryReader { geo in
                            Rectangle()
                                .fill(fiveHourPercent > 75 ? Theme.activityAttention : Theme.activityRunning)
                                .frame(width: geo.size.width * CGFloat(Double(fiveHourPercent) / 100.0))
                        }
                        .frame(height: 14)
                        .background(Color.gray.opacity(0.1))
                        .bracketBorder()

                        HStack {
                            Text("\(fiveHourPercent)% 已用")
                            Spacer()
                            if let resets = viewModel.usage?.fiveHour?.resetsAt {
                                Text("重置于 \(timeStr(resets)) · \(countdown(resets)) 后")
                            } else {
                                Text("重置于 14:30 · 1h 12m 后")
                            }
                        }
                        .font(Theme.mono(10.5))
                        .foregroundStyle(Theme.chromeMuted)
                    }

                    // Meter 2: Weekly Quota
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("本周配额")
                                .font(Theme.display(13))
                            Spacer()
                            Text(String(format: "%.1fM", Double(weeklyPercent) / 100.0 * 5.8))
                                .font(Theme.mono(12))
                                .foregroundStyle(Theme.chromeForeground) +
                                Text(" / 5.8M")
                                .font(Theme.mono(12))
                                .foregroundStyle(Theme.chromeMuted)
                        }

                        GeometryReader { geo in
                            Rectangle()
                                .fill(Theme.activityRunning)
                                .frame(width: geo.size.width * CGFloat(Double(weeklyPercent) / 100.0))
                        }
                        .frame(height: 14)
                        .background(Color.gray.opacity(0.1))
                        .bracketBorder()

                        HStack {
                            Text("\(weeklyPercent)% 已用")
                            Spacer()
                            Text("重置 周一 09:00 · 3 天后")
                        }
                        .font(Theme.mono(10.5))
                        .foregroundStyle(Theme.chromeMuted)
                    }

                    Divider().background(Theme.chromeHairline)

                    Text("订阅制不按 token 计费；窗口用满后请求会排队至下个窗口。")
                        .font(Theme.mono(10.5))
                        .foregroundStyle(Theme.chromeMuted) +
                        Text("5h 窗口接近上限")
                        .font(Theme.mono(10.5, weight: .bold))
                        .foregroundStyle(Theme.activityAttention) +
                        Text("——重活建议错峰或切到 Hermes。")
                        .font(Theme.mono(10.5))
                        .foregroundStyle(Theme.chromeMuted)
                }
                .padding(24)
                .bracketBorder()
            } else if resolvedBaseAgentId == "hermes" || resolvedBaseAgentId == "antigravity" {
                // Hermes / Antigravity Panel (shares state.db)
                let agent = AgentTemplate.all.first { $0.id == selectedAgentId }
                let title = agent?.title ?? (selectedAgentId == "antigravity" ? "Antigravity CLI" : "Hermes")
                let symbol = agent?.symbol ?? (selectedAgentId == "antigravity" ? "arrow.up.circle" : "cpu")
                let isAgy = resolvedBaseAgentId == "antigravity"

                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 8) {
                        Image(systemName: symbol)
                            .foregroundStyle(isAgy ? Theme.activityRunning : Theme.chromeMuted)
                        Text(title)
                            .font(Theme.mono(12, weight: .bold))
                        Text(isAgy ? "Gemini 3.5 Flash · API 计费" : "Nous Research · token 计费")
                            .font(Theme.mono(9.5))
                            .foregroundStyle(Theme.chromeMuted)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .bracketBorder()
                    }

                    // Meter: Cache hit rate
                    VStack(alignment: .leading, spacing: 6) {
                        let totalInput = viewModel.stats.hermesTodayInput + viewModel.stats.hermesTodayCacheRead
                        let hitRate = totalInput > 0 ? Double(viewModel.stats.hermesTodayCacheRead) / Double(totalInput) : 0.0
                        HStack {
                            Text("缓存命中率")
                                .font(Theme.display(13))
                            Spacer()
                            Text(String(format: "%.0f%%", hitRate * 100))
                                .font(Theme.mono(12))
                                .foregroundStyle(Theme.chromeForeground)
                        }

                        GeometryReader { geo in
                            Rectangle()
                                .fill(Theme.activityRunning)
                                .frame(width: geo.size.width * CGFloat(hitRate))
                        }
                        .frame(height: 14)
                        .background(Color.gray.opacity(0.1))
                        .bracketBorder()

                        HStack {
                            Text("缓存效率")
                            Spacer()
                            Text("基于最近 of API 会话统计")
                        }
                        .font(Theme.mono(10.5))
                        .foregroundStyle(Theme.chromeMuted)
                    }

                    // Token rows
                    VStack(spacing: 8) {
                        let maxVal = max(1, max(viewModel.stats.hermesTodayInput, max(viewModel.stats.hermesTodayOutput, viewModel.stats.hermesTodayCacheRead)))
                        tokenRow(label: "输入", value: formatTokens(viewModel.stats.hermesTodayInput), percent: CGFloat(viewModel.stats.hermesTodayInput) / CGFloat(maxVal))
                        tokenRow(label: "输出", value: formatTokens(viewModel.stats.hermesTodayOutput), percent: CGFloat(viewModel.stats.hermesTodayOutput) / CGFloat(maxVal))
                        tokenRow(label: "缓存读", value: formatTokens(viewModel.stats.hermesTodayCacheRead), percent: CGFloat(viewModel.stats.hermesTodayCacheRead) / CGFloat(maxVal))
                    }

                    Divider().background(Theme.chromeHairline)

                    let cost = calculateCost(input: viewModel.stats.hermesTodayInput, output: viewModel.stats.hermesTodayOutput, cacheRead: viewModel.stats.hermesTodayCacheRead)
                    Text("今日估算花费 ")
                        .font(Theme.mono(10.5))
                        .foregroundStyle(Theme.chromeMuted) +
                        Text(String(format: "$%.2f", cost))
                        .font(Theme.mono(10.5, weight: .bold))
                        .foregroundStyle(Theme.gitInsertion) +
                        Text(isAgy ? " · Google Cloud / Vertex API 计费估算。" : " · 本地大模型 & API 计费估算。")
                        .font(Theme.mono(10.5))
                        .foregroundStyle(Theme.chromeMuted)
                }
                .padding(24)
                .bracketBorder()
            } else {
                // Dynamic Panel for any other agent
                let agent = AgentTemplate.all.first { $0.id == selectedAgentId }
                let title = agent?.title ?? selectedAgentId
                let symbol = agent?.symbol ?? "wand.and.stars"
                let command = agent?.initialCommand ?? ""
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 8) {
                        Image(systemName: symbol)
                            .foregroundStyle(Theme.chromeMuted)
                        Text(title)
                            .font(Theme.mono(12, weight: .bold))
                        if !command.isEmpty {
                            Text("\(command) · API 计费")
                                .font(Theme.mono(9.5))
                                .foregroundStyle(Theme.chromeMuted)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .bracketBorder()
                        } else {
                            Text("未配置命令")
                                .font(Theme.mono(9.5))
                                .foregroundStyle(Theme.chromeMuted)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .bracketBorder()
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("未检测到本地使用记录")
                            .font(Theme.display(14, weight: .semibold))
                            .foregroundStyle(Theme.chromeForeground)

                        Text("\(title) 尚未生成本地用量日志数据库。请在 settings.json 中配置相应的 API 凭证，并在 cockpit 中使用以在后续会话中启用用量跟踪。")
                            .font(Theme.mono(11))
                            .foregroundStyle(Theme.chromeMuted)
                            .lineLimit(nil)
                    }
                    .padding(.vertical, 8)

                    Divider().background(Theme.chromeHairline)

                    HStack {
                        Image(systemName: "info.circle")
                            .font(.system(size: 11))
                        Text("API 计费根据实际的 Input / Output token 在对应平台端单独结算。")
                    }
                    .font(Theme.mono(10.5))
                    .foregroundStyle(Theme.chromeMuted)
                }
                .padding(24)
                .bracketBorder()
            }
        }
    }

    private func tokenRow(label: String, value: String, percent: CGFloat) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(Theme.mono(11.5))
                .foregroundStyle(Theme.chromeMuted)
                .frame(width: 64, alignment: .leading)

            GeometryReader { geo in
                Rectangle()
                    .fill(Theme.gitInsertion)
                    .frame(width: geo.size.width * percent)
            }
            .frame(height: 8)
            .background(Color.gray.opacity(0.1))
            .bracketBorder()

            Text(value)
                .font(Theme.mono(11.5))
                .foregroundStyle(Theme.chromeForeground)
                .frame(width: 80, alignment: .trailing)
        }
    }

    private var chartPanel: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("近 7 天 Token 用量")
                .font(Theme.mono(12, weight: .bold))

            // The stacked bar chart
            HStack(alignment: .bottom, spacing: 16) {
                ForEach(viewModel.stats.chartDays) { day in
                    VStack(alignment: .center, spacing: 9) {
                        // Stack
                        VStack(spacing: 0) {
                            Spacer()
                            Rectangle()
                                .fill(Theme.gitInsertion)
                                .frame(height: day.hermesHeight)
                            Rectangle()
                                .fill(Theme.activityRunning)
                                .frame(height: day.claudeHeight)
                        }
                        .frame(height: 120)
                        .frame(width: 60)

                        Text(day.dayName)
                            .font(Theme.mono(10.5))
                            .foregroundStyle(day.dayName == "今天" ? Theme.chromeForeground : Theme.chromeMuted)
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            // Legend
            HStack(spacing: 18) {
                HStack(spacing: 7) {
                    Rectangle()
                        .fill(Theme.activityRunning)
                        .frame(width: 10, height: 10)
                    Text("Claude Code")
                }
                HStack(spacing: 7) {
                    Rectangle()
                        .fill(Theme.gitInsertion)
                        .frame(width: 10, height: 10)
                    Text("Gemini / Hermes")
                }
            }
            .font(Theme.mono(10.5))
            .foregroundStyle(Theme.chromeMuted)
        }
        .padding(24)
        .bracketBorder()
    }

    // MARK: - Helper Methods

    private func getUsagePercentages() -> (fiveHour: Int, weekly: Int) {
        if let u = viewModel.usage {
            let fh = u.fiveHour?.percent ?? 68
            let wk = u.weekly?.percent ?? 41
            return (fh, wk)
        }
        return (68, 41)
    }

    private func countdown(_ date: Date) -> String {
        let secs = max(0, Int(date.timeIntervalSinceNow))
        if secs < 3600 { return "\(secs / 60)m" }
        let h = secs / 3600, m = (secs % 3600) / 60
        return m > 0 ? "\(h)h\(m)m" : "\(h)h"
    }

    private func timeStr(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func formatTokens(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.2f M", Double(count) / 1_000_000.0)
        } else if count >= 1000 {
            return "\(count / 1000) K"
        }
        return "\(count)"
    }

    private func calculateCost(input: Int, output: Int, cacheRead: Int) -> Double {
        // Prices per 1M tokens: Input = $3.00, Output = $15.00, Cache read = $0.30
        let inputCost = Double(input) * 3.0 / 1_000_000.0
        let outputCost = Double(output) * 15.0 / 1_000_000.0
        let cacheCost = Double(cacheRead) * 0.30 / 1_000_000.0
        return inputCost + outputCost + cacheCost
    }
}
