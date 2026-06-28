// [archer] Cockpit — multi-agent pane dashboard
// HTML prototype: cockpit.html → SwiftUI native
import SwiftUI

// MARK: - Cockpit View Model

@MainActor
final class CockpitViewModel: ObservableObject {
    /// Bridge activity log
    @Published var bridgeEvents: [BridgeEvent] = [
        BridgeEvent(kind: .type, route: "@claude → @codex", detail: "review src/auth.ts"),
        BridgeEvent(kind: .keys, route: "→ @codex", detail: "Enter"),
        BridgeEvent(kind: .read, route: "@claude reads @codex 20", detail: "2 issues found"),
    ]
}

enum BridgeEventKind: String, CaseIterable {
    case read, type, keys
}

struct BridgeEvent: Identifiable {
    let id = UUID()
    let kind: BridgeEventKind
    let route: String
    let detail: String
}

// MARK: - Cockpit View

struct CockpitView: View {
    @StateObject private var vm = CockpitViewModel()
    @State private var bridgeOpen = false

    /// Stub data — wired to WorkspaceStore in production
    let panes: [CockpitPane] = [
        CockpitPane(agent: .claude, drivenBy: nil),
        CockpitPane(agent: .hermes, drivenBy: "claude"),
    ]

    var body: some View {
        HStack(spacing: 0) {
            // ── left sidebar ──
            cockpitSidebar

            Divider()

            // ── center cockpit ──
            VStack(spacing: 0) {
                // agent status strip
                agentStrip

                Divider()

                // tab bar (stub)
                tabBar

                Divider()

                // pane area
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(panes) { pane in
                            CockpitPaneView(pane: pane)
                            Divider()
                        }
                    }
                }

                // bridge activity bar
                bridgeBar
            }

            Divider()

            // ── right files ──
            cockpitFiles
        }
        .frame(minWidth: 900, minHeight: 600)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Sidebar

    var cockpitSidebar: some View {
        VStack(spacing: 0) {
            // title
            HStack {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 11))
                Text("Workspaces")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            // workspace list (stub)
            List {
                workspaceRow("~/archer", active: true)
                workspaceRow("~/hermes", active: false)
                workspaceRow("~/archviz", active: false)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .frame(width: 200)
    }

    func workspaceRow(_ name: String, active: Bool) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(active ? Color.blue : Color.gray.opacity(0.3))
                .frame(width: 6, height: 6)
            Text(name)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(active ? .primary : .secondary)
            Spacer()
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    // MARK: - Agent Strip

    var agentStrip: some View {
        HStack(spacing: 12) {
            ForEach(AgentSpec.allCases) { agent in
                HStack(spacing: 6) {
                    Image(systemName: agent.symbol)
                        .font(.system(size: 10))
                    Text("@\(agent.label)")
                        .font(.system(size: 10, design: .monospaced))
                    Circle()
                        .fill(agent.color)
                        .frame(width: 5, height: 5)
                }
                .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .frame(height: 36)
    }

    // MARK: - Tab Bar

    var tabBar: some View {
        HStack(spacing: 2) {
            Text("Tab 1")
                .font(.system(size: 11, design: .monospaced))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.06)))
            Text("Tab 2")
                .font(.system(size: 11, design: .monospaced))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            Spacer()
            // split controls
            HStack(spacing: 8) {
                Image(systemName: "rectangle.split.2x1")
                    .font(.system(size: 10))
                Image(systemName: "rectangle.split.1x2")
                    .font(.system(size: 10))
            }
            .foregroundColor(.secondary)
            .padding(.trailing, 12)
        }
        .frame(height: 40)
    }

    // MARK: - Bridge Bar

    var bridgeBar: some View {
        VStack(spacing: 0) {
            Divider()

            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    bridgeOpen.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Text("Bridge")
                        .font(.system(size: 10, design: .monospaced))
                        .kerning(0.6)
                    if let last = vm.bridgeEvents.last {
                        Text("\(last.route) · \(last.detail)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .rotationEffect(.degrees(bridgeOpen ? 180 : 0))
                }
                .padding(.horizontal, 14)
                .frame(height: 30)
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)

            if bridgeOpen {
                VStack(spacing: 0) {
                    ForEach(vm.bridgeEvents) { event in
                        HStack(spacing: 10) {
                            Text(event.kind.rawValue)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(event.kind.color)
                                .frame(width: 38, alignment: .leading)
                            Text("**\(event.route)** \(event.detail)")
                                .font(.system(size: 10, design: .monospaced))
                            Spacer()
                        }
                        .padding(.vertical, 3)
                        .padding(.horizontal, 14)
                    }
                }
                .padding(.bottom, 8)
                .transition(.opacity)
            }
        }
    }

    // MARK: - Files Grid

    var cockpitFiles: some View {
        VStack(spacing: 0) {
            // header
            HStack {
                Text("Files")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 14)
            .frame(height: 38)

            Divider()

            // file grid (stub)
            ScrollView {
                LazyVGrid(columns: Array(repeating: .init(.flexible()), count: 3), spacing: 6) {
                    ForEach(["AGENTS.md", "Package.swift", "Sources/", "Tests/", "README.md", "DESIGN.md"], id: \.self) { file in
                        VStack(spacing: 8) {
                            Image(systemName: file.hasSuffix("/") ? "folder" : "doc.text")
                                .font(.system(size: 16))
                            Text(file)
                                .font(.system(size: 9, design: .monospaced))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                        )
                    }
                }
                .padding(10)
            }
        }
        .frame(width: 280)
        .background(Color.primary.opacity(0.03))
    }
}

// MARK: - Agent Spec (matches HTML AGENTS map)

enum AgentSpec: String, CaseIterable, Identifiable {
    case claude, codex, grok, hermes

    var id: String {
        rawValue
    }

    var label: String {
        rawValue
    }

    var symbol: String {
        switch self {
        case .claude: "cpu"
        case .codex: "terminal"
        case .grok: "bolt"
        case .hermes: "antenna.radiowaves.left.and.right"
        }
    }

    var color: Color {
        switch self {
        case .claude: .orange
        case .codex: .green
        case .grok: .blue
        case .hermes: .mint
        }
    }
}

extension BridgeEventKind {
    var color: Color {
        switch self {
        case .read: .secondary
        case .type: .blue
        case .keys: .orange
        }
    }
}

// MARK: - Cockpit Pane

struct CockpitPane: Identifiable {
    let id = UUID()
    let agent: AgentSpec
    var drivenBy: String?
}

// MARK: - Cockpit Pane View

struct CockpitPaneView: View {
    let pane: CockpitPane

    var body: some View {
        VStack(spacing: 0) {
            // pane head
            HStack(spacing: 8) {
                Image(systemName: pane.agent.symbol)
                    .font(.system(size: 11))

                Text(pane.agent.label.capitalized)
                    .font(.system(size: 11, design: .monospaced))
                    .fontWeight(.medium)

                Text("@\(pane.agent.label)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.blue)

                Circle()
                    .fill(pane.agent.color)
                    .frame(width: 6, height: 6)

                if let drv = pane.drivenBy {
                    Text("← \(drv)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.blue)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                        )
                }

                Spacer()

                Button {
                    // close pane
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .frame(height: 30)

            Divider()

            // pane body (stub)
            VStack(alignment: .leading, spacing: 4) {
                Text("$ swift build")
                    .font(.system(size: 12, design: .monospaced))
                Text("Build complete! (0.13s)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.green)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .background(
            pane.drivenBy != nil
                ? RoundedRectangle(cornerRadius: 0).stroke(Color.blue.opacity(0.3), lineWidth: 1)
                : nil
        )
    }
}
