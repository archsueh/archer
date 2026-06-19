import SwiftUI

/// Bundles every modal sheet the sidebar can show so they share one
/// `.sheet(item:)` modifier. `.sheet(isPresented:)` per state would race
/// when switching directly between modes (create → confirm-remove).
private enum SidebarSheet: Identifiable {
    case createWorktree(Workspace)
    case confirmRemoveWorktree(Workspace)
    case confirmCloseOthers(WorkspaceStore.BulkRemovalRequest)
    case confirmCloseSource(WorkspaceStore.CloseSourceRequest)

    var id: String {
        switch self {
        case .createWorktree(let ws): return "create-\(ws.id.uuidString)"
        case .confirmRemoveWorktree(let ws): return "remove-\(ws.id.uuidString)"
        case .confirmCloseOthers(let req): return "close-others-\(req.keeping.id.uuidString)"
        case .confirmCloseSource(let req): return "close-source-\(req.source.id.uuidString)"
        }
    }
}

// MARK: - Developer File Tree Section

struct DeveloperFileTreeSection: View {
    let onOpenInFinder: (URL) -> Void
    @State private var isExpanded = true
    @State private var rootItems: [FileTreeItem] = []
    @State private var expandedDirs: Set<URL> = []

    private let rootURL = URL(fileURLWithPath: "/")

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Disclosure row
            HStack(spacing: Theme.space2) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.chromeForeground.opacity(0.6))
                    .frame(width: 12, height: 12)
                Image(systemName: "folder.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.chromeForeground.opacity(0.85))
                Text("Developer")
                    .font(Theme.mono(10.5))
                    .foregroundStyle(Theme.chromeForeground.opacity(0.9))
                Spacer(minLength: 0)
                Text("/")
                    .font(Theme.mono(9))
                    .foregroundStyle(Theme.chromeForeground.opacity(0.45))
            }
            .padding(.horizontal, Theme.space2)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.easeOut(duration: 0.12)) { isExpanded.toggle() } }

            if isExpanded {
                // Lazy-loaded root children
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        if rootItems.isEmpty {
                            ProgressView()
                                .padding(.vertical, 6)
                        } else {
                            ForEach(rootItems) { item in
                                DeveloperTreeRow(
                                    item: item,
                                    depth: 0,
                                    expandedDirs: $expandedDirs,
                                    onOpenInFinder: onOpenInFinder
                                )
                            }
                        }
                    }
                    .padding(.horizontal, Theme.space2)
                    .padding(.vertical, Theme.space1)
                }
                .frame(maxHeight: 260)
            }
        }
        .background(Theme.chromeBackground)
        .onAppear { loadRoot() }
    }

    private func loadRoot() {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return }
        rootItems = urls.map { url in
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            return FileTreeItem(id: url, url: url, isDirectory: isDir)
        }
        .sorted { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory && !b.isDirectory }
            return a.url.lastPathComponent.localizedStandardCompare(b.url.lastPathComponent) == .orderedAscending
        }
        // Auto-expand root dirs up to depth 1 by default
        expandedDirs = Set(rootItems.filter { $0.isDirectory }.prefix(6).map(\.url.standardizedFileURL))
    }
}

// MARK: - Developer Tree Row

private struct DeveloperTreeRow: View {
    let item: FileTreeItem
    let depth: Int
    @Binding var expandedDirs: Set<URL>
    let onOpenInFinder: (URL) -> Void

    @State private var children: [FileTreeItem] = []

    private var indent: CGFloat { Theme.space2 + CGFloat(depth) * Theme.space3 }
    private var isExpanded: Bool { expandedDirs.contains(item.url.standardizedFileURL) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Theme.space2) {
                // Disclosure triangle for dirs
                if item.isDirectory {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.chromeForeground.opacity(0.5))
                        .frame(width: 12, height: 12)
                        .onTapGesture { toggle() }
                } else {
                    Color.clear.frame(width: 12, height: 12)
                }

