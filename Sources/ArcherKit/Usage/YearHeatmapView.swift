import SwiftUI

/// GitHub-style year heatmap of daily token usage. Reads the lightweight
/// `yearlyTokens` dictionary (day → total tokens) from `UsageStats` — no
/// record-level detail is held in memory. // [archer]
struct YearHeatmapView: View {
    let yearlyTokens: [String: Int]

    /// Heatmap window: last 365 days ending today, laid out as 53 weeks × 7
    /// days (GitHub convention: columns are weeks, rows are weekdays).
    private var cells: [HeatCell] {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let today = Date()
        guard let start = calendar.date(byAdding: .day, value: -364, to: today) else { return [] }

        // Align start to the beginning of its week (Sunday) so columns are clean.
        var startWeek = start
        if let diff = calendar.dateComponents([.weekday], from: start).weekday {
            let back = (diff - 1) % 7 // Sunday=1
            startWeek = calendar.date(byAdding: .day, value: -back, to: start) ?? start
        }

        var result: [HeatCell] = []
        var cursor = startWeek
        while cursor <= today {
            let key = formatter.string(from: cursor)
            let tokens = yearlyTokens[key] ?? 0
            let weekday = calendar.component(.weekday, from: cursor) // 1=Sun … 7=Sat
            result.append(HeatCell(date: cursor, tokens: tokens, weekday: weekday, isFuture: cursor > today))
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return result
    }

    private func level(_ tokens: Int) -> Int {
        guard tokens > 0 else { return 0 }
        // Logarithmic-ish buckets so a few heavy days don't wash out the rest.
        switch tokens {
        case 1 ..< 50000: return 1
        case 50000 ..< 200_000: return 2
        case 200_000 ..< 600_000: return 3
        default: return 4
        }
    }

    private var maxTokens: Int {
        yearlyTokens.values.max() ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("全年 Token 热力图")
                    .font(Theme.mono(12, weight: .bold))
                    .foregroundStyle(Theme.chromeForeground)
                Spacer()
                if maxTokens > 0 {
                    HStack(spacing: 4) {
                        Text("少")
                            .font(Theme.mono(9))
                            .foregroundStyle(Theme.chromeMuted)
                        ForEach(0 ..< 5) { lvl in
                            Rectangle()
                                .fill(cellColor(lvl))
                                .frame(width: 10, height: 10)
                        }
                        Text("多")
                            .font(Theme.mono(9))
                            .foregroundStyle(Theme.chromeMuted)
                    }
                }
            }

            // Weekday labels (Mon/Wed/Fri) + grid
            HStack(alignment: .top, spacing: 4) {
                VStack(alignment: .trailing, spacing: 3) {
                    ForEach(1 ..< 7) { wd in
                        Text(wd == 2 ? "一" : wd == 4 ? "三" : wd == 6 ? "五" : " ")
                            .font(Theme.mono(8))
                            .foregroundStyle(Theme.chromeMuted)
                            .frame(height: 11)
                    }
                }
                .padding(.top, 1)

                let columns = stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0 ..< min($0 + 7, cells.count)]) }
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(columns.enumerated()), id: \.offset) { _, week in
                        HStack(spacing: 3) {
                            ForEach(week) { cell in
                                Rectangle()
                                    .fill(cellColor(level(cell.tokens)))
                                    .frame(width: 11, height: 11)
                                    .opacity(cell.isFuture ? 0.15 : 1)
                                    .help(cell.tokens > 0 ? "\(cell.date, style: .date): \(formatTokens(cell.tokens)) tokens" : "\(cell.date, style: .date): 无记录")
                            }
                        }
                    }
                }
            }
        }
        .padding(24)
        .bracketBorder()
    }

    private func cellColor(_ lvl: Int) -> Color {
        switch lvl {
        case 0: return Color.gray.opacity(0.12)
        case 1: return Theme.activityRunning.opacity(0.35)
        case 2: return Theme.activityRunning.opacity(0.6)
        case 3: return Theme.activityRunning
        default: return Theme.activityAttention
        }
    }

    private func formatTokens(_ count: Int) -> String {
        if count >= 1_000_000 { return String(format: "%.2fM", Double(count) / 1_000_000.0) }
        if count >= 1000 { return "\(count / 1000)K" }
        return "\(count)"
    }
}

private struct HeatCell: Identifiable {
    let id = UUID()
    let date: Date
    let tokens: Int
    let weekday: Int
    let isFuture: Bool
}
