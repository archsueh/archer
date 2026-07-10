import SwiftUI

// [archer] Status-bar pill for the active tab's cumulative session $ / tokens.
// P1c: file-watch driven (SessionLiveUsageMonitor); no periodic poll once
// the log path is attached.

/// Compact session cost gauge. Shape mirrors `CodexUsagePill` /
/// `ToolCallActivityPill`. Hidden until the first UsageRecord lands. // [archer]
struct SessionCostPill: View {
    @Bindable var session: Session
    @State private var live: SessionLiveUsage?
    @State private var detailOpen = false

    var body: some View {
        Group {
            if let live {
                Button { detailOpen = true } label: {
                    pillContent(live)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $detailOpen, arrowEdge: .top) {
                    SessionCostDetailPopover(usage: live, agent: session.displayAgent)
                }
                .help(helpText(live))
                .accessibilityLabel(accessibilityLabel(live))
            }
        }
        .task(id: refreshKey) {
            await attachMonitor()
        }
    }

    /// Agent + conversation id + cwd re-bind the file watch. // [archer]
    private var refreshKey: String {
        let agentKey = session.displayAgent.baseAgentId ?? session.displayAgent.id
        let cid = session.conversationId ?? ""
        let cwd = session.currentDirectory.path
        return "\(agentKey)|\(cid)|\(cwd)"
    }

    /// Start shared monitor for this tab; `defer` stops the watch when the
    /// `.task` is cancelled (tab switch / hide). // [archer]
    private func attachMonitor() async {
        let surfaceId = session.id
        guard let tool = SessionLiveUsageSource.toolLabel(for: session.displayAgent) else {
            live = nil
            return
        }
        let conversationId = session.conversationId
        let cwd = session.currentDirectory

        SessionLiveUsageMonitor.shared.start(
            surfaceId: surfaceId,
            tool: tool,
            conversationId: conversationId,
            cwd: cwd
        ) { usage in
            live = usage
        }
        defer {
            SessionLiveUsageMonitor.shared.stop(surfaceId: surfaceId)
        }

        // Stay suspended until cancellation — file events drive updates.
        while !Task.isCancelled {
            do {
                try await Task.sleep(nanoseconds: 60_000_000_000)
            } catch {
                break
            }
        }
    }

    /// Test / call-site alias for `SessionLiveUsageSource.resolveSessionKey`. // [archer]
    nonisolated static func resolveSessionKey(
        tool: String,
        conversationId: String?,
        cwd: URL
    ) -> String? {
        SessionLiveUsageSource.resolveSessionKey(
            tool: tool,
            conversationId: conversationId,
            cwd: cwd
        )
    }

    // MARK: - Layout (wide → compact → icon)

    private func pillContent(_ usage: SessionLiveUsage) -> some View {
        ViewThatFits(in: .horizontal) {
            fullPill(usage)
            compactPill(usage)
            iconOnlyPill(usage)
        }
    }

    private func fullPill(_ usage: SessionLiveUsage) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            dollarGlyph
            Text(SessionLiveUsageAggregator.costText(usage.costUSD))
                .font(Theme.mono(11, weight: .medium))
                .foregroundStyle(Theme.chromeForeground)
                .fixedSize(horizontal: true, vertical: false)
            Text("·")
                .foregroundStyle(Theme.chromeFaint)
            Text(SessionLiveUsageAggregator.tokensText(usage.tokens))
                .font(Theme.mono(11, weight: .regular))
                .foregroundStyle(Theme.chromeMuted)
                .fixedSize(horizontal: true, vertical: false)
            if usage.estimated {
                Text("est.")
                    .font(Theme.mono(9, weight: .medium))
                    .foregroundStyle(Theme.chromeFaint)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .overlay(border)
    }

    private func compactPill(_ usage: SessionLiveUsage) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            dollarGlyph
            Text(SessionLiveUsageAggregator.costText(usage.costUSD))
                .font(Theme.mono(11, weight: .medium))
                .foregroundStyle(Theme.chromeForeground)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .overlay(border)
    }

    private func iconOnlyPill(_ usage: SessionLiveUsage) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            dollarGlyph
            Text(SessionLiveUsageAggregator.costText(usage.costUSD))
                .font(Theme.mono(11, weight: .medium))
                .foregroundStyle(Theme.chromeForeground)
                .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .overlay(border)
    }

    private var dollarGlyph: some View {
        Image(systemName: "dollarsign.circle")
            .imageScale(.small)
            .foregroundStyle(Theme.chromeMuted)
    }

    private var border: some View {
        RoundedRectangle(cornerRadius: 4).stroke(Theme.chromeFaint, lineWidth: 1)
    }

    private func helpText(_ usage: SessionLiveUsage) -> String {
        var parts = [
            SessionLiveUsageAggregator.costText(usage.costUSD),
            SessionLiveUsageAggregator.tokensText(usage.tokens) + " tokens",
        ]
        if usage.estimated { parts.append("estimated") }
        return parts.joined(separator: " · ")
    }

    private func accessibilityLabel(_ usage: SessionLiveUsage) -> String {
        helpText(usage)
    }
}

/// Click-through detail: cost, tokens breakdown, model, est. flag. // [archer]
private struct SessionCostDetailPopover: View {
    let usage: SessionLiveUsage
    let agent: AgentTemplate

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                AgentIconView(
                    asset: agent.iconAsset,
                    fallbackSymbol: agent.symbol,
                    size: 16
                )
                Text("session cost")
                    .font(Theme.mono(12, weight: .medium))
                    .foregroundStyle(Theme.chromeForeground)
                Spacer()
                if usage.estimated {
                    Text("EST.")
                        .font(Theme.mono(9, weight: .medium))
                        .tracking(0.5)
                        .foregroundStyle(Theme.chromeMuted)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(Theme.chromeFaint, lineWidth: 1)
                        )
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(SessionLiveUsageAggregator.costText(usage.costUSD))
                    .font(Theme.mono(18, weight: .medium))
                    .foregroundStyle(Theme.chromeForeground)
                Text(SessionLiveUsageAggregator.tokensText(usage.tokens) + " tok")
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.chromeMuted)
            }

            if let model = usage.model, !model.isEmpty {
                row(label: "model", value: model)
            }
            row(label: "input", value: SessionLiveUsageAggregator.tokensText(usage.inputTokens))
            row(label: "output", value: SessionLiveUsageAggregator.tokensText(usage.outputTokens))
            if usage.cacheReadTokens > 0 {
                row(label: "cache read", value: SessionLiveUsageAggregator.tokensText(usage.cacheReadTokens))
            }
            if usage.cacheWriteTokens > 0 {
                row(label: "cache write", value: SessionLiveUsageAggregator.tokensText(usage.cacheWriteTokens))
            }
        }
        .padding(14)
        .frame(minWidth: 220)
        .background(Theme.chromeBackground)
        .preferredColorScheme(Theme.chromeColorScheme)
    }

    private func row(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(Theme.mono(11))
                .foregroundStyle(Theme.chromeMuted)
            Spacer()
            Text(value)
                .font(Theme.mono(11, weight: .medium))
                .foregroundStyle(Theme.chromeForeground)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}