                Image(systemName: item.isDirectory ? "folder.fill" : "doc.text.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.chromeForeground.opacity(item.isDirectory ? 0.88 : 0.6))
                    .frame(width: 14, height: 14)

                Text(item.url.lastPathComponent)
                    .font(Theme.mono(10.5))
                    .foregroundStyle(Theme.chromeForeground.opacity(item.isDirectory ? 0.88 : 0.65))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 0)

                if item.isDirectory {
                    HoverableIconButton(
                        systemName: "arrow.up.right.square",
                        fontSize: 9,
                        size: 16,
                        help: "Open in Finder"
                    ) { onOpenInFinder(item.url) }
                    .opacity(0.6)
                }
            }
            .padding(.leading, indent)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .onTapGesture {
                // Paste path to active pane
                let escaped = item.url.path.replacingOccurrences(of: " ", with: "\\ ")
                guard let data = "\(escaped)\n".data(using: .utf8) else { return }
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setData(data, forType: .string)
            }

            if isExpanded && item.isDirectory && !children.isEmpty {
                ForEach(children) { child in
                    DeveloperTreeRow(
                        item: child,
                        depth: depth + 1,
                        expandedDirs: $expandedDirs,
                        onOpenInFinder: onOpenInFinder
                    )
                }
            }
        }
        .task(id: "dev-tree-\(item.id.path)") {
            if item.isDirectory && children.isEmpty {
                loadChildren()
            }
        }
    }

    private func loadChildren() {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(
            at: item.url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return }
        children = urls.map { url in
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            return FileTreeItem(id: url, url: url, isDirectory: isDir)
        }
        .sorted { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory && !b.isDirectory }
            return a.url.lastPathComponent.localizedStandardCompare(b.url.lastPathComponent) == .orderedAscending
        }
        withAnimation(.easeOut(duration: 0.12)) { expandedDirs.insert(item.url.standardizedFileURL) }
    }

    private func toggle() {
        withAnimation(.easeOut(duration: 0.12)) {
            if expandedDirs.contains(item.url.standardizedFileURL) {
                expandedDirs.remove(item.url.standardizedFileURL)
            } else {
                expandedDirs.insert(item.url.standardizedFileURL)
            }
        }
    }
}



struct SidebarView: View {
    static let fullWidth: CGFloat = 220
    static let compactWidth: CGFloat = 52
    @Bindable var store: WorkspaceStore
    /// Id of the workspace currently being dragged. Set by `.onDrag`, cleared
    /// on drop. Lets each row compute whether the drag origin is above or
    /// below it so the drop indicator can flip edges.
    @State private var draggingWorkspaceId: UUID?
    /// True while a Finder folder drag is hovering the sidebar — gates the
    /// drop-zone outline so the user sees that releasing here opens a new
    /// workspace.
    @State private var isFolderDropTargeted = false
    /// Source workspace ids whose worktree subtree the user collapsed.
    /// Default behaviour is expanded — only ids the user explicitly closed
    /// land here. Ephemeral by design: a archer relaunch always shows every
    /// worktree on first paint so nothing is hidden by stale state.
    @State private var collapsedParents: Set<UUID> = []
    /// Active modal sheet (create worktree / confirm-delete worktree).
    /// Nil = no sheet. Set by row callbacks and an onChange observer that
    /// watches `store.pendingRemovalRequest` for ⌘⇧W routed via AppDelegate.
    @State private var sheet: SidebarSheet?



