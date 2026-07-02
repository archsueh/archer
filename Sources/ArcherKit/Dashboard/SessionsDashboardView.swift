import SwiftUI

/// The Sessions dashboard content: a left status-filter sidebar with live
/// counts, a right table of every session across every window, and a
/// keyboard-driven selection (j/k, Return to jump, d to close). v1 is
/// read-only + close only — no pause/restart, see
/// `Dashboard/SessionDashboardRow.swift`'s doc comment for why.
struct SessionsDashboardView: View {
    let rows: [SessionDashboardRow]
    let onJump: (SessionDashboardRow) -> Void
    let onClose: (SessionDashboardRow) -> Void

    @State private var filter: SessionDashboardStatus?
    @State private var selected: Int = 0
    @FocusState private var listFocused: Bool

    private var filteredRows: [SessionDashboardRow] {
        guard let filter else { return rows }
        return rows.filter { $0.status == filter }
    }

    var body: some View {
        HStack(spacing: 0) {
            statusSidebar
            Rectangle().fill(Theme.chromeHairline).frame(width: 1)
            VStack(spacing: 0) {
                table
                Rectangle().fill(Theme.chromeHairline).frame(height: 1)
                hintBar
            }
        }
        .background(Theme.chromeBackground)
        .preferredColorScheme(Theme.chromeColorScheme)
        .onAppear { listFocused = true }
        // Filter changes can leave `selected` pointing past the new,
        // shorter list — clamp instead of letting the row lookup silently
        // no-op on stale indices.
        .onChange(of: filter) { _, _ in
            selected = 0
        }
        .onChange(of: rows) { _, _ in
            if selected >= filteredRows.count { selected = max(0, filteredRows.count - 1) }
        }
    }

    // MARK: Sidebar

    private var statusSidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            statusRow(title: "All", count: rows.count, isSelected: filter == nil) { filter = nil }
            ForEach(SessionDashboardStatus.allCases, id: \.self) { status in
                statusRow(
                    title: status.label,
                    count: rows.filter { $0.status == status }.count,
                    isSelected: filter == status
                ) { filter = status }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 6)
        .frame(width: 150, alignment: .leading)
    }

    private func statusRow(title: String, count: Int, isSelected: Bool, onSelect: @escaping () -> Void) -> some View {
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
        .onTapGesture { onSelect() }
    }

    // MARK: Table

    private var table: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(filteredRows.enumerated()), id: \.element.id) { idx, row in
                        SessionDashboardRowView(row: row, isSelected: idx == selected)
                            .id(row.id)
                            .contentShape(Rectangle())
                            .onTapGesture { selected = idx }
                            .onTapGesture(count: 2) { onJump(row) }
                    }
                    if filteredRows.isEmpty {
                        Text("No sessions.")
                            .font(Theme.mono(12))
                            .foregroundStyle(Theme.chromeMuted)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 32)
                    }
                }
            }
            .onChange(of: selected) { _, newIdx in
                guard filteredRows.indices.contains(newIdx) else { return }
                proxy.scrollTo(filteredRows[newIdx].id, anchor: .center)
            }
            // Zero-size focus target — there's no search field here (unlike
            // CommandPaletteView), so the key handling attaches directly to
            // an invisible view rather than a TextField.
            .overlay(alignment: .topLeading) {
                Color.clear
                    .frame(width: 0, height: 0)
                    .focusable()
                    .focused($listFocused)
                    .onKeyPress { press in
                        guard ["j", "k", "d"].contains(press.characters) else { return .ignored }
                        handleKey(press.characters)
                        return .handled
                    }
                    .onKeyPress(.return) {
                        guard filteredRows.indices.contains(selected) else { return .ignored }
                        onJump(filteredRows[selected])
                        return .handled
                    }
            }
        }
    }

    private func handleKey(_ characters: String) {
        switch characters {
        case "j":
            selected = min(max(0, filteredRows.count - 1), selected + 1)
        case "k":
            selected = max(0, selected - 1)
        case "d":
            guard filteredRows.indices.contains(selected) else { return }
            onClose(filteredRows[selected])
        default:
            break
        }
    }

    private var hintBar: some View {
        HStack(spacing: 16) {
            hint("j/k", "move")
            hint("\u{21A9}", "jump")
            hint("d", "close")
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func hint(_ key: String, _ action: String) -> some View {
        HStack(spacing: 4) {
            Text(key).font(Theme.mono(10.5, weight: .medium)).foregroundStyle(Theme.chromeForeground.opacity(0.75))
            Text(action).font(Theme.mono(10.5)).foregroundStyle(Theme.chromeMuted)
        }
    }
}

private struct SessionDashboardRowView: View {
    let row: SessionDashboardRow
    let isSelected: Bool

    private var statusColor: Color {
        switch row.status {
        case .running: Theme.activityRunning
        case .waiting: Theme.activityAttention
        case .error: Theme.activityFailure
        case .idle: Theme.chromeMuted.opacity(0.5)
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(statusColor).frame(width: 7, height: 7)
            AgentIconView(asset: row.agentIconAsset, fallbackSymbol: row.agentSymbol, size: 14)
                .foregroundStyle(row.agentTint ?? Theme.chromeMuted)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(Theme.mono(12))
                    .foregroundStyle(Theme.chromeForeground)
                    .lineLimit(1)
                Text("\(row.agentTitle)\(row.windowLabel)")
                    .font(Theme.mono(10))
                    .foregroundStyle(Theme.chromeMuted)
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            Text(row.tokenTotal.map { formattedTokenCount($0) } ?? "—")
                .font(Theme.mono(11))
                .foregroundStyle(Theme.chromeMuted)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(isSelected ? Theme.chromeActive : Color.clear)
    }

    private func formattedTokenCount(_ count: Int) -> String {
        switch count {
        case 1_000_000...: String(format: "%.1fM", Double(count) / 1_000_000)
        case 1000...: String(format: "%.0fK", Double(count) / 1000)
        default: "\(count)"
        }
    }
}
