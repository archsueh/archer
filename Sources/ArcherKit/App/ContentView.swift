import AppKit
import SwiftUI

struct ContentView: View {
    @Bindable var store: WorkspaceStore

    var body: some View {
        VStack(spacing: 0) {
            if store.activeScreen == .cockpit {
                topStrip
                Rectangle().fill(Theme.chromeHairline).frame(height: 1)
                HStack(spacing: 0) {
                    if store.sidebarMode != .hidden {
                        SidebarView(store: store)
                        Rectangle().fill(Theme.chromeHairline).frame(width: 1)
                            .overlay {
                                if store.sidebarMode == .full {
                                    PanelResizer(
                                        width: Binding(
                                            get: { store.panelWidths.sidebar },
                                            set: { store.resizePanel(.sidebar, to: $0) }
                                        ),
                                        range: PanelWidths.sidebarRange,
                                        panelSide: .leading
                                    )
                                }
                            }
                    }
                    mainPane
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if store.rightSidebarMode != .hidden {
                        Rectangle().fill(Theme.chromeHairline).frame(width: 1)
                            .overlay {
                                if firstActiveRightPanel == .rightSidebar {
                                    rightResizer
                                }
                            }
                        AgentOverviewSidebar(mode: store.rightSidebarMode, width: store.panelWidths.rightPanel)
                    }
                    if store.filePanelMode != .hidden { // [archer]
                        Rectangle().fill(Theme.chromeHairline).frame(width: 1)
                            .overlay {
                                if firstActiveRightPanel == .filePanel {
                                    rightResizer
                                }
                            }
                        FilePanelView(rootURL: store.active?.workingDirectory
                            ?? FileManager.default.homeDirectoryForCurrentUser,
                            width: store.panelWidths.rightPanel)
                            .id("\(store.active?.id.uuidString ?? "")-\(store.active?.workingDirectory.path ?? "")")
                    }
                    if store.diffPanelMode != .hidden { // [archer]
                        Rectangle().fill(Theme.chromeHairline).frame(width: 1)
                            .overlay {
                                if firstActiveRightPanel == .diffPanel {
                                    rightResizer
                                }
                            }
                        DiffPanelView(rootURL: store.active?.workingDirectory
                            ?? FileManager.default.homeDirectoryForCurrentUser,
                            width: store.panelWidths.rightPanel)
                            .id("\(store.active?.id.uuidString ?? "")-\(store.active?.workingDirectory.path ?? "")")
                    }
                }
            } else {
                mainPane
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(chromeBackground.opacity(Theme.glassOpacity)) // [archer] glass
        .preferredColorScheme(Theme.chromeColorScheme)
        .ignoresSafeArea(.all)
    }

    /// Top 32pt strip. `window.isMovable = false` is set globally, so the
    /// `WindowDragHandle` background is the only place AppKit allows
    /// window dragging. The `SearchTriggerPill` lives in an *inner* ZStack
    /// scoped to the drag-handle area (not the whole strip) so it centers
    /// in the available space and can't overlap the sidebar toggle when
    /// the window is dragged narrow. `ViewThatFits` drops the pill
    /// entirely once even the inner area can't hold its 280pt frame —
    /// `⌘P` + the File menu still reach the palette.
    private var topStrip: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: 82).allowsHitTesting(false)
            HoverableIconButton(
                systemName: "sidebar.left",
                fontSize: 12,
                size: 28,
                help: sidebarTooltip
            ) {
                withAnimation(Theme.chromeTransition) {
                    store.setSidebarMode(store.sidebarMode.next)
                }
            }
            WindowDragHandle()
                .overlay {
                    if ArcherSettingsModel.shared.showSearchPill {
                        ViewThatFits(in: .horizontal) {
                            SearchTriggerPill {
                                NSApp.sendAction(#selector(AppDelegate.handleQuickOpen), to: nil, from: nil)
                            }
                            EmptyView()
                        }
                    }
                }
            HoverableIconButton( // [archer]
                systemName: "gauge.medium",
                fontSize: 12,
                size: 28,
                help: L10n.string("Usage strip")
            ) {
                withAnimation(Theme.chromeTransition) {
                    store.toggleUsageStrip()
                }
            }
            HoverableIconButton( // [archer]
                systemName: "folder",
                fontSize: 12,
                size: 28,
                help: L10n.string("File panel")
            ) {
                withAnimation(Theme.chromeTransition) {
                    store.setFilePanelMode(store.filePanelMode.next)
                }
            }
            InboxBell()
                .padding(.trailing, 8)
        }
        .frame(height: 48)
    }

    private var mainPane: some View {
        VStack(spacing: 0) {
            switch store.activeScreen {
            case .cockpit:
                if store.usageStripVisible { // [archer] single usage strip, aligned to the main column
                    UsageStripView()
                    Rectangle().fill(Theme.chromeHairline).frame(height: 1)
                }
                if let workspace = store.active {
                    PaneTreeView(node: workspace.root, workspace: workspace, store: store)
                        .id(workspace.id)
                } else {
                    Color.clear
                }
            case .skills:
                SkillsView(store: store)
            case .usage:
                UsageView(store: store)
            }
        }
    }

