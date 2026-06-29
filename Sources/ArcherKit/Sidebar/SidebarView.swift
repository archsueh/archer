import SwiftUI

// MARK: - Sidebar Sheet (from original)

private enum SidebarSheet: Identifiable {
    case createWorktree(Workspace)
    case parallelTask(Workspace)
    case confirmRemoveWorktree(Workspace)
    case confirmCloseOthers(WorkspaceStore.BulkRemovalRequest)
    case confirmCloseSource(WorkspaceStore.CloseSourceRequest)

    var id: String {
        switch self {
        case let .createWorktree(ws): return "create-\(ws.id.uuidString)"
        case let .parallelTask(ws): return "parallel-\(ws.id.uuidString)"
        case let .confirmRemoveWorktree(ws): return "remove-\(ws.id.uuidString)"
        case let .confirmCloseOthers(req): return "close-others-\(req.keeping.id.uuidString)"
        case let .confirmCloseSource(req): return "close-source-\(req.source.id.uuidString)"
        }
    }
}

// MARK: - Sidebar Row Item (for OutlineGroup)

private enum SidebarRowItem: Identifiable, Hashable {
    case workspace(UUID)
    case developerRoot
    case memory

    var id: String {
        switch self {
        case let .workspace(id): return id.uuidString
        case .developerRoot: return "developer-root"
        case .memory: return "memory"
        }
    }
}

// MARK: - Section Data

private struct SectionData {
    let section: SidebarSection
    let items: [SidebarRowItem]
    let isCollapsed: Bool
    let onToggle: () -> Void
}

// MARK: - Developer File Tree Section (from original)

struct DeveloperFileTreeSection: View {
    let onOpenInFinder: (URL) -> Void
    @State private var isExpanded = true
    @State private var rootItems: [FileTreeItem] = []
    @State private var expandedDirs: Set<URL> = []

    private let rootURL = URL(fileURLWithPath: "/")

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Theme.space2) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.chromeForeground.opacity(0.6))
                    .frame(width: 12, height: 12)
                Image(systemName: "folder.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.chromeForeground.opacity(0.85))
                Text(L10n.string("Developer"))
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
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        if rootItems.isEmpty {
                            ProgressView().padding(.vertical, 6)
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
        expandedDirs = Set(rootItems.filter { $0.isDirectory }.prefix(6).map(\.url.standardizedFileURL))
    }
}

// MARK: - Developer Tree Row (from original)

private struct DeveloperTreeRow: View {
    let item: FileTreeItem
    let depth: Int
    @Binding var expandedDirs: Set<URL>
    let onOpenInFinder: (URL) -> Void

    @State private var children: [FileTreeItem] = []

    private var indent: CGFloat {
        Theme.space2 + CGFloat(depth) * Theme.space3
    }

