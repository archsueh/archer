import Foundation

/// Coarse bucket for the Sessions dashboard's status filter. Deliberately
/// narrower than the mockup this screen is based on — "Done" and
/// "RateLtd" have no backing signal anywhere in the session model today,
/// so they're omitted rather than faked.
enum SessionDashboardStatus: String, CaseIterable {
    case running, waiting, idle, error

    var label: String {
        switch self {
        case .running: "Running"
        case .waiting: "Waiting"
        case .idle: "Idle"
        case .error: "Error"
        }
    }
}

/// Pure derivation, `nonisolated` so it's callable from tests (and any
/// future background aggregation) without a main-actor hop.
///
/// Precedence mirrors `SidebarWorkspaceRow.activityDotColor` /
/// `Workspace.sidebarReadout` exactly (attention > failure > running >
/// idle) — this is the same three-signal read the sidebar dot already
/// uses per-workspace, just re-labeled for the dashboard's four buckets.
enum SessionStatusDeriver {
    nonisolated static func status(
        activityState: SessionActivityState,
        lastCommandExit: Int?
    ) -> SessionDashboardStatus {
        if activityState == .attention { return .waiting }
        if let exit = lastCommandExit, exit != 0 { return .error }
        if activityState == .running { return .running }
        return .idle
    }
}