    private var chromeBackground: Color {
        let color = store.active?.activeSession?.engine.backgroundColor ?? Theme.terminalSurface
        return Color(nsColor: color)
    }

    private var sidebarTooltip: String {
        switch store.sidebarMode {
        case .full: return "Compact sidebar"
        case .compact: return "Hide sidebar"
        case .hidden: return "Show sidebar"
        }
    }

    private enum RightPanelType {
        case rightSidebar, filePanel, diffPanel, downloaderPanel
    }

    private var firstActiveRightPanel: RightPanelType? {
        if store.rightSidebarMode != .hidden { return .rightSidebar }
        if store.filePanelMode != .hidden { return .filePanel }
        if store.diffPanelMode != .hidden { return .diffPanel }
        if store.downloaderPanelMode != .hidden { return .downloaderPanel }
        return nil
    }

    private var rightResizer: some View {
        PanelResizer(
            width: Binding(
                get: { store.panelWidths.rightPanel },
                set: { store.resizePanel(.rightPanel, to: $0) }
            ),
            range: PanelWidths.rightRange,
            panelSide: .trailing
        )
    }
}

// MARK: - Agent Template Picker (Topbar Dropdown)

private struct AgentTemplatePicker: View {
    let store: WorkspaceStore
    @State private var isPresented = false

    private var availableTemplates: [AgentTemplate] {
        AgentTemplate.visibleOrdered(model: ArcherSettingsModel.shared)
    }

    private var currentTemplate: AgentTemplate? {
        // Try to get the agent from the active session
        if let session = store.active?.activeSession {
            let displayAgent = session.displayAgent
            if let template = availableTemplates.first(where: { $0.id == displayAgent.id }) {
                return template
            }
        }
        // Fall back to default launch template
        return AgentTemplate.defaultLaunchTemplate(model: ArcherSettingsModel.shared)
            ?? availableTemplates.first
    }

    var body: some View {
        Menu {
            // Current agent section
            if let current = currentTemplate {
                Section {
                    AgentTemplateMenuRow(template: current, isCurrent: true) {
                        // No-op for current - visual only
                    }
                }
            }

            Divider()

            // Terminal presets
            let presets = availableTemplates.filter { $0.isShell && $0.id != AgentTemplate.terminal.id }
            if !presets.isEmpty {
                Section {
                    ForEach(presets) { template in
                        AgentTemplateMenuRow(template: template, isCurrent: currentTemplate?.id == template.id) {
                            switchToTemplate(template)
                        }
                    }
                } header: {
                    Text(L10n.string("Topbar.section.terminals"))
                        .font(Theme.mono(10, weight: .semibold))
                        .foregroundStyle(Theme.chromeMuted)
                }
            }

            // Agents
            let agents = availableTemplates.filter { !$0.isShell }
            if !agents.isEmpty {
                Section {
                    ForEach(agents) { template in
                        AgentTemplateMenuRow(template: template, isCurrent: currentTemplate?.id == template.id) {
                            switchToTemplate(template)
                        }
                    }
                } header: {
                    Text(L10n.string("Topbar.section.agents"))
                        .font(Theme.mono(10, weight: .semibold))
                        .foregroundStyle(Theme.chromeMuted)
                }
            }

            Divider()

            // Manage agents
            Button {
                NSApp.sendAction(#selector(AppDelegate.handleOpenSettings), to: nil, from: nil)
            } label: {
                Label(L10n.string("Topbar.manage.agents"), systemImage: "gear")
            }
        } label: {
            HStack(spacing: 6) {
                if let current = currentTemplate {
                    AgentIconView(asset: current.iconAsset, fallbackSymbol: current.symbol, size: 14)
                } else {
                    Image(systemName: AgentTemplate.terminal.symbol)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.chromeMuted)
                }
                Text(currentTemplate?.title ?? "Agent")
                    .font(Theme.mono(11, weight: .medium))
                    .foregroundStyle(Theme.chromeForeground)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(Theme.chromeForeground.opacity(0.5))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Theme.chromeBackground)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Theme.chromeHairline, lineWidth: 1)
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(L10n.string("Topbar.switch.agent"))
    }

    private func switchToTemplate(_ template: AgentTemplate) {
        // Update the global default agent for new tabs
        ArcherSettingsModel.shared.defaultAgentId = template.id
        ArcherSettingsModel.shared.scheduleSave()
    }
}

private struct AgentTemplateMenuRow: View {
    let template: AgentTemplate
    let isCurrent: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                AgentIconView(asset: template.iconAsset, fallbackSymbol: template.symbol, size: 14)
                Text(template.title)
                    .font(Theme.mono(11))
                    .foregroundStyle(isCurrent ? Theme.chromeForeground : Theme.chromeForeground.opacity(0.85))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                if isCurrent {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.gitInsertion)
                }
            }
            .padding(.vertical, 2)
        }
        .disabled(isCurrent)
    }
}