    private var isExpanded: Bool {
        expandedDirs.contains(item.url.standardizedFileURL)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Theme.space2) {
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
            if item.isDirectory && children.isEmpty { loadChildren() }
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

// MARK: - Memory Bank Section (from original)

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
                Text(L10n.string("Memory"))
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

// MARK: - SidebarView

struct SidebarView: View {
    static let fullWidth: CGFloat = 220
    static let compactWidth: CGFloat = 52

    @Bindable var store: WorkspaceStore

    @State private var draggingWorkspaceId: UUID?
    @State private var isFolderDropTargeted = false
    @State private var collapsedSections: Set<SidebarSection> = []
    @State private var collapsedParents: Set<UUID> = []

    @State private var sheet: SidebarSheet?

    var body: some View {
        let isCompact = store.sidebarMode == .compact

        VStack(spacing: 0) {
            brand(isCompact: isCompact)

            if isCompact {
                compactList
            } else {
                fullList
            }

            Spacer(minLength: 0)

            sideNav // [archer]
        }
        .frame(width: isCompact ? Self.compactWidth : CGFloat(store.panelWidths.sidebar))
        .background(Theme.chromeBackground)
        .overlay { dropZoneOverlay }
        .dropDestination(for: URL.self) { urls, _ in
            let folders = urls.filter(isDirectory)
            guard !folders.isEmpty else { return false }
            for folder in folders {
                store.addWorkspace(workingDirectory: folder)
            }
            return true
        } isTargeted: { isFolderDropTargeted = $0 }
        .sheet(item: $sheet) { current in sheetContent(for: current) }
        .onChange(of: store.pendingRemovalRequest?.id) { _, _ in
            if let ws = store.pendingRemovalRequest { sheet = .confirmRemoveWorktree(ws) }
        }
        .onChange(of: store.pendingCreateWorktreeRequest?.id) { _, _ in
            if let ws = store.pendingCreateWorktreeRequest { sheet = .createWorktree(ws) }
        }
        .onChange(of: store.pendingParallelTaskRequest?.id) { _, _ in
            if let ws = store.pendingParallelTaskRequest { sheet = .parallelTask(ws) }
        }
        .onAppear {
            if let ws = store.pendingCreateWorktreeRequest { sheet = .createWorktree(ws) }
        }
        .onChange(of: store.pendingCloseOthersRequest?.keeping.id) { _, _ in
            if let req = store.pendingCloseOthersRequest { sheet = .confirmCloseOthers(req) }
        }
        .onChange(of: store.pendingCloseSourceRequest?.source.id) { _, _ in
            if let req = store.pendingCloseSourceRequest { sheet = .confirmCloseSource(req) }
        }
    }

    private var compactList: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: 2) {
                ForEach(Array(store.workspaces.enumerated()), id: \.element.id) { index, workspace in
                    let canCreate = canCreateWorktree(from: workspace)
                    let goToSource: (() -> Void)? = workspace.worktreeParentId
                        .flatMap { id in store.workspaces.first { $0.id == id } }
                        .map { parent in { store.activateWorkspace(parent) } }

                    DraggableWorkspaceRow(
                        workspace: workspace,
                        store: store,
                        myIndex: index,
                        isCompact: true,
                        draggingId: $draggingWorkspaceId,
                        onCreateWorktree: canCreate ? { presentCreateWorktree(workspace) } : nil,
                        onParallelTask: canCreate ? { presentParallelTask(workspace) } : nil,
                        onGoToSource: goToSource
                    )
                }
            }
            .padding(.horizontal, Theme.space2)
            .padding(.vertical, Theme.space2)
        }
    }

    private var fullList: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 2) {
                    // Flat workspace list (Kooky parity) — no section header.
                    // A workspace is "top-level" when it has no parent, or its
                    // parent is gone (defensive: a stranded worktree still shows).
                    let parentIds = Set(store.workspaces.map(\.id))
                    let topLevel = store.workspaces.enumerated().filter { _, ws in
                        guard let parentId = ws.worktreeParentId else { return true }
                        return !parentIds.contains(parentId)
                    }
                    ForEach(Array(topLevel), id: \.element.id) { index, workspace in
                        workspaceTree(parent: workspace, parentIndex: index)
                    }
                }
                .padding(.horizontal, Theme.space2)
                .padding(.vertical, Theme.space2)
            }
            .onChange(of: store.pendingRenameWorkspace?.id) { _, _ in
                if let ws = store.pendingRenameWorkspace { revealWorkspaceForRename(ws, using: proxy) }
            }
            .onAppear { if let ws = store.pendingRenameWorkspace { revealWorkspaceForRename(ws, using: proxy) } }
        }
    }

    /// One source workspace row plus its worktree children (when expanded).
    @ViewBuilder
    private func workspaceTree(parent: Workspace, parentIndex: Int) -> some View {
        let worktrees = store.workspaces.filter { $0.worktreeParentId == parent.id }
        let hasWorktrees = !worktrees.isEmpty
        let isCollapsed = collapsedParents.contains(parent.id)
        let canCreate = canCreateWorktree(from: parent)

        DraggableWorkspaceRow(
            workspace: parent,
            store: store,
            myIndex: parentIndex,
            isCompact: false,
            draggingId: $draggingWorkspaceId,
            disclosure: hasWorktrees
                ? SidebarWorkspaceRow.WorktreeDisclosure(isCollapsed: isCollapsed, toggle: { toggleCollapsed(parent.id) })
                : nil,
            onCreateWorktree: canCreate ? { presentCreateWorktree(parent) } : nil,
            onParallelTask: canCreate ? { presentParallelTask(parent) } : nil
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
        withAnimation(Theme.collapseAnimation) {
            if collapsedParents.contains(id) { collapsedParents.remove(id) } else { collapsedParents.insert(id) }
        }
    }

    private var favoriteItems: [SidebarRowItem] {
        []
    }

    private var workspaceItems: [SidebarRowItem] {
        let parentIds = Set(store.workspaces.map(\.id))
        let topLevel = store.workspaces.filter { ws in
            guard let parentId = ws.worktreeParentId else { return true }
            return !parentIds.contains(parentId)
        }
        return topLevel.map { .workspace($0.id) }
    }

    private var toolItems: [SidebarRowItem] {
        [.developerRoot, .memory]
    }

    private func isSectionCollapsed(_ section: SidebarSection) -> Bool {
        collapsedSections.contains(section)
    }

    private func toggleSection(_ section: SidebarSection) {
        withAnimation(Theme.collapseAnimation) {
            if collapsedSections.contains(section) { collapsedSections.remove(section) }
            else { collapsedSections.insert(section) }
        }
    }

    @ViewBuilder
    private func brand(isCompact: Bool) -> some View {
        if isCompact {
            HoverableIconButton(
                systemName: "plus", fontSize: 12, size: 28,
                help: L10n.string("New workspace")
            ) { store.addWorkspace() }
                .padding(.top, Theme.space3).padding(.bottom, Theme.space2)
        } else {
            HStack(spacing: 0) {
                Text("Archer").font(Theme.display(15, weight: .medium)).foregroundStyle(Theme.chromeForeground)
                Spacer()
                HoverableIconButton(
                    systemName: "plus", fontSize: 12, size: 28,
                    help: L10n.string("New workspace")
                ) { store.addWorkspace() }
            }
            .padding(.horizontal, Theme.space4).padding(.top, Theme.space3).padding(.bottom, Theme.space2)
        }
    }

    private var dropZoneOverlay: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(Theme.chromeActive)
            RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.chromeForeground.opacity(0.55), lineWidth: 1)
        }
        .padding(Theme.space2)
        .opacity(isFolderDropTargeted ? 1 : 0)
        .animation(.easeOut(duration: 0.12), value: isFolderDropTargeted)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func sheetContent(for current: SidebarSheet) -> some View {
        switch current {
        case let .createWorktree(source):
            CreateWorktreeSheet(
                source: source,
                launchTemplates: AgentTemplate.visibleOrdered(model: ArcherSettingsModel.shared),
                defaultLaunchTemplate: AgentTemplate.defaultLaunchTemplate(model: ArcherSettingsModel.shared) ?? .terminal,
                alreadyAdoptedPaths: Set(store.workspaces.map { $0.diskPath.standardizedFileURL.path }),
                create: { await store.createWorktree(source: source, request: $0) },
                dismiss: { store.pendingCreateWorktreeRequest = nil; sheet = nil }
            )
        case let .parallelTask(source):
            ParallelTaskSheet(
                source: source,
                launchTemplates: AgentTemplate.visibleOrdered(model: ArcherSettingsModel.shared),
                defaultLaunchTemplate: AgentTemplate.defaultLaunchTemplate(model: ArcherSettingsModel.shared) ?? .terminal,
                launch: { await store.launchParallelTask(source: source, request: $0) },
                dismiss: { store.pendingParallelTaskRequest = nil; sheet = nil }
            )
        case let .confirmRemoveWorktree(workspace):
            ConfirmRemoveWorktreeSheet(
                workspace: workspace,
                confirm: { alsoDelete in
                    if alsoDelete { if let msg = await store.removeWorktreeDirectory(workspace) { return .failure(msg) } }
                    store.closeWorkspace(workspace)
                    store.pendingRemovalRequest = nil
                    return .success
                },
                dismiss: { store.pendingRemovalRequest = nil; sheet = nil }
            )
        case let .confirmCloseOthers(request):
            ConfirmBulkCloseSheet(
                statusLabel: "CLOSE-OTHERS", headlineText: "keeping \(request.keeping.title)",
                subtitleText: bulkSubtitle(closingCount: request.others.count, worktreeCount: request.worktreeOthers.count),
                worktreesAmong: request.worktreeOthers,
                confirm: { alsoDelete in if let msg = await store.performCloseOthers(request, alsoDelete: alsoDelete) { return .failure(msg) }; return .success },
                dismiss: { store.pendingCloseOthersRequest = nil; sheet = nil }
            )
        case let .confirmCloseSource(request):
            ConfirmBulkCloseSheet(
                statusLabel: "CLOSE-WORKSPACE", headlineText: "closing \(request.source.title)",
                subtitleText: bulkSubtitle(closingCount: request.worktrees.count + 1, worktreeCount: request.worktrees.count),
                worktreesAmong: request.worktrees,
                confirm: { alsoDelete in if let msg = await store.performCloseSource(request, alsoDelete: alsoDelete) { return .failure(msg) }; return .success },
                dismiss: { store.pendingCloseSourceRequest = nil; sheet = nil }
            )
        }
    }

    private func canCreateWorktree(from workspace: Workspace) -> Bool {
        guard workspace.worktreeParentId == nil else { return false }
        return GitWatcher.findGitDir(near: workspace.workingDirectory) != nil
    }

    private func presentCreateWorktree(_ workspace: Workspace) {
        store.pendingCreateWorktreeRequest = workspace
    }

    private func presentParallelTask(_ workspace: Workspace) {
        store.pendingParallelTaskRequest = workspace
    }

    private func revealWorkspaceForRename(_ workspace: Workspace, using proxy: ScrollViewProxy) {
        store.pendingRenameWorkspace = nil
        if let parentId = workspace.worktreeParentId, collapsedParents.contains(parentId) {
            collapsedParents.remove(parentId)
        }
        workspace.renameRequested = true
        DispatchQueue.main.async { proxy.scrollTo(workspace.id, anchor: .center) }
    }

    private func bulkSubtitle(closingCount: Int, worktreeCount: Int) -> String {
        let ws = closingCount == 1 ? "workspace" : "workspaces"
        let wt = worktreeCount == 1 ? "worktree" : "worktrees"
        return "\(closingCount) \(ws) will close · \(worktreeCount) \(wt)"
    }

    private var sideNav: some View {
        let isCompact = store.sidebarMode == .compact
        return VStack(spacing: 2) {
            if isCompact {
                VStack(spacing: 6) {
                    HoverableIconButton(
                        systemName: "square.stack.3d.up",
                        fontSize: 12,
                        size: 28,
                        help: "Skills"
                    ) {
                        SkillsPanelWindowController.show()
                    }

                    HoverableIconButton(
                        systemName: "gauge.medium",
                        fontSize: 12,
                        size: 28,
                        help: L10n.string("Agent usage")
                    ) {
                        UsagePanelWindowController.show()
                    }

                    HoverableIconButton(
                        systemName: "text.justify.left",
                        fontSize: 12,
                        size: 28,
                        help: "Bridge & hook log"
                    ) {
                        LogPanelWindowController.show()
                    }
                }
            } else {
                VStack(spacing: 4) {
                    HoverableNavButton(
                        title: "SKILLS",
                        iconName: "square.stack.3d.up",
                        isActive: false
                    ) {
                        SkillsPanelWindowController.show()
                    }

                    HoverableNavButton(
                        title: "USAGE",
                        iconName: "gauge.medium",
                        isActive: false
                    ) {
                        UsagePanelWindowController.show()
                    }

                    HoverableNavButton(
                        title: "LOG",
                        iconName: "text.justify.left",
                        isActive: false
                    ) {
                        LogPanelWindowController.show()
                    }
                }
                .padding(.horizontal, Theme.space2)
            }
        }
        .padding(.vertical, 8)
        .overlay(
            VStack {
                Rectangle().fill(Theme.chromeHairline).frame(height: 1)
                Spacer()
            }
        )
    }
}

