// [archer] Cockpit — multi-agent pane dashboard
// HTML prototype: cockpit.html → native SwiftUI with Archer Theme
import SwiftUI

// MARK: - Models

@MainActor
final class CockpitViewModel: ObservableObject {
    @Published var bridgeEvents: [BridgeEvent] = [
        BridgeEvent(kind: .type, route: "@claude → @codex", detail: "review src/auth.ts"),
        BridgeEvent(kind: .keys, route: "→ @codex", detail: "Enter"),
        BridgeEvent(kind: .read, route: "@claude reads @codex 20", detail: "2 issues found"),
    ]
}

enum BridgeEventKind: String, CaseIterable { case read, type, keys }
struct BridgeEvent: Identifiable {
    let id = UUID(); let kind: BridgeEventKind; let route: String; let detail: String
}

struct WorkspaceEntry: Identifiable {
    let id = UUID()
    let name: String
    let path: String
    let icon: String
    let color: Color
}

// MARK: - Cockpit View

struct CockpitView: View {
    @StateObject private var vm = CockpitViewModel()
    @State private var bridgeOpen = false
    @State private var activeWorkspaceName = "Antigravity CLI"

    let workspaces: [WorkspaceEntry] = [
        WorkspaceEntry(name: "Hermes", path: "~/dev/hermes", icon: "antenna.radiowaves.left.and.right", color: .mint),
        WorkspaceEntry(name: "Claude Code", path: "~/dev/archer", icon: "sparkle", color: .orange),
        WorkspaceEntry(name: "Grok", path: "~/dev/grok", icon: "xmark", color: .green),
        WorkspaceEntry(name: "Antigravity CLI", path: "~", icon: "arrowshape.up.fill", color: .blue),
        WorkspaceEntry(name: "Codex", path: "~/dev/api", icon: "hexagon", color: .blue),
    ]

    let panes: [CockpitPane] = [
        CockpitPane(agent: .claude, drivenBy: nil),
        CockpitPane(agent: .hermes, drivenBy: "claude"),
    ]

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider().background(Theme.chromeHairline)
            center
            Divider().background(Theme.chromeHairline)
            files
        }
        .frame(minWidth: 900, minHeight: 600)
        .background(Theme.chromeBackground)
        .environment(\.colorScheme, .dark)
    }

    // MARK: Sidebar

    var sidebar: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Workspaces")
                    .font(Theme.mono(11, weight: .semibold))
                    .foregroundStyle(Theme.chromeMuted)
                    .textCase(.uppercase)
                    .kerning(0.6)
                Spacer()
                Image(systemName: "plus")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.chromeFaint)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)

            Divider().background(Theme.chromeHairline)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(workspaces) { ws in
                        wsRow(ws)
                    }
                }
            }

            Spacer()

            Divider().background(Theme.chromeHairline)

            // Skills only — Usage panel was removed (10d952b); do not reintroduce.
            sidebarFooterItem("Skills", icon: "wand.and.stars")
        }
        .frame(width: 200)
    }

    func wsRow(_ ws: WorkspaceEntry) -> some View {
        let isActive = ws.name == activeWorkspaceName
        return HStack(spacing: 10) {
            Image(systemName: ws.icon)
                .font(.system(size: 11))
                .foregroundStyle(isActive ? ws.color : Theme.chromeMuted)
                .frame(width: 16, alignment: .center)
            VStack(alignment: .leading, spacing: 1) {
                Text(ws.name)
                    .font(Theme.mono(11, weight: isActive ? .medium : .regular))
                    .foregroundStyle(isActive ? Theme.chromeForeground : Theme.chromeMuted)
                    .lineLimit(1)
                Text(ws.path)
                    .font(Theme.mono(9))
                    .foregroundStyle(Theme.chromeFaint)
            }
            Spacer()
            Circle()
                .fill(ws.color)
                .frame(width: 5, height: 5)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .contentShape(Rectangle())
        .background(isActive ? Theme.chromeHover : .clear)
        .onTapGesture { activeWorkspaceName = ws.name }
    }

    func sidebarFooterItem(_ label: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(Theme.chromeFaint)
            Text(label)
                .font(Theme.mono(10))
                .foregroundStyle(Theme.chromeFaint)
                .kerning(0.4)
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
    }

    // MARK: Center

    var center: some View {
        VStack(spacing: 0) {
            agentStrip
            Divider().background(Theme.chromeHairline)
            tabBar
            Divider().background(Theme.chromeHairline)
            paneArea
            bridgeBar
        }
    }

    // MARK: Agent Strip

    var agentStrip: some View {
        HStack(spacing: 12) {
            ForEach(AgentSpec.allCases) { agent in
                HStack(spacing: 5) {
                    agent.icon
                        .font(.system(size: 11))
                    Text("@\(agent.label)")
                        .font(Theme.mono(11))
                    Circle()
                        .fill(agent.color)
                        .frame(width: 5, height: 5)
                }
                .foregroundStyle(Theme.chromeMuted)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .frame(height: 36)
    }

    // MARK: Tab Bar

    var tabBar: some View {
        HStack(spacing: 2) {
            tabChip("Tab 1", active: true)
            tabChip("Tab 2", active: false)
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: "rectangle.split.2x1").font(.system(size: 10))
                Image(systemName: "rectangle.split.1x2").font(.system(size: 10))
            }
            .foregroundStyle(Theme.chromeFaint)
            .padding(.trailing, 12)
        }
        .frame(height: 40)
    }

    func tabChip(_ name: String, active: Bool) -> some View {
        Text(name)
            .font(Theme.mono(11))
            .foregroundStyle(active ? Theme.chromeForeground : Theme.chromeMuted)
            .padding(.horizontal, 12).padding(.vertical, 5)
            .background(active ? Theme.chromeActive : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    // MARK: Pane Area

    var paneArea: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(panes) { pane in
                    CockpitPaneRow(pane: pane)
                }
            }
        }
    }

    // MARK: Bridge Bar

    var bridgeBar: some View {
        VStack(spacing: 0) {
            Divider().background(Theme.chromeHairline)
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { bridgeOpen.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Text("Bridge")
                        .font(Theme.mono(10)).kerning(0.6)
                        .textCase(.uppercase)
                        .foregroundStyle(Theme.chromeMuted)
                    if let last = vm.bridgeEvents.last {
                        Text("\(last.route) · \(last.detail)")
                            .font(Theme.mono(10)).lineLimit(1)
                            .foregroundStyle(Theme.chromeForeground)
                    }
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .rotationEffect(.degrees(bridgeOpen ? 180 : 0))
                        .foregroundStyle(Theme.chromeFaint)
                }
                .padding(.horizontal, 14).frame(height: 30)
            }
            .buttonStyle(.plain)

            if bridgeOpen {
                VStack(spacing: 0) {
                    ForEach(vm.bridgeEvents) { event in
                        HStack(spacing: 10) {
                            Text(event.kind.rawValue)
                                .font(Theme.mono(9))
                                .foregroundStyle(event.kind.color)
                                .frame(width: 38, alignment: .leading)
                            Text("\(event.route) \(event.detail)")
                                .font(Theme.mono(10))
                                .foregroundStyle(Theme.chromeMuted)
                            Spacer()
                        }
                        .padding(.vertical, 3).padding(.horizontal, 14)
                    }
                }
                .padding(.bottom, 8)
                .transition(.opacity)
            }
        }
    }

    // MARK: Files

    var files: some View {
        VStack(spacing: 0) {
            Text("Files")
                .font(Theme.mono(11, weight: .semibold))
                .foregroundStyle(Theme.chromeMuted)
                .textCase(.uppercase).kerning(0.6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14).frame(height: 38)
            Divider().background(Theme.chromeHairline)
            ScrollView {
                LazyVGrid(columns: Array(repeating: .init(.flexible()), count: 3), spacing: 6) {
                    ForEach(["AGENTS.md", "Package.swift", "Sources/", "Tests/", "README.md", "DESIGN.md"], id: \.self) { f in
                        fileCell(f)
                    }
                }
                .padding(10)
            }
        }
        .frame(width: 280)
    }

    func fileCell(_ name: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: name.hasSuffix("/") ? "folder" : "doc.text")
                .font(.system(size: 16))
                .foregroundStyle(Theme.chromeMuted)
            Text(name)
                .font(Theme.mono(9)).lineLimit(1)
                .foregroundStyle(Theme.chromeFaint)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 6).fill(Theme.chromeHover))
    }
}

