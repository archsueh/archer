import SwiftUI

// Minimal multi-agent observability panel.
// - Reads from `WorkspaceStore` only.
// - Zero Bridge/Memory* coupling.
// - Hosting/wiring to be done by a separate window/controller when desired.

struct ObservabilityView: View {
    let rows: [AgentObservabilityRow]
    let onDrillDown: (AgentObservabilityRow) -> Void

    @State private var filter: SessionDashboardStatus? = nil
    @State private var selected: Int = 0

    @State private var tokenScale: Double = 1.0

    private var filtered: [AgentObservabilityRow] {
        guard let filter else { return rows }
        return rows.filter { $0.status == filter }
    }

    var body: some View {
        HStack(spacing: 0) {
            statusRail
            Rectangle().fill(Theme.chromeHairline).frame(width: 1)
            VStack(spacing: 0) {
                timelineTable
                Rectangle().fill(Theme.chromeHairline).frame(height: 1)
                hintBar
            }
        }
        .background(Theme.chromeBackground)
        .preferredColorScheme(Theme.chromeColorScheme)
        .onAppear { selected = 0 }
        .onChange(of: filter) { _, _ in selected = 0 }
        .onChange(of: rows) { _, _ in
            if selected >= filtered.count { selected = max(0, filtered.count - 1) }
        }
    }

    private var statusRail: some View {
        VStack(alignment: .leading, spacing: 2) {
            statusPill("All", count: rows.count, isSelected: filter == nil) { filter = nil }
            ForEach(SessionDashboardStatus.allCases, id: \.self) { status in
                statusPill(
                    status.label,
                    count: rows.filter { $0.status == status }.count,
                    isSelected: filter == status
                ) { filter = status }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 6)
        .frame(width: 140, alignment: .leading)
    }

    private func statusPill(_ title: String, count: Int, isSelected: Bool, action: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
                .font(Theme.mono(12))
                .foregroundStyle(isSelected ? Theme.chromeForeground : Theme.chromeMuted)
            Spacer(minLength: 8)
            Text("\(count)")
                .font(Theme.mono(11))
                .foregroundStyle(Theme.chromeMuted)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(isSelected ? Theme.chromeActive : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { action() }
    }

    private var timelineTable: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(filtered.enumerated()), id: \.element.id) { idx, row in
                        timelineRow(row, isSelected: idx == selected)
                            .id(row.id)
                            .contentShape(Rectangle())
                            .onTapGesture { selected = idx }
                            .onTapGesture(count: 2) { onDrillDown(row) }
                    }
                    if filtered.isEmpty {
                        Text("No active agents.")
                            .font(Theme.mono(12))
                            .foregroundStyle(Theme.chromeMuted)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 32)
                    }
                }
            }
            .onChange(of: selected) { _, newIdx in
                guard filtered.indices.contains(newIdx) else { return }
                proxy.scrollTo(filtered[newIdx].id, anchor: .center)
            }
            .overlay(alignment: .topLeading) {
                Color.clear
                    .frame(width: 0, height: 0)
                    .focusable()
                    .onKeyPress { press in
                        guard ["j", "k", "d"].contains(press.characters) else { return .ignored }
                        handleKey(press.characters)
                        return .handled
                    }
                    .onKeyPress(.return) {
                        guard filtered.indices.contains(selected) else { return .ignored }
                        onDrillDown(filtered[selected])
                        return .handled
                    }
            }
        }
    }

    private func handleKey(_ characters: String) {
        switch characters {
        case "j":
            selected = min(max(0, filtered.count - 1), selected + 1)
        case "k":
            selected = max(0, selected - 1)
        case "d":
            guard filtered.indices.contains(selected) else { return }
            onDrillDown(filtered[selected])
        default:
            break
        }
    }

    private var hintBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                hint("j/k", "move")
                hint("⏎", "drill")
                hint("d", "drill")
                Spacer()
            }
            Divider().background(Theme.chromeHairline)
            HStack(spacing: 12) {
                Text("Token delta scale")
                    .font(Theme.mono(10.5))
                    .foregroundStyle(Theme.chromeMuted)
                Slider(value: $tokenScale, in: 0.1 ... 5.0, step: 0.1)
                    .frame(width: 180)
                Text("×\(String(format: "%.1f", tokenScale))")
                    .font(Theme.mono(10.5, weight: .medium))
                    .foregroundStyle(Theme.chromeForeground.opacity(0.75))
                    .frame(width: 36, alignment: .trailing)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }

    private func hint(_ key: String, _ action: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(Theme.mono(10.5, weight: .medium))
                .foregroundStyle(Theme.chromeForeground.opacity(0.75))
            Text(action)
                .font(Theme.mono(10.5))
                .foregroundStyle(Theme.chromeMuted)
        }
    }

    private func timelineRow(_ row: AgentObservabilityRow, isSelected: Bool) -> some View {
        HStack(spacing: 10) {
            Circle().fill(stateColor(row.status)).frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.chromeForeground)
                    .lineLimit(1)
                Text("\(row.agentTitle) · \(row.track)")
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.chromeMuted)
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            Text(row.tokenDelta.map { formattedTokenDelta($0) } ?? "—")
                .font(Theme.mono(11))
                .foregroundStyle(Theme.chromeMuted)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(isSelected ? Theme.chromeActive : Color.clear)
    }

    private func stateColor(_ status: SessionDashboardStatus) -> Color {
        switch status {
        case .running: Theme.activityRunning
        case .waiting: Theme.activityAttention
        case .error: Theme.activityFailure
        case .idle: Theme.chromeMuted.opacity(0.5)
        }
    }

    private func formattedTokenDelta(_ delta: Int) -> String {
        let scaled = Double(delta) * tokenScale
        switch scaled {
        case 0: return "0"
        case 1_000_000...: return String(format: "+%.1fM", scaled / 1_000_000)
        case 1000...: return String(format: "+%.0fK", scaled / 1000)
        default: return String(format: "+%.0f", scaled)
        }
    }
}