private struct HoverableNavButton: View {
    let title: String
    let iconName: String
    let isActive: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: iconName)
                    .font(.system(size: 13))
                Text(title)
                    .font(Theme.mono(11.5, weight: .medium))
                Spacer()
            }
            .foregroundStyle(isActive ? Theme.chromeForeground : Theme.chromeMuted)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(isActive ? Theme.chromeActive : (isHovered ? Theme.chromeHover : Color.clear))
            .bracketBorder()
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { isHovered = $0 }
    }
}

// MARK: - SectionView

private struct SectionView: View {
    let data: SectionData
    let store: WorkspaceStore
    @Binding var draggingId: UUID?

    let onActivate: (Workspace) -> Void
    let onCreateWorktree: ((Workspace) -> Void)?
    let onParallelTask: ((Workspace) -> Void)?
    let onGoToSource: (Workspace) -> Void
    let onRevealForRename: ((Workspace) -> Void)?
    @Binding var collapsedParents: Set<UUID>

    var body: some View {
        VStack(spacing: 0) {
            SidebarSectionHeader(
                section: data.section,
                isCollapsed: data.isCollapsed,
                action: data.onToggle
            )

            if !data.isCollapsed {
                VStack(spacing: 0) {
                    ForEach(data.items) { item in
                        sectionContent(for: item)
                    }
                }
                .padding(.leading, Theme.space2)
            }
        }
    }

