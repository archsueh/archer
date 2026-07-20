import Foundation

/// On-disk shape of `WorkspaceStore`. Just the metadata — engine state
/// (scrollback, in-flight processes) can't survive PTY exit, so a restored
/// workspace re-spawns a fresh `LibghosttyEngine` per leaf and lands it in
/// the saved cwd via `TerminalSessionConfig.workingDirectory`.
struct PersistedState: Codable, Equatable {
    var workspaces: [PersistedWorkspace]
    var activeWorkspaceId: UUID?
    var sidebarMode: SidebarMode?
    var rightSidebarMode: SidebarMode?
    var filePanelMode: SidebarMode?
    var diffPanelMode: SidebarMode? // [archer]
    var downloaderPanelMode: SidebarMode? // [archer]
    var panelWidths: PanelWidths?
}

/// Root of the multi-window `state.json`. Each `PersistedWindow` is one
/// archer window's `WorkspaceStore`; array order is window restore order.
struct PersistedApp: Codable, Equatable {
    var windows: [PersistedWindow]
}

/// Window frame (size / position) is intentionally not persisted — archer
/// has never restored window geometry; restored windows just cascade.
struct PersistedWindow: Codable, Equatable {
    var id: UUID
    var state: PersistedState
}

struct PersistedWorkspace: Codable, Equatable {
    var id: UUID
    var workingDirectoryPath: String
    var root: PersistedPaneNode
    var activePaneId: UUID?
    var customTitle: String?
    /// nil = top-level workspace; non-nil = this is a git worktree whose
    /// source workspace persisted with this id. Decoded with
    /// `decodeIfPresent` so pre-worktree `state.json` files still load.
    var worktreeParentId: UUID?
    var worktreeBranch: String?
    /// Disk root captured at worktree-create time. Separate from
    /// `workingDirectoryPath` so the latter can drift with OSC 7 cwd
    /// reports without breaking close/reconcile path lookups.
    var worktreePath: String?
    /// SSH destination of an SSH workspace. Decoded as optional so state
    /// files written before the field restore as plain local workspaces.
    var sshRemoteHost: String?

    @MainActor
    init(_ ws: Workspace) {
        id = ws.id
        workingDirectoryPath = ws.workingDirectory.path
        root = PersistedPaneNode(ws.root)
        activePaneId = ws.activePaneId
        customTitle = ws.customTitle
        worktreeParentId = ws.worktreeParentId
        worktreeBranch = ws.worktreeBranch
        worktreePath = ws.worktreePath?.path
        sshRemoteHost = ws.sshRemoteHost
    }

    init(id: UUID, workingDirectoryPath: String, root: PersistedPaneNode, activePaneId: UUID? = nil, customTitle: String? = nil, worktreeParentId: UUID? = nil, worktreeBranch: String? = nil, worktreePath: String? = nil, sshRemoteHost: String? = nil) {
        self.id = id
        self.workingDirectoryPath = workingDirectoryPath
        self.root = root
        self.activePaneId = activePaneId
        self.customTitle = customTitle
        self.worktreeParentId = worktreeParentId
        self.worktreeBranch = worktreeBranch
        self.worktreePath = worktreePath
        self.sshRemoteHost = sshRemoteHost
    }

    private enum CodingKeys: String, CodingKey {
        case id, workingDirectoryPath, root, activePaneId, customTitle
        case worktreeParentId, worktreeBranch, worktreePath, sshRemoteHost
        /// Legacy keys
        case tabs, activeTabId
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(workingDirectoryPath, forKey: .workingDirectoryPath)
        try c.encode(root, forKey: .root)
        try c.encodeIfPresent(activePaneId, forKey: .activePaneId)
        try c.encodeIfPresent(customTitle, forKey: .customTitle)
        try c.encodeIfPresent(worktreeParentId, forKey: .worktreeParentId)
        try c.encodeIfPresent(worktreeBranch, forKey: .worktreeBranch)
        try c.encodeIfPresent(worktreePath, forKey: .worktreePath)
        try c.encodeIfPresent(sshRemoteHost, forKey: .sshRemoteHost)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        workingDirectoryPath = try c.decode(String.self, forKey: .workingDirectoryPath)
        customTitle = try c.decodeIfPresent(String.self, forKey: .customTitle)
        worktreeParentId = try c.decodeIfPresent(UUID.self, forKey: .worktreeParentId)
        worktreeBranch = try c.decodeIfPresent(String.self, forKey: .worktreeBranch)
        worktreePath = try c.decodeIfPresent(String.self, forKey: .worktreePath)
        sshRemoteHost = try c.decodeIfPresent(String.self, forKey: .sshRemoteHost)
        if let root = try c.decodeIfPresent(PersistedPaneNode.self, forKey: .root) {
            self.root = root
            activePaneId = try c.decodeIfPresent(UUID.self, forKey: .activePaneId)
        } else {
            // Legacy schema: flat `tabs: [PersistedTab]`. Wrap into a single Pane.
            let legacy = try c.decode([PersistedTab].self, forKey: .tabs)
            let activeTabId = try c.decodeIfPresent(UUID.self, forKey: .activeTabId)
            let pane = PersistedPane(
                id: UUID(),
                tabs: legacy,
                activeTabId: activeTabId
            )
            root = PersistedPaneNode(id: pane.id, kind: .pane(pane))
            activePaneId = pane.id
        }
    }
}

struct PersistedPaneNode: Codable, Equatable {
    var id: UUID
    var kind: PersistedPaneKind
}

indirect enum PersistedPaneKind: Equatable {
    case pane(PersistedPane)
    case split(orientation: SplitOrientation, first: PersistedPaneNode, second: PersistedPaneNode, fraction: Double)
}

