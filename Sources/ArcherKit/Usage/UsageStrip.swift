import SwiftUI

/// Polls Claude usage every 60s for the top strip.
@MainActor
final class UsageStripModel: ObservableObject {
    @Published var usage: ServiceUsage?
    @Published var error: String?
    private let provider = ClaudeUsageProvider()
    private var task: Task<Void, Never>?

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(nanoseconds: 60_000_000_000)
            }
        }
    }

    func stop() {
        task?.cancel(); task = nil
    }

    private func refresh() async {
        do {
            usage = try await provider.fetch()
            error = nil
        } catch {
            self.error = (error as? UsageError)?.errorDescription ?? error.localizedDescription
        }
    }
}

/// Always-on top strip: Claude 5h + weekly utilization with reset countdown.
struct UsageStripView: View {
    @StateObject private var model = UsageStripModel()

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "sparkles").font(.system(size: 10)).foregroundStyle(Theme.chromeMuted)
            Text("Claude").font(Theme.mono(11, weight: .medium)).foregroundStyle(Theme.chromeForeground)
            if let u = model.usage {
                meter("5h", u.fiveHour)
                meter("week", u.weekly)
                if let reset = u.fiveHour?.resetsAt ?? u.weekly?.resetsAt {
                    Text("resets \(countdown(reset))")
                        .font(Theme.mono(10)).foregroundStyle(Theme.chromeMuted)
                }
            } else if let e = model.error {
                Text(e).font(Theme.mono(10)).foregroundStyle(Theme.chromeMuted).lineLimit(1)
            } else {
                Text("loading…").font(Theme.mono(10)).foregroundStyle(Theme.chromeMuted)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(height: 26)
        .background(Theme.chromeBackground)
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }

    @ViewBuilder
    private func meter(_ label: String, _ limit: RateLimit?) -> some View {
        if let limit {
            HStack(spacing: 5) {
                Text(label).font(Theme.mono(10)).foregroundStyle(Theme.chromeMuted)
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.gray.opacity(0.2)).frame(width: 46, height: 5)
                    Capsule().fill(color(limit.utilization))
                        .frame(width: 46 * min(max(limit.utilization, 0), 1), height: 5)
                }
                Text("\(limit.percent)%")
                    .font(Theme.mono(10, weight: .medium))
                    .foregroundStyle(Theme.chromeForeground.opacity(0.85))
            }
        }
    }

    private func color(_ v: Double) -> Color {
        if v < 0.7 { return .green }
        if v < 0.85 { return .orange }
        return .red
    }

    private func countdown(_ date: Date) -> String {
        let secs = max(0, Int(date.timeIntervalSinceNow))
        if secs < 3600 { return "\(secs / 60)m" }
        let h = secs / 3600, m = (secs % 3600) / 60
        return m > 0 ? "\(h)h\(m)m" : "\(h)h"
    }
}