    var body: some View {
        let isCompact = store.sidebarMode == .compact
        VStack(spacing: 0) {
            brand(isCompact: isCompact)
            

            
            ScrollViewReader { proxy in
                list(isCompact: isCompact, proxy: proxy)
            }
            Spacer(minLength: 0)
        }
        .frame(width: isCompact ? Self.compactWidth : CGFloat(store.panelWidths.sidebar))
        .background(Theme.chromeBackground)
        .overlay {
            // Drop affordance: tinted fill + hairline stroke, inset from the
            // sidebar edges so the splitter / titlebar don't clip it. Always
            // in the view tree (alpha-driven) so `easeOut(0.12)` can animate.
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Theme.chromeActive)
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Theme.chromeForeground.opacity(0.55), lineWidth: 1)
            }
            .padding(Theme.space2)
            .opacity(isFolderDropTargeted ? 1 : 0)
            .animation(.easeOut(duration: 0.12), value: isFolderDropTargeted)
            .allowsHitTesting(false)
        }
        // Files are silently ignored — `GhosttySurfaceView` already handles
        // "drop a file path at the cursor" inside a pane (M5.kk). The outline
        // lights up for any URL drag (SwiftUI's `.dropDestination` can't
        // pre-filter file-vs-folder); file drags release as no-ops.
        .dropDestination(for: URL.self) { urls, _ in
            let folders = urls.filter(isDirectory)
            guard !folders.isEmpty else { return false }
            for folder in folders {
                store.addWorkspace(workingDirectory: folder)
            }
            return true
        } isTargeted: { isFolderDropTargeted = $0 }
        .sheet(item: $sheet) { current in
            switch current {
            case .createWorktree(let source):
                CreateWorktreeSheet(
                    source: source,
                    launchTemplates: AgentTemplate.visibleOrdered(model: ArcherSettingsModel.shared),
                    defaultLaunchTemplate: AgentTemplate.defaultLaunchTemplate(model: ArcherSettingsModel.shared)
                        ?? .terminal,
                    // Include every workspace's diskPath, not just worktree
                    // children — if the user opened a worktree directory as
                    // a top-level workspace (Finder drop / ⌘O), adopting it
                    // again would spawn a duplicate row pointing at the same
                    // dir. Source workspaces (the repo root) also belong in
                    // the exclusion set because the adopt picker already
                    // drops them via `sourceRootKey`; including them here is
                    // belt-and-suspenders against multi-source ⌘O scenarios.
                    alreadyAdoptedPaths: Set(
                        store.workspaces.map { $0.diskPath.standardizedFileURL.path }
                    ),
                    create: { request in
                        await store.createWorktree(source: source, request: request)
                    },
                    dismiss: {
                        store.pendingCreateWorktreeRequest = nil
                        sheet = nil
                    }
                )
            case .confirmRemoveWorktree(let workspace):
                ConfirmRemoveWorktreeSheet(
                    workspace: workspace,
                    confirm: { alsoDelete in
                        if alsoDelete {
                            if let message = await store.removeWorktreeDirectory(workspace) {
                                return .failure(message)
                            }
                        }
                        store.closeWorkspace(workspace)
                        store.pendingRemovalRequest = nil
                        return .success
                    },
                    dismiss: {
                        store.pendingRemovalRequest = nil
                        sheet = nil
                    }
                )
            case .confirmCloseOthers(let request):
                ConfirmBulkCloseSheet(
                    statusLabel: "CLOSE-OTHERS",
                    headlineText: "keeping \(request.keeping.title)",
                    subtitleText: bulkSubtitle(
                        closingCount: request.others.count,
                        worktreeCount: request.worktreeOthers.count
                    ),
                    worktreesAmong: request.worktreeOthers,
                    confirm: { alsoDelete in
                        if let message = await store.performCloseOthers(request, alsoDelete: alsoDelete) {
                            return .failure(message)
                        }
                        return .success
                    },
                    dismiss: {
                        store.pendingCloseOthersRequest = nil
                        sheet = nil
                    }
                )
            case .confirmCloseSource(let request):
                ConfirmBulkCloseSheet(
                    statusLabel: "CLOSE-WORKSPACE",
                    headlineText: "closing \(request.source.title)",
                    subtitleText: bulkSubtitle(
                        closingCount: request.worktrees.count + 1,
                        worktreeCount: request.worktrees.count
                    ),
                    worktreesAmong: request.worktrees,
                    confirm: { alsoDelete in
                        if let message = await store.performCloseSource(request, alsoDelete: alsoDelete) {
                            return .failure(message)
                        }
                        return .success
                    },
                    dismiss: {
                        store.pendingCloseSourceRequest = nil
                        sheet = nil
                    }
                )
            }
        }
        // ⌘⇧W routes through AppDelegate → store.requestCloseWorkspace,
        // which parks worktree workspaces in `pendingRemovalRequest` for
        // the sidebar to pop the confirm sheet on. Identity-keyed so the
        // observer only fires on a fresh request, not internal renames.
        .onChange(of: store.pendingRemovalRequest?.id) { _, _ in
            if let workspace = store.pendingRemovalRequest {
                sheet = .confirmRemoveWorktree(workspace)
            }
        }
        // Global create requests (currently the command palette). When the
        // sidebar was hidden, `onAppear` below catches the already-parked
        // request after AppDelegate makes the sidebar visible.
        .onChange(of: store.pendingCreateWorktreeRequest?.id) { _, _ in
            if let workspace = store.pendingCreateWorktreeRequest {
                sheet = .createWorktree(workspace)
            }
        }
        .onAppear {
            if let workspace = store.pendingCreateWorktreeRequest {
                sheet = .createWorktree(workspace)
            }
        }
        // Bulk close-others request — keyed off keeping.id since the
        // others list can vary in length but each request is anchored
        // on its keeping workspace.
        .onChange(of: store.pendingCloseOthersRequest?.keeping.id) { _, _ in
            if let request = store.pendingCloseOthersRequest {
                sheet = .confirmCloseOthers(request)
            }
        }
        // Close-source-with-worktrees request — keyed off source.id; the
        // store parks it when ⌘⇧W / × on a top-level workspace would
        // strand its worktrees.
        .onChange(of: store.pendingCloseSourceRequest?.source.id) { _, _ in
            if let request = store.pendingCloseSourceRequest {
                sheet = .confirmCloseSource(request)
            }
        }

    }

    /// Shared subtitle string between the two bulk-close flows — folds
    /// pluralisation into one place so the count never reads as
    /// "1 workspaces" or "1 worktrees".
    private func bulkSubtitle(closingCount: Int, worktreeCount: Int) -> String {
        let workspaceWord = closingCount == 1 ? "workspace" : "workspaces"
        let worktreeWord = worktreeCount == 1 ? "worktree" : "worktrees"
        return "\(closingCount) \(workspaceWord) will close · \(worktreeCount) \(worktreeWord)"
    }

    /// True when `workspace` is a top-level source workspace *and* its
    /// cwd is inside a git repo. Worktree rows are excluded (worktree
    /// nesting isn't supported); non-git workspaces (e.g. `~/Downloads`
    /// opened as a workspace) hide the menu item so users never see an
    /// option that can only error.
    private func canCreateWorktree(from workspace: Workspace) -> Bool {
        guard workspace.worktreeParentId == nil else { return false }
        return GitWatcher.findGitDir(near: workspace.workingDirectory) != nil
    }

    @ViewBuilder
    private func brand(isCompact: Bool) -> some View {
        if isCompact {
            HoverableIconButton(
                systemName: "plus",
                fontSize: 12,
                size: 28,
                help: "New workspace"
            ) {
                store.addWorkspace()
            }
            .padding(.top, Theme.space3)
            .padding(.bottom, Theme.space2)
        } else {
            HStack(spacing: 0) {
                Text("Archer") // [archer]
                    .font(Theme.display(15, weight: .medium))
                    .foregroundStyle(Theme.chromeForeground)
                Spacer()
                HoverableIconButton(
                    systemName: "plus",
                    fontSize: 12,
                    size: 28,
                    help: "New workspace"
                ) {
                    store.addWorkspace()
                }
            }
            .padding(.horizontal, Theme.space4)
            .padding(.top, Theme.space3)
            .padding(.bottom, Theme.space2)
        }
    }

    @ViewBuilder
    private func list(isCompact: Bool, proxy: ScrollViewProxy) -> some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 2) {
                if isCompact {
                    // 52pt-wide sidebar can't fit a disclosure triangle next
                    // to a 28pt icon — fall back to a flat list. The order
                    // is stable: store.workspaces already places worktrees
                    // after their source by virtue of being appended at
                    // creation time.
                    ForEach(Array(store.workspaces.enumerated()), id: \.element.id) { index, workspace in
                        // canCreateWorktree walks the fs (`findGitDir`) —
                        // hoist once per workspace so the two row callbacks
                        // don't each stat the same ancestor chain.
                        let canCreate = canCreateWorktree(from: workspace)
                        let goToSource: (() -> Void)? = workspace.worktreeParentId
                            .flatMap { id in store.workspaces.first { $0.id == id } }
                            .map { parent in { store.activateWorkspace(parent) } }
                        DraggableWorkspaceRow(
                            workspace: workspace,
                            store: store,
                            myIndex: index,
                            isCompact: isCompact,
                            draggingId: $draggingWorkspaceId,
                            onCreateWorktree: canCreate ? { presentCreateWorktree(workspace) } : nil,
                            onGoToSource: goToSource
                        )
                    }
                } else {
                    // A workspace is "top-level" either because it has no
                    // parent, or because its parent is gone — defensive
                    // fallback so a bug that strands a worktree (parent
                    // closed while child kept) still surfaces the row in
                    // the sidebar instead of vanishing it entirely.
                    let parentIds = Set(store.workspaces.map(\.id))
                    let topLevel = store.workspaces.enumerated().filter { _, ws in
                        guard let parentId = ws.worktreeParentId else { return true }
                        return !parentIds.contains(parentId)
                    }
                    ForEach(Array(topLevel), id: \.element.id) { index, workspace in
                        workspaceTree(parent: workspace, parentIndex: index)
                    }
                }
            }
            .padding(.horizontal, Theme.space2)
            .padding(.vertical, Theme.space2)
        }
        .onChange(of: store.pendingCloseSourceRequest?.source.id) { _, _ in
            if let request = store.pendingCloseSourceRequest {
                sheet = .confirmCloseSource(request)
            }
        }

        // ⌘⇧R: reveal active workspace row for rename popover
        .onChange(of: store.pendingRenameWorkspace?.id) { _, _ in
            revealWorkspaceForRename(using: proxy)
        }
        .onAppear { revealWorkspaceForRename(using: proxy) }

        // Developer file tree section — toggled by a disclosure row
        if !isCompact {
            DeveloperFileTreeSection(onOpenInFinder: { url in
                let escaped = url.path.replacingOccurrences(of: " ", with: "\\ ")
                guard let data = "\(escaped)\n".data(using: .utf8) else { return }
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setData(data, forType: .string)
            })
            MemoryBankSection()
        }
    }

    @ViewBuilder
    private func workspaceTree(parent: Workspace, parentIndex: Int) -> some View {
        let worktrees = store.workspaces.filter { $0.worktreeParentId == parent.id }
        let hasWorktrees = !worktrees.isEmpty
        let isCollapsed = collapsedParents.contains(parent.id)

        // canCreateWorktree walks the fs (`findGitDir`) — hoist once so
        // the two callbacks don't each stat the same ancestor chain.
        let canCreate = canCreateWorktree(from: parent)
        DraggableWorkspaceRow(
            workspace: parent,
            store: store,
            myIndex: parentIndex,
            isCompact: false,
            draggingId: $draggingWorkspaceId,
            disclosure: hasWorktrees
                ? SidebarWorkspaceRow.WorktreeDisclosure(
                    isCollapsed: isCollapsed,
                    toggle: { toggleCollapsed(parent.id) }
                )
                : nil,
            onCreateWorktree: canCreate ? { presentCreateWorktree(parent) } : nil
        )

        if hasWorktrees && !isCollapsed {
            ForEach(worktrees) { worktree in
                SidebarWorkspaceRow(
                    workspace: worktree,
                    isActive: worktree.id == store.activeWorkspaceId,
                    isCompact: false,
                    canCloseOthers: store.workspaces.count > 1,
                    onActivate: { store.activateWorkspace(worktree) },
                    onClose: { store.requestCloseWorkspace(worktree) },
                    onCloseOthers: { store.closeOtherWorkspaces(keeping: worktree) },
                    onDuplicate: { store.duplicateWorkspace(worktree) },
                    onRename: { store.renameWorkspace(worktree, to: $0) },
                    onGoToSource: { store.activateWorkspace(parent) }
                )
            }
        }
    }

    private func toggleCollapsed(_ id: UUID) {
        withAnimation(.easeOut(duration: 0.12)) {
            if collapsedParents.contains(id) {
                collapsedParents.remove(id)
            } else {
                collapsedParents.insert(id)
            }
        }
    }

    /// Bring the active workspace's row into the view hierarchy so its rename
    /// popover can anchor, then hand off to the row via `renameRequested`. The
    /// row may be unmounted — nested under a collapsed worktree parent, or
    /// scrolled out of the LazyVStack's realized window. Without this the ⌘⇧R
    /// flag would sit unconsumed and then fire stale when the user later
    /// scrolled to / expanded that row.
    private func revealWorkspaceForRename(using proxy: ScrollViewProxy) {
        guard let workspace = store.pendingRenameWorkspace else { return }
        store.pendingRenameWorkspace = nil
        if let parentId = workspace.worktreeParentId, collapsedParents.contains(parentId) {
            collapsedParents.remove(parentId)
        }
        workspace.renameRequested = true
        // Defer so a just-expanded subtree is laid out before scrolling to a
        // row that may have only now been inserted.
        DispatchQueue.main.async {
            proxy.scrollTo(workspace.id, anchor: .center)
        }
    }

    private func presentCreateWorktree(_ workspace: Workspace) {
        // Single channel: parking on the store triggers the `.onChange`
        // observer that sets `sheet`. Direct row clicks and command-palette
        // / AppDelegate routes all go through here, so this stays the one
        // mechanism that opens the create sheet.
        store.pendingCreateWorktreeRequest = workspace
    }
}

