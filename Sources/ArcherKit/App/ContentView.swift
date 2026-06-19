import AppKit
import SwiftUI

struct ContentView: View {
    @Bindable var store: WorkspaceStore

    var body: some View {
        VStack(spacing: 0) {
            topStrip
            Rectangle().fill(Theme.chromeHairline).frame(height: 1)
            if store.usageStripVisible { // [archer]
                UsageStripView()
                Rectangle().fill(Theme.chromeHairline).frame(height: 1)
            }
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
                if store.downloaderPanelMode != .hidden { // [archer]
                    Rectangle().fill(Theme.chromeHairline).frame(width: 1)
                        .overlay {
                            if firstActiveRightPanel == .downloaderPanel {
                                rightResizer
                            }
                        }
                    FanboxDownloaderView(rootURL: store.active?.workingDirectory
                        ?? FileManager.default.homeDirectoryForCurrentUser,
                        onFinished: {},
                        width: store.panelWidths.rightPanel)
                        .id("\(store.active?.id.uuidString ?? "")-\(store.active?.workingDirectory.path ?? "")")
                }
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
                help: "Usage strip"
            ) {
                withAnimation(Theme.chromeTransition) {
                    store.toggleUsageStrip()
                }
            }
            HoverableIconButton( // [archer]
                systemName: "folder",
                fontSize: 12,
                size: 28,
                help: "File panel"
            ) {
                withAnimation(Theme.chromeTransition) {
                    store.setFilePanelMode(store.filePanelMode.next)
                }
            }
            HoverableIconButton( // [archer]
                systemName: "arrow.triangle.pull",
                fontSize: 12,
                size: 28,
                help: "Git Diff panel"
            ) {
                withAnimation(Theme.chromeTransition) {
                    store.setDiffPanelMode(store.diffPanelMode.next)
                }
            }
            HoverableIconButton( // [archer]
                systemName: "square.and.arrow.down",
                fontSize: 12,
                size: 28,
                help: "Fanbox Downloader"
            ) {
                withAnimation(Theme.chromeTransition) {
                    store.setDownloaderPanelMode(store.downloaderPanelMode.next)
                }
            }
            HoverableIconButton(
                systemName: "square.grid.2x2",
                fontSize: 12,
                size: 28,
                help: "Agent Panel"
            ) {
                withAnimation(Theme.chromeTransition) {
                    store.setRightSidebarMode(store.rightSidebarMode.next)
                }
            }
            InboxBell()
                .padding(.trailing, 8)
        }
        .frame(height: 32)
    }

    @ViewBuilder
    private var mainPane: some View {
        if let workspace = store.active {
            PaneTreeView(node: workspace.root, workspace: workspace, store: store)
                .id(workspace.id)
        } else {
            Color.clear
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