extension PersistedPaneNode {
    @MainActor
    init(_ node: PaneNode) {
        id = node.id
        switch node.content {
        case let .pane(pane):
            kind = .pane(PersistedPane(pane))
        case let .split(orientation, first, second, fraction):
            kind = .split(
                orientation: orientation,
                first: PersistedPaneNode(first),
                second: PersistedPaneNode(second),
                fraction: fraction
            )
        }
    }
}

extension PersistedPaneKind: Codable {
    private enum CodingKeys: String, CodingKey { case pane, split }

    private struct SplitPayload: Codable, Equatable {
        var orientation: SplitOrientation
        var first: PersistedPaneNode
        var second: PersistedPaneNode
        var fraction: Double
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .pane(p):
            try c.encode(p, forKey: .pane)
        case let .split(orient, first, second, fraction):
            try c.encode(
                SplitPayload(orientation: orient, first: first, second: second, fraction: fraction),
                forKey: .split
            )
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let pane = try c.decodeIfPresent(PersistedPane.self, forKey: .pane) {
            self = .pane(pane)
        } else if let payload = try c.decodeIfPresent(SplitPayload.self, forKey: .split) {
            self = .split(
                orientation: payload.orientation,
                first: payload.first,
                second: payload.second,
                fraction: payload.fraction
            )
        } else {
            throw DecodingError.dataCorruptedError(
                forKey: .pane, in: c,
                debugDescription: "PersistedPaneKind requires either pane or split"
            )
        }
    }
}

struct PersistedPane: Codable, Equatable {
    var id: UUID
    var tabs: [PersistedTab]
    var activeTabId: UUID?

    @MainActor
    init(_ pane: Pane) {
        id = pane.id
        tabs = pane.tabs.map(PersistedTab.init)
        activeTabId = pane.activeTabId
    }

    init(id: UUID, tabs: [PersistedTab], activeTabId: UUID? = nil) {
        self.id = id
        self.tabs = tabs
        self.activeTabId = activeTabId
    }
}

struct PersistedTab: Codable, Equatable {
    var id: UUID
    var agentId: String
    var currentDirectoryPath: String
    var customTitle: String?
    /// Optional — only Claude reports it today. Decoded with
    /// `decodeIfPresent` so state.json files written by pre-resume archer
    /// versions still load.
    var conversationId: String?

    @MainActor
    init(_ session: Session) {
        id = session.id
        agentId = session.agent.id
        currentDirectoryPath = session.currentDirectory.path
        customTitle = session.customTitle
        conversationId = session.conversationId
    }

    init(id: UUID, agentId: String, currentDirectoryPath: String, customTitle: String? = nil, conversationId: String? = nil) {
        self.id = id
        self.agentId = agentId
        self.currentDirectoryPath = currentDirectoryPath
        self.customTitle = customTitle
        self.conversationId = conversationId
    }
}

@MainActor
protocol Persistence {
    func load() -> PersistedState?
    func save(_ state: PersistedState)
}

/// Owns the single `state.json` for the whole app. Holds every window's
/// `PersistedState` in memory (ordered) and writes the file synchronously
/// on each change. `WorkspaceStore`s never touch this directly — each gets
/// a `WindowPersistence` scoped to its own `windowId`.
@MainActor
final class AppPersistence {
    /// The real `state.json`. Tests inject a temp path via `init(fileURL:)`.
    static var defaultFileURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("archer", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("state.json")
    }

    private let fileURL: URL
    private var windows: [PersistedWindow]

    init(fileURL: URL = AppPersistence.defaultFileURL) {
        self.fileURL = fileURL
        windows = Self.loadFromDisk(from: fileURL)
    }

    /// Window ids in restore order — `AppDelegate` rebuilds one window each.
    var windowIds: [UUID] {
        windows.map(\.id)
    }

    func state(for id: UUID) -> PersistedState? {
        windows.first { $0.id == id }?.state
    }

    /// Upserts a window's state — a new id appends (so a `⌘⇧N` window
    /// restores last) — and writes the file. The write is synchronous:
    /// `WorkspaceStore.scheduleSave` already debounces upstream, and a
    /// closing window must reach disk before the process can exit.
    func setWindow(_ id: UUID, state: PersistedState) {
        if let idx = windows.firstIndex(where: { $0.id == id }) {
            windows[idx].state = state
        } else {
            windows.append(PersistedWindow(id: id, state: state))
        }
        writeToDisk()
    }

    func removeWindow(_ id: UUID) {
        windows.removeAll { $0.id == id }
        writeToDisk()
    }

    private func writeToDisk() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(PersistedApp(windows: windows)) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    /// Reads `state.json`, accepting both the current `{windows:[…]}` shape
    /// and the legacy bare `PersistedState` (pre-multi-window) — a legacy
    /// file migrates to one window. Returns `[]` for a missing / corrupt file.
    static func loadFromDisk(from url: URL) -> [PersistedWindow] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        if let app = try? decoder.decode(PersistedApp.self, from: data) {
            return app.windows
        }
        if let legacy = try? decoder.decode(PersistedState.self, from: data) {
            return [PersistedWindow(id: UUID(), state: legacy)]
        }
        return []
    }
}

/// No-op persistence for panel windows (Skills, Usage) that don't save state.
final class NullPersistence: Persistence {
    func load() -> PersistedState? {
        nil
    }

    func save(_: PersistedState) {}
}

/// A `Persistence` scoped to one window's slice of the shared `state.json`.
/// `WorkspaceStore` uses it like any `Persistence` and never knows it's one
/// window among several.
@MainActor
struct WindowPersistence: Persistence {
    let windowId: UUID
    let app: AppPersistence

    func load() -> PersistedState? {
        app.state(for: windowId)
    }

    func save(_ state: PersistedState) {
        app.setWindow(windowId, state: state)
    }
}