/// Drag source + drop target with a direction-aware edge indicator —
/// `top` when origin is below (dragging up), `bottom` when origin is above
/// (dragging down), so the line always shows where the dropped row will land.
private struct DraggableWorkspaceRow: View {
    @Bindable var workspace: Workspace
    @Bindable var store: WorkspaceStore
    let myIndex: Int
    let isCompact: Bool
    @Binding var draggingId: UUID?
    /// Non-nil only for source workspaces that own at least one worktree.
    /// Worktree rows themselves render via `SidebarWorkspaceRow` directly,
    /// without this wrapper, so they don't pick up drag/drop handlers.
    var disclosure: SidebarWorkspaceRow.WorktreeDisclosure? = nil
    var onCreateWorktree: (() -> Void)? = nil
    var onGoToSource: (() -> Void)? = nil

    @State private var isTargeted = false

    var body: some View {
        let originIndex: Int? = {
            guard let id = draggingId, id != workspace.id else { return nil }
            return store.workspaces.firstIndex(where: { $0.id == id })
        }()
        let dragsDownward = (originIndex ?? Int.max) < myIndex
        let edge: Alignment = dragsDownward ? .bottom : .top
        let isSelfDrag = draggingId == workspace.id

        SidebarWorkspaceRow(
            workspace: workspace,
            isActive: workspace.id == store.activeWorkspaceId,
            isCompact: isCompact,
            canCloseOthers: store.workspaces.count > 1,
            onActivate: { store.activateWorkspace(workspace) },
            onClose: { store.requestCloseWorkspace(workspace) },
            onCloseOthers: { store.closeOtherWorkspaces(keeping: workspace) },
            onDuplicate: { store.duplicateWorkspace(workspace) },
            onRename: { store.renameWorkspace(workspace, to: $0) },
            disclosure: disclosure,
            onCreateWorktree: onCreateWorktree,
            onGoToSource: onGoToSource
        )
        .dropIndicator(active: isTargeted && !isSelfDrag, on: edge)
        .onDrag {
            draggingId = workspace.id
            return NSItemProvider(object: workspace.id.uuidString as NSString)
        }
        .dropDestination(for: String.self) { dropped, _ in
            defer { draggingId = nil }
            guard let id = dropped.first.flatMap(UUID.init),
                  let from = store.workspaces.firstIndex(where: { $0.id == id })
            else { return false }
            withAnimation(.easeInOut(duration: 0.18)) {
                store.moveWorkspace(from: from, to: myIndex)
            }
            return true
        } isTargeted: { isTargeted = $0 }
    }
}