// MARK: - Agent Spec

enum AgentSpec: String, CaseIterable, Identifiable {
    case claude, codex, grok, hermes
    var id: String {
        rawValue
    }

    var label: String {
        rawValue
    }

    var icon: some View {
        Image(systemName: {
            switch self {
            case .claude: return "cpu"
            case .codex: return "terminal"
            case .grok: return "bolt"
            case .hermes: return "antenna.radiowaves.left.and.right"
            }
        }())
    }

    var color: Color {
        switch self {
        case .claude: return .orange
        case .codex: return .green
        case .grok: return .blue
        case .hermes: return .mint
        }
    }
}

@MainActor
extension BridgeEventKind {
    var color: Color {
        switch self {
        case .read: return Theme.chromeMuted
        case .type: return .blue
        case .keys: return .orange
        }
    }
}

// MARK: - Pane

struct CockpitPane: Identifiable {
    let id = UUID(); let agent: AgentSpec; var drivenBy: String?
}

struct CockpitPaneRow: View {
    let pane: CockpitPane

    var body: some View {
        VStack(spacing: 0) {
            // pane head
            HStack(spacing: 6) {
                pane.agent.icon.font(.system(size: 11)).foregroundStyle(Theme.chromeMuted)

                Text(pane.agent.label.capitalized)
                    .font(Theme.mono(11, weight: .medium))
                    .foregroundStyle(Theme.chromeForeground)

                Text("@\(pane.agent.label)")
                    .font(Theme.mono(10))
                    .foregroundStyle(.blue)

                Circle()
                    .fill(pane.agent.color).frame(width: 5, height: 5)

                if let drv = pane.drivenBy {
                    Text("← \(drv)")
                        .font(Theme.mono(9))
                        .foregroundStyle(.blue).padding(.horizontal, 5).padding(.vertical, 1)
                        .overlay(RoundedRectangle(cornerRadius: 3).stroke(.blue.opacity(0.3), lineWidth: 1))
                }

                Spacer()

                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Theme.chromeFaint)
            }
            .padding(.horizontal, 12).frame(height: 30)
            .background(Theme.chromeHover)

            Divider().background(Theme.chromeHairline)

            // pane body
            VStack(alignment: .leading, spacing: 4) {
                Text("$ swift build").font(Theme.mono(12)).foregroundStyle(Theme.chromeForeground)
                Text("Build complete! (0.13s)").font(Theme.mono(12)).foregroundStyle(.green)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .overlay(alignment: .top) {
            if pane.drivenBy != nil {
                Rectangle().fill(.blue.opacity(0.2)).frame(height: 1)
            }
        }
    }
}