// MARK: - Models

struct AgentObservabilityRow: Identifiable, Hashable {
    let id: UUID
    let title: String
    let agentTitle: String
    let track: String
    let status: SessionDashboardStatus
    let tokenDelta: Int?

    init(
        id: UUID = UUID(),
        title: String,
        agentTitle: String,
        track: String,
        status: SessionDashboardStatus,
        tokenDelta: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.agentTitle = agentTitle
        self.track = track
        self.status = status
        self.tokenDelta = tokenDelta
    }
}

// MARK: - Index builder

@MainActor
enum ObservabilityIndex {
    static func build(
        stores: [WorkspaceStore],
        usageLookup: (String) -> Int? = { _ in nil },
        bridgeLog: BridgeEventLog? = BridgeEventLog.shared
    ) -> [AgentObservabilityRow] {
        var rows: [AgentObservabilityRow] = []
        for store in stores {
            for workspace in store.workspaces {
                for pane in workspace.root.allPanes {
                    for tab in pane.tabs {
                        let track = tab.displayAgent.id
                        let status = SessionStatusDeriver.status(
                            activityState: tab.activityState,
                            lastCommandExit: tab.lastCommandExit
                        )
                        let tokenDelta = tab.conversationId.flatMap(usageLookup)
                        rows.append(AgentObservabilityRow(
                            title: tab.title,
                            agentTitle: tab.displayAgent.title,
                            track: track,
                            status: status,
                            tokenDelta: tokenDelta
                        ))
                    }
                }
            }
        }
        if let bridgeLog {
            for entry in bridgeLog.entries {
                rows.append(AgentObservabilityRow(
                    title: entry.summary,
                    agentTitle: entry.category.rawValue,
                    track: "bridge",
                    status: .running,
                    tokenDelta: nil
                ))
            }
        }
        return rows
    }
}