// MARK: - Memory Bank Section
// Stores memory-bank metadata under the active workspace's root:
//   ~/Library/Application Support/Archer/memory/claude/<branch>/

struct MemoryBankSection: View {
    @Environment(\.controlActiveState) private var controlActive
    @FocusState private var focusedField: String?

    private let fm = FileManager.default
    private var memos: [URL] {
        let dir = memoryDir
        guard let urls = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return [] }
        return urls.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            HStack(spacing: Theme.space2) {
                Image(systemName: "brain")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.orange)
                    .frame(width: 16, height: 16)
                Text("Memory")
                    .font(Theme.mono(11, weight: .semibold))
                    .foregroundStyle(Theme.chromeForeground.opacity(0.9))
                Spacer(minLength: 0)
                Text(memoryDir.lastPathComponent)
                    .font(Theme.mono(9))
                    .foregroundStyle(Theme.chromeForeground.opacity(0.45))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, Theme.space2)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.easeOut(duration: 0.15)) { focusedField = "memory-open" } }

            if isExpanded {
                ScrollView(showsIndicators: true) {
                    LazyVStack(alignment: .trailing, spacing: 0) {
                        ForEach(memos, id: \.path) { memo in
                            HStack(alignment: .firstTextBaseline, spacing: Theme.space1) {
                                Text("→")
                                    .font(Theme.mono(9))
                                    .foregroundStyle(Theme.chromeForeground.opacity(0.45))
                                Text(memo.lastPathComponent)
                                    .font(Theme.mono(10))
                                    .foregroundStyle(Theme.chromeForeground.opacity(0.8))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, Theme.space3)
                            .padding(.vertical, 3)
                            .contentShape(Rectangle())
                            .onTapGesture { copyToPasteboard(memo.path) }
                        }
                        if memos.isEmpty {
                            Text("暂无记忆")
                                .font(Theme.mono(10))
                                .foregroundStyle(Theme.chromeForeground.opacity(0.4))
                                .padding(.vertical, 4)
                        }
                    }
                    .padding(.horizontal, Theme.space2)
                    .padding(.vertical, Theme.space1)
                }
                .frame(maxHeight: 180)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.vertical, 2)
        .onAppear { ensureMemoryDir() }
    }

    @State private var isExpanded = true

    private var memoryDir: URL {
        let activeBranch: String = {
            let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            let head = cwd.appendingPathComponent(".git/HEAD")
            guard let content = try? String(contentsOf: head, encoding: .utf8),
                  content.hasPrefix("ref: refs/heads/") else { return "default" }
            let ref = content.trimmingCharacters(in: .whitespacesAndNewlines)
            return ref.replacingOccurrences(of: "ref: ", with: "").components(separatedBy: "/").last ?? "default"
        }()
        return URL(fileURLWithPath: "~/Library/Application Support/Archer/memory/claude")
            .standardizedFileURL
            .appendingPathComponent(activeBranch)
    }

    private func ensureMemoryDir() {
        try? fm.createDirectory(at: memoryDir, withIntermediateDirectories: true, attributes: nil)
    }

    private func copyToPasteboard(_ text: String) {
        let escaped = text.replacingOccurrences(of: " ", with: "\\ ")
        guard let data = "\(escaped)\n".data(using: .utf8) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(data, forType: .string)
    }
}
