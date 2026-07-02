import SwiftUI

/// Flattened, display-ready snapshot of one `Session` for the Sessions
/// dashboard. Carries only what the row needs to render + a session `id`
/// for jump/close — deliberately does NOT carry raw workspace/window UUIDs
/// because `AppDelegate.dockTabLocation(for:)` already resolves a session
/// back to its (controller, workspace, session) trio by id alone (it's the
/// same lookup the Dock menu's tab-jump already uses), so there's nothing
/// else for this struct to route through.
struct SessionDashboardRow: Identifiable, Hashable {
    let id: UUID
    let title: String
    let agentTitle: String
    let agentTint: Color?
    let agentSymbol: String
    let agentIconAsset: String?
    /// `""` in the single-window case, `" · window 2"` etc. otherwise —
    /// same convention as `PaletteIndex.build`'s `winLabel`.
    let windowLabel: String
    let status: SessionDashboardStatus
    /// `nil` renders as "—": either the agent isn't Claude Code (no
    /// `conversationId`) or `tokenLookup` had no matching usage record yet.
    let tokenTotal: Int?
}

/// Builds the cross-window row list. Takes `[WorkspaceStore]` rather than
/// `[ArcherWindowController]` so it stays testable the way
/// `WorkspaceStoreTests` already tests bare stores, with no AppKit window
/// type in the signature.
@MainActor
enum SessionDashboardIndex {
    static func build(
        stores: [WorkspaceStore],
        tokenLookup: (String) -> Int?
    ) -> [SessionDashboardRow] {
        var rows: [SessionDashboardRow] = []
        let multiWindow = stores.count > 1
        for (idx, store) in stores.enumerated() {
            let windowLabel = multiWindow ? " · window \(idx + 1)" : ""
            for workspace in store.workspaces {
                for pane in workspace.root.allPanes {
                    for tab in pane.tabs {
                        let agent = tab.displayAgent
                        rows.append(SessionDashboardRow(
                            id: tab.id,
                            title: tab.title,
                            agentTitle: agent.title,
                            agentTint: agent.tint,
                            agentSymbol: agent.symbol,
                            agentIconAsset: agent.iconAsset,
                            windowLabel: windowLabel,
                            status: SessionStatusDeriver.status(
                                activityState: tab.activityState,
                                lastCommandExit: tab.lastCommandExit
                            ),
                            tokenTotal: tab.conversationId.flatMap(tokenLookup)
                        ))
                    }
                }
            }
        }
        return rows
    }
}