    @ViewBuilder
    private func sectionContent(for item: SidebarRowItem) -> some View {
        switch item {
        case let .workspace(wsId):
            if let workspace = store.workspaces.first(where: { $0.id == wsId }) {
                let worktrees = store.workspaces.filter { $0.worktreeParentId == workspace.id }
                let hasWorktrees = !worktrees.isEmpty
                let isCollapsed = collapsedParents.contains(workspace.id)

                let canCreate = canCreateWorktree(from: workspace)
                DraggableWorkspaceRow(
                    workspace: workspace,
                    store: store,
                    myIndex: store.workspaces.firstIndex(where: { $0.id == workspace.id }) ?? 0,
                    isCompact: false,
                    draggingId: $draggingId,
                    disclosure: hasWorktrees
                        ? SidebarWorkspaceRow.WorktreeDisclosure(isCollapsed: isCollapsed, toggle: { toggleCollapsed(workspace.id) })
                        : nil,
                    onCreateWorktree: canCreate ? { onCreateWorktree?(workspace) } : nil,
                    onParallelTask: canCreate ? { onParallelTask?(workspace) } : nil,
                    onGoToSource: { onGoToSource(workspace) }
                )

                if hasWorktrees && !isCollapsed {
                    ForEach(worktrees) { worktree in
                        SidebarWorkspaceRow(
                            workspace: worktree, isActive: worktree.id == store.activeWorkspaceId,
                            isCompact: false, canCloseOthers: store.workspaces.count > 1,
                            onActivate: { onActivate(worktree) },
                            onClose: { store.requestCloseWorkspace(worktree) },
                            onCloseOthers: { store.closeOtherWorkspaces(keeping: worktree) },
                            onDuplicate: { store.duplicateWorkspace(worktree) },
                            onRename: { store.renameWorkspace(worktree, to: $0) },
                            onGoToSource: { onGoToSource(workspace) }
                        )
                    }
                }
            }

        case .developerRoot:
            DeveloperFileTreeSection(onOpenInFinder: { url in
                let escaped = url.path.replacingOccurrences(of: " ", with: "\\ ")
                guard let data = "\(escaped)\n".data(using: .utf8) else { return }
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setData(data, forType: .string)
            })

        case .memory:
            MemoryBankSection()
        }
    }

    private func toggleCollapsed(_ id: UUID) {
        withAnimation(Theme.collapseAnimation) {
            if collapsedParents.contains(id) { collapsedParents.remove(id) } else { collapsedParents.insert(id) }
        }
    }

    private func canCreateWorktree(from workspace: Workspace) -> Bool {
        guard workspace.worktreeParentId == nil else { return false }
        return GitWatcher.findGitDir(near: workspace.workingDirectory) != nil
    }
}

// MARK: - DraggableWorkspaceRow

private struct DraggableWorkspaceRow: View {
    @Bindable var workspace: Workspace
    @Bindable var store: WorkspaceStore
    let myIndex: Int
    let isCompact: Bool
    @Binding var draggingId: UUID?
    var disclosure: SidebarWorkspaceRow.WorktreeDisclosure? = nil
    var onCreateWorktree: (() -> Void)? = nil
    var onParallelTask: (() -> Void)? = nil
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
            onParallelTask: onParallelTask,
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
