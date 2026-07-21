import Combine
import SwiftUI

// [archer] Design interface.html `.agent-strip` — live @labels for the
// active workspace. Click focuses that tab. Not a chat roster.

struct AgentRosterStrip: View {
    let store: WorkspaceStore

    @State private var labels: [(label: String, sessionId: UUID)] = []

    var body: some View {
        Group {
            if !labels.isEmpty {
                HStack(spacing: 10) {
                    ForEach(labels, id: \.label) { item in
                        Button {
                            focus(sessionId: item.sessionId)
                        } label: {
                            HStack(spacing: 5) {
                                Text(PaneRegistry.at(item.label))
                                    .font(Theme.mono(11.5, weight: .semibold))
                                    .foregroundStyle(Theme.chromeForeground.opacity(0.9))
                                Circle()
                                    .fill(dotColor(for: item.sessionId))
                                    .frame(width: 6, height: 6)
                            }
                        }
                        .buttonStyle(.plain)
                        .help("Focus \(PaneRegistry.at(item.label))")
                    }
                    Spacer(minLength: 0)
                    Button {
                        BridgeConsoleLauncher.open(store: store)
                    } label: {
                        Text("Bridge")
                            .font(Theme.mono(10, weight: .medium))
                            .foregroundStyle(Theme.chromeMuted)
                    }
                    .buttonStyle(.plain)
                    .help("Open Agent Bridge (⌘⇧B)")
                }
                .padding(.horizontal, 14)
                .frame(height: 32)
                .background(Theme.chromeHover.opacity(0.35))
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Theme.chromeHairline).frame(height: 1)
                }
            }
        }
        .onAppear(perform: refresh)
        .onChange(of: store.activeWorkspaceId) { _, _ in refresh() }
        .onReceive(Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()) { _ in
            refresh()
        }
    }

    private func refresh() {
        guard let ws = store.active else {
            labels = []
            return
        }
        PaneRegistry.shared.sync(workspace: ws)
        labels = PaneRegistry.shared.entries
            .map { (label: $0.key, sessionId: $0.value.id) }
            .sorted { $0.label < $1.label }
    }

    private func focus(sessionId: UUID) {
        guard let ws = store.active else { return }
        for pane in ws.root.allPanes {
            if let tab = pane.tabs.first(where: { $0.id == sessionId }) {
                store.activateTab(tab, in: ws)
                return
            }
        }
    }

    private func dotColor(for sessionId: UUID) -> Color {
        guard let ws = store.active,
              let session = ws.root.allPanes.flatMap(\.tabs).first(where: { $0.id == sessionId })
        else { return Theme.chromeMuted }
        switch session.activityState {
        case .running: return Theme.activityRunning
        case .attention: return Theme.activityAttention
        case .idle: return Theme.chromeMuted
        }
    }
}
